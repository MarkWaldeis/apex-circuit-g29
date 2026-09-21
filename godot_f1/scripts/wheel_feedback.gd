extends RefCounted
## Was der Fahrer am Lenkrad fuehlt - die In-Game-Seite.
##
## Die Rechnung selbst steht in `ffb_model.gd`. Diese Klasse liest genau
## dieselben Zahlen und gibt sie an alles weiter, was im Spiel reagieren kann:
## HUD, Cockpit-Kamera (Kopf lehnt sich, ruckelt) und - auf einem Gamepad,
## nicht auf dem G29 - `Input.start_joy_vibration`.
##
## Frueher hatte dieses Modul seine eigene, grobe Schaetzung aus Fahrbahn und
## Schlupf. Das war eine zweite Wahrheit neben dem echten Lenkradkanal: HUD und
## Lenkrad konnten unterschiedliche Dinge erzaehlen. Jetzt teilen sich beide ein
## Modell - das Auto reicht es ueber `setup(..., model)` herein.
##
## OWNER: ROOT (workstream "Lenkrad-Gefuehl").

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const BRIDGE_PATH := "user://ffb_state.json"

var car
var wheel
var model
## 0..1 Zielintensitaet fuer Kamera/HUD/Vibration - aus Kraft, Ruetteln und Stoss.
var strength: float = 0.0
var last_event: String = ""
var source: String = "-"
## True, wenn dieses Modul das Modell selbst rechnet (KI-Auto ohne Lenkrad-
## kanal). Beim Spielerauto rechnet `ffb_link.gd` und hier wird nur gelesen.
var owns_model: bool = true
## The JSON bridge is opt-in (launcher sets APEX_FFB=1), so a normal double-click
## start does no extra file I/O at all.
var _bridge_on: bool = OS.get_environment("APEX_FFB") == "1"
var _bridge_cd: float = 0.0


func setup(owner_car, wheel_input, shared_model = null) -> void:
	car = owner_car
	wheel = wheel_input
	if shared_model != null:
		model = shared_model
		owns_model = false
	else:
		model = Model.new()
		model.setup(Settings.new())
		owns_model = true
	if wheel and wheel.has_signal("shift_up") and not wheel.shift_up.is_connected(_on_shift):
		wheel.shift_up.connect(_on_shift)
		wheel.shift_down.connect(_on_shift)


func _on_shift() -> void:
	poke("shift", 0.35)


func poke(kind: String, severity: float) -> void:
	last_event = kind
	if model:
		model.poke(kind, severity)


func update(delta: float, ctx: Dictionary) -> void:
	if model == null:
		return
	if owns_model:
		model.update(delta, ctx)
	var torque: float = absf(float(model.torque))
	var rumble: float = clampf(float(model.rumble), 0.0, 1.0)
	var pulse: float = clampf(float(model.pulse), 0.0, 1.0)
	source = String(model.source)
	# Die Kamera soll die Kraft spueren, nicht das Rauschen: Ruetteln zaehlt
	# nur mit einem Drittel, ein Aufprall voll.
	var target: float = clampf(maxf(torque * 0.85, maxf(rumble * 0.35, pulse * 0.7)), 0.0, 1.0)
	strength = lerpf(strength, target, clampf(delta * 12.0, 0.0, 1.0))
	_drive(strength, ctx)


func _drive(amount: float, ctx: Dictionary) -> void:
	if wheel != null:
		var raw_device = wheel.get("device")
		var device: int = int(raw_device) if raw_device != null else -1
		if device >= 0 and amount > 0.02:
			Input.start_joy_vibration(device, amount * 0.6, amount, 0.08)
	if _bridge_on:
		_bridge_cd -= 0.011
		if _bridge_cd <= 0.0:
			_bridge_cd = 0.033
			bridge_state(amount, ctx)


## Optional channel for a real force-feedback driver. One small JSON file per
## physics tick; nothing reads it unless the driver is running. Kept for
## compatibility with older external tools - the real wheel is driven by
## `ffb_link.gd` (UDP) now.
func bridge_state(amount: float, ctx: Dictionary) -> void:
	var f := FileAccess.open(BRIDGE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"strength": snappedf(amount, 0.001),
		"torque": snappedf(float(model.torque), 0.001) if model else 0.0,
		"source": source,
		"speed": snappedf(float(ctx.get("speed", 0.0)), 0.1),
		"lateral_g": snappedf(float(ctx.get("lateral_g", 0.0)), 0.01),
		"event": last_event,
	}))
	f.close()
