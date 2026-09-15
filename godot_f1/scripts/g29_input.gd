extends Node
## Logitech G29: wheel, 3 pedals (right gas, middle brake, left clutch), paddles.

signal connection_changed(connected: bool, device_name: String)
signal calibrated
signal shift_up
signal shift_down

const CAL_PATH := "user://g29_cal.json"
const PADDLE_UP := [4, 10] ## right paddle (DirectInput 4, XInput shoulder fallback)
const PADDLE_DOWN := [5, 9] ## left paddle

var device: int = -1
var device_name: String = ""
var connected: bool = false
var steer: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var clutch: float = 0.0

var steer_axis: int = 0
var throttle_axis: int = 1
var brake_axis: int = 2
var clutch_axis: int = 3
var invert_throttle: bool = true
var invert_brake: bool = true
var invert_clutch: bool = true
var steer_deadzone: float = 0.025

## Calibration: 0 idle, 1 sample rest, 2 gas, 3 brake, 4 clutch, 5 done
var cal_phase: int = 0
var cal_hint: String = ""
var rest: PackedFloat32Array = PackedFloat32Array()
var _cal_timer: float = 0.0
var _prev_buttons: PackedByteArray = PackedByteArray()
var _axis_debug: String = ""


func _ready() -> void:
	rest.resize(8)
	_prev_buttons.resize(16)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_rescan()
	if connected:
		if _load_cal():
			cal_phase = 5
			cal_hint = ""
		else:
			cal_phase = 1
			_cal_timer = 0.0
			cal_hint = "Pedale loslassen — Kalibrierung startet…"


func _process(delta: float) -> void:
	if device < 0:
		steer = 0.0
		throttle = 0.0
		brake = 0.0
		clutch = 0.0
		_axis_debug = "kein G29"
		return
	_read_axes()
	_read_paddles()
	if cal_phase > 0 and cal_phase < 5:
		_run_cal(delta)


func has_driver_input() -> bool:
	return connected and cal_phase >= 5 and (abs(steer) > 0.12 or throttle > 0.08 or brake > 0.08)


func skip_calibration() -> void:
	if cal_phase >= 5:
		return
	_guess_pedal_axes()
	cal_phase = 5
	cal_hint = ""
	_save_cal()
	calibrated.emit()


func _guess_pedal_axes() -> void:
	var pedals: Array = []
	for i in 8:
		if i == steer_axis:
			continue
		var v: float = Input.get_joy_axis(device, i) if device >= 0 else 0.0
		if abs(v) > 0.62:
			pedals.append(i)
	if pedals.size() >= 3:
		throttle_axis = int(pedals[0])
		brake_axis = int(pedals[1])
		clutch_axis = int(pedals[2])
	else:
		throttle_axis = 1
		brake_axis = 2
		clutch_axis = 3
		if device >= 0:
			if abs(Input.get_joy_axis(device, 2)) < 0.4 and abs(Input.get_joy_axis(device, 5)) > 0.6:
				brake_axis = 5
			if abs(Input.get_joy_axis(device, 3)) < 0.4 and abs(Input.get_joy_axis(device, 6)) > 0.6:
				clutch_axis = 6
	invert_throttle = true
	invert_brake = true
	invert_clutch = true


func _read_axes() -> void:
	var raw_steer := Input.get_joy_axis(device, steer_axis)
	steer = 0.0 if abs(raw_steer) < steer_deadzone else clampf(raw_steer, -1.0, 1.0)
	if cal_phase >= 5 or cal_phase == 0:
		throttle = _pedal(Input.get_joy_axis(device, throttle_axis), invert_throttle)
		brake = _pedal(Input.get_joy_axis(device, brake_axis), invert_brake)
		clutch = _pedal(Input.get_joy_axis(device, clutch_axis), invert_clutch)
	var parts: PackedStringArray = PackedStringArray()
	for i in 8:
		parts.append("a%d=%.2f" % [i, Input.get_joy_axis(device, i)])
	_axis_debug = " ".join(parts)


func _pedal(v: float, invert: bool) -> float:
	if invert:
		v = -v
	return clampf((v + 1.0) * 0.5, 0.0, 1.0)


func _read_paddles() -> void:
	for i in 16:
		var down := Input.is_joy_button_pressed(device, i)
		var was: bool = _prev_buttons[i] == 1
		if down and not was:
			if i in PADDLE_UP:
				shift_up.emit()
			if i in PADDLE_DOWN:
				shift_down.emit()
		_prev_buttons[i] = 1 if down else 0


func _run_cal(delta: float) -> void:
	_cal_timer += delta
	match cal_phase:
		1:
			cal_hint = "Alle Pedale loslassen…"
			if _cal_timer > 0.7:
				for i in 8:
					rest[i] = Input.get_joy_axis(device, i)
				cal_phase = 2
				_cal_timer = 0.0
		2:
			cal_hint = "GAS — rechtes Pedal voll durchtreten"
			var ax := _moved_axis([])
			if ax >= 0:
				throttle_axis = ax
				invert_throttle = rest[ax] > 0.15
				cal_phase = 3
				_cal_timer = 0.0
		3:
			cal_hint = "BREMSE — mittleres Pedal voll durchtreten"
			var ax2 := _moved_axis([throttle_axis])
			if ax2 >= 0:
				brake_axis = ax2
				invert_brake = rest[ax2] > 0.15
				cal_phase = 4
				_cal_timer = 0.0
		4:
			cal_hint = "KUPPLUNG — linkes Pedal voll durchtreten"
			var ax3 := _moved_axis([throttle_axis, brake_axis])
			if ax3 >= 0:
				clutch_axis = ax3
				invert_clutch = rest[ax3] > 0.15
				cal_phase = 5
				cal_hint = ""
				_save_cal()
				calibrated.emit()
				print("G29 cal gas=", throttle_axis, " brake=", brake_axis, " clutch=", clutch_axis)


func _moved_axis(exclude: Array) -> int:
	if _cal_timer < 0.25:
		return -1
	var best := -1
	var best_d := 0.28
	for i in 8:
		if i == steer_axis or i in exclude:
			continue
		var d: float = abs(Input.get_joy_axis(device, i) - rest[i])
		if d > best_d:
			best_d = d
			best = i
	return best


func _save_cal() -> void:
	var f := FileAccess.open(CAL_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"throttle_axis": throttle_axis,
		"brake_axis": brake_axis,
		"clutch_axis": clutch_axis,
		"invert_throttle": invert_throttle,
		"invert_brake": invert_brake,
		"invert_clutch": invert_clutch,
		"steer_axis": steer_axis,
	}))


func _load_cal() -> bool:
	if not FileAccess.file_exists(CAL_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAL_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	throttle_axis = int(d.get("throttle_axis", 1))
	brake_axis = int(d.get("brake_axis", 2))
	clutch_axis = int(d.get("clutch_axis", 3))
	invert_throttle = bool(d.get("invert_throttle", true))
	invert_brake = bool(d.get("invert_brake", true))
	invert_clutch = bool(d.get("invert_clutch", true))
	steer_axis = int(d.get("steer_axis", 0))
	return true


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
		if connected and cal_phase == 0 and not _load_cal():
			cal_phase = 1
			_cal_timer = 0.0
