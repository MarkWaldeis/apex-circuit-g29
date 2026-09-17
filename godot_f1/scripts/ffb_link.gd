extends RefCounted
## Der Kanal vom Spiel zum echten Lenkrad.
##
## Godot 4 hat keine Force-Feedback-Schnittstelle, und das G29 hat keine
## Rumble-Motoren, auf die `Input.start_joy_vibration` wirken koennte. Deshalb
## rechnet das Spiel hier aus, was der Fahrer fuehlen muesste, und schickt es
## als kleines UDP-Paket an `tools/g29_ffb.py`, das daraus per DirectInput
## echte Kraefte am G29 erzeugt.
##
## Protokoll (identisch zu tools/g29_ffb.py, UTF-8 JSON, ein Objekt pro Paket):
##
##   {"v":1,"force":0.0,"damp":0.0,"fric":0.0,"rumble":0.0,"pulse":0.0,
##    "event":"shift","speed":42.5,"surface":"Asphalt","damage":0.0}
##
##   force   -1.0 .. +1.0  Grundkraft (Zentrierung, Aufprall, Untersteuern)
##   damp     0.0 ..  1.0  geschwindigkeitsabhaengige Daempfung
##   fric     0.0 ..  1.0  Reibung (Kerb, Kies, Gras)
##   rumble   0.0 ..  1.0  Ruetteln (Kerb, Ausritt)
##   pulse    0.0 ..  1.0  einmaliger Stoss (Schalten, Aufprall)
##
## Laeuft die Bruecke nicht, senden die Pakete ins Leere - das kostet nichts und
## das Spiel laeuft unveraendert weiter. Mit APEX_FFB=0 laesst sich der Kanal
## ganz abschalten.
##
## OWNER: ROOT.

const HOST := "127.0.0.1"
const PORT := 5601
const SEND_HZ := 60.0
## Werte, die die Bruecke oben drauf setzt (siehe tools/g29_ffb.py::apply).
const SPRING := 0.35

var enabled: bool = OS.get_environment("APEX_FFB") != "0"
var sent_packets: int = 0
var last_force: float = 0.0
var last_damp: float = 0.0
var last_fric: float = 0.0
var last_rumble: float = 0.0
var last_packet: Dictionary = {}

var _udp: PacketPeerUDP
var _ready_socket: bool = false
var _accumulator: float = 0.0
var _pulse: float = 0.0
var _last_event: String = ""


func setup() -> void:
	if not enabled:
		return
	_udp = PacketPeerUDP.new()
	# Port 0: let the OS pick the local port, the bridge only listens.
	if _udp.bind(0) != OK:
		enabled = false
		return
	if _udp.connect_to_host(HOST, PORT) != OK:
		enabled = false
		return
	_ready_socket = true


## One-off event the bridge should feel immediately (gear shift, impact).
func poke(kind: String, severity: float) -> void:
	_last_event = kind
	_pulse = maxf(_pulse, clampf(severity, 0.0, 1.0))


## `ctx` comes from the car: steering angle, cornering load, what the front
## tyres are doing and what is under them.
func update(delta: float, ctx: Dictionary) -> void:
	if not enabled:
		return
	_pulse = maxf(_pulse - delta * 3.5, 0.0)
	_accumulator += delta
	if _accumulator < 1.0 / SEND_HZ:
		return
	_accumulator = 0.0

	var steer: float = float(ctx.get("steer_angle", 0.0))
	var lat_g: float = float(ctx.get("lateral_g", 0.0))
	var speed: float = maxf(float(ctx.get("speed", 0.0)), 0.0)
	var slip_front: float = float(ctx.get("slip_front", 0.0))
	var understeer: float = clampf(float(ctx.get("understeer", 0.0)), 0.0, 1.0)
	var surface: Dictionary = ctx.get("surface", {})
	var rough: float = clampf(float(surface.get("rough", 0.0)), 0.0, 1.0)
	var rumble_src: float = clampf(float(surface.get("rumble", 0.0)), 0.0, 1.0)
	var speed_scale: float = clampf(speed / 55.0, 0.0, 1.0)

	# --- self-aligning torque ------------------------------------------------
	# A tyre pushes the wheel back towards straight, harder the more load it
	# carries. When the front slides (understeer) that push collapses - the
	# wheel goes light, which is the warning every driver uses.
	var load: float = clampf(absf(lat_g) / 4.0, 0.0, 1.0)
	var align: float = (0.18 + 0.62 * load) * speed_scale
	align *= 1.0 - 0.65 * understeer
	# The sign has to oppose the steering angle: `steering` is the physics
	# angle, i.e. positive = the front wheels point one way, so the feedback
	# pushes the other way.
	var direction: float = -signf(steer) if absf(steer) > 0.004 else 0.0
	var force: float = direction * align

	# --- how heavy and how rough the wheel is --------------------------------
	var damp: float = 0.22 + 0.38 * speed_scale
	var fric: float = clampf(0.12 + 0.75 * rough, 0.0, 1.0)
	var rumble: float = clampf(rumble_src * speed_scale, 0.0, 1.0)
	# Sliding front tyres grind through the wheel even on asphalt.
	rumble = maxf(rumble, clampf(absf(slip_front) - 0.12, 0.0, 0.25) * 3.0 * speed_scale)

	last_force = clampf(force, -1.0, 1.0)
	last_damp = clampf(damp, 0.0, 1.0)
	last_fric = clampf(fric, 0.0, 1.0)
	last_rumble = clampf(rumble, 0.0, 1.0)
	_send(_last_event)
	_last_event = ""


func _send(event: String) -> void:
	last_packet = {
		"v": 1,
		"force": snappedf(last_force, 0.001),
		"damp": snappedf(last_damp, 0.001),
		"fric": snappedf(last_fric, 0.001),
		"rumble": snappedf(last_rumble, 0.001),
		"pulse": snappedf(clampf(_pulse, 0.0, 1.0), 0.001),
		"spring": SPRING,
		"event": event,
	}
	if not _ready_socket or _udp == null:
		return
	if _udp.put_packet(JSON.stringify(last_packet).to_utf8_buffer()) == OK:
		sent_packets += 1
