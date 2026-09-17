extends SceneTree
## The tyres must visibly turn with the car, at the rate the speed demands.
##
## This is a regression test for a bug that was invisible in the numbers the
## code produced but obvious on screen: the rim was a child of the
## VehicleWheel3D node, Godot rotates that node itself, and the two rotations
## cancelled exactly. Measured while driving at 150 km/h, the tyre's world
## orientation did not move at all - only the node and the mesh turned, 73 deg
## per tick, in opposite directions. The same cancellation dragged the rim's
## centre around the suspension mount by +/-0.15 m.

const F1Car = preload("res://scripts/car_controller.gd")
const REST := 0.18
const ROLES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		failed += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis(), Vector3(0, 0.4, 0)))
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var radius: float = car._wheel_radius_avg
	_check(radius > 0.2 and radius < 0.6, "wheel_radius_is_plausible", "r=%.3f m" % radius)

	# --- every wheel draws from a carrier the physics node cannot rotate -----
	for role in ROLES:
		var wheel := car.get_node_or_null(role)
		var vis := car.get_node_or_null("Vis_" + role)
		_check(wheel != null and vis != null, "carrier_exists_%s" % role)
		if wheel == null or vis == null:
			continue
		_check(vis.get_parent() == car, "carrier_hangs_on_the_car_%s" % role)
		var dy: float = vis.position.y - (wheel.position.y - REST)
		_check(absf(dy) < 0.001, "carrier_sits_on_the_axle_%s" % role, "dy=%.3f" % dy)

	# --- the roll follows the driven speed, forward and in reverse -----------
	var front := car.get_node_or_null("Wheel_FL")
	var vis_front := car.get_node_or_null("Vis_Wheel_FL")
	if front and vis_front:
		# Whatever Godot does to the physics node, the visible rim must not care.
		front.rotation = Vector3(1.7, 0.0, 0.0)
		car._wheel_roll = 0.0
		car._animate_wheels(dt, 30.0)
		var want: float = 30.0 * dt / radius
		_check(absf(_roll_of(vis_front) - want) < 0.002, "roll_matches_speed",
			"roll=%.4f want=%.4f" % [_roll_of(vis_front), want])
		_check(absf(_node_roll(front) - 1.7) < 0.01,
			"physics_node_roll_does_not_leak_into_the_rim",
			"node=%.3f rim=%.3f" % [_node_roll(front), _roll_of(vis_front)])

		car._wheel_roll = 0.0
		car._animate_wheels(dt, -30.0)
		_check(absf(_roll_of(vis_front) + want) < 0.002, "roll_reverses_with_reverse_speed",
			"roll=%.4f" % _roll_of(vis_front))

	# --- all four wheels turn at the same rate -------------------------------
	var rolls: Array = []
	for role in ROLES:
		var vis := car.get_node_or_null("Vis_" + role)
		if vis:
			rolls.append(_roll_of(vis))
	var spread: float = 0.0
	for r in rolls:
		spread = maxf(spread, absf(float(r) - float(rolls[0])))
	_check(rolls.size() == 4 and spread < 0.001, "all_four_wheels_turn_together",
		"spread=%.5f rad" % spread)

	# --- the markings fade as the wheel spins up -----------------------------
	# A crisp spoke star at 200 km/h cannot read as rotation, it can only
	# shimmer frame to frame; the material has to dissolve into the tyre.
	var slow: Color = _decal_color(car, 5.0)
	var fast: Color = _decal_color(car, 70.0)
	_check(fast.get_luminance() < slow.get_luminance() - 0.2,
		"tyre_markings_blur_at_speed",
		"slow=%.2f fast=%.2f" % [slow.get_luminance(), fast.get_luminance()])

	if failed > 0:
		print("TYRE_MOTION FAIL count=", failed)
		quit(1)
	else:
		print("TYRE_MOTION PASS")
		quit(0)


func _decal_color(car, speed: float) -> Color:
	car._wheel_roll = 0.0
	car._animate_wheels(1.0 / 90.0, speed)
	for item in car._wheel_meshes:
		var mat: StandardMaterial3D = item.get("decal_mat")
		if mat:
			return mat.albedo_color
	return Color.BLACK


## Rolling angle of a visual carrier: Y(yaw) * X(roll), so the yaw comes out of
## the x axis and the roll out of what is left.
func _roll_of(vis: Node3D) -> float:
	var b: Basis = vis.transform.basis
	var yaw: float = atan2(-b.x.z, b.x.x)
	var r: Basis = Basis(Vector3.UP, -yaw) * b
	return atan2(r.y.z, r.y.y)


func _node_roll(wheel: Node3D) -> float:
	var b: Basis = wheel.transform.basis
	var yaw: float = atan2(-b.x.z, b.x.x)
	var r: Basis = Basis(Vector3.UP, -yaw) * b
	return atan2(r.y.z, r.y.y)
