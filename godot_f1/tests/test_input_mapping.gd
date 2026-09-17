extends SceneTree
## Gating test for the G29 input module: pedal maths for every polarity the
## driver can report, steering scale/deadzone/invert, the guided calibration
## (rest sample -> full press -> remembered), profile round trip and the
## "device connected but silent" detector.

const G29 = preload("res://scripts/g29_input.gd")

var g
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _near(a: float, b: float, eps: float = 0.02) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	g = G29.new()
	g.auto_load_profile = false
	g.profile_path = "user://g29_profile_test.json"
	g.enable_sim()
	root.add_child(g)

	_pedal_polarities()
	_steer_math()
	_guided_pedal_calibration()
	_guided_steer_calibration()
	_profile_round_trip()
	_silent_device_detector()

	if failed > 0:
		print("INPUT_MAPPING FAIL count=", failed)
		quit(1)
	else:
		print("INPUT_MAPPING PASS")
		quit(0)


func _configure_pedals(rest: float, press: float) -> void:
	g.throttle_axis = 1
	g.brake_axis = 2
	g.clutch_axis = 3
	g.steer_axis = 0
	g._pedal_rest = {"throttle": rest, "brake": rest, "clutch": rest}
	g._pedal_press = {"throttle": press, "brake": press, "clutch": press}
	g._pedal_span = {"throttle": press - rest, "brake": press - rest, "clutch": press - rest}
	g._steer_rest = 0.0
	g._steer_span = 1.0
	g.steer_invert = false
	g.steer_deadzone = 0.03


func _pedal_polarities() -> void:
	# released = +1, pressed = -1 (classic DirectInput pedal)
	_configure_pedals(1.0, -1.0)
	g.sim_set(1, 1.0)
	g.sim_set(2, 1.0)
	g.sim_set(3, 1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 0.0) and _near(g.brake, 0.0), "pedal_released_is_zero",
		"gas=%.2f brake=%.2f" % [g.throttle, g.brake])
	g.sim_set(1, -1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 1.0) and _near(g.brake, 0.0), "gas_axis_drives_gas_only",
		"gas=%.2f brake=%.2f" % [g.throttle, g.brake])
	g.sim_set(1, 0.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 0.5), "pedal_half_travel_is_half", "gas=%.2f" % g.throttle)
	_check(g.invert_throttle and g.invert_brake, "invert_flags_follow_polarity",
		"inv_gas=%s inv_brake=%s" % [g.invert_throttle, g.invert_brake])

	# released = 0, pressed = -1 (what the G29 on this machine reports at rest)
	_configure_pedals(0.0, -1.0)
	g.sim_set(1, 0.0)
	g.sim_set(2, 0.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 0.0), "rest_zero_is_zero", "gas=%.2f" % g.throttle)
	g.sim_set(1, -1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 1.0), "rest_zero_full_press_is_one", "gas=%.2f" % g.throttle)

	# released = -1, pressed = +1 (opposite polarity)
	_configure_pedals(-1.0, 1.0)
	g.sim_set(1, -1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 0.0), "opposite_polarity_rest_is_zero", "gas=%.2f" % g.throttle)
	g.sim_set(1, 1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.throttle, 1.0), "opposite_polarity_press_is_one", "gas=%.2f" % g.throttle)
	_check(not g.invert_throttle, "opposite_polarity_not_inverted")


func _steer_math() -> void:
	_configure_pedals(1.0, -1.0)
	g.sim_set(1, 1.0)
	g.sim_set(2, 1.0)
	g.sim_set(3, 1.0)
	g.sim_set(0, 0.0)
	g.step(1.0 / 60.0)
	_check(_near(g.steer, 0.0), "steer_centre_is_zero", "steer=%.3f" % g.steer)
	g.sim_set(0, 0.02)
	g.step(1.0 / 60.0)
	_check(_near(g.steer, 0.0), "steer_deadzone_suppresses_jitter", "steer=%.3f" % g.steer)
	g.sim_set(0, 1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.steer, 1.0, 0.05), "steer_full_left_or_right_is_one", "steer=%.3f" % g.steer)
	g.sim_set(0, -1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.steer, -1.0, 0.05), "steer_other_side_is_minus_one", "steer=%.3f" % g.steer)
	g.steer_invert = true
	g.sim_set(0, 1.0)
	g.step(1.0 / 60.0)
	_check(_near(g.steer, -1.0, 0.05), "steer_invert_flips_direction", "steer=%.3f" % g.steer)
	g.steer_invert = false


func _guided_pedal_calibration() -> void:
	g._pedal_rest.clear()
	g._pedal_press.clear()
	g._pedal_span.clear()
	g.steer_axis = 0
	for i in 12:
		g.sim_set(i, 0.0)
	g.begin_pedal_calibration("throttle")
	_check(g.cal_phase == 1 and g.cal_hint != "", "calibration_starts_with_rest_sampling",
		"phase=%d hint=%s" % [g.cal_phase, g.cal_hint])
	for i in 80:
		g.step(0.02)
	_check(g.cal_phase == 2, "calibration_waits_for_the_pedal", "phase=%d" % g.cal_phase)
	_check("GAS" in g.cal_hint, "gas_is_asked_for", g.cal_hint)
	# driver presses the gas pedal (axis 5 here, negative polarity)
	g.sim_set(5, -1.0)
	g.step(0.02)
	_check(g.cal_phase == 5, "calibration_finishes_on_full_press", "phase=%d" % g.cal_phase)
	_check(g.throttle_axis == 5, "detected_axis_is_remembered", "axis=%d" % g.throttle_axis)
	_check(_near(g._pedal_rest["throttle"], 0.0) and _near(g._pedal_press["throttle"], -1.0),
		"rest_and_press_are_stored")
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "detected_pedal_reads_full", "gas=%.2f" % g.throttle)
	g.sim_set(5, 0.0)
	g.step(0.02)
	_check(_near(g.throttle, 0.0), "detected_pedal_reads_zero_at_rest", "gas=%.2f" % g.throttle)

	# a second pedal must not steal the first axis
	g.begin_pedal_calibration("brake")
	for i in 60:
		g.step(0.02)
	g.sim_set(7, 1.0)
	g.step(0.02)
	_check(g.brake_axis == 7 and g.throttle_axis == 5, "second_pedal_gets_its_own_axis",
		"brake=%d gas=%d" % [g.brake_axis, g.throttle_axis])


func _guided_steer_calibration() -> void:
	for i in 12:
		g.sim_set(i, 0.0)
	g.begin_steer_calibration()
	_check(g.cal_phase == 1, "steer_calibration_samples_rest", "phase=%d" % g.cal_phase)
	for i in 60:
		g.step(0.02)
	_check(g.cal_phase == 2 and "rechts" in g.cal_hint, "steer_asks_to_turn_right", g.cal_hint)
	# wheel axis decreases when turned right -> module has to invert it
	g.sim_set(0, -1.0)
	g.step(0.02)
	_check(g.cal_phase == 5 and g.steer_axis == 0, "steer_calibration_finishes",
		"phase=%d axis=%d" % [g.cal_phase, g.steer_axis])
	_check(g.steer_invert, "steer_direction_is_detected")
	g.step(0.02)
	_check(_near(g.steer, 1.0, 0.05), "turning_right_is_positive", "steer=%.3f" % g.steer)


func _profile_round_trip() -> void:
	g.throttle_axis = 6
	g.brake_axis = 7
	g.clutch_axis = 8
	g.steer_axis = 1
	g.steer_invert = true
	g._pedal_rest["throttle"] = 0.25
	g._pedal_press["throttle"] = -0.75
	g.save_profile()
	g.throttle_axis = 0
	g.brake_axis = 0
	g.clutch_axis = 0
	g.steer_axis = 0
	g.steer_invert = false
	var loaded: bool = g.load_profile()
	_check(loaded, "profile_loads")
	_check(g.throttle_axis == 6 and g.brake_axis == 7 and g.clutch_axis == 8 and g.steer_axis == 1,
		"profile_restores_axes", "gas=%d brake=%d clutch=%d steer=%d" % [
			g.throttle_axis, g.brake_axis, g.clutch_axis, g.steer_axis])
	_check(g.steer_invert, "profile_restores_steer_invert")
	_check(_near(float(g._pedal_rest["throttle"]), 0.25) and _near(float(g._pedal_press["throttle"]), -0.75),
		"profile_restores_pedal_points")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.profile_path))


func _silent_device_detector() -> void:
	var h = G29.new()
	h.auto_load_profile = false
	h.profile_path = "user://g29_profile_test2.json"
	h.enable_sim()
	root.add_child(h)
	for i in 12:
		h.sim_set(i, 0.0)
	for i in 100:
		h.step(0.04)
	_check(not h.axes_live and h.hardware_hint != "", "silent_device_is_detected",
		"live=%s hint=%s" % [h.axes_live, h.hardware_hint])
	h.sim_set(2, 0.5)
	h.step(0.04)
	_check(h.axes_live, "moving_an_axis_clears_the_warning")
	h.queue_free()
