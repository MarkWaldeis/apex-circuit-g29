extends SceneTree
## Measures the braking performance: from ~150 km/h down to walking speed.
## Gives a number for "do the pedals actually do something sensible".

const F1Car = preload("res://scripts/car_controller.gd")

var car
var frames: int = 0
var brake_frame: int = -1
var brake_pos: Vector3
var brake_speed: float = 0.0
var brake_time: float = 0.0
var stopped: bool = false
const TARGET_KMH := 150.0
const PHYS_HZ := 90.0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 3000)
	col.shape = box
	col.position = Vector3(0, -0.5, -1200)
	floor_body.add_child(col)
	world.add_child(floor_body)
	car = F1Car.new()
	car.is_ai = false
	car.auto_drive = false
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0)))
	car.apply_throttle(0.9)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if brake_frame < 0:
		if car.speed_kmh >= TARGET_KMH and frames > 60:
			brake_frame = frames
			brake_pos = car.global_position
			brake_speed = car.speed_kmh
			car.apply_throttle(0.0)
			car.apply_brake(1.0)
		return
	var t: float = float(frames - brake_frame) / PHYS_HZ
	if not stopped and car.speed_kmh < 5.0:
		stopped = true
		brake_time = t
		var dist: float = brake_pos.distance_to(car.global_position)
		print("BRAKE from %.0f km/h stopped in %.2f s over %.1f m" % [brake_speed, t, dist])
		quit(0)
		return
	if t > 15.0:
		print("BRAKE did not stop the car within 15 s, speed=%.1f km/h" % car.speed_kmh)
		quit(1)
