extends Node
## Logitech G29 (and compatible) wheel, three pedals and paddle shifters.
##
## Everything is learned from the device instead of assumed: the module samples
## the rest position of every axis, remembers the value reached when a pedal is
## pressed and maps linearly in between. That survives drivers that report
## released = +1, released = -1 or even a frozen 0.0, and it is what fixes the
## "gas shows up as brake" problem.
##
## Public API (used by the HUD and the menu/calibration screen):
##   signals  connection_changed, calibrated, calibration_step_changed,
##            shift_up, shift_down
##   state    device, device_name, connected, steer, throttle, brake, clutch,
##            steer_axis, throttle_axis, brake_axis, clutch_axis, invert_*,
##            steer_invert, steer_deadzone, cal_phase (0..5), cal_hint,
##            axes_live, hardware_hint
##   methods  begin_calibration(), begin_pedal_calibration(which),
##            begin_steer_calibration(), skip_calibration(),
##            cancel_calibration(), reset_to_defaults(), save_profile(),
##            load_profile(), apply_manual(which, axis, invert),
##            axis_snapshot(), axis_moved(), has_axis_data(), has_driver_input()

signal connection_changed(connected: bool, device_name: String)
signal calibrated
signal calibration_step_changed(step: int, hint: String)
signal shift_up
signal shift_down

const PROFILE_PATH := "user://g29_profile.json"
const PROFILE_VERSION := 2
const AXES := 12
const BUTTONS := 24
const PADDLE_UP := [4, 10]   ## right paddle
const PADDLE_DOWN := [5, 9]  ## left paddle
const DEVICE_HINTS := ["g29", "g920", "g923", "driving force", "trueforce", "logitech"]

const REST_TIME := 0.8        ## seconds of rest sampling before calibration
const DETECT_MIN := 0.25      ## smallest movement that counts at all
const DETECT_GOOD := 0.55     ## "pedal fully pressed" movement
const DETECT_TIMEOUT := 8.0   ## accept a half press after this long
const DEADZONE_DEFAULT := 0.03

## ---- device state ---------------------------------------------------------
var device: int = -1
var device_name: String = ""
var connected: bool = false

var steer: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var clutch: float = 0.0

## ---- mapping --------------------------------------------------------------
var steer_axis: int = 0
var throttle_axis: int = 1
var brake_axis: int = 2
var clutch_axis: int = 3
var invert_throttle: bool = true
var invert_brake: bool = true
var invert_clutch: bool = true
var steer_invert: bool = false
var steer_deadzone: float = DEADZONE_DEFAULT
var steer_locked: bool = false

## ---- calibration ----------------------------------------------------------
var cal_phase: int = 0        ## 0 idle, 1 rest sampling, 2 waiting, 5 done
var cal_hint: String = ""
var cal_target: String = "all"

## ---- diagnostics ----------------------------------------------------------
var axes_live: bool = true
var hardware_hint: String = ""
var last_axis_moved: int = -1

## ---- test hooks -----------------------------------------------------------
var sim_enabled: bool = false
var sim_axes: PackedFloat32Array = PackedFloat32Array()
var auto_load_profile: bool = true
var profile_path: String = PROFILE_PATH

var _raw: PackedFloat32Array = PackedFloat32Array()
var _prev_raw: PackedFloat32Array = PackedFloat32Array()
var _axis_seen_motion: PackedByteArray = PackedByteArray()
var _prev_buttons: PackedByteArray = PackedByteArray()
var _rest: PackedFloat32Array = PackedFloat32Array()
var _pedal_rest: Dictionary = {}     ## "throttle"/"brake"/"clutch" -> float
var _pedal_press: Dictionary = {}    ## value when fully pressed
var _steer_rest: float = 0.0
var _steer_span: float = 0.0         ## signed: rest + span == full right
var _steer_right: float = 0.0
var _cal_queue: Array = []
var _cal_assigned: Array = []
var _cal_timer: float = 0.0
var _cal_rest_frames: int = 0
var _cal_peak_dev: float = 0.0
var _cal_peak_value: float = 0.0
var _live_timer: float = 0.0
var _live_checked: bool = false
var _profile_loaded: bool = false
## True once the device has delivered at least one believable axis value. A G29
## that was just plugged in (or that has not sent its first HID report yet)
## reports a flat 0.0 on every axis, and those zeros must never be mistaken for
## real pedal positions - that is what made all three pedals read 100 %.
var _have_data: bool = false
var _auto_rest: Dictionary = {}    ## pedal -> sampled rest position
var _auto_press: Dictionary = {}   ## pedal -> extreme reached while pressing
## Set when the mapping learned something new (a longer pedal travel or a
## corrected rest position); written to disk a few seconds later.
var _profile_dirty: bool = false
var _save_timer: float = 0.0


func _ready() -> void:
	_raw.resize(AXES)
	_prev_raw.resize(AXES)
	_rest.resize(AXES)
	_axis_seen_motion.resize(AXES)
	_prev_buttons.resize(BUTTONS)
	sim_axes.resize(AXES)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_rescan()
	if auto_load_profile:
		load_profile()
	# Rest positions of whatever axes we can already see, so pedals work even
	# before the driver opens the settings screen. A stored profile wins: its
	# rest points were sampled during calibration, and the driver might already
	# be resting a foot on a pedal right now.
	for i in AXES:
		_rest[i] = _raw_axis(i)
		if _profile_loaded:
			continue
		_steer_rest = _rest[i] if i == steer_axis else _steer_rest
		if i == throttle_axis:
			_pedal_rest["throttle"] = _rest[i]
		elif i == brake_axis:
			_pedal_rest["brake"] = _rest[i]
		elif i == clutch_axis:
			_pedal_rest["clutch"] = _rest[i]
	cal_phase = 5
	cal_hint = ""


func _process(delta: float) -> void:
	step(delta)


## One input step. Called from _process; tests call it directly.
func step(delta: float) -> void:
	if device < 0 and not sim_enabled:
		steer = 0.0
		throttle = 0.0
		brake = 0.0
		clutch = 0.0
		_scan_axes(delta)
		return
	_sample()
	_scan_axes(delta)
	if cal_phase > 0 and cal_phase < 5:
		_run_cal(delta)
	else:
		_apply_mapping()
	_read_paddles()
	if _profile_dirty:
		_save_timer += delta
		if _save_timer > 3.0:
			save_profile()
			_profile_dirty = false
			_save_timer = 0.0


func has_driver_input() -> bool:
	return connected and (absf(steer) > 0.12 or throttle > 0.08 or brake > 0.08)


func axis_snapshot() -> PackedFloat32Array:
	return _raw


func axis_moved() -> int:
	return last_axis_moved


## True as soon as the device has delivered one believable sample. A G29 that
## only enumerates reports a flat 0.0 on every axis, so "connected" alone does
## not mean the wheel is really talking to us.
func has_axis_data() -> bool:
	return _have_data


## ---- raw input ------------------------------------------------------------

func _raw_axis(index: int) -> float:
	if sim_enabled:
		return sim_axes[index] if index < sim_axes.size() else 0.0
	if device < 0:
		return 0.0
	return Input.get_joy_axis(device, index)


func _sample() -> void:
	for i in AXES:
		_prev_raw[i] = _raw[i]
		_raw[i] = _raw_axis(i)
		if absf(_raw[i] - _prev_raw[i]) > 0.005:
			_axis_seen_motion[i] = 1
	if not _have_data:
		for i in AXES:
			if absf(_raw[i]) > 0.02:
				_have_data = true
				_anchor_auto_rest()
				break


func _anchor_auto_rest() -> void:
	## First believable sample: the pedals are released, so this is their rest
	## position. Only used when the driver has not calibrated yet.
	for name in ["throttle", "brake", "clutch"]:
		_auto_rest[name] = _raw[_axis_of(name)]
	if not steer_locked:
		_steer_rest = _raw[steer_axis]
	# A profile written by an older, broken build can claim a rest of 0.0 where
	# the pedal really sits at 1.0. Trust the live device for the rest position
	# (the pedals are released when the game starts) and keep the calibrated
	# range, shifted along with it.
	if _profile_loaded:
		for name in ["throttle", "brake", "clutch"]:
			if not (_pedal_rest.has(name) and _pedal_press.has(name)):
				## A manual axis change before the first HID report erases both
				## points; re-anchor on the live device instead of keeping the
				## flat zeros that the G29 sends while it is still waking up.
				_auto_rest[name] = _raw[_axis_of(name)]
				continue
			var stored_rest: float = float(_pedal_rest[name])
			var stored_press: float = float(_pedal_press[name])
			var now: float = _raw[_axis_of(name)]
			if absf(now - stored_rest) > 0.5:
				_pedal_rest[name] = now
				_pedal_press[name] = now + (stored_press - stored_rest)
				_profile_dirty = true
				print("G29 profile rest for %s corrected: %.2f -> %.2f" % [name, stored_rest, now])
	print("G29 data arrived: rest gas=%.2f brake=%.2f clutch=%.2f steer=%.2f" % [
		_auto_rest.get("throttle", 0.0), _auto_rest.get("brake", 0.0),
		_auto_rest.get("clutch", 0.0), _steer_rest])


func _scan_axes(delta: float) -> void:
	## Detect a device that enumerates but delivers no data at all.
	if not connected:
		return
	if _have_data or _any_axis_moved():
		if not axes_live:
			axes_live = true
			hardware_hint = ""
	if _live_checked:
		return
	_live_timer += delta
	# A G29 stays completely quiet until something moves, so give it a few
	# seconds before calling it silent.
	if _live_timer < 6.0:
		return
	_live_checked = true
	if not _any_axis_moved():
		axes_live = false
		hardware_hint = ("G29 erkannt, aber noch keine Achsendaten — "
			+ "Lenkrad/Pedal einmal bewegen; sonst Netzteil und Pedalkabel prüfen.")


func _any_axis_moved() -> bool:
	for i in AXES:
		if _axis_seen_motion[i] == 1:
			return true
	return false


## ---- mapping --------------------------------------------------------------

func _apply_mapping() -> void:
	# The device reports a flat 0.0 on every axis until its first HID report
	# arrives. Feeding those zeros into a stored calibration computes nonsense
	# (with rest = 1.0 and press = 0.43 a raw 0.0 means "fully pressed"), which
	# is what made all three pedals read 100 % during the first seconds.
	if not _have_data:
		throttle = 0.0
		brake = 0.0
		clutch = 0.0
		steer = 0.0
		return
	last_axis_moved = -1
	var best := 0.02
	for i in AXES:
		var d: float = absf(_raw[i] - _rest[i])
		if d > best:
			best = d
			last_axis_moved = i
	throttle = _pedal_value("throttle", throttle_axis)
	brake = _pedal_value("brake", brake_axis)
	clutch = _pedal_value("clutch", clutch_axis)
	invert_throttle = _pedal_press.get("throttle", _pedal_rest.get("throttle", 0.0) - 1.0) < _pedal_rest.get("throttle", 0.0)
	invert_brake = _pedal_press.get("brake", _pedal_rest.get("brake", 0.0) - 1.0) < _pedal_rest.get("brake", 0.0)
	invert_clutch = _pedal_press.get("clutch", _pedal_rest.get("clutch", 0.0) - 1.0) < _pedal_rest.get("clutch", 0.0)
	_apply_steer()


func _pedal_value(name: String, axis: int) -> float:
	if axis < 0 or axis >= AXES:
		return 0.0
	var v: float = _raw[axis]
	# A calibrated pedal always wins.
	if _pedal_press.has(name) and _pedal_rest.has(name):
		var c_rest: float = float(_pedal_rest[name])
		var c_press: float = float(_pedal_press[name])
		var c_span: float = c_press - c_rest
		if absf(c_span) < 0.15:
			# Implausible calibration (a pedal travels much further than that):
			# fall through to the automatic mapping instead of believing it.
			_pedal_press.erase(name)
		else:
			# Learn a longer travel: the driver often presses harder during the
			# race than during calibration, and a mapped range that is too short
			# makes the pedal reach 100 % far too early.
			var c_dev: float = v - c_rest
			if absf(c_dev) > absf(c_span) and signf(c_dev) == signf(c_span):
				_pedal_press[name] = v
				c_span = c_dev
				_profile_dirty = true
			return clampf(c_dev / c_span, 0.0, 1.0)
	# Before calibration: anchor on the first believable sample (pedals
	# released) and extend towards the far end while the driver presses.
	if not _auto_rest.has(name):
		return 0.0
	var rest: float = float(_auto_rest[name])
	var dev: float = v - rest
	if not _auto_press.has(name):
		if absf(dev) > 0.05:
			_auto_press[name] = v
		else:
			return 0.0
	elif absf(dev) > absf(float(_auto_press[name]) - rest):
		# driver pushes further than anything seen so far
		_auto_press[name] = v
	var press: float = float(_auto_press[name])
	var span: float = press - rest
	if absf(span) < 0.05:
		return 0.0
	var value: float = dev / span
	return clampf(value, 0.0, 1.0)


func _apply_steer() -> void:
	var v: float = _raw[steer_axis]
	var dev: float = v - _steer_rest
	# Learn a bigger lock: the driver may turn the wheel much further than he did
	# during calibration, and a short range makes the steering twitchy.
	if absf(dev) > _steer_span * 1.02 and absf(dev) > 0.05:
		_steer_span = absf(dev)
		_profile_dirty = true
	var s: float = 0.0
	if absf(_steer_span) > 0.05:
		s = clampf(dev / _steer_span, -1.0, 1.0)
	if steer_invert:
		s = -s
	if absf(s) < steer_deadzone:
		s = 0.0
	else:
		s = signf(s) * ((absf(s) - steer_deadzone) / maxf(1.0 - steer_deadzone, 0.01))
	steer = clampf(s, -1.0, 1.0)


## ---- calibration ----------------------------------------------------------

func begin_calibration() -> void:
	_start_cal("all")


func begin_pedal_calibration(which: String) -> void:
	_start_cal(which if which in ["throttle", "brake", "clutch"] else "all")


func begin_steer_calibration() -> void:
	_start_cal("steer")


func _start_cal(target: String) -> void:
	if device < 0 and not sim_enabled:
		cal_phase = 0
		cal_hint = "Kein Lenkrad gefunden — bitte G29 anschließen (USB und Netzteil)."
		calibration_step_changed.emit(0, cal_hint)
		return
	cal_target = target
	_cal_queue.clear()
	_cal_assigned.clear()
	if target == "all":
		_cal_queue = ["throttle", "brake", "clutch"]
	elif target in ["throttle", "brake", "clutch"]:
		_cal_queue = [target]
	_cal_timer = 0.0
	_cal_rest_frames = 0
	_cal_peak_dev = 0.0
	for i in AXES:
		_rest[i] = 0.0
	_set_step(1, "Pedale loslassen und Lenkrad nicht anfassen — Ruhewerte werden gemessen…")


func _set_step(phase: int, hint: String) -> void:
	cal_phase = phase
	cal_hint = hint
	calibration_step_changed.emit(phase, hint)


func _run_cal(delta: float) -> void:
	_cal_timer += delta
	match cal_phase:
		1:
			if not _have_data:
				# Nothing believable has arrived yet: sampling a flat line of
				# zeros as "rest" would invert the whole pedal afterwards.
				_cal_timer = 0.0
				var wait_hint := "Bitte einmal Pedal oder Lenkrad bewegen — es kommen noch keine Daten vom Lenkrad an…"
				if cal_hint != wait_hint:
					_set_step(1, wait_hint)
				return
			for i in AXES:
				_rest[i] += _raw[i]
			_cal_rest_frames += 1
			if _cal_timer >= REST_TIME and _cal_rest_frames > 0:
				for i in AXES:
					_rest[i] /= float(_cal_rest_frames)
				_steer_rest = _rest[steer_axis]
				_cal_timer = 0.0
				_cal_peak_dev = 0.0
				if cal_target == "steer":
					_set_step(2, "Lenkrad GANZ nach rechts drehen und dort halten…")
				else:
					_set_step(2, "%s — Pedal voll durchtreten" % _pedal_hint(_next_pedal()))
		2:
			var axis := _detect_axis()
			if axis >= 0:
				if cal_target == "steer":
					_finish_steer(axis)
				else:
					_finish_pedal(_next_pedal(), axis)


func _next_pedal() -> String:
	return String(_cal_queue[0]) if not _cal_queue.is_empty() else "throttle"


func _pedal_hint(name: String) -> String:
	match name:
		"throttle":
			return "GAS (rechtes Pedal)"
		"brake":
			return "BREMSE (mittleres Pedal)"
		_:
			return "KUPPLUNG (linkes Pedal)"


func _detect_axis() -> int:
	var exclude: Array = []
	if cal_target != "steer":
		exclude.append(steer_axis)
		for ax in _cal_assigned:
			exclude.append(ax)
	var best := -1
	var best_dev := 0.0
	for i in AXES:
		if i in exclude:
			continue
		var d: float = absf(_raw[i] - _rest[i])
		if d > best_dev:
			best_dev = d
			best = i
	if best >= 0 and best_dev > _cal_peak_dev:
		_cal_peak_dev = best_dev
		_cal_peak_value = _raw[best]
	if best_dev >= DETECT_GOOD:
		return best
	if best_dev >= DETECT_MIN and _cal_timer > DETECT_TIMEOUT:
		return best
	return -1


func _finish_pedal(name: String, axis: int) -> void:
	_pedal_rest[name] = _rest[axis]
	_pedal_press[name] = _cal_peak_value
	_set_axis_of(name, axis)
	_cal_assigned.append(axis)
	_cal_queue.erase(name)
	_cal_timer = 0.0
	_cal_peak_dev = 0.0
	if _cal_queue.is_empty():
		_finish_cal()
	else:
		_set_step(2, "%s — Pedal voll durchtreten" % _pedal_hint(_next_pedal()))


func _finish_steer(axis: int) -> void:
	steer_axis = axis
	_steer_rest = _rest[axis]
	_steer_right = _cal_peak_value
	var span: float = _cal_peak_value - _steer_rest
	if absf(span) < 0.1:
		_set_step(2, "Bewegung war zu klein — Lenkrad bitte weiter nach rechts drehen…")
		return
	steer_invert = span < 0.0
	_steer_span = absf(span)
	_finish_cal()


func _finish_cal() -> void:
	_set_step(5, "")
	save_profile()
	calibrated.emit()
	print("G29 cal steer=", steer_axis, " gas=", throttle_axis, " brake=", brake_axis,
		" clutch=", clutch_axis, " steer_invert=", steer_invert)


func skip_calibration() -> void:
	_set_step(5, "")
	save_profile()
	calibrated.emit()


func cancel_calibration() -> void:
	_cal_queue.clear()
	_set_step(0, "")


func reset_to_defaults() -> void:
	## "Standardwerte" must NOT throw away the axes the driver taught the game:
	## on this wheel the pedals are 2/3/1, not 1/2/3, so resetting them would
	## swap gas and clutch. It clears the learned points instead - the automatic
	## mapping then re-anchors on the live device, and the guided calibration
	## re-detects the axes if they really are wrong.
	steer_invert = false
	steer_deadzone = DEADZONE_DEFAULT
	_steer_span = 0.0
	_pedal_rest.clear()
	_pedal_press.clear()
	_auto_rest.clear()
	_auto_press.clear()
	_have_data = false
	for i in AXES:
		_rest[i] = _raw_axis(i)
	_steer_rest = _rest[steer_axis]
	invert_throttle = true
	invert_brake = true
	invert_clutch = true
	save_profile()


func apply_manual(which: String, axis: int, invert: bool) -> void:
	match which:
		"steer":
			steer_axis = clampi(axis, 0, AXES - 1)
			steer_invert = invert
			_steer_rest = _raw_axis(steer_axis)
			_steer_span = 0.0
		"throttle", "brake", "clutch":
			_set_axis_of(which, clampi(axis, 0, AXES - 1))
			_pedal_press.erase(which)
			_raw_pedal_reset(which, invert)
	save_profile()


func _raw_pedal_reset(which: String, invert: bool) -> void:
	## Manual assignment: the current value becomes the released position, the
	## pressed end is learned from the driver's first press, so the direction can
	## never be wrong and `invert` is not needed for pedals.
	var ax: int = _axis_of(which)
	_pedal_rest.erase(which)
	_auto_rest[which] = _raw_axis(ax)
	_auto_press.erase(which)


func _axis_of(name: String) -> int:
	match name:
		"throttle":
			return throttle_axis
		"brake":
			return brake_axis
		"clutch":
			return clutch_axis
	return -1


func _set_axis_of(name: String, axis: int) -> void:
	match name:
		"throttle":
			throttle_axis = axis
		"brake":
			brake_axis = axis
		"clutch":
			clutch_axis = axis


## ---- persistence ----------------------------------------------------------

func save_profile() -> void:
	## A simulated run (headless test, diagnostic probe, scratch script) must
	## never overwrite the driver's real profile: every value it produces is
	## invented, and a fabricated pedal travel silently ruins the mapping the
	## driver calibrated by hand.
	if sim_enabled and profile_path == PROFILE_PATH:
		return
	var data := {
		"version": PROFILE_VERSION,
		"device": device_name,
		"steer_axis": steer_axis,
		"throttle_axis": throttle_axis,
		"brake_axis": brake_axis,
		"clutch_axis": clutch_axis,
		"steer_invert": steer_invert,
		"steer_deadzone": steer_deadzone,
		"steer_rest": _steer_rest,
		"steer_span": _steer_span,
		"throttle_rest": float(_pedal_rest.get("throttle", 0.0)),
		"throttle_press": float(_pedal_press.get("throttle", 0.0)),
		"brake_rest": float(_pedal_rest.get("brake", 0.0)),
		"brake_press": float(_pedal_press.get("brake", 0.0)),
		"clutch_rest": float(_pedal_rest.get("clutch", 0.0)),
		"clutch_press": float(_pedal_press.get("clutch", 0.0)),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(profile_path, FileAccess.WRITE)
	if f == null:
		push_warning("G29 profile not writable: " + profile_path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("G29 profile saved: ", data)


func load_profile() -> bool:
	if not FileAccess.file_exists(profile_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("G29 profile corrupt — using defaults")
		return false
	var d: Dictionary = parsed
	steer_axis = int(d.get("steer_axis", steer_axis))
	throttle_axis = int(d.get("throttle_axis", throttle_axis))
	brake_axis = int(d.get("brake_axis", brake_axis))
	clutch_axis = int(d.get("clutch_axis", clutch_axis))
	steer_invert = bool(d.get("steer_invert", steer_invert))
	steer_deadzone = float(d.get("steer_deadzone", steer_deadzone))
	_steer_rest = float(d.get("steer_rest", _raw_axis(steer_axis)))
	_steer_span = float(d.get("steer_span", 0.0))
	for name in ["throttle", "brake", "clutch"]:
		var rest_key: String = str(name) + "_rest"
		var press_key: String = str(name) + "_press"
		# Only believe a stored calibration when both points exist and the
		# travel between them is long enough to be a real pedal.
		if d.has(rest_key) and d.has(press_key):
			var r: float = float(d[rest_key])
			var p: float = float(d[press_key])
			if absf(p - r) >= 0.15:
				_pedal_rest[name] = r
				_pedal_press[name] = p
	for name in ["throttle", "brake", "clutch"]:
		_auto_rest.erase(name)
		_auto_press.erase(name)
	_profile_loaded = true
	print("G29 profile loaded: gas=", throttle_axis, " brake=", brake_axis,
		" clutch=", clutch_axis, " steer=", steer_axis, " invert=", steer_invert)
	return true


## ---- device discovery -----------------------------------------------------

func _on_joy_changed(_id: int, _is_connected: bool) -> void:
	_rescan()


func _rescan() -> void:
	if sim_enabled:
		return
	var previous := device
	device = -1
	device_name = ""
	var fallback := -1
	var fallback_name := ""
	for id in Input.get_connected_joypads():
		var n := Input.get_joy_name(id)
		var low := n.to_lower()
		var matched := false
		for hint in DEVICE_HINTS:
			if hint in low:
				matched = true
				break
		if matched:
			device = id
			device_name = n
			break
		if fallback < 0:
			fallback = id
			fallback_name = n
	if device < 0 and fallback >= 0:
		# A wheel we do not know by name is still better than nothing.
		device = fallback
		device_name = fallback_name
	connected = device >= 0
	if device != previous:
		_live_timer = 0.0
		_live_checked = false
		axes_live = true
		hardware_hint = ""
		for i in AXES:
			_axis_seen_motion[i] = 0
		connection_changed.emit(connected, device_name)
		print("G29Input device=", device, " name=", device_name, " connected=", connected)
		if connected and cal_phase > 0 and cal_phase < 5:
			_set_step(1, "Pedale loslassen — Ruhewerte werden gemessen…")


func _read_paddles() -> void:
	for i in BUTTONS:
		var down: bool = false
		if sim_enabled:
			down = false
		elif device >= 0:
			down = Input.is_joy_button_pressed(device, i)
		var was: bool = _prev_buttons[i] == 1
		if down and not was:
			if i in PADDLE_UP:
				shift_up.emit()
			if i in PADDLE_DOWN:
				shift_down.emit()
		_prev_buttons[i] = 1 if down else 0


## ---- test helpers ---------------------------------------------------------

func enable_sim() -> void:
	sim_enabled = true
	sim_axes.resize(AXES)
	for i in AXES:
		sim_axes[i] = 0.0
	device = 0
	device_name = "SIM WHEEL"
	connected = true


func sim_set(axis: int, value: float) -> void:
	if axis >= 0 and axis < AXES:
		sim_axes[axis] = value
