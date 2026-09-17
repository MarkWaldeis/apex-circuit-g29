extends SceneTree
## Measures the grip curve of the car on flat asphalt: how many g it can hold
## at each speed. This is the number that decides whether the car feels like a
## Formula car or like a toy, so it is measured, not guessed.
##
## Method: put the car on an endless flat plane, hold the SPEED constant
## (rescale the velocity vector, never its direction - that would hide the slip
## angle) and sweep the steering. The steady-state yaw rate times the speed is
## the lateral acceleration the tyres are actually delivering.
##
##   godot --headless --path godot_f1 --script tests/probe_grip.gd

const F1Car = preload("res://scripts/car_controller.gd")

const SPEEDS_KMH := [80.0, 120.0, 180.0, 240.0, 300.0]
const STEPS := [0.15, 0.3, 0.5, 0.75, 1.0]
const SETTLE := 150
const MEASURE := 90

var world: Node3D
var car
var frames: int = 0
var speed_index: int = 0
var step_index: int = 0
var phase_frames: int = 0
var acc_g: float = 0.0
var acc_count: int = 0
var measure_heading: float = 0.0
var heading_start: float = 0.0
var peak_g: float = 0.0
var peak_steer: float = 0.0
var peak_slip: float = 0.0
var rows: Array = []


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40000.0, 1.0, 40000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	world.add_child(floor_body)
	car = F1Car.new()
	car.name = "TestCar"
	car.livery = "crimson"
	car.is_ai = false
	world.add_child(car)
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, null, start)
	car.global_transform = start
	car.apply_throttle(1.0)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if frames < 3:
		return
	var target: float = SPEEDS_KMH[speed_index] / 3.6
	# Hold the speed with the pedals, never by writing the velocity: forcing
	# `linear_velocity` also cancels gravity, and the car flies off the plane.
	var speed: float = car.linear_velocity.length()
	var err: float = target - speed
	car.apply_throttle(clampf(err * 0.6, 0.0, 1.0))
	car.apply_brake(clampf(-err * 0.25, 0.0, 1.0))
	var steer: float = STEPS[step_index]
	Input.action_press("steer_right", steer)
	phase_frames += 1
	if phase_frames == SETTLE:
		heading_start = _heading()
	elif phase_frames > SETTLE:
		acc_g += absf(car.angular_velocity.y)
		acc_count += 1
	if phase_frames >= SETTLE + MEASURE:
		# Two independent readings of the same turn: the heading the car has
		# actually gained over the window, and the mean yaw rate. a = v * w.
		var swept: float = absf(angle_difference(_heading(), heading_start))
		var yaw_mean: float = acc_g / maxf(float(acc_count), 1.0)
		var speed_now: float = car.linear_velocity.length()
		if not car.get_node("Wheel_FL").is_in_contact():
			rows.append("%4.0f km/h steer %.2f -> NO CONTACT (y=%.2f)" % [
				SPEEDS_KMH[speed_index], steer, car.global_position.y])
		else:
			var g: float = speed_now * yaw_mean / 9.81
			if g > peak_g:
				peak_g = g
				peak_steer = steer
				peak_slip = maxf(float(car.tyres.slip_front), float(car.tyres.slip_rear))
			rows.append("%4.0f km/h steer %.2f -> %.2f g (swept %.0f deg means %.1f m/s, yaw %.3f, slip_f %.3f slip_r %.3f, wheels %.3f)" % [
				SPEEDS_KMH[speed_index], steer, g, rad_to_deg(swept),
				speed_now, yaw_mean,
				float(car.tyres.slip_front), float(car.tyres.slip_rear), car.steering])
		acc_g = 0.0
		acc_count = 0
		phase_frames = 0
		step_index += 1
		if step_index >= STEPS.size():
			step_index = 0
			speed_index += 1
		# Clean slate for the next step: same place, same heading, target speed.
		var fwd: Vector3 = car.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		car.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), Vector3(0, 0.25, 0))
		car.linear_velocity = fwd * SPEEDS_KMH[speed_index] / 3.6 if speed_index < SPEEDS_KMH.size() else fwd * 20.0
		car.angular_velocity = Vector3.ZERO
		if speed_index >= SPEEDS_KMH.size():
			_finish()


func _finish() -> void:
	for r in rows:
		print("GRIP ", r)
	print("GRIP peak %.2f g at steer %.2f (slip %.3f)" % [peak_g, peak_steer, peak_slip])
	quit(0)


## Heading of the car in the ground plane: 0 = +Z (the car's own forward).
func _heading() -> float:
	var f: Vector3 = car.global_transform.basis.z
	return atan2(f.x, f.z)
