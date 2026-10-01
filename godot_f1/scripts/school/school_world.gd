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
var _exam_beam: MeshInstance3D
var surfaces := SchoolSurfaces.new()
var lights := JunctionLights.new()
var cam
var _lights_data: Dictionary = {}
var _spawn := Transform3D.IDENTITY
var _night := false
var _wet := false


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
	player.world = self
	player.global_transform = _spawn

	cam = ChaseCamera.new()
	cam.name = "ChaseCam"
	add_child(cam)
	cam.target = player

	# KI-Gegenverkehr: zwei Stadtautos auf der Blockrunde, halbe Runde
	# versetzt — die Welt fuehlt sich belebt an, der Fahrlehrer passt auf.
	var traffic_cars := []
	for s in [1, 5]:
		var tc := TrafficCar.new()
		tc.name = "TrafficCar%d" % s
		add_child(tc)
		tc.setup(lights, player, s)
		traffic_cars.append(tc)
	# Drittes Stadtauto auf der Kreisverkehr-Schleife: dort wer in den
	# Kreis einfaehrt, muss dem Ringverkehr Vorfahrt gewaehren.
	var tc_ring := TrafficCar.new()
	tc_ring.name = "TrafficCarRing"
	add_child(tc_ring)
	tc_ring.setup(lights, player, 3, 1)
	traffic_cars.append(tc_ring)

	var ped := Pedestrian.new()
	ped.name = "Pedestrian"
	add_child(ped)
	# Zweiter Fussgaenger am neuen Zebrastreifen in der Weststrasse.
	var ped2 := Pedestrian.new()
	ped2.name = "PedestrianWest"
	add_child(ped2)
	ped2.setup_crossing(Vector2(-94.5, -150.0), Vector2(-105.5, -150.0),
		Vector2(-100.0, -150.0), 3.6)
	# Beide gehen erst los, wenn kein Fahrzeug an der Querung ankommt.
	var peds := [ped, ped2]
	for p in peds:
		p.watchers = [player] + traffic_cars
	for tc in traffic_cars:
		tc.pedestrians = peds

	instructor = SchoolInstructor.new()
	instructor.setup(player, surfaces, lights)
	instructor.pedestrians = peds
	instructor.cams = built.get("cams", [])
	instructor.cyclist = built.get("cyclist")
	instructor.traffic = traffic_cars
	# Ziel-Marker der Pruefungsfahrt: leuchtende Saeule am naechsten Wegpunkt.
	_exam_beam = MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.45
	bcyl.bottom_radius = 0.45
	bcyl.height = 26.0
	_exam_beam.mesh = bcyl
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.9, 1.0, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color(0.2, 0.9, 1.0)
	bmat.emission_energy_multiplier = 1.6
	_exam_beam.material_override = bmat
	_exam_beam.visible = false
	add_child(_exam_beam)
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
		_update_exam_beam()
	if player and DisplayServer.get_name() == "headless":
		var frames: int = Engine.get_physics_frames()
		if frames in [60, 180, 360, 720, 1440]:
			print("SCHOOL_DRIVE pos=", player.global_position, " kmh=", snapped(player.speed_kmh, 0.1),
				" gear=", player.gear, " rpm=", int(player.rpm), " stalled=", player.stalled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_U:
		_night = not _night
		WorldEnv.set_night(self, _night)
		if instructor:
			if _night:
				instructor._say("Nachtfahrt — Abblendlicht an (Taste L).", 0)
			else:
				instructor._say("Wieder hell — Licht kann aus bleiben.", 0)
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_M:
		_wet = not _wet
		if surfaces:
			surfaces.set_wet(_wet)
		if instructor:
			if _wet:
				instructor._say("Nasse Fahrbahn — Grip lässt nach: früher bremsen, sanfter lenken, mehr Abstand.", 0)
			else:
				instructor._say("Wieder trocken — normale Fahrbahnhaftung.", 0)
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_P:
		if instructor:
			instructor.toggle_exam()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F1:
		if hud and hud.has_method("toggle_help"):
			hud.toggle_help()


func _update_exam_beam() -> void:
	if instructor == null or _exam_beam == null:
		return
	var on: bool = instructor.exam.active
	_exam_beam.visible = on
	if on:
		var wp: Vector2 = instructor.exam.next_wp()
		_exam_beam.position = Vector3(wp.x, 13.0, wp.y)
