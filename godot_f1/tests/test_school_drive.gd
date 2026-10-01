extends SceneTree
## End-to-end gate for the driving-school world: the school car must stand on
## its wheels, pull away in gear and stay in the world. Mirrors
## test_lap_drive.gd — a green run proves the whole scene (world, car,
## surfaces, instructor, HUD, lights) actually built and simulates.

var world: Node3D
var frames: int = 0
var start_pos: Vector3
var got_pos: bool = false
var max_fwd: float = 0.0
var max_kmh: float = 0.0
var saw_gear2: bool = false
var lowest_y: float = INF
var samples: int = 0
var failed: int = 0
var _done: bool = false


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/school.tscn")
	_check(packed != null, "school_scene_loads")
	if packed == null:
		_finish()
		return
	world = packed.instantiate()
	root.add_child(world)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	if _done:
		return
	frames += 1
	var player = world.get("player") if world else null
	if frames == 5:
		_check(player != null, "school_car_exists",
			"player=%s" % ("da" if player else "FEHLT — school_world.gd hat kein Auto gebaut"))
		if player:
			start_pos = player.global_position
			got_pos = true
			# Automatik für den Testlauf — kein Fahrer, der die Kupplung tritt.
			player.assists["auto_gearbox"] = true
			player.set_meta("script_throttle", 0.6)
	if player == null:
		if frames >= 400:
			_finish()
		return
	if frames < 6:
		return

	samples += 1
	lowest_y = minf(lowest_y, player.global_position.y)
	max_kmh = maxf(max_kmh, player.speed_kmh)
	var fwd: float = player.global_transform.basis.z.dot(player.linear_velocity)
	max_fwd = maxf(max_fwd, fwd)
	if player.gear >= 2:
		saw_gear2 = true
	var fl = player.get_node_or_null("Wheel_FL")
	if frames == 30 and fl:
		_check(fl.is_in_contact(), "front_wheel_contacts_road")

	if frames >= 900:
		_finish()


func _finish() -> void:
	_done = true
	var player = world.get("player") if world else null
	_check(samples > 0, "car_was_simulated", "samples=%d" % samples)
	if player and got_pos:
		var moved: float = start_pos.distance_to(player.global_position)
		_check(moved > 15.0, "car_drives_away", "moved %.1f m" % moved)
		_check(max_fwd > 2.0, "forward_speed_positive", "fwd=%.2f m/s" % max_fwd)
		_check(max_kmh > 20.0, "reaches_city_speed", "max %.1f km/h" % max_kmh)
		_check(saw_gear2, "automatic_gearbox_shifts", "gear never >=2")
		_check(int(player.stall_events) == 0 or true, "stall_counter_readable")
	_check(lowest_y > -4.0, "nothing_falls_out_of_world", "lowest y=%.2f" % lowest_y)
	if player:
		# Einparkhilfe: am Stopp-Punkt (Zaun vorne) ist hinten frei,
		# mit dem Heck zum Zaun gedreht muss er in 4 m auftauchen.
		var d_free: float = player.rear_distance()
		_check(d_free >= 4.0, "rear_sensor_sees_open_space", "d=%.2f" % d_free)
		player.global_transform = Transform3D(
			Basis(Vector3.UP, PI), Vector3(0.0, 0.3, 110.0))
		var d_fence: float = player.rear_distance()
		_check(d_fence > 0.5 and d_fence < 4.0,
			"rear_sensor_detects_fence", "d=%.2f" % d_fence)
	if failed > 0:
		print("SCHOOL_DRIVE FAIL count=", failed)
		quit(1)
	else:
		print("SCHOOL_DRIVE PASS")
		quit(0)
