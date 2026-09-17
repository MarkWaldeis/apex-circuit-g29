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
	_silent_start_then_real_data()
	_partial_calibration_keeps_learning()
	_repairs_a_broken_profile_rest()
	_profile_waits_for_data()
	_profile_round_trip()
	_manual_pedal_assignment()
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
	g._auto_rest.clear()
	g._auto_press.clear()
	g._steer_rest = 0.0
	g._steer_span = 1.0
	g.steer_invert = false
	g.steer_deadzone = 0.03


func _uncalibrated() -> void:
	## Drop everything the driver has calibrated so far and start like a fresh
	## installation: no profile, no explicit pedal points.
	g._pedal_rest.clear()
	g._pedal_press.clear()
	g._auto_rest.clear()
	g._auto_press.clear()
	g._have_data = false
	# start from a clean bus: a leftover non-zero axis would count as "data has
	# arrived" and anchor the rest position too early
	for i in 12:
		g.sim_set(i, 0.0)
	g.throttle_axis = 1
	g.brake_axis = 2
	g.clutch_axis = 3
	g.steer_axis = 0
	g._steer_rest = 0.0
	g._steer_span = 1.0
	g.steer_invert = false
	g.steer_deadzone = 0.03


func _silent_start_then_real_data() -> void:
	## Measured on the real G29: SDL reports a flat 0.0 on every pedal until the
	## wheel sends its first HID report, and only then the true value
	## (released = 1.0). Treating those zeros as "released" made all three
	## pedals read 100 % the moment the driver touched anything.
	_uncalibrated()
	for i in 12:
		g.sim_set(i, 0.0)
	for i in 60:
		g.step(0.05)
	_check(_near(g.throttle, 0.0) and _near(g.brake, 0.0) and _near(g.clutch, 0.0),
		"flat_zeros_read_as_idle", "gas=%.2f brake=%.2f" % [g.throttle, g.brake])
	_check(not g._have_data, "flat_zeros_are_not_trusted_as_data")

	# first believable report: pedals released, value +1 on axes 1..3
	g.sim_set(1, 1.0)
	g.sim_set(2, 1.0)
	g.sim_set(3, 1.0)
	g.step(0.05)
	_check(g._have_data, "first_real_report_is_recognised")
	_check(_near(g.throttle, 0.0) and _near(g.brake, 0.0) and _near(g.clutch, 0.0),
		"released_pedals_read_zero", "gas=%.2f brake=%.2f clutch=%.2f" % [
			g.throttle, g.brake, g.clutch])

	# driver presses the gas only
	g.sim_set(1, 0.0)
	g.step(0.05)
	_check(_near(g.throttle, 1.0) and _near(g.brake, 0.0) and _near(g.clutch, 0.0),
		"gas_press_moves_gas_only", "gas=%.2f brake=%.2f clutch=%.2f" % [
			g.throttle, g.brake, g.clutch])
	g.sim_set(1, 0.5)
	g.step(0.05)
	_check(g.throttle > 0.3 and g.throttle < 0.7, "half_press_is_half",
		"gas=%.2f" % g.throttle)

	# driver presses the brake only: gas must fall back to zero
	g.sim_set(1, 1.0)
	g.sim_set(2, 0.0)
	g.step(0.05)
	_check(_near(g.brake, 1.0) and _near(g.throttle, 0.0), "brake_press_moves_brake_only",
		"gas=%.2f brake=%.2f" % [g.throttle, g.brake])
	# and releasing everything reads idle again
	g.sim_set(2, 1.0)
	g.step(0.05)
	_check(_near(g.brake, 0.0) and _near(g.throttle, 0.0), "released_again_reads_idle",
		"gas=%.2f brake=%.2f" % [g.throttle, g.brake])


func _partial_calibration_keeps_learning() -> void:
	## Measured on this machine: the driver pressed the pedals only about 57 %
	## of the way during calibration, which would make the game reach 100 % far
	## too early. Pressing further during the race has to extend the range.
	_uncalibrated()
	g._have_data = true
	g.throttle_axis = 2
	g._pedal_rest["throttle"] = 1.0
	g._pedal_press["throttle"] = 0.43      # partial press recorded by calibration
	g.sim_set(2, 0.43)
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "partial_calibration_reads_full_at_its_end",
		"gas=%.2f" % g.throttle)
	g.sim_set(2, 0.0)
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "fuller_press_still_reads_full", "gas=%.2f" % g.throttle)
	_check(_near(float(g._pedal_press["throttle"]), 0.0), "range_grew_to_the_real_end",
		"press=%.2f" % float(g._pedal_press["throttle"]))
	g.sim_set(2, 0.5)
	g.step(0.02)
	_check(g.throttle > 0.4 and g.throttle < 0.6, "halfway_is_halfway_again",
		"gas=%.2f" % g.throttle)
	g.sim_set(2, 1.0)
	g.step(0.02)
	_check(_near(g.throttle, 0.0) and _near(float(g._pedal_press["throttle"]), 0.0),
		"release_does_not_break_the_range")

	# same idea for the steering: a partial right turn must not mean full lock
	g._steer_rest = 0.0
	g._steer_span = 0.55
	g.steer_invert = false
	g.sim_set(0, 0.55)
	g.step(0.02)
	_check(_near(g.steer, 1.0, 0.06), "partial_steer_calibration_reaches_full_lock",
		"steer=%.2f" % g.steer)
	g.sim_set(0, 1.0)
	g.step(0.02)
	_check(_near(g._steer_span, 1.0), "steer_range_grew", "span=%.2f" % g._steer_span)
	g.sim_set(0, 0.55)
	g.step(0.02)
	_check(g.steer < 0.75, "steering_is_no_longer_twitchy", "steer=%.2f" % g.steer)


func _repairs_a_broken_profile_rest() -> void:
	## An older build could save a rest of 0.0 although the pedals sit at 1.0
	## when released. The live device decides, the calibrated range is kept.
	_uncalibrated()
	g._profile_loaded = true
	g._pedal_rest = {"throttle": 0.0, "brake": 0.0, "clutch": 0.0}
	g._pedal_press = {"throttle": -1.0, "brake": -1.0, "clutch": -1.0}
	for i in 12:
		g.sim_set(i, 0.0)
	g.sim_set(1, 1.0)
	g.step(0.05)
	_check(_near(float(g._pedal_rest["throttle"]), 1.0), "broken_rest_is_repaired",
		"rest=%.2f" % float(g._pedal_rest["throttle"]))
	_check(_near(g.throttle, 0.0), "repaired_profile_reads_idle", "gas=%.2f" % g.throttle)
	g.sim_set(1, 0.0)
	g.step(0.05)
	_check(_near(g.throttle, 1.0), "repaired_profile_still_reaches_full", "gas=%.2f" % g.throttle)

	# a calibration with an impossibly short range is ignored altogether
	_uncalibrated()
	g._profile_loaded = true
	g.throttle_axis = 1
	g._pedal_rest["throttle"] = 0.5
	g._pedal_press["throttle"] = 0.53
	g.sim_set(1, 0.5)
	g.step(0.05)
	_check(_near(g.throttle, 0.0) and not g._pedal_press.has("throttle"),
		"implausible_calibration_is_discarded", "gas=%.2f" % g.throttle)


func _profile_waits_for_data() -> void:
	## Regression: a loaded profile was evaluated against the flat zeros the
	## device reports before its first HID report, so the game started with all
	## three pedals at 100 %.
	_uncalibrated()
	g._profile_loaded = true
	g.throttle_axis = 2
	g._pedal_rest["throttle"] = 1.0
	g._pedal_press["throttle"] = 0.43
	g.sim_set(2, 0.0)
	for i in 30:
		g.step(0.02)
	_check(_near(g.throttle, 0.0), "stored_profile_is_ignored_before_data",
		"gas=%.2f have_data=%s" % [g.throttle, g._have_data])
	g.sim_set(2, 1.0)
	g.step(0.02)
	_check(_near(g.throttle, 0.0), "stored_profile_reads_idle_once_data_arrives",
		"gas=%.2f" % g.throttle)
	g.sim_set(2, 0.43)
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "stored_profile_still_maps_the_press",
		"gas=%.2f phase=%d raw2=%.2f rest=%.2f press=%.2f" % [
			g.throttle, g.cal_phase, g._raw[2],
			float(g._pedal_rest.get("throttle", -9.0)), float(g._pedal_press.get("throttle", -9.0))])
	# nothing changed, so there is nothing to write
	g._profile_dirty = false
	g.sim_set(2, 1.0)
	for i in 20:
		g.step(0.02)
	_check(not g._profile_dirty, "no_endless_profile_writes")


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
	_uncalibrated()
	# a real device always reports something before calibration starts
	g.sim_set(5, 1.0)
	g.step(0.05)
	for i in 12:
		if i != 5:
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
	# released = +1 (rest), fully pressed = -1, exactly like the real G29
	_check(_near(g._pedal_rest["throttle"], 1.0) and _near(g._pedal_press["throttle"], -1.0),
		"rest_and_press_are_stored", "rest=%.2f press=%.2f" % [
			float(g._pedal_rest["throttle"]), float(g._pedal_press["throttle"])])
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "detected_pedal_reads_full", "gas=%.2f" % g.throttle)
	g.sim_set(5, 1.0)
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
	# a real wheel always delivers data before the driver starts calibrating
	g.sim_set(5, 1.0)
	g.step(0.05)
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


func _manual_pedal_assignment() -> void:
	## Manual axis assignment for a pedal, with and without inversion, has to
	## behave like the guided calibration: 0 at rest, 1 at full press.
	for i in 12:
		g.sim_set(i, 0.0)
	g.apply_manual("throttle", 4, false)
	g.sim_set(4, 0.0)
	g.step(0.02)
	_check(g.throttle_axis == 4 and _near(g.throttle, 0.0), "manual_axis_takes_effect",
		"axis=%d gas=%.2f" % [g.throttle_axis, g.throttle])
	g.sim_set(4, 1.0)
	g.step(0.02)
	_check(_near(g.throttle, 1.0), "manual_axis_press_reads_full", "gas=%.2f" % g.throttle)

	# a manual assignment never needs an invert flag: the direction is learned
	# from the driver's first press, so it cannot end up backwards.
	g.sim_set(4, 0.0)
	g.apply_manual("brake", 4, true)
	g.step(0.02)
	_check(_near(g.brake, 0.0), "manual_inverted_rest_is_zero", "brake=%.2f" % g.brake)
	g.sim_set(4, -1.0)
	g.step(0.02)
	_check(_near(g.brake, 1.0), "manual_press_reads_full_regardless_of_invert",
		"brake=%.2f" % g.brake)
	g.sim_set(4, 0.0)
	g.step(0.02)
	_check(_near(g.brake, 0.0), "manual_release_reads_zero_again", "brake=%.2f" % g.brake)


func _silent_device_detector() -> void:
	var h = G29.new()
	h.auto_load_profile = false
	h.profile_path = "user://g29_profile_test2.json"
	h.enable_sim()
	root.add_child(h)
	for i in 12:
		h.sim_set(i, 0.0)
	for i in 200:
		h.step(0.04)
	_check(not h.axes_live and h.hardware_hint != "", "silent_device_is_detected",
		"live=%s hint=%s" % [h.axes_live, h.hardware_hint])
	h.sim_set(2, 0.5)
	h.step(0.04)
	_check(h.axes_live, "moving_an_axis_clears_the_warning")
	h.queue_free()
