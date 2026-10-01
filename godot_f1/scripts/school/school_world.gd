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
const PedCrossing = preload("res://scripts/school/ped_crossing.gd")
const Deer = preload("res://scripts/school/deer.gd")
const RailCrossing = preload("res://scripts/school/rail_crossing.gd")
const StreetBall = preload("res://scripts/school/street_ball.gd")
const RescueVehicle = preload("res://scripts/school/rescue_vehicle.gd")
const DoorCar = preload("res://scripts/school/door_car.gd")
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
var _fog := false
var _wet := false
var _icy := false
var _ground_mat: StandardMaterial3D
var _extra_traffic: Array = []   ## zusaetzliche KI-Autos (Taste G)
var _rain: GPUParticles3D        ## Regenpartikel ueber dem Auto
var _warndreieck: Node3D         ## aufgestelltes Warndreieck (Taste D)


func _ready() -> void:
	WorldEnv.build(self)
	surfaces.setup()
	var built: Dictionary = CityBuilder.new().build(self)
	_lights_data = built.get("lights", {})
	# Der Radfahrer bekommt den Ampel-Controller — er haelt bei Rot —
	# und das Schulauto, damit er nicht auffaehrt.
	if built.get("cyclist") != null:
		built["cyclist"].lights = lights
		built["cyclist"].player = player

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
	# Viertes Stadtauto auf Route C: Kreis -> Kreis-Nordstrasse, dort
	# Engstelle mit parkenden Autos — die VZ-208-Lektion braucht
	# echten Gegenverkehr in der Luecke.
	var tc_narrow := TrafficCar.new()
	tc_narrow.name = "TrafficCarNarrow"
	add_child(tc_narrow)
	tc_narrow.setup(lights, player, 2, 2)
	traffic_cars.append(tc_narrow)
	# Lkw auf der grossen Ring-Runde (Route D): er zieht mit ~40 km/h
	# seine Kreise — ein echter Anlass zum sicheren Ueberholen.
	var tc_truck := TrafficCar.new()
	tc_truck.name = "TrafficCarTruck"
	add_child(tc_truck)
	tc_truck.setup(lights, player, 4, 3)
	traffic_cars.append(tc_truck)

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
	# Die Fussgaengerampel haelt auch KI an, solange die Figur quert.
	var pedx_early := PedCrossing.new()
	pedx_early.name = "PedCrossing"
	add_child(pedx_early)
	_pedx = pedx_early
	peds.append(pedx_early.ped_node())
	_peds = peds
	for p in peds:
		p.watchers = [player] + traffic_cars

	# Reh am Wildwechsel am West-Ring: sprintet unvermittelt quer,
	# die KI bremst davor ueber dieselbe Schnittstelle wie Fussgaenger.
	var deer := Deer.new()
	deer.name = "DeerWest"
	add_child(deer)
	deer.player = player
	peds.append(deer)
	for tc in traffic_cars:
		tc.pedestrians = peds

	# Bahnuebergang an der Ring-Ost-Strasse (Schranken + Zug).
	var rail := RailCrossing.new()
	rail.center = CityLayout.rail_crossing()["center"]
	add_child(rail)
	_make_rain()

	# Ball zwischen parkenden Autos auf der Kreisverkehr-Nordstrasse.
	var ball := StreetBall.new()
	ball.name = "StreetBall"
	var sb := CityLayout.street_ball()
	ball.from = sb["from"]
	ball.to = sb["to"]
	ball._road = sb["road"]
	add_child(ball)

	# Zweiter Ball in der verkehrsberuhigten Zone: hier ist er kein
	# Aussenseiter, sondern Alltag — Kinder spielen auf der Strasse.
	var ball2 := StreetBall.new()
	ball2.name = "StreetBallSpiel"
	ball2.from = Vector2(-206.0, -176.5)
	ball2.to = Vector2(-206.0, -183.5)
	ball2._road = Vector2(-206.0, -180.0)
	add_child(ball2)

	# Dooring-Gefahr: parkendes Auto an der Weststrasse, dessen
	# Fahrertuer sich gelegentlich zur Fahrbahn oeffnet.
	var door_car := DoorCar.new()
	door_car.name = "DoorCar"
	door_car.position = Vector3(-102.4, 0.0, -90.0)
	add_child(door_car)

	# Rettungswagen: faehrt alle ~2,5 Min eine Alarmrunde ueber die
	# Hauptstrasse — Schueler muss Platz machen.
	var rescue := RescueVehicle.new()
	rescue.name = "RescueVehicle"
	add_child(rescue)
	rescue.setup(player)

	instructor = SchoolInstructor.new()
	# Der Schulbus geht an den Fahrlehrer: §20-Schritttempo-Check.
	instructor.school_bus = built.get("school_bus")
	_ground_mat = built.get("ground_mat")
	instructor.setup(player, surfaces, lights)
	instructor.pedestrians = [ped, ped2]
	instructor.deer = deer
	instructor.rail = rail
	instructor.ball = ball
	instructor.balls = [ball2]
	instructor.rescue = rescue
	instructor.door_car = door_car
	instructor.ped_crossing = _pedx
	instructor.cams = built.get("cams", [])
	instructor.cyclist = built.get("cyclist")
	instructor.cam = cam
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
	_rbl_trainer_tick(delta)
	_onc_trainer_tick(delta)
	if _rain and player:
		_rain.global_position = player.global_position + Vector3(0, 18, 0)
	if instructor:
		instructor.night = _night
		# Bei Nacht leuchten die Scheinwerfer des Gegenverkehrs.
		for t in instructor.traffic:
			if is_instance_valid(t):
				t.night = _night
		instructor.update(delta)
		_update_exam_beam()
	if player and DisplayServer.get_name() == "headless":
		var frames: int = Engine.get_physics_frames()
		if frames in [60, 180, 360, 720, 1440]:
			print("SCHOOL_DRIVE pos=", player.global_position, " kmh=", snapped(player.speed_kmh, 0.1),
				" gear=", player.gear, " rpm=", int(player.rpm), " stalled=", player.stalled)


## Verkehrsdichte umschalten: zwei zusaetzliche KI-Autos spawnen oder
## entfernen — so laesst sich die Stadt zwischen "ruhig zum Ueben" und
## "voll wie Berufsverkehr" umstellen (Taste G).
var _rbl_t: float = 20.0       ## Cooldown fuer den RvL-Trainer
var _onc_t: float = 30.0       ## Cooldown fuer den Gegenverkehr-Trainer
var _peds: Array = []          ## Fussgaenger+Reh — KI-Spawn braucht sie zum Bremsen
var _pedx                    ## Fussgaengerampel (ped_crossing.gd)


## Zufalls-RvL-Training: naehert sich der Schueler der RvL-Kreuzung
## (-100,-180), schickt die Welt gelegentlich ein KI-Auto von RECHTS
## des Schuelers quer — es hat Vorfahrt, der Schueler muss warten.
## Nur ausserhalb der Pruefungsfahrt, damit die Route nicht stoert.
func _rbl_trainer_tick(delta: float) -> void:
	_rbl_t = maxf(_rbl_t - delta, 0.0)
	if _rbl_t > 0.0 or player == null or instructor == null \
			or instructor.exam.active:
		return
	var jp := Vector2(-100.0, -180.0)
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var dj := pp.distance_to(jp)
	if dj < 13.0 or dj > 42.0:
		return
	var spd: float = player.linear_velocity.length()
	if spd < 1.5:
		return   # steht schon in der Kreuzung — nichts trainierbar
	_rbl_t = 50.0
	# Der naechste Arm rechts der Fahrtrichtung ist der "rechts von
	# dir"-Verkehr — der Trainer kommt genau von dort.
	var s_fwd := Vector2(player.global_transform.basis.z.x,
		player.global_transform.basis.z.z).normalized()
	if s_fwd == Vector2.ZERO:
		return
	var right := Vector2(-s_fwd.y, s_fwd.x)
	var want := jp + right * 6.5
	var best: Dictionary = {}
	var bd := 1e9
	for arm in CityLayout.junctions()["rbl_west"]["arms"]:
		var d: float = Vector2(arm["pos"]).distance_to(want)
		if d < bd:
			bd = d
			best = arm
	if best.is_empty():
		return
	var enter: Vector2 = best["enter"]
	# Auf der rechten Fahrspur des Arms — sonst faehrt der Trainer
	# mittig durch die Kreuzung.
	var off := Vector2(-enter.y, enter.x) * 1.8
	var start := Vector2(best["pos"]) - enter * 19.0 + off
	var goal := Vector2(best["pos"]) + enter * 28.0 + off
	# Freiheit fuer den Spawn: steht da schon ein KI-Auto, spaeter.
	for t in instructor.traffic:
		if is_instance_valid(t):
			var tp := Vector2(t.global_position.x, t.global_position.z)
			if tp.distance_to(start) < 12.0 or tp.distance_to(goal) < 12.0:
				_rbl_t = 8.0
				return
	var tc := TrafficCar.new()
	tc.name = "RvlTrainer"
	add_child(tc)
	tc.setup(lights, player, 1, -1, [start, goal])
	tc.pedestrians = _peds
	tc.night = _night
	instructor.traffic.append(tc)


## Linksabbiegen mit Gegenverkehr: blinkt der Schueler links an einer
## Kreuzung, schickt die Welt gelegentlich ein KI-Auto vom Gegenarm
## geradeaus durch — es hat Vorfahrt, der Schueler muss warten (§9).
## Nur ausserhalb der Pruefungsfahrt.
func _onc_trainer_tick(delta: float) -> void:
	_onc_t = maxf(_onc_t - delta, 0.0)
	if _onc_t > 0.0 or player == null or instructor == null \
			or instructor.exam.active:
		return
	if not bool(player.get("indicator_left")):
		return
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var s_fwd := Vector2(player.global_transform.basis.z.x,
		player.global_transform.basis.z.z).normalized()
	if s_fwd == Vector2.ZERO:
		return
	var spd: float = player.linear_velocity.length()
	if spd > 5.0:
		return
	# Naechste Kreuzung vor dem Schueler (kein Kreisverkehr: dort gilt
	# ein anderes Regelwerk).
	var best_j: Dictionary = {}
	var bd := 1e9
	for j in CityLayout.junctions().values():
		if String(j["kind"]) == "roundabout" or j["arms"].size() < 3:
			continue
		var c: Vector2 = j["center"]
		var d: float = p2.distance_to(c)
		if d < 7.0 or d > 24.0:
			continue
		if (c - p2).normalized().dot(s_fwd) < 0.35:
			continue
		if d < bd:
			bd = d
			best_j = j
	if best_j.is_empty():
		return
	# Schueler-Arm (naehester) und der gegenueberliegende Arm —
	# dessen enter zeigt dem des Schuelers entgegen.
	var s_arm: Dictionary = {}
	var o_arm: Dictionary = {}
	var sd := 1e9
	for arm in best_j["arms"]:
		var d: float = Vector2(arm["pos"]).distance_to(p2)
		if d < sd:
			sd = d
			s_arm = arm
	if s_arm.is_empty():
		return
	var s_enter: Vector2 = s_arm["enter"]
	var od := 1e9
	for arm in best_j["arms"]:
		var e: Vector2 = arm["enter"]
		var d: float = (e + s_enter).length()   # ~0 wenn genau entgegengesetzt
		if d < od:
			od = d
			o_arm = arm
	if o_arm.is_empty() or o_arm == s_arm or od > 0.4:
		return
	# Verkehrte Lektion vermeiden: steht der Schueler auf einem
	# Biegungsarm der Vorfahrtstrasse oder muesste der Trainer an
	# einem Vorfahrt-gewaehren-Arm selbst warten, haette der Trainer
	# gar keine Vorfahrt — also lieber gar nicht spawnen.
	if s_arm.get("bend_yaw") != null or o_arm.get("yield", false):
		return
	_onc_t = 60.0
	var enter: Vector2 = o_arm["enter"]
	# Rechte Spur des Gegenarms; der Kurs fuehrt mittig durch die Kreuzung
	# in den Schueler-Arm — so muss der Linksabbieger wirklich warten.
	var off := Vector2(-enter.y, enter.x) * 1.8
	var start := Vector2(o_arm["pos"]) - enter * 18.0 + off
	var goal := Vector2(o_arm["pos"]) + enter * 30.0 + off
	for t in instructor.traffic:
		if is_instance_valid(t):
			var tp := Vector2(t.global_position.x, t.global_position.z)
			if tp.distance_to(start) < 12.0 or tp.distance_to(goal) < 12.0:
				_onc_t = 10.0
				return
	var tc := TrafficCar.new()
	tc.name = "OncomingTrainer"
	tc.set_meta("oncoming_j", best_j["center"])
	add_child(tc)
	tc.setup(lights, player, 1, -1, [start, goal])
	tc.ttl = 30.0                 # blockiert der Schueler den Kurs, despawnt er
	tc.pedestrians = _peds
	tc.night = _night
	instructor.traffic.append(tc)


## Regen-Partikelstrahl ueber dem Spieler (Naesse-Taste M).
func _make_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-40, -15, -40), Vector3(80, 30, 80))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	mat.direction = Vector3(0.0, -1.0, 0.15)
	mat.spread = 4.0
	mat.initial_velocity_min = 26.0
	mat.initial_velocity_max = 34.0
	mat.gravity = Vector3(0.0, -2.0, 0.0)
	_rain.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.015, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.65, 0.75, 0.9, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	_rain.draw_pass_1 = quad
	add_child(_rain)


func _toggle_traffic() -> void:
	if _extra_traffic.is_empty():
		for cfg in [{"route": 0, "start": 3}, {"route": 1, "start": 7}]:
			var tc := TrafficCar.new()
			tc.name = "TrafficExtra%d" % _extra_traffic.size()
			add_child(tc)
			tc.setup(lights, player, int(cfg["start"]), int(cfg["route"]))
			_extra_traffic.append(tc)
			instructor.traffic.append(tc)
		if instructor:
			instructor._say("Mehr Verkehr — wie Berufsverkehr: mehr Vorausschau, mehr Abstand.", 0)
	else:
		for tc in _extra_traffic:
			instructor.traffic.erase(tc)
			tc.queue_free()
		_extra_traffic.clear()
		if instructor:
			instructor._say("Verkehr wieder normal — Platz zum Üben.", 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_B:
		if player and player.has_method("honk"):
			player.honk()
		if instructor:
			instructor._warn("Hupe ist das Warnsignal — in der Stadt nur bei Gefahr erlaubt.")
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_Z:
		if instructor:
			instructor.report()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_G:
		_toggle_traffic()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_X:
		if instructor and player:
			instructor.explain_nearest_sign(
				Vector2(player.global_position.x, player.global_position.z))
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_U:
		_night = not _night
		if instructor:
			instructor.night = _night
		WorldEnv.set_night(self, _night)
		if _fog:
			WorldEnv.set_fog(self, true)    ## Nebeldichte zuruecksetzen
		if instructor:
			if _night:
				instructor._say("Nachtfahrt — Abblendlicht an (Taste L).", 0)
			else:
				instructor._say("Wieder hell — Licht kann aus bleiben.", 0)
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_I:
		_fog = not _fog
		WorldEnv.set_fog(self, _fog)
		if instructor:
			instructor.fog = _fog
			if _fog:
				instructor._say("Nebel — Sichtweite unter 100 m: Abblendlicht an, Tempo runter, Abstand größer.", 0)
			else:
				instructor._say("Nebel hat sich gelichtet.", 0)
		if not _fog and _night:
			WorldEnv.set_night(self, true)   ## Nacht-Nebelwerte zurueck
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_M:
		_wet = not _wet
		if surfaces:
			surfaces.set_wet(_wet)
		if _rain:
			_rain.emitting = _wet
		if instructor:
			if _wet:
				instructor._say("Regen — Grip lässt nach und die Scheibe beschlägt: früher bremsen, sanfter lenken, mehr Abstand.", 0)
			else:
				instructor._say("Wieder trocken — normale Fahrbahnhaftung.", 0)
	# Glätte/Winter: Grip bricht stark ein, die Landschaft faerbt sich
	# weiss — ideale Uebungswelt fuer Bremsweg und ruhige Fahrweise.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_O:
		_icy = not _icy
		if surfaces:
			surfaces.set_icy(_icy)
		if _ground_mat:
			_ground_mat.albedo_color = Color(0.82, 0.85, 0.9) if _icy \
				else Color(0.20, 0.36, 0.17)
		if instructor:
			if _icy:
				instructor._say("Glatteis! Sehr sanft lenken und bremsen — der Bremsweg vervielfacht sich.", 0)
			else:
				instructor._say("Wieder normale Haftung — der Winter ist vorbei.", 0)
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_D:
		_place_warndreieck()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_P:
		if instructor:
			instructor.toggle_exam()
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F1:
		if hud and hud.has_method("toggle_help"):
			hud.toggle_help()


## Warndreieck (Taste D): gehoert zur Pannen-Absicherung — nur sinnvoll,
## wenn das Auto in der Pannenzone steht und der Warnblinker laeuft.
## Es wird ~50 m hinter dem Auto auf die Fahrbahnkante gestellt
## (StVO: innerorts ca. 50 m Sicherungsabstand).
func _place_warndreieck() -> void:
	if instructor == null or player == null:
		return
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var zone := CityLayout.pannen_zone()
	if not zone.has_point(p2) or player.linear_velocity.length() > 0.5:
		instructor._say("Das Warndreieck gehört zur Panne — erst in der Pannenzone am Rand anhalten.", 0)
		return
	if not bool(player.get("hazard")):
		instructor._say("Erst den Warnblinker einschalten (Taste H), dann das Warndreieck.", 0)
		return
	if _warndreieck != null:
		instructor._say("Das Warndreieck steht schon.", 0)
		return
	var fwd := Vector2(player.global_transform.basis.z.x,
		player.global_transform.basis.z.z).normalized()
	var spot := p2 - fwd * 50.0
	# Auf der Fahrbahnkante der Schulstrasse bleiben, nicht daneben.
	spot.x = clampf(spot.x, zone.position.x + 1.5, zone.end.x - 1.5)
	spot.y = clampf(spot.y, -183.5, -180.5)
	var tri := _build_warndreieck()
	tri.position = Vector3(spot.x, 0.0, spot.y)
	# Die reflektierende Seite zeigt zum nachfolgenden Verkehr —
	# d.h. entgegen der Fahrtrichtung des stehenden Autos.
	tri.rotation.y = atan2(-fwd.x, -fwd.y)
	add_child(tri)
	_warndreieck = tri
	instructor._done("warndreieck", "Warndreieck rund 50 m dahinter aufgestellt — Pannenstelle vorbildlich abgesichert.")


func _build_warndreieck() -> Node3D:
	var w := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.10, 0.08)
	red.emission_enabled = true
	red.emission = Color(0.9, 0.15, 0.1)
	red.emission_energy_multiplier = 1.2
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.45, 0.05)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.3, 0.3, 0.32)
	# Dreiecksrahmen: zwei schraege Schenkel + Grundbalken.
	for spec in [
		[Vector3(0.07, 0.55, 0.03), Vector3(-0.20, 0.28, 0.0), -30.0, red],
		[Vector3(0.07, 0.55, 0.03), Vector3(0.20, 0.28, 0.0), 30.0, red],
		[Vector3(0.55, 0.07, 0.03), Vector3(0.0, 0.06, 0.0), 0.0, red],
		[Vector3(0.30, 0.40, 0.012), Vector3(0.0, 0.30, -0.005), 0.0, orange],
		[Vector3(0.30, 0.02, 0.25), Vector3(0.0, 0.012, 0.10), 0.0, grey],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = spec[3]
		mi.position = spec[1]
		mi.rotation_degrees.z = spec[2]
		w.add_child(mi)
	return w


func _update_exam_beam() -> void:
	if instructor == null or _exam_beam == null:
		return
	var on: bool = instructor.exam.active
	_exam_beam.visible = on
	if on:
		var wp: Vector2 = instructor.exam.next_wp()
		_exam_beam.position = Vector3(wp.x, 13.0, wp.y)
