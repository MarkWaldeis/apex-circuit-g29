extends RefCounted
## Der Kanal vom Spiel zum echten Lenkrad.
##
## Godot 4 hat keine Force-Feedback-Schnittstelle, und das G29 hat keine
## Rumble-Motoren, auf die `Input.start_joy_vibration` wirken koennte. Deshalb
## rechnet `ffb_model.gd` aus, was der Fahrer fuehlen muesste, und diese Klasse
## schickt das Ergebnis als kleines UDP-Paket an `tools/g29_ffb.py`, das daraus
## per DirectInput echte Kraefte am G29 erzeugt.
##
## Protokoll v2 (identisch zu tools/g29_ffb.py, UTF-8 JSON, ein Paket):
##
##   {"v":2,"torque":-0.42,"damper":0.29,"friction":0.14,"rumble":0.55,
##    "rumble_hz":31.0,"pulse":0.0,"pulse_dir":0.0,"spring":0.0,"gain":0.75,
##    "event":"kerb","speed":48.3,"source":"Kerb","clip":0.0,"damage":0.0}
##
##   torque     -1.0 .. +1.0  Grundkraft OHNE Stoss, + = drueckt nach rechts
##                            (die Staerke aus dem Menue steckt schon darin;
##                            der Helfer verstaerkt nicht ein zweites Mal)
##   damper      0.0 ..  1.0  geschwindigkeitsabhaengige Daempfung
##   friction    0.0 ..  1.0  Reibung (Stand, Kerb, Kies, Gras)
##   rumble      0.0 ..  1.0  Amplitude des Ruettelns
##   rumble_hz   5.0 .. 60.0  Frequenz dazu (Kerb schnell, Kies grob)
##   pulse       0.0 ..  1.0  einmaliger Stoss (Schalten, Aufprall). Er ist
##                            ein eigener Kanal und steckt NICHT in `torque`:
##                            der Helfer setzt ihn sofort (ohne Rampe) auf die
##                            Kraft. Sonst kaeme er doppelt an.
##   pulse_dir  -1.0 .. +1.0  Richtung des Stosses (+ = rechts)
##   spring      0.0 ..  1.0  Rest-Zentrierfeder (Standard 0: die Kraft kommt
##                            aus dem Nachlauf, nicht aus einer Feder)
##
## Laeuft die Bruecke nicht, senden die Pakete ins Leere - das kostet nichts und
## das Spiel laeuft unveraendert weiter. Mit APEX_FFB=0 laesst sich der Kanal
## ganz abschalten.
##
## Rueckkanal: Der Helfer antwortet auf jedes Paket mit `{"v":2,"ack":1,
## "mode":"wheel"|"dry"}`. Das Spiel liest das auf demselben Socket
## (`_read_acks`) und kann damit sagen, ob ueberhaupt jemand zuhoert - ohne
## diese Antwort bliebe ein totes Lenkrad unsichtbar (UDP bestaetigt nichts).
##
## OWNER: ROOT (workstream "Lenkrad-Gefuehl").

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const HOST := "127.0.0.1"
const PORT := 5601
## Wer zwei Spiele (oder einen Test neben dem Spiel) laufen laesst, gibt dem
## Kanal mit `APEX_FFB_PORT` einen eigenen Port - sonst hoeren beide auf
## dieselben Pakete und ein Test misst die Pakete des anderen.
const PORT_ENV := "APEX_FFB_PORT"
const SEND_HZ := 60.0
const PROTOCOL := 2
## So lange darf das letzte Lebenszeichen des Helfers alt sein, waehrend das
## Spiel sendet, bis das HUD sagt: da antwortet keiner mehr.
const HELPER_TIMEOUT_MS := 1500
## So kurz darf das letzte eigene Senden her sein, damit ein fehlendes
## Lebenszeichen ueberhaupt etwas bedeutet: im Menue (Pause) sendet das Spiel
## nichts, dann kommt auch keine Antwort - das ist kein Fehler.
const SEND_FRESH_MS := 500
## Der Helfer setzt keine eigene Zentrierfeder mehr obendrauf: das Zentrieren
## ist die Aufgabe des Nachlaufs (siehe ffb_model.gd).
const SPRING := 0.0

var enabled: bool = OS.get_environment("APEX_FFB") != "0"
var settings
var model
var sent_packets: int = 0
## Was zuletzt ans Lenkrad ging - HUD, Tests und Diagnose lesen das.
var last_state: Dictionary = {}
var last_packet: Dictionary = {}
var last_event: String = ""
## Lebenszeichen des Helfers (`tools/g29_ffb.py` antwortet auf jedes Paket mit
## `{"ack":1}`). Nur damit laesst sich von innen sagen, ob die Kraft ueberhaupt
## einen Empfaenger hat: UDP allein verraet das nicht.
var helper_acks: int = 0
var helper_mode: String = ""
var helper_last_ms: int = -1
## Nur fuer die Hardware-Diagnose (`tests/probe_ffb_steer.gd`): wenn gesetzt,
## geht genau diese Grundkraft ans Lenkrad, ohne Physik. Damit laesst sich
## nachmessen, in welche Richtung eine positive Kraft das Rad wirklich dreht.
var force_torque_override = null

var _udp: PacketPeerUDP
var _ready_socket: bool = false
var _accumulator: float = 0.0
var _last_send_ms: int = -1


func setup(ffb_settings = null) -> void:
	settings = ffb_settings
	if settings == null:
		settings = Settings.new()
	model = Model.new()
	model.setup(settings)
	last_state = model.last_state()
	if not enabled:
		return
	_udp = PacketPeerUDP.new()
	# Port 0: let the OS pick the local port, the bridge only listens.
	if _udp.bind(0) != OK:
		enabled = false
		return
	if _udp.connect_to_host(HOST, _port()) != OK:
		enabled = false
		return
	_ready_socket = true


static func _port() -> int:
	var env: String = OS.get_environment(PORT_ENV)
	if env.is_valid_int() and int(env) > 0 and int(env) < 65536:
		return int(env)
	return PORT


## One-off event the bridge should feel immediately (gear shift, impact).
func poke(kind: String, severity: float, direction: float = 0.0) -> void:
	if model:
		model.poke(kind, severity, direction)
	last_event = kind


## `ctx` comes from the car: steering angle, cornering load, what the tyres are
## doing, what is under them and what the driver is asking for.
func update(delta: float, ctx: Dictionary) -> Dictionary:
	if model == null:
		model = Model.new()
		model.setup(settings)
	last_state = model.update(delta, ctx)
	if not enabled:
		return last_state
	_accumulator += delta
	var period: float = 1.0 / SEND_HZ
	if _accumulator < period:
		return last_state
	# Den Rest mitnehmen, nicht wegwerfen: die Physik laeuft mit 90 Hz, ein
	# 60-Hz-Takt liegt also zwischen zwei Ticks. Mit `_accumulator = 0.0` wurde
	# jeder zweite Tick verschenkt, und der Kanal sendete real nur 45 Hz
	# (gemessen: 159 Pakete in 3,6 s, 1036 Pakete in 30 s), obwohl das
	# Protokoll 60 Hz zusagt - 22 ms ohne neue Information fuer das Lenkrad.
	_accumulator = maxf(_accumulator - period, 0.0)
	var events: Array = model.take_events()
	_send(String(events[0]) if events.size() > 0 else "")
	_read_acks()
	return last_state


## Lebenszeichen des Helfers einsammeln. Sie kommen auf demselben Socket
## zurueck, auf den gesendet wird.
func _read_acks() -> void:
	if not _ready_socket or _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = _udp.get_packet()
		var msg = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY and int(msg.get("ack", 0)) == 1:
			helper_acks += 1
			helper_last_ms = Time.get_ticks_msec()
			helper_mode = String(msg.get("mode", ""))


## Laeuft ein Helfer, der antwortet? `false` heisst nicht automatisch "kaputt":
## solange das Spiel nichts sendet (Pause, Menue), ist die Aussage leer. Das
## HUD fragt deshalb nur, wenn wirklich schon Pakete unterwegs waren
## (`sent_packets`).
func helper_alive() -> bool:
	if not _ready_socket or helper_acks == 0:
		return false
	if _last_send_ms >= 0 and Time.get_ticks_msec() - _last_send_ms > SEND_FRESH_MS:
		return true
	return Time.get_ticks_msec() - helper_last_ms <= HELPER_TIMEOUT_MS


func _send(event: String) -> void:
	var s: Dictionary = last_state
	var torque: float = float(s.get("torque", 0.0))
	if force_torque_override != null:
		torque = clampf(float(force_torque_override), -1.0, 1.0)
	last_packet = {
		"v": PROTOCOL,
		"torque": snappedf(torque, 0.001),
		"damper": snappedf(float(s.get("damper", 0.0)), 0.001),
		"friction": snappedf(float(s.get("friction", 0.0)), 0.001),
		"rumble": snappedf(float(s.get("rumble", 0.0)), 0.001),
		"rumble_hz": snappedf(float(s.get("rumble_hz", 24.0)), 0.1),
		"pulse": snappedf(float(s.get("pulse", 0.0)), 0.001),
		"pulse_dir": snappedf(float(s.get("pulse_dir", 0.0)), 0.01),
		"spring": SPRING,
		# Die Staerke aus dem Menue steckt schon in `torque` (ffb_model.gd wendet
		# sie genau einmal an, dort wo auch die Anzeige entsteht). Dieses Feld
		# ist deshalb 1.0: es ist die Zusatzverstaerkung des Helfers, und die
		# bleibt neutral. Frueher stand hier die Menue-Staerke, und der Helfer
		# hat sie ein zweites Mal angewendet - gemessen: 30 % Einstellung kamen
		# als 9 % am Lenkrad an (docs/reviews/ffb_f1_style.md).
		"gain": 1.0,
		"event": event,
		"speed": snappedf(last_ctx_speed(), 0.1),
		"source": String(s.get("source", "-")),
		"clip": snappedf(float(s.get("clip", 0.0)), 0.001),
		"damage": snappedf(last_ctx_damage(), 0.01),
	}
	if not _ready_socket or _udp == null:
		return
	if _udp.put_packet(JSON.stringify(last_packet).to_utf8_buffer()) == OK:
		sent_packets += 1
		_last_send_ms = Time.get_ticks_msec()


func last_ctx_speed() -> float:
	return float(model.last_ctx.get("speed", 0.0)) if model else 0.0


func last_ctx_damage() -> float:
	return float(model.last_ctx.get("damage", 0.0)) if model else 0.0
