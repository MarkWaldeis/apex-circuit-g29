extends Node3D
## Fahrschul-Welt: Übungsplatz + Stadtverkehr auf den Daten aus
## city_layout.gd. Gegenstück zu main.gd (F1); beide werden aus
## scenes/boot.tscn gewählt und teilen sich Menü, Lenkradmodul und
## Force-Feedback-Kette.
##
## headless: Tests setzen `player.set_meta("headless_gas")` oder die
## script_*-Haken des Autos; das Menü startet ohne Wartezeit durch.

const CityBuilder = preload("res://scripts/school/city_builder.gd")
const CityLayout = preload("res://scripts/school/city_layout.gd")
const JunctionLights = preload("res://scripts/school/junction_lights.gd")
const SchoolCar = preload("res://scripts/school/school_car.gd")
const SchoolSurfaces = preload("res://scripts/school/school_surfaces.gd")
const SchoolInstructor = preload("res://scripts/school/school_instructor.gd")
const TrafficCar = preload("res://scripts/school/traffic_car.gd")
const Pedestrian = preload("res://scripts/school/pedestrian.gd")
const SchoolHUD = preload("res://scripts/school/school_hud.gd")
const ChaseCamera = preload("res://scripts/chase_camera.gd")
const G29Input = preload("res://scripts/g29_input.gd")
const MenuUI = preload("res://scripts/menu.gd")
const FfbSettings = preload("res://scripts/ffb_settings.gd")
const WorldEnv = preload("res://scripts/world_env.gd")

var player
var g29
var ffb_settings
var menu
var hud
var instructor
var surfaces := SchoolSurfaces.new()
var lights := JunctionLights.new()
var cam
var _lights_data: Dictionary = {}
var _spawn := Transform3D.IDENTITY


func _ready() -> void:
	WorldEnv.build(self)
	surfaces.setup()
	var built: Dictionary = CityBuilder.new().build(self)
	_lights_data = built.get("lights", {})

	ffb_settings = FfbSettings.new()
	ffb_settings.load_profile()
	ffb_settings.auto_save = DisplayServer.get_name() != "headless"
	g29 = G29Input.new()
	g29.name = "G29"
	g29.ffb_settings = ffb_settings
	add_child(g29)
	g29.process_mode = Node.PROCESS_MODE_ALWAYS

	_spawn = CityLayout.spawn()
	player = SchoolCar.new()
	player.name = "SchoolCar"
	player.ffb_settings = ffb_settings
	add_child(player)
	player.setup(g29, surfaces, _spawn)
	player.global_transform = _spawn

	cam = ChaseCamera.new()
	cam.name = "ChaseCam"
	add_child(cam)
	cam.target = player

	# KI-Gegenverkehr: zwei Stadtautos auf der Blockrunde, halbe Runde
	# versetzt — die Welt fuehlt sich belebt an, der Fahrlehrer passt auf.
	for s in [1, 5]:
		var tc := TrafficCar.new()
		tc.name = "TrafficCar%d" % s
		add_child(tc)
		tc.setup(lights, player, s)

	var ped := Pedestrian.new()
	ped.name = "Pedestrian"
	add_child(ped)

	instructor = SchoolInstructor.new()
	instructor.setup(player, surfaces, lights)
	instructor.pedestrian = ped
	if DisplayServer.get_name() == "headless":
		player.set_meta("headless_gas", true)
		player.assists["auto_gearbox"] = true

	hud = SchoolHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, g29, instructor)

	menu = MenuUI.new()
	menu.name = "Menu"
	add_child(menu)
	menu.setup(player, g29, self)
	if DisplayServer.get_name() == "headless":
		menu.headless_autostart()
	else:
		menu.open_start_menu()


func _physics_process(delta: float) -> void:
	if lights:
		lights.update(delta)
	# Ampeln dem aktuellen Zyklus nachschalten.
	for item in _lights_data.get("lights", []):
		var light = item["light"]
		if is_instance_valid(light):
			light.set_phase(lights.phase_of(String(item["arm"])))
	if instructor:
		instructor.update(delta)
	if player and DisplayServer.get_name() == "headless":
		var frames: int = Engine.get_physics_frames()
		if frames in [60, 180, 360, 720, 1440]:
			print("SCHOOL_DRIVE pos=", player.global_position, " kmh=", snapped(player.speed_kmh, 0.1),
				" gear=", player.gear, " rpm=", int(player.rpm), " stalled=", player.stalled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
