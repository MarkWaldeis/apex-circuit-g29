extends RefCounted
## What the driver feels through the wheel.
##
## Godot exposes no force feedback API, so this module computes the intensity
## and hands it to everything that CAN react today: the HUD, the camera and
## `Input.start_joy_vibration` (a no-op on a G29, which has no rumble motors,
## but correct on any pad). `bridge_state()` writes the same numbers to
## `user://ffb_state.json` so an optional external driver can turn them into a
## real constant force.
##
## OWNER: agent CRASH.

const BRIDGE_PATH := "user://ffb_state.json"

var car
var wheel
var strength: float = 0.0
var last_event: String = ""
var _impulse: float = 0.0
## The JSON bridge is opt-in (launcher sets APEX_FFB=1), so a normal double-click
## start does no extra file I/O at all.
var _bridge_on: bool = OS.get_environment("APEX_FFB") == "1"
var _bridge_cd: float = 0.0


func setup(owner_car, wheel_input) -> void:
	car = owner_car
	wheel = wheel_input
	if wheel and wheel.has_signal("shift_up") and not wheel.shift_up.is_connected(_on_shift):
		wheel.shift_up.connect(_on_shift)
		wheel.shift_down.connect(_on_shift)


func _on_shift() -> void:
	poke("shift", 0.35)


func poke(kind: String, severity: float) -> void:
	last_event = kind
	_impulse = maxf(_impulse, clampf(severity, 0.0, 1.0))


func update(delta: float, ctx: Dictionary) -> void:
	_impulse = maxf(_impulse - delta * 2.0, 0.0)
	var surface: Dictionary = ctx.get("surface", {})
	var rumble: float = float(surface.get("rumble", 0.0))
	var speed: float = float(ctx.get("speed", 0.0))
	var speed_scale: float = clampf(speed / 30.0, 0.0, 1.0)
	var slip: float = clampf(float(ctx.get("slip", 0.0)), 0.0, 1.0)
	var target: float = maxf(_impulse, maxf(rumble * speed_scale * 0.8, slip * 0.55))
	strength = lerpf(strength, clampf(target, 0.0, 1.0), clampf(delta * 12.0, 0.0, 1.0))
	_drive(strength, ctx)


func _drive(amount: float, ctx: Dictionary) -> void:
	if wheel == null:
		return
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
## physics tick; nothing reads it unless the driver is running.
func bridge_state(amount: float, ctx: Dictionary) -> void:
	var f := FileAccess.open(BRIDGE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"strength": snappedf(amount, 0.001),
		"speed": snappedf(float(ctx.get("speed", 0.0)), 0.1),
		"lateral_g": snappedf(float(ctx.get("lateral_g", 0.0)), 0.01),
		"event": last_event,
	}))
	f.close()
