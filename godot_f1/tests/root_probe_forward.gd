extends SceneTree
## Root probe: which world direction does a POSITIVE engine_force push a
## VehicleBody3D? Also reports the local -Z / +Z convention, so the "I drive
## backwards" bug can be settled with a measurement instead of a comment.
##
## Run: godot --headless --path godot_f1 --script tests/root_probe_forward.gd

var car: VehicleBody3D
var start_z: float = 0.0
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	var floor_body := StaticBody3D.new()
	world.add_child(floor_body)
	var cs := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(80.0, 1.0, 600.0)
	cs.shape = slab
	cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(cs)

	car = VehicleBody3D.new()
	car.mass = 740.0
	car.can_sleep = false
	world.add_child(car)

	var col := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(1.8, 0.55, 3.9)
	col.shape = hull
	col.position = Vector3(0.0, 0.60, -0.28)
	car.add_child(col)

	# Real axle layout of car_crimson.glb: FRONT axle at z=-2.0, REAR at z=+1.43.
	var axles := [
		{"name": "F_L", "pos": Vector3(-0.86, 0.18, -2.005), "front": true},
		{"name": "F_R", "pos": Vector3(0.88, 0.18, -2.005), "front": true},
		{"name": "R_L", "pos": Vector3(-0.91, 0.18, 1.434), "front": false},
		{"name": "R_R", "pos": Vector3(0.91, 0.18, 1.433), "front": false},
	]
	for a in axles:
		var w := VehicleWheel3D.new()
		w.name = a["name"]
		w.position = a["pos"]
		w.use_as_steering = a["front"]
		w.use_as_traction = not a["front"]
		w.wheel_radius = 0.3654
		w.wheel_rest_length = 0.18
		w.suspension_travel = 0.18
		w.suspension_stiffness = 52.0
		w.suspension_max_force = 14000.0
		w.damping_compression = 0.82
		w.damping_relaxation = 0.92
		w.wheel_friction_slip = 7.8
		w.wheel_roll_influence = 0.08
		car.add_child(w)

	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0))
	start_z = car.global_position.z
	print("PROBE_GENERIC car forward=-Z?  basis.z=", car.global_transform.basis.z)
	await physics_frame
	car.engine_force = 500.0
	await physics_frame


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames % 60 == 0 and frames <= 180:
		var dz: float = car.global_position.z - start_z
		var fwd_along_minus_z: float = -car.linear_velocity.z
		print("PROBE_GENERIC f=%d pos=%s dz=%+.3f v=%s minusZ_speed=%+.3f" % [
			frames, str(car.global_position), dz, str(car.linear_velocity), fwd_along_minus_z])
	if frames == 200:
		var dz: float = car.global_position.z - start_z
		print("PROBE_GENERIC RESULT positive engine_force moved the car dz=%+.3f (negative dz == towards -Z)" % dz)
		print("PROBE_GENERIC VERDICT ", ("positive engine_force pushes towards -Z" if dz < -0.5 else (
			"positive engine_force pushes towards +Z" if dz > 0.5 else "inconclusive")))
		quit()
	return false
