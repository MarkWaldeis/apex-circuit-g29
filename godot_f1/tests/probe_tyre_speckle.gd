extends SceneTree
## Independent check of the driver's tyre complaint ("die Reifen flackern").
##
## A stationary car with a stationary camera still flickers if two surfaces are
## fighting for the same depth: the patchwork pattern is fixed for one camera
## position and jumps to a different pattern as soon as the view moves. So this
## probe renders the same wheel twice from camera positions 1 mm apart and the
## two images are compared afterwards - coplanar geometry changes a large,
## scattered share of the wheel's pixels between the two.

const F1Car = preload("res://scripts/car_controller.gd")

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"
const FRAMES_PER_SHOT := 6

var car
var cam: Camera3D
var frames: int = 0
## Two frames from the identical pose: any difference between them is temporal
## instability (TAA jitter, depth fighting that depends on sub-pixel sample
## positions) rather than parallax. Then the same pair with TAA switched off, so
## the two causes can be told apart.
var shots := [
	{"nudge": 0.0000, "taa": true, "file": "tyre_taa_1.png"},
	{"nudge": 0.0000, "taa": true, "file": "tyre_taa_2.png"},
	{"nudge": 0.0000, "taa": false, "file": "tyre_notaa_1.png"},
	{"nudge": 0.0000, "taa": false, "file": "tyre_notaa_2.png"},
	{"nudge": 0.0010, "taa": false, "file": "tyre_notaa_moved.png"},
]
var step: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)

	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))
	car.set_physics_process(false)
	# Without this the car simply falls, and every frame differs for that reason
	# alone - which is what made the first version of this probe meaningless.
	car.freeze = true

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(60, 1, 60)
	shape.shape = slab
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	var floor := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(60, 0.04, 60)
	floor.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.16, 0.17)
	floor.material_override = fmat
	floor.position = Vector3(0, -0.02, 0)
	ground.add_child(floor)
	world.add_child(ground)

	cam = Camera3D.new()
	cam.name = "TyreCam"
	cam.fov = 32.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true
	_aim(0.0)
	process_frame.connect(_on_frame)


func _aim(nudge: float) -> void:
	## Looking straight at the outer face of the front-left tyre, which is where
	## the sidewall band, the rim spokes and the two decals all meet the rubber.
	var hub: Vector3 = car.global_position + Vector3(-0.860, 0.365, 1.434)
	var eye: Vector3 = hub + Vector3(-1.05 + nudge, 0.10, 0.0)
	cam.global_position = eye
	cam.look_at(hub, Vector3.UP)


func _on_frame() -> void:
	frames += 1
	var base: int = step * FRAMES_PER_SHOT
	if frames == base + 2:
		_aim(float(shots[step]["nudge"]))
		get_root().use_taa = bool(shots[step]["taa"])
		print("taa=", get_root().use_taa, " for ", shots[step]["file"])
		var w := car.get_node_or_null("Wheel_FL") as Node3D
		print("   car pos=", car.global_position, " wheel=",
			w.global_position if w else Vector3.ZERO)
	if frames == base + FRAMES_PER_SHOT:
		var img: Image = get_root().get_viewport().get_texture().get_image()
		var file: String = String(shots[step]["file"])
		print("SHOT ", file, " err=", img.save_png(OUT_DIR + "/" + file))
		step += 1
		if step >= shots.size():
			quit(0)
