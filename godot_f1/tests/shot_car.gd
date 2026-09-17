extends SceneTree
## Renders the car with the real cockpit camera and saves PNGs so the layout can
## be eyeballed. A red pillar stands on +Z (driving direction), a blue one on -Z.

const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var car
var cam
var frames: int = 0
var plan := [
	{"frame": 100, "mode": 0, "file": "shot_cockpit.png"},
	{"frame": 150, "mode": 1, "file": "shot_chase.png"},
	{"frame": 200, "mode": 2, "file": "shot_heli.png"},
	{"frame": 260, "mode": 3, "file": "shot_side.png"},
	# Steering pair: same camera, wheels straight vs. full lock to the right.
	# The front rims used to be pinned straight ahead, so this is the picture
	# that proves the visible wheels really turn with the input.
	{"frame": 290, "mode": 3, "file": "shot_steer_straight.png", "steer": 0.0},
	# Ask for full right lock, then let the car slew its steering (~0.3 s)
	# before the second picture so the two are actually comparable.
	{"frame": 296, "steer": 1.0},
	{"frame": 350, "mode": 3, "file": "shot_steer_right.png", "steer": 1.0},
	# Same pair from inside the cockpit: the wheel and the gloved hands have to
	# turn together, and the front wheels must be visible steering.
	{"frame": 380, "mode": 0, "file": "shot_cockpit_straight.png", "steer": 0.0},
	{"frame": 386, "steer": 1.0},
	{"frame": 440, "mode": 0, "file": "shot_cockpit_right.png", "steer": 1.0},
]
var _side_cam: Camera3D


class StubWheel:
	## car_controller connects these in setup(); the shots only need the axes.
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


var stub: StubWheel


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	_build_world()
	process_frame.connect(_on_frame)


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 38, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
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
	road_mat.albedo_color = Color(0.13, 0.13, 0.15)
	road.material_override = road_mat
	road.position = Vector3(0, -0.02, -120)
	ground.add_child(road)
	var verge := MeshInstance3D.new()
	var verge_mesh := BoxMesh.new()
	verge_mesh.size = Vector3(80, 0.02, 400)
	verge.mesh = verge_mesh
	var verge_mat := StandardMaterial3D.new()
	verge_mat.albedo_color = Color(0.14, 0.28, 0.12)
	verge.material_override = verge_mat
	verge.position = Vector3(0, -0.05, -120)
	ground.add_child(verge)
	world.add_child(ground)

	_marker(world, Vector3(0, 1.5, 8.0), Color(0.85, 0.1, 0.1))    # ahead (+Z)
	_marker(world, Vector3(0, 1.5, -8.0), Color(0.15, 0.25, 0.9))   # behind (-Z)

	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	car.is_ai = false
	car.auto_drive = false
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))

	cam = CockpitCamera.new()
	cam.name = "Cam"
	world.add_child(cam)
	cam.setup(car, null)


func _marker(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 3.0, 0.4)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _on_frame() -> void:
	frames += 1
	for step in plan:
		if frames == int(step["frame"]):
			if step.has("steer"):
				# Hand the car a stub wheel so it steers itself at full lock:
				# at a standstill the speed-sensitive limiter allows all of it.
				if stub == null:
					stub = StubWheel.new()
					car.g29 = stub
				stub.steer = float(step["steer"])
			if step.has("mode") and int(step["mode"]) == 3:
				_make_side_camera()
			elif step.has("mode"):
				if _side_cam:
					_side_cam.queue_free()
					_side_cam = null
				cam.current = true
				cam.mode = int(step["mode"])
			# give the new pose one frame before grabbing it
		elif frames == int(step["frame"]) + 2 and step.has("file"):
			_shot(String(step["file"]))
	if frames > int(plan[plan.size() - 1]["frame"]) + 5:
		quit(0)


func _make_side_camera() -> void:
	_side_cam = Camera3D.new()
	_side_cam.name = "SideCam"
	root.get_child(0).add_child(_side_cam)
	_side_cam.position = Vector3(6.5, 2.6, -7.0)
	_side_cam.look_at(car.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	_side_cam.fov = 55.0
	_side_cam.current = true


func _shot(file: String) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT failed for ", file)
		return
	var err: int = img.save_png(OUT_DIR + "/" + file)
	print("SHOT ", file, " err=", err, " size=", img.get_size())
