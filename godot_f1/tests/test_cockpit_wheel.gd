extends SceneTree
## Gating test: the rim inside the cockpit follows the real wheel, in the right
## direction, and the car turns the same way.
##
## The G29 hands the game one signed value (`g29.steer`). Calibration defines
## "turn right" as positive. That single value feeds two consumers:
##   * the car - positive steering yaws the hull to the right, towards -X,
##     because the nose (the direction engine_force pushes) is +Z;
##   * the rim in the cockpit - the driver looks down the camera's own -Z, so
##     "right" is a clockwise turn, i.e. a NEGATIVE rotation.z.
## This test wires the real cockpit camera to a stub G29 and measures both.

const CockpitCamera = preload("res://scripts/cockpit_camera.gd")
const F1Car = preload("res://scripts/car_controller.gd")


class StubWheel:
	## car_controller connects these two signals in setup().
	signal shift_up
	signal shift_down
	var steer: float = 0.0
	var throttle: float = 0.0
	var brake: float = 0.0
	var clutch: float = 0.0
	var connected: bool = true
	var cal_phase: int = 0

	func has_driver_input() -> bool:
		return connected and (absf(steer) > 0.12 or throttle > 0.08 or brake > 0.08)


var world: Node3D
var car: Node3D
var driven_car
var stub: StubWheel
var cam: Camera3D
var failed: int = 0
var idle_frames: int = 0
var phys_frames: int = 0
var stage: int = 0
var z_right: float = 0.0
var z_left: float = 0.0
var start_heading: float = 0.0


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1
		print("FAIL ", label, " ", detail)


func _boot() -> void:
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)

	# A bare node stands in for the car: the rim only needs a transform to
	# hang off, that keeps this phase independent of the physics.
	car = Node3D.new()
	car.name = "Car"
	world.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0))

	stub = StubWheel.new()
	cam = CockpitCamera.new()
	cam.name = "CockpitCam"
	world.add_child(cam)
	cam.setup(car, stub)

	_check(cam.wheel_visual != null, "cockpit_has_a_steering_wheel")
	if cam.wheel_visual:
		_check(cam.wheel_visual.position.z < -0.2, "rim_in_front_of_the_lens",
			"z=%.3f" % cam.wheel_visual.position.z)
		_check(cam.wheel_visual.visible, "rim_is_visible_in_cockpit_mode")
		_check(absf(cam.wheel_visual.rotation.z) < 0.05, "rim_starts_centred",
			"z=%.3f" % cam.wheel_visual.rotation.z)
	process_frame.connect(_on_idle)


func _on_idle() -> void:
	if cam.wheel_visual == null:
		return
	idle_frames += 1
	match stage:
		0:
			stub.steer = 1.0
			if idle_frames >= 24:
				z_right = cam.wheel_visual.rotation.z
				_check(z_right < -0.6, "rim_turns_right_when_the_driver_steers_right",
					"rot.z=%.3f (clockwise == negative)" % z_right)
				stage = 1
		1:
			stub.steer = -1.0
			if idle_frames >= 60:
				z_left = cam.wheel_visual.rotation.z
				_check(z_left > 0.6, "rim_turns_left_when_the_driver_steers_left",
					"rot.z=%.3f" % z_left)
				stage = 2
		2:
			stub.steer = 0.0
			if idle_frames >= 132:
				var z: float = cam.wheel_visual.rotation.z
				_check(absf(z) < 0.15, "rim_returns_to_centre", "rot.z=%.3f" % z)
				stage = 3
				_boot_drive_phase()


## Second phase: the very same positive steer value has to steer the real car
## to the right. That is the end-to-end proof that the wheel is not mirrored.
func _boot_drive_phase() -> void:
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	world.add_child(floor_body)

	driven_car = F1Car.new()
	driven_car.name = "Driven"
	driven_car.livery = "crimson"
	driven_car.is_ai = false
	driven_car.auto_drive = false
	world.add_child(driven_car)
	var start := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0))
	driven_car.setup(null, stub, start)
	driven_car.global_transform = start
	start_heading = _heading()
	stub.steer = 1.0
	stub.throttle = 0.5
	physics_frame.connect(_on_phys)


func _heading() -> float:
	var nose: Vector3 = driven_car.global_transform.basis.z
	return atan2(nose.x, nose.z)


## Where a wheel points inside the car, in radians. Measured from the wheel's
## spin axis, which stays horizontal while the rim rolls (the wheel's own
## forward axis would flip by 180 deg once the wheel has rolled past a quarter
## turn). The GLB wheel nodes also carry a baked 180 deg flip, so this is only
## meaningful relative to another wheel of the same car.
func _wheel_yaw(wheel_name: String) -> float:
	var w = driven_car.get_node_or_null(wheel_name)
	if w == null:
		return 0.0
	var p: Vector3 = driven_car.global_transform.basis.inverse() * w.global_transform.basis.x
	return atan2(-p.z, p.x)


## Steering angle of the front axle, with the baked 180 deg offsets removed.
## A real steering angle is always well below 90 deg, so anything that lands
## beyond that was a flip and gets folded back.
func _steer_angle() -> float:
	var delta: float = wrapf(_wheel_yaw("Wheel_FL") - _wheel_yaw("Wheel_RL"), -PI, PI)
	if delta > PI * 0.5:
		delta -= PI
	elif delta < -PI * 0.5:
		delta += PI
	return delta


func _on_phys() -> void:
	if driven_car == null:
		return
	phys_frames += 1
	if phys_frames == 180:
		# The nose is +Z, so "right" is the car's own -X and a right turn is a
		# heading that decreases. Measure the sideways drift in the car's frame
		# so the answer cannot depend on how the harness is oriented.
		var turn: float = wrapf(_heading() - start_heading, -PI, PI)
		var side: float = driven_car.global_transform.basis.x.dot(driven_car.linear_velocity)
		var fwd: float = driven_car.global_transform.basis.z.dot(driven_car.linear_velocity)
		var front = driven_car.get_node_or_null("Wheel_FL")
		var rim_yaw: float = 0.0
		if front and front.get_child_count() > 0:
			rim_yaw = front.get_child(0).rotation.y
		# The rear wheels never steer, so they are the "straight ahead" ruler.
		var visible_steer: float = _steer_angle()
		_check(fwd > 0.5, "car_still_drives_forward", "fwd=%.2f" % fwd)
		_check(turn < -0.1, "car_turns_right_with_positive_steer",
			"heading change=%.3f rad" % turn)
		_check(side < -0.3, "car_drifts_to_its_right_side", "local side=%.2f" % side)
		_check(visible_steer < -0.05, "front_wheel_is_visibly_steered_right",
			"steering angle=%.3f rad" % visible_steer)
		_check(absf(rim_yaw) < 0.001, "rim_does_not_cancel_the_wheel_steer",
			"rim yaw=%.3f" % rim_yaw)
		_finish()


func _finish() -> void:
	if failed > 0:
		print("COCKPIT_WHEEL FAIL count=", failed)
		quit(1)
	else:
		print("COCKPIT_WHEEL PASS rim_right=%.3f rim_left=%.3f" % [z_right, z_left])
		quit(0)
