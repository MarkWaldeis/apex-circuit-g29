extends SceneTree
## Renders the cockpit from several eye heights with the horizon pinned at the
## reference's 30 %, so the effect of the eye height on how much of the driver's
## own car is in the way can be seen and measured instead of argued about.
##
## The cockpit camera's own _process() is switched off here and the pose is set
## from this harness, because camera_poses.gd is a constant.

const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"
const FOV := 54.0
const HORIZON_FRAC := 0.30
const HEIGHTS := [1.12, 1.30, 1.40, 1.48]

var car
var cam
var frames: int = 0
var step: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	env.environment = e
	world.add_child(env)

	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 400)
	col.shape = box
	col.position = Vector3(0, -0.5, -120)
	ground.add_child(col)
	var road := MeshInstance3D.new()
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(16, 0.04, 400)
	road.mesh = road_mesh
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.16, 0.16, 0.17)
	road.material_override = road_mat
	road.position = Vector3(0, -0.02, -120)
	ground.add_child(road)
	var verge := MeshInstance3D.new()
	var verge_mesh := BoxMesh.new()
	verge_mesh.size = Vector3(80, 0.02, 400)
	verge.mesh = verge_mesh
	var verge_mat := StandardMaterial3D.new()
	verge_mat.albedo_color = Color(0.16, 0.30, 0.14)
	verge.material_override = verge_mat
	verge.position = Vector3(0, -0.05, -120)
	ground.add_child(verge)
	world.add_child(ground)

	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))
	car.set_physics_process(false)

	cam = CockpitCamera.new()
	cam.name = "Cam"
	world.add_child(cam)
	cam.setup(car, null)
	cam.set_process(false)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_pose(float(HEIGHTS[0]))
	process_frame.connect(_on_frame)


func _pose(eye_y: float) -> void:
	var look_z: float = 16.0
	var pitch: float = deg_to_rad((HORIZON_FRAC - 0.5) * -FOV)
	cam.global_position = car.global_transform * Vector3(0.0, eye_y, 0.05)
	cam.look_at(car.global_transform * Vector3(0.0, eye_y - look_z * tan(pitch), 0.05 + look_z),
		Vector3.UP)
	cam.fov = FOV


func _on_frame() -> void:
	frames += 1
	if frames == 20 + step * 20:
		var eye_y: float = float(HEIGHTS[step])
		_pose(eye_y)
	if frames == 30 + step * 20:
		var img: Image = get_root().get_viewport().get_texture().get_image()
		var name := "occ_eye_%.2f.png" % float(HEIGHTS[step])
		print("SHOT ", name, " err=", img.save_png(OUT_DIR + "/" + name))
		step += 1
		if step >= HEIGHTS.size():
			quit(0)
