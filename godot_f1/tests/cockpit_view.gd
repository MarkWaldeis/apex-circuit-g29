extends SceneTree
## Diagnostic harness for the cockpit rebuild. Renders the real cockpit camera
## plus the same view with individual parts switched off, so a grey blob in the
## frame can be attributed to the car's own bodywork or to a cockpit prop.

const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var car
var cam
var inspect: Camera3D
var frames: int = 0


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
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	world.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
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

	# Kerb-like stripes beside the road, so the direction of travel is obvious.
	for i in 24:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.0, 0.03, 4.0)
		stripe.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color(0.92, 0.92, 0.92)
		stripe.material_override = mat
		stripe.position = Vector3(8.6, -0.01, 20.0 - float(i) * 4.0)
		world.add_child(stripe)

	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))

	cam = CockpitCamera.new()
	cam.name = "Cam"
	world.add_child(cam)
	cam.setup(car, null)


func _on_frame() -> void:
	frames += 1
	match frames:
		50:
			_shot("cv_full.png")
		60:
			if cam.cockpit:
				cam.cockpit.visible = false
		63:
			_shot("cv_car_only.png")
			if cam.cockpit:
				cam.cockpit.visible = true
		70:
			var halo = cam.cockpit.get_node_or_null("HaloRing")
			if halo:
				halo.visible = false
		73:
			_shot("cv_no_halo.png")
		75:
			var halo2 = cam.cockpit.get_node_or_null("HaloRing")
			if halo2:
				halo2.visible = true
			_make_inspect()
		80:
			_shot("cv_inspect.png")
		88:
			# Narrow lens from the driver's own eye: this is the shot that shows
			# whether the hands really grip the rim.
			inspect.current = false
			var zoom := Camera3D.new()
			zoom.name = "WheelZoom"
			root.get_child(0).add_child(zoom)
			zoom.fov = 24.0
			zoom.near = 0.02
			zoom.global_transform = cam.global_transform
			var aim: Vector3 = cam.global_transform * Vector3(0.0, -0.13, -0.40)
			zoom.look_at(aim, Vector3.UP)
			zoom.current = true
		92:
			_shot("cv_wheel.png")
		100:
			_dump(car)
			quit(0)


func _make_inspect() -> void:
	inspect = Camera3D.new()
	inspect.name = "Inspect"
	root.get_child(0).add_child(inspect)
	inspect.fov = 50.0
	inspect.near = 0.02
	var xf: Transform3D = car.global_transform
	inspect.global_position = xf * Vector3(0.0, 1.95, 1.35)
	inspect.look_at(xf * Vector3(0.0, 1.02, -0.45), Vector3.UP)
	inspect.current = true


func _dump(node: Node, depth: int = 0) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var mats: Array = []
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(i)
			mats.append(m.resource_name if m else "<none>")
		print("MESH ", "  ".join(mats), " node=", node.name, " layers=", mi.layers,
			" aabb=", mi.get_aabb())
	for c in node.get_children():
		_dump(c, depth + 1)


func _shot(file: String) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT failed ", file)
		return
	print("SHOT ", file, " err=", img.save_png(OUT_DIR + "/" + file))
