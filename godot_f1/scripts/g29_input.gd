extends Node
## Logitech G29 / G920 / G923 (and generic wheels) via Godot joypad axes.

signal connection_changed(connected: bool, device_name: String)

var device: int = -1
var device_name: String = ""
var connected: bool = false
var steer: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var clutch: float = 0.0

@export var steer_axis: int = 0
@export var throttle_axis: int = 1
@export var brake_axis: int = 2
@export var clutch_axis: int = 3
@export var invert_throttle: bool = true
@export var invert_brake: bool = true
@export var invert_clutch: bool = true
@export var steer_deadzone: float = 0.03


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed)
	_rescan()


func _process(_delta: float) -> void:
	if device < 0:
		steer = 0.0
		throttle = 0.0
		brake = 0.0
		clutch = 0.0
		return
	var raw_steer := Input.get_joy_axis(device, steer_axis)
	if abs(raw_steer) < steer_deadzone:
		steer = 0.0
	else:
		steer = clampf(raw_steer, -1.0, 1.0)
	throttle = _pedal(Input.get_joy_axis(device, throttle_axis), invert_throttle)
	brake = _pedal(Input.get_joy_axis(device, brake_axis), invert_brake)
	clutch = _pedal(Input.get_joy_axis(device, clutch_axis), invert_clutch)


func has_driver_input() -> bool:
	return connected and (abs(steer) > 0.12 or throttle > 0.08 or brake > 0.08)


func _pedal(v: float, invert: bool) -> float:
	if invert:
		v = -v
	return clampf((v + 1.0) * 0.5, 0.0, 1.0)


func _on_joy_changed(_id: int, _connected: bool) -> void:
	_rescan()


func _rescan() -> void:
	var prev := device
	device = -1
	device_name = ""
	for id in Input.get_connected_joypads():
		var n := Input.get_joy_name(id)
		var low := n.to_lower()
		if "g29" in low or "g920" in low or "g923" in low or "driving force" in low or "trueforce" in low:
			device = id
			device_name = n
			break
	connected = device >= 0
	if device != prev:
		connection_changed.emit(connected, device_name)
		print("G29Input device=", device, " name=", device_name)
