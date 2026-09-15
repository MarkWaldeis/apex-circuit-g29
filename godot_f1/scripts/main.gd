extends Node3D

const RacingLine = preload("res://scripts/racing_line.gd")
const G29Input = preload("res://scripts/g29_input.gd")
const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")
const TrackLoader = preload("res://scripts/track_loader.gd")
const RaceHUD = preload("res://scripts/hud.gd")

var line = RacingLine.new()
var player
var ai_car
var cam
var g29
var _start_z: float = 0.0


func _ready() -> void:
	_build_world()
	if not line.load_json("res://assets/track/racing_line.json"):
		push_error("Failed to load racing line")
		return
	g29 = G29Input.new()
	g29.name = "G29"
	add_child(g29)

	var track := TrackLoader.new()
	track.name = "Track"
	add_child(track)
	_build_road_boxes()

	var start := _start_transform(0)
	player = _spawn_car("crimson", false, false, start)
	var ai_start := _start_transform(1)
	ai_car = _spawn_car("papaya", true, true, ai_start)
	ai_car.collision_layer = 2
	ai_car.collision_mask = 1
	player.collision_layer = 2
	player.collision_mask = 1

	cam = CockpitCamera.new()
	cam.name = "CockpitCam"
	player.add_child(cam)
	cam.setup(player, g29)
	_start_z = player.global_position.z
	if DisplayServer.get_name() == "headless":
		player.set_meta("headless_gas", true)
		print("LAP_DRIVE start_z=", _start_z)

	var hud := RaceHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.car = player
	hud.g29 = g29


func _start_transform(grid_index: int) -> Transform3D:
	# Main straight is Godot -Z. Aim vehicle +Z that way so the cockpit
	# looks down the road, not into T9's 10° join tangent.
	var forward := Vector3(0, 0, -1)
	var right := Vector3.UP.cross(forward).normalized()
	var side := -2.6 if grid_index % 2 == 0 else 2.6
	var along := 14.0 + float(grid_index) * 8.0
	var origin := Vector3(0, 0.14, 0) + forward * along + right * side
	var basis := Basis.looking_at(-forward, Vector3.UP)
	return Transform3D(basis, origin)


func _build_road_boxes() -> void:
	# VehicleWheel rays are unreliable on a zero-thickness trimesh. Lay convex
	# boxes along the racing line so the cars have a solid driving surface.
	var body := StaticBody3D.new()
	body.name = "RoadBoxes"
	add_child(body)
	# Backup slab on the main straight (Godot -Z from the S/F).
	var slab := CollisionShape3D.new()
	var slab_box := BoxShape3D.new()
	slab_box.size = Vector3(18.0, 0.5, 420.0)
	slab.shape = slab_box
	slab.position = Vector3(0.0, -0.12, -210.0)
	body.add_child(slab)
	var step := 2
	var n: int = line.points.size()
	var i := 0
	while i < n:
		var p: Vector3 = line.points[i]
		var t: Vector3 = line.tangents[i]
		t.y = 0.0
		if t.length() < 0.001:
			t = Vector3(0, 0, -1)
		t = t.normalized()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(18.0, 0.3, 4.0)
		col.shape = box
		var basis := Basis.looking_at(-t, Vector3.UP)
		col.transform = Transform3D(basis, p + Vector3(0, -0.11, 0))
		body.add_child(col)
		i += step
	print("RoadBoxes ", body.get_child_count())


func _spawn_car(livery: String, is_ai: bool, auto: bool, xform: Transform3D):
	var car := F1Car.new()
	car.name = "AI_" + livery if is_ai else "Player"
	car.livery = livery
	car.is_ai = is_ai
	car.auto_drive = auto
	add_child(car)
	car.setup(line, g29, xform)
	car.global_transform = xform
	return car


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "World"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_bottom_color = Color(0.08, 0.16, 0.08)
	sky_mat.ground_horizon_color = Color(0.18, 0.28, 0.16)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_density = 0.0008
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = environment
	add_child(env)


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var frames: int = Engine.get_physics_frames()
	if frames in [80, 160, 320, 640, 1200, 1800, 2400]:
		var fl = player.get_node_or_null("Wheel_FL")
		var contact: bool = false
		if fl:
			contact = fl.is_in_contact()
		var fwd: float = player.global_transform.basis.z.dot(player.linear_velocity)
		var disp: float = _start_z - player.global_position.z
		print("LAP_DRIVE pos=", player.global_position, " kmh=", snapped(player.speed_kmh, 0.1), " gear=", player.gear, " fwd=", snapped(fwd, 0.01), " contact=", contact, " disp=", snapped(disp, 0.1))
		print("PLAYER pos=", player.global_position, " kmh=", snapped(player.speed_kmh, 0.1), " gear=", player.gear, " fwd=", snapped(fwd, 0.01), " contact=", contact)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
