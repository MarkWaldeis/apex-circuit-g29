extends SceneTree
## Diagnostic: which sign of VehicleBody3D.steering yaws the car to the right?
## Right turn = the +Z forward axis rotates towards -X (Godot yaw decreases).

const F1Car = preload("res://scripts/car_controller.gd")

var car
var frames: int = 0


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
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	car.steering = 0.45
	if frames == 1:
		print("PROBE steer start yaw=", snapped(car.global_rotation.y, 0.0001))
	if frames == 180:
		var yaw: float = car.global_rotation.y
		var x: float = car.global_position.x
		print("PROBE steer=+0.45 after 180 frames yaw=", snapped(yaw, 0.0001), " x=", snapped(x, 0.01),
			" -> ", ("turns RIGHT (-X, negative yaw)" if (x < -0.2 or yaw < -0.05) else "turns LEFT (+X, positive yaw)"))
		quit(0)
