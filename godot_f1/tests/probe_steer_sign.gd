extends SceneTree
## Diagnostic: which sign of VehicleBody3D.steering yaws the car to the right?
## Right turn = the nose (+Z, the direction engine_force pushes) rotates
## towards -X, so the car drifts towards its own -X side.
##
## Measured in the car's own frame on purpose: reading the world x/yaw of a
## harness whose basis is rotated (looking_at flips the hull by 180 deg) gives
## the opposite answer for the same physics. That mistake once made this probe
## report "turns RIGHT" while the car was really steering left.

const F1Car = preload("res://scripts/car_controller.gd")

var car
var frames: int = 0
var start_heading: float = 0.0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	world.add_child(floor_body)
	car = F1Car.new()
	car.is_ai = false
	car.auto_drive = false
	world.add_child(car)
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, null, start)
	car.apply_throttle(0.7)
	car.set("_probe_steer", 0.45)
	start_heading = _heading()
	physics_frame.connect(_on_phys)


func _heading() -> float:
	var nose: Vector3 = car.global_transform.basis.z
	return atan2(nose.x, nose.z)


func _on_phys() -> void:
	frames += 1
	car.steering = 0.45
	if frames == 1:
		print("PROBE steer start heading=", snapped(start_heading, 0.0001))
	if frames == 180:
		var turn: float = wrapf(_heading() - start_heading, -PI, PI)
		var side: float = car.global_transform.basis.x.dot(car.linear_velocity)
		print("PROBE steering=+0.45 after 180 frames heading change=", snapped(turn, 0.0001),
			" rad, sideways drift=", snapped(side, 0.01), " m/s (negative == towards -X)",
			" -> ", ("turns RIGHT" if (turn < -0.05 or side < -0.1) else "turns LEFT"))
		quit(0)
