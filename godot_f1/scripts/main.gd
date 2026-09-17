extends Node3D

const RacingLine = preload("res://scripts/racing_line.gd")
const G29Input = preload("res://scripts/g29_input.gd")
const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")
const TrackLoader = preload("res://scripts/track_loader.gd")
const RaceHUD = preload("res://scripts/hud.gd")
const MenuUI = preload("res://scripts/menu.gd")
const IdealLine = preload("res://scripts/ideal_line.gd")
const RacingLineDisplay = preload("res://scripts/racing_line_display.gd")
const Barriers = preload("res://scripts/barriers.gd")

var line = RacingLine.new()
## The ideal line and the ribbon that shows it: green where the throttle stays
## down, yellow where the driver lifts, red where the brakes come on.
var ideal
var guide
var player
var ai_car
var cam
var g29
var menu
var hud
var _start_z: float = 0.0


func _ready() -> void:
	_build_world()
	if not line.load_json("res://assets/track/racing_line.json"):
		push_error("Failed to load racing line")
		return
	ideal = IdealLine.new()
	ideal.build(line)
	g29 = G29Input.new()
	g29.name = "G29"
	add_child(g29)
	# Pedals/wheel must keep being read while the menu pauses the race
	# (calibration happens with the race frozen).
	g29.process_mode = Node.PROCESS_MODE_ALWAYS

	var track := TrackLoader.new()
	track.name = "Track"
	add_child(track)
	_build_road_boxes()
	# Walls where the circuit's barriers stand. Without them the barrier mesh
	# is decoration and the car drives straight through it.
	Barriers.build(self, line)

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

	hud = RaceHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.car = player
	hud.g29 = g29
	hud.cam = cam

	guide = RacingLineDisplay.new()
	guide.name = "Guide"
	add_child(guide)
	guide.build(line, ideal)

	menu = MenuUI.new()
	menu.name = "Menu"
	add_child(menu)
	menu.setup(player, g29, self)
	if DisplayServer.get_name() == "headless":
		# Smoke runs and tests drive straight away — no menu, no pause.
		menu.headless_autostart()
	else:
		menu.open_start_menu()


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
	# The 18 m road strip only reaches ~9 m either side of the line. Everything
	# beyond it used to be empty space, so a car that ran wide free-fell out of
	# the world (test_lap_drive telemetry: player at y = -30 m at 175 km/h).
	# A wide apron at track height gives those excursions a surface to rejoin
	# from; car_controller.gd::rejoin_to_line() is the net below that.
	_build_strip(body, 60.0, 8.0, 6, -0.11)
	_build_strip(body, 18.0, 4.0, 2, -0.11)
	# Backup slab on the main straight (Godot -Z from the S/F).
	var slab := CollisionShape3D.new()
	var slab_box := BoxShape3D.new()
	slab_box.size = Vector3(18.0, 0.5, 420.0)
	slab.shape = slab_box
	slab.position = Vector3(0.0, -0.12, -210.0)
	body.add_child(slab)
	print("RoadBoxes ", body.get_child_count())


func _build_strip(body: StaticBody3D, width: float, depth: float, step: int, y_offset: float) -> void:
	## Boxes every `step` line points, laid flat along the local tangent.
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
		box.size = Vector3(width, 0.3, depth)
		col.shape = box
		var basis := Basis.looking_at(-t, Vector3.UP)
		col.transform = Transform3D(basis, p + Vector3(0, y_offset, 0))
		body.add_child(col)
		i += step


func _spawn_car(livery: String, is_ai: bool, auto: bool, xform: Transform3D):
	var car := F1Car.new()
	car.name = "AI_" + livery if is_ai else "Player"
	car.livery = livery
	car.is_ai = is_ai
	car.auto_drive = auto
	add_child(car)
	car.setup(line, g29, xform)
	# The AI drives the ideal line (apex, corner speed, brake points); the
	# player's car gets it too, so the HUD and the tests can see the same line
	# the game shows on the road.
	car.set_ideal_line(ideal)
	car.global_transform = xform
	return car


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Warm, low-ish afternoon sun with a soft edge.
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "World"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Late-afternoon race light: warm horizon, deeper blue overhead.
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.85, 0.80, 0.72)
	sky_mat.ground_bottom_color = Color(0.07, 0.12, 0.06)
	sky_mat.ground_horizon_color = Color(0.24, 0.32, 0.18)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.fog_enabled = true
	environment.fog_density = 0.0009
	environment.fog_light_color = Color(0.78, 0.80, 0.86)
	environment.fog_sky_affect = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 3.0
	environment.ssao_intensity = 1.4
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.15
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.05
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
	if event.is_action_pressed("toggle_line") and guide != null:
		guide.set_enabled(not guide.is_enabled())
