extends SceneTree
## Gating test: real F1Car + floor, throttle + upshifts, forward + contact + gear.

const F1Car = preload("res://scripts/car_controller.gd")

var world: Node3D
var car
var frames: int = 0
var start_gear: int = 1


func _initialize() -> void:
	print("DRIVE_UNIT boot")
	call_deferred("_boot")


func _boot() -> void:
	print("DRIVE_UNIT deferred")
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 400)
	col.shape = box
	col.position = Vector3(0, -0.5, -100)
	floor_body.add_child(col)
	world.add_child(floor_body)
	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	car.is_ai = false
	car.auto_drive = false
	world.add_child(car)
	print("DRIVE_UNIT car in tree=", car.is_inside_tree())
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, null, start)
	print("DRIVE_UNIT setup ok")
	car.global_transform = start
	car.apply_throttle(0.9)
	start_gear = car.gear
	print("DRIVE_UNIT start gear=", start_gear, " pos=", car.global_position)
	physics_frame.connect(_on_phys)
	print("DRIVE_UNIT physics connected")


func _on_phys() -> void:
	frames += 1
	if frames % 40 == 0:
		car._on_shift_up()
	if frames in [80, 160, 240, 400]:
		_report()
	if frames == 400:
		_finish()


func _report() -> void:
	var fwd: float = car.global_transform.basis.z.dot(car.linear_velocity)
	var fl = car.get_node_or_null("Wheel_FL")
	var contact: bool = false
	if fl:
		contact = fl.is_in_contact()
	print("DRIVE_UNIT f=", frames, " kmh=", snapped(car.speed_kmh, 0.1), " gear=", car.gear, " fwd=", snapped(fwd, 0.01), " contact=", contact)


func _finish() -> void:
	var fwd: float = car.global_transform.basis.z.dot(car.linear_velocity)
	var fl = car.get_node_or_null("Wheel_FL")
	var contact: bool = false
	if fl:
		contact = fl.is_in_contact()
	var failed := 0
	if fwd <= 0.0:
		push_error("FAIL fwd=%s expected > 0" % fwd)
		failed += 1
	if car.speed_kmh < 8.0:
		push_error("FAIL speed=%s expected rise" % car.speed_kmh)
		failed += 1
	if car.gear <= start_gear:
		push_error("FAIL gear=%s did not increase from %s" % [car.gear, start_gear])
		failed += 1
	if not contact:
		push_error("FAIL wheels not in contact")
		failed += 1
	if failed > 0:
		print("DRIVE_UNIT FAIL count=", failed)
		quit(1)
	else:
		print("DRIVE_UNIT PASS kmh=", snapped(car.speed_kmh, 0.1), " gear=", car.gear, " fwd=", snapped(fwd, 0.01))
		quit(0)
