extends SceneTree
## Abnahme für `scripts/gearbox.gd`: erst die Mechanik als Einheitentest, dann
## eine echte Messung - ein Wagen auf einer langen Geraden, Vollgas, bis die
## Endgeschwindigkeit steht.
##
##   godot --headless --path godot_f1 --script tests/test_gearbox.gd

const Gearbox = preload("res://scripts/gearbox.gd")
const F1Car = preload("res://scripts/car_controller.gd")

var failed: int = 0
var world: Node3D
var car
var frames: int = 0
var t100: float = -1.0
var top_speed: float = 0.0
var top_gear: int = 0
var shift_log: Array = []
var last_gear: int = 1
var lap_start_gear: int = 1


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _initialize() -> void:
	_unit()
	call_deferred("_boot")


func _unit() -> void:
	var gb = Gearbox.new()
	gb.setup()
	# Ratios: strictly shorter in every lower gear, first short, eighth long.
	var monotone := true
	for g in range(1, Gearbox.MAX_GEAR):
		if gb.ratio(g) <= gb.ratio(g + 1):
			monotone = false
	_check(monotone, "ratios_get_shorter_with_every_gear",
		"1st %.2f .. 8th %.2f" % [gb.ratio(1), gb.ratio(8)])
	# Eighth gear must be able to reach a real Formula top speed at the limiter.
	var vmax: float = (Gearbox.REDLINE - Gearbox.IDLE_RPM) / (gb.ratio(8) * Gearbox.RPM_PER_MPS_UNIT)
	_check(vmax > 90.0, "eighth_gear_reaches_over_320_km_h", "%.0f km/h at the limiter" % (vmax * 3.6))
	# Torque: peak in the upper half, falls at the limiter, never zero.
	var peak_rpm: float = 0.0
	var peak: float = 0.0
	for r in range(4200, 12600, 100):
		var t: float = gb.torque_at(float(r))
		if t > peak:
			peak = t
			peak_rpm = float(r)
	_check(peak_rpm > 9000.0 and peak_rpm < 12200.0, "torque_peaks_high_up",
		"peak at %.0f rpm" % peak_rpm)
	_check(gb.torque_at(Gearbox.IDLE_RPM) > 500.0, "idle_torque_lets_the_car_creep",
		"%.0f" % gb.torque_at(Gearbox.IDLE_RPM))
	_check(gb.torque_at(Gearbox.REDLINE) < peak * 0.85, "torque_falls_off_at_the_limiter")
	# Shift times.
	gb.setup()
	var up_ok: bool = gb.request_shift(true)
	_check(up_ok and gb.gear == 2, "upshift_changes_gear")
	_check(not gb.request_shift(true), "no_second_shift_while_the_first_is_running")
	var t: float = 0.0
	while gb.shift_cd > 0.0 and t < 1.0:
		gb.update(1.0 / 90.0, {"speed": 20.0, "throttle": 1.0, "auto": false})
		t += 1.0 / 90.0
	_check(t > 0.02 and t < 0.12, "a_shift_takes_a_real_moment", "%.3f s" % t)
	# Over-rev protection: at 340 km/h 8th is fine, 4th is not.
	_check(not gb.would_overrev(8, 90.0), "top_gear_is_safe_at_top_speed")
	_check(gb.would_overrev(4, 90.0), "a_random_downshift_from_top_speed_would_over_rev")
	# The limiter: 1st gear at 60 m/s is far past the redline, so it has to cut.
	gb.setup()
	gb.force_gear(1)
	for i in 20:
		gb.update(1.0 / 90.0, {"speed": 60.0, "throttle": 1.0, "auto": false})
	_check(gb.rpm <= Gearbox.REDLINE + 410.0, "the_limiter_holds_the_revs",
		"%.0f rpm" % gb.rpm)
	_check(gb.limiter_hits > 0, "the_limiter_is_recorded")
	# A car that is standing still must not stall.
	gb.setup()
	for i in 300:
		gb.update(1.0 / 90.0, {"speed": 0.0, "throttle": 0.0, "auto": false})
	_check(gb.rpm >= Gearbox.IDLE_RPM - 1.0, "the_engine_idles_at_a_standstill",
		"%.0f rpm" % gb.rpm)
	# No hunting: settling on a constant speed must not keep shifting.
	gb.setup()
	var shifts_before: int = gb.shifts_up + gb.shifts_down
	for i in 400:
		gb.update(1.0 / 90.0, {"speed": 60.0, "throttle": 0.8, "auto": true})
	var settled: int = gb.shifts_up + gb.shifts_down - shifts_before
	_check(settled <= 8, "automatic_mode_settles_instead_of_hunting",
		"%d shifts while settling" % settled)


func _boot() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 12000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, -5000)
	ground.add_child(col)
	world.add_child(ground)
	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	car.is_ai = false
	world.add_child(car)
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, null, start)
	car.global_transform = start
	car.apply_throttle(1.0)
	last_gear = car.gear
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if t100 < 0.0 and car.speed_kmh >= 100.0:
		t100 = float(frames) * dt
	if car.gear != last_gear:
		shift_log.append("f=%d %d->%d at %.0f km/h and %.0f rpm" % [
			frames, last_gear, car.gear, car.speed_kmh, car.rpm])
		last_gear = car.gear
	if car.speed_kmh > top_speed:
		top_speed = car.speed_kmh
		top_gear = car.gear
	if frames % 300 == 0:
		print("STATE f=%d kmh=%.1f gear=%d rpm=%.0f force=%.0f drag=%.0f resets=%d shuffts=%d up=%.3f pos=%.1f,%.1f,%.1f vy=%.2f yaw=%.3f" % [
			frames, car.speed_kmh, car.gear, car.rpm, car.engine_force, car.aero_drag_n,
			car.reset_count, car.gearbox.shifts_up,
			car.global_transform.basis.y.dot(Vector3.UP),
			car.global_position.x, car.global_position.y, car.global_position.z,
			car.linear_velocity.dot(car.global_transform.basis.x), car.angular_velocity.y])
	# 40 s is enough to reach the terminal speed on this straight.
	if frames >= 3600:
		_finish()


func _finish() -> void:
	var gb = car.gearbox
	_check(t100 > 1.5 and t100 < 4.5, "zero_to_hundred_is_plausible", "%.2f s" % t100)
	_check(top_speed > 300.0, "top_speed_is_a_formula_car_number", "%.0f km/h" % top_speed)
	_check(top_speed < 380.0, "top_speed_is_not_absurd", "%.0f km/h" % top_speed)
	_check(top_gear >= 7, "top_speed_is_reached_in_the_last_gears", "gear %d" % top_gear)
	_check(gb.shifts_up >= 6, "the_car_works_through_the_gears",
		"%d upshifts" % gb.shifts_up)
	# A correctly geared Formula car is drag limited in top gear, not limiter
	# limited - hitting the limiter on every straight would mean the gearing is
	# too short. Either is allowed, but it has to be one of them.
	_check(gb.rpm > Gearbox.REDLINE - 1600.0 or gb.limiter_hits > 0,
		"top_gear_is_used_up_to_the_limit",
		"%.0f rpm, %d limiter ticks" % [gb.rpm, gb.limiter_hits])
	_check(int(car.reset_count) == 0, "the_car_stays_on_its_wheels_at_top_speed",
		"%d resets" % car.reset_count)
	var gear_at_100: String = shift_log[0] if shift_log.size() > 0 else "none"
	for line in shift_log.slice(0, 8):
		print("SHIFT ", line)
	print("GEARBOX 0-100 %.2f s, top %.0f km/h in gear %d, upshifts %d, downshifts %d, refused %d" % [
		t100, top_speed, top_gear, gb.shifts_up, gb.shifts_down, gb.refused_downshifts])
	print("GEARBOX first shift: ", gear_at_100)
	if failed > 0:
		print("GEARBOX FAIL count=", failed)
		quit(1)
	else:
		print("GEARBOX PASS")
		quit(0)
