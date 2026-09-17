extends SceneTree
## Independent check of the steering chain, measured in world space.
##
## Ground truth: the car spawns nose-first down the main straight, so its nose
## points at world -Z and a driver sitting in it has his right hand towards
## world +X (a Godot camera looking down -Z also has +X on its right).
## A command "steer right" must therefore swing the nose towards world +X, the
## visible front rim must yaw the same way relative to the body, and the rim in
## the cockpit must turn clockwise (negative rotation.z in camera space).

const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")


class StubWheel:
	signal shift_up
	signal shift_down
	var steer: float = 0.0
	var throttle: float = 0.0
	var brake: float = 0.0
	var clutch: float = 0.0
	var connected: bool = true
	var cal_phase: int = 0

	func has_driver_input() -> bool:
		return true


var car
var cam
var wheel
var frames: int = 0
var heading0: Vector3


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
	col.position = Vector3(0, -0.5, -200)
	floor_body.add_child(col)
	world.add_child(floor_body)

	wheel = StubWheel.new()

	car = F1Car.new()
	car.name = "Player"
	car.is_ai = false
	car.auto_drive = false
	world.add_child(car)
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, wheel, start)
	car.global_transform = start
	car.apply_throttle(0.4)
	heading0 = car.global_transform.basis.z

	cam = CockpitCamera.new()
	cam.name = "Cam"
	world.add_child(cam)
	cam.setup(car, wheel)
	# driver turns the wheel fully to the right
	wheel.steer = 1.0
	print("PROBE start heading=", heading0, " (expect ~(0,0,-1) = down the straight)")
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames < 90:
		return
	var heading: Vector3 = car.global_transform.basis.z
	var swing: float = heading.x - heading0.x
	print("PROBE after %d frames heading.x swings by %+.3f -> %s" % [
		frames, swing, "RIGHT (+X)" if swing > 0.02 else ("LEFT (-X)" if swing < -0.02 else "none")])
	print("PROBE physics steering value=%.3f" % car.steering)
	for key in ["Wheel_FL", "Wheel_FR"]:
		var w: Node3D = car.get_node_or_null(key)
		if w == null:
			continue
		var rim: Node3D = w.get_child(0) if w.get_child_count() > 0 else null
		var rel: float = 0.0
		if rim:
			var rel_basis: Basis = car.global_transform.basis.inverse() * rim.global_transform.basis
			rel = rel_basis.get_euler().y
		print("PROBE %s node.rotation.y=%+.3f rim yaw vs car=%+.3f -> %s" % [
			key, w.rotation.y, rel, "rim to the RIGHT" if rel < -0.02 else (
				"rim to the LEFT" if rel > 0.02 else "rim straight ahead")])
	if cam.wheel_visual:
		print("PROBE cockpit rim rotation.z=%+.3f -> %s" % [
			cam.wheel_visual.rotation.z,
			"clockwise (right)" if cam.wheel_visual.rotation.z < -0.02 else (
				"counter-clockwise (left)" if cam.wheel_visual.rotation.z > 0.02 else "centred")])
	quit(0)
