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
## Achsenstellung des Helfers (Rohwert der DirectInput-Achse, 0..65535) aus dem
## Lebenszeichen. Das Spiel liest dieselbe Achse ueber SDL; aus dem Vergleich
## folgt die richtige Kraftrichtung, ohne dass jemand das Rad mit Kraft drehen
## muss (siehe `measure_direction`).
var helper_wheel_raw: int = -1
var helper_wheel_ms: int = -1
## Ergebnis der Selbstmessung: -1 unbekannt, 0 gegenlaeufig, 1 gleichlaeufig.
var direction_aligned: int = -1
var direction_samples: int = 0
## Einmaliger Hinweis fuer das HUD ("Kraftrichtung gemessen: ...").
var direction_note: String = ""
var direction_note_ms: int = -1
## Solange "auto", darf die Messung die Kraftrichtung setzen. Sobald der Fahrer
## den Schalter im Menue selbst anfasst, ist hier "fahrer" und die Automatik
## haelt sich heraus.
var auto_direction: bool = true
## Das G29 selbst: nur fuer die Richtungsmessung (Achsenvergleich). Fehlt es
## (Test ohne Rad), unterbleibt die Messung - es wird nichts erfunden.
var wheel = null
## Nur fuer die Hardware-Diagnose (`tests/probe_ffb_steer.gd`): wenn gesetzt,
## geht genau diese Grundkraft ans Lenkrad, ohne Physik. Damit laesst sich
## nachmessen, in welche Richtung eine positive Kraft das Rad wirklich dreht.
var force_torque_override = null

var _udp: PacketPeerUDP
var _ready_socket: bool = false
var _accumulator: float = 0.0
var _last_send_ms: int = -1
## Mitte der Helferachse, aus dem Stehen gelernt (kein fester Wert: das G29
## ruht gemessen bei 32767..33104, ein fester Nullpunkt waere schon schief).
var _axis_center: float = -1.0
var _axis_center_votes: int = 0
## Letzter Achsenwert, der in die Abstimmung eingegangen ist: die Antwort kommt
## mit 10 Hz, die Physik mit 90 Hz - ohne diese Sperre waere "12 gleiche
## Stimmen" nur ein einziger Messwert, der zwoelfmal gezaehlt wurde.
var _axis_vote_ms: int = -1
var _direction_votes: int = 0
var _direction_last: bool = false
## Die Entscheidung steht, ist aber noch nicht angewandt (im Bogen wird nicht
## umgedreht, siehe `_apply_direction`).
var _direction_applied: bool = false


func setup(ffb_settings = null, wheel_input = null) -> void:
	settings = ffb_settings
	wheel = wheel_input
	if settings == null:
		settings = Settings.new()
	auto_direction = String(settings.invert_source) != "fahrer"
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
	measure_direction(delta)
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
			# Nur eine echte Zahl aus dem Achsenbereich zaehlt. Ein fehlendes
			# Feld heisst "keine Achsendaten" und darf nie als Messung gelten.
			var axis = msg.get("axis", null)
			if typeof(axis) == TYPE_FLOAT or typeof(axis) == TYPE_INT:
				var axis_value: int = int(axis)
				if axis_value >= 0 and axis_value <= 65535:
					helper_wheel_raw = axis_value
					helper_wheel_ms = helper_last_ms


## Die Kraftrichtung selbst messen - statt sie nur zu vermuten.
##
## Was gemessen ist (`tools/ffb_hw_probe.py`, 21.09.2026): eine positive
## DirectInput-Kraft faehrt die G29-Achse zu ihrem **Minimum**. Ob "Achse
## runter" im Spiel links oder rechts ist, haengt daran, wie die
## DirectInput-Achse zur SDL-Achse steht, aus der das Spiel "rechts = +1"
## gelernt hat - und genau das laesst sich messen, sobald der Fahrer das
## Lenkrad dreht:
##
##   * der Helfer schickt seinen Achsenwert mit jedem Lebenszeichen (10 Hz),
##   * das Spiel liest dieselbe Achse ueber SDL,
##   * zeigen beide beim Drehen in dieselbe Richtung, ist die Kraft
##     spiegelverkehrt und muss umgedreht werden, sonst nicht.
##
## Damit faellt die letzte Annahme der Kette weg, ohne dass jemand das Rad mit
## Kraft drehen muss. Ohne Achsendaten wird **nichts** entschieden: `-1` bleibt
## stehen und das HUD schweigt.
func measure_direction(delta: float) -> void:
	if not auto_direction or wheel == null or not enabled:
		return
	# Steht die Entscheidung, wird sie in jedem Tick erneut zu setzen versucht,
	# bis das Rad ruhig genug ist. Ohne diesen Zweig haette sie nur beim
	# naechsten *neuen* Messwert eine Chance gehabt - und neue Messwerte gibt es
	# nur beim Lenken, also genau dann, wenn Kraft am Rad liegt.
	if direction_aligned >= 0:
		if not _direction_applied:
			_apply_direction()
		return
	if helper_wheel_raw < 0 or Time.get_ticks_msec() - helper_wheel_ms > 400:
		return
	if not wheel.has_method("axis_snapshot") or not wheel.has_method("has_axis_data"):
		return
	if not bool(wheel.has_axis_data()):
		return
	var snap: PackedFloat32Array = wheel.axis_snapshot()
	var idx: int = int(wheel.get("steer_axis"))
	if idx < 0 or idx >= snap.size():
		return
	var steer: float = clampf(float(snap[idx]), -1.0, 1.0)
	var raw_now: float = float(helper_wheel_raw)
	# Die Mitte aus dem Stehen lernen. Ein fester Wert waere falsch: gemessen
	# ruht die G29-Achse je nach Lauf bei 32767 bis 33104.
	if absf(steer) < 0.05:
		if _axis_center < 0.0:
			_axis_center = raw_now
		else:
			_axis_center = lerpf(_axis_center, raw_now, 0.10)
		_axis_center_votes += 1
		return
	if _axis_center < 0.0 or _axis_center_votes < 10:
		return
	# Erst ab deutlichem Lenkeinschlag: in der Totzone ist die Aussage duenn.
	if absf(steer) < 0.15:
		return
	var offset: float = raw_now - _axis_center
	if absf(offset) < 0.10 * 32767.0:
		return
	if helper_wheel_ms == _axis_vote_ms:
		return
	_axis_vote_ms = helper_wheel_ms
	var aligned: bool = signf(offset) == signf(steer)
	if aligned == _direction_last:
		_direction_votes += 1
	else:
		_direction_last = aligned
		_direction_votes = 1
	if _direction_votes < 5:
		return
	direction_aligned = 1 if aligned else 0
	direction_samples = _direction_votes
	_apply_direction()


## Ergebnis anwenden - aber nur in einem ruhigen Moment. Mitten im Bogen waere
## ein Vorzeichenwechsel ein Ruck am Lenkrad, und der Fahrer haette keine
## Chance zu verstehen, woher er kommt.
func _apply_direction() -> void:
	if settings == null or direction_aligned < 0:
		return
	# Hat der Fahrer den Schalter selbst gestellt, gilt seine Entscheidung -
	# auch mitten in der Sitzung.
	if String(settings.invert_source) == "fahrer":
		auto_direction = false
		return
	if absf(float(last_state.get("torque", 0.0))) > 0.15:
		return
	var want: bool = direction_aligned == 1
	var had: bool = bool(settings.invert)
	if had == want:
		direction_note = "Kraftrichtung gemessen: %s — war schon richtig" % _direction_word(want)
	else:
		settings.set_invert(want, "gemessen")
		direction_note = "Kraftrichtung gemessen: %s — automatisch gesetzt" % _direction_word(want)
	direction_note_ms = Time.get_ticks_msec()
	_direction_applied = true


func _direction_word(inverted: bool) -> String:
	return "umgekehrt" if inverted else "normal"


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
