extends SceneTree
## Unit gate for the school world's logic modules — no scene needed:
##   * h_gearbox: Kupplung, Schleifpunkt, Abwürgen, Automatik
##   * junction_lights: deutscher Lichtzyklus (rot → rot+gelb → grün …)
##   * school_surfaces: Untergrund, Tempolimits, Einbahnstraße
##   * city_layout: konsistente Daten (Haltelinien liegen auf Straßen)
##   * traffic_car: KI-Regeln (Ampel, Stoppschild, Auffahrschutz)
##   * pedestrian + Fahrlehrer: Zebrastreifen-Vorrang-Aufgabe

const HGearbox = preload("res://scripts/school/h_gearbox.gd")
const JunctionLights = preload("res://scripts/school/junction_lights.gd")
const Surfaces = preload("res://scripts/school/school_surfaces.gd")
const Layout = preload("res://scripts/school/city_layout.gd")
const TrafficCar = preload("res://scripts/school/traffic_car.gd")
const Pedestrian = preload("res://scripts/school/pedestrian.gd")
const Instructor = preload("res://scripts/school/school_instructor.gd")
const ExamRoute = preload("res://scripts/school/exam_route.gd")

var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run() -> void:
	_test_gearbox()
	_test_lights()
	_test_surfaces()
	_test_layout()
	_test_traffic()
	_test_pedestrian()
	_test_exam_route()
	if failed > 0:
		print("SCHOOL_UNITS FAIL count=", failed)
		quit(1)
	else:
		print("SCHOOL_UNITS PASS")
		quit(0)


func _test_gearbox() -> void:
	var gb := HGearbox.new()
	gb.setup()
	# Leerlauf: Gas gibt Drehzahl, aber keine Kraft.
	var r: Dictionary = gb.update(0.05, {"speed": 0.0, "throttle": 0.8, "clutch": 1.0})
	_check(r["rpm"] > 1500.0, "neutral_revs_up", "rpm=%d" % int(r["rpm"]))
	_check(absf(r["engine_force"]) < 1.0, "neutral_no_force", "force=%.1f" % r["engine_force"])
	# Gang ohne Kupplung -> knirscht, Gang bleibt draußen.
	_check(not gb.request_gear(1, 0.1, 0.0), "shift_without_clutch_grinds", "grinds=%d" % gb.grinds)
	_check(gb.gear == 0, "gear_stays_out")
	# Mit durchgetretener Kupplung geht der erste Gang.
	_check(gb.request_gear(1, 1.0, 0.0), "first_gear_engages")
	# Zu schnelles Kommenlassen im Stand = Abwürgen.
	r = gb.update(0.02, {"speed": 0.0, "throttle": 0.1, "clutch": 0.0})
	_check(bool(r["stalled"]), "clutch_dump_stalls", "stalled=%s" % r["stalled"])
	# Motor startet wieder mit getretener Kupplung.
	for i in range(40):
		gb.start_motor(1.0)
		r = gb.update(0.02, {"speed": 0.0, "throttle": 0.0, "clutch": 1.0})
	_check(not bool(r["stalled"]), "motor_restarts")
	# Sanftes Einkuppeln mit Gas rollt das Auto an — Kraft positiv.
	gb.reset()
	gb.request_gear(1, 1.0, 0.0)
	var v := 0.0
	for i in range(250):
		# ueber ~1.2 s zur Schleifpunktkante, dann zuletzt ganz kommen lassen
		var pedal: float = clampf(1.0 - i / 170.0, 0.15, 1.0)
		r = gb.update(0.02, {"speed": v, "throttle": 0.30, "clutch": pedal})
		v += float(r["engine_force"]) * 0.02 / 1280.0
	_check(not bool(r["stalled"]), "gentle_launch_no_stall", "v=%.1f" % v)
	_check(v > 0.5, "car_creeps_away", "v=%.2f" % v)
	# Rückwärtsgang sperrt bei Fahrt.
	gb.reset()
	gb.request_gear(2, 1.0, 0.0)
	_check(not gb.request_gear(-1, 1.0, 5.0), "reverse_locked_over_5ms")
	# Automatik waehlt Gänge.
	gb.reset()
	var auto_gear := 0
	for i in range(400):
		v += float(gb.update(0.05, {"speed": v, "throttle": 0.9, "auto": true})["engine_force"]) * 0.05 / 1280.0
		auto_gear = gb.gear
	_check(auto_gear >= 2, "auto_box_shifts_up", "gear=%d v=%.1f" % [auto_gear, v])


func _test_lights() -> void:
	var jl := JunctionLights.new()
	# Nach genug Zeit muss die B-Achse grün bekommen (Rot-tot liegt nie an).
	var saw_b_green := false
	var saw_a_red := false
	var illegal := false
	var last_a := ""
	var last_b := ""
	for i in range(3000):
		jl.update(0.02)
		var a: String = jl.phase_of("a")
		var b: String = jl.phase_of("b")
		if a == "green" and b == "green":
			illegal = true
		if b == "green":
			saw_b_green = true
		if a == "red" and b == "green":
			saw_a_red = true
		last_a = a
		last_b = b
	_check(not illegal, "lights_never_both_green")
	_check(saw_b_green, "cross_traffic_gets_green")
	_check(saw_a_red, "main_road_stops_for_cross")


func _test_surfaces() -> void:
	var s := Surfaces.new()
	s.setup()
	# Auf der Hauptstraße Asphalt, daneben Gehweg, weit weg Wiese.
	_check(s.sample(Vector3(-150, 0, -60))["surface"] == "asphalt", "road_is_asphalt")
	_check(s.sample(Vector3(-150, 0, -64.0))["surface"] in ["kerb", "asphalt"], "roadside_kerb")
	_check(s.sample(Vector3(-150, 0, 200))["surface"] == "grass", "offroad_is_grass")
	_check(s.sample(Vector3(0, 0, 80))["surface"] == "asphalt", "lot_is_asphalt")
	# Tempolimits.
	_check(s.limit_at(Vector3(-150, 0, -60)) == 50, "hauptstr_limit_50")
	_check(s.limit_at(Vector3(0, 0, -180)) == 30, "schulstr_limit_30")
	_check(s.limit_at(Vector3(-220, 0, -240)) == 100, "ring_limit_100")
	_check(s.limit_at(Vector3(0, 0, 80)) == -1, "lot_has_no_limit")
	# Einbahnstraße: westwaerts ok, ostwaerts Falschfahrer.
	_check(s.wrong_way(Vector3(0, 0, -120), Vector3(-5, 0, 0)) == "", "oneway_correct_way_free")
	_check(s.wrong_way(Vector3(0, 0, -120), Vector3(5, 0, 0)) != "", "oneway_wrong_way_flagged")


func _test_layout() -> void:
	# Jede Haltelinie liegt auf einer Fahrbahn (oder auf einer Kreuzung) —
	# sonst kann man sie nicht erreichen.
	var s := Surfaces.new()
	s.setup()
	for stop in Layout.stop_lines():
		var p: Vector2 = stop["pos"]
		var surf := s.sample(Vector3(p.x, 0, p.y))
		_check(surf["surface"] in ["asphalt"], "stop_line_on_road", "pos=%s kind=%s" % [p, surf["surface"]])
	# Schilder haben bekannte Arten.
	const TrafficSigns = preload("res://scripts/school/traffic_signs.gd")
	for sg in Layout.signs():
		var node := TrafficSigns.make_sign(String(sg["kind"]), sg.get("arg", ""))
		_check(node != null, "sign_builds", String(sg["kind"]))
		node.free()


func _test_traffic() -> void:
	var tc := TrafficCar.new()
	var jl := JunctionLights.new()
	tc.lights = jl
	# Ampel rot -> das KI-Auto muss auf der Ostspur anhalten.
	jl.state["a"] = "red"
	var v: float = tc._apply_rules(Vector2(-97.0, -58.2), Vector2(1, 0), 8.0)
	_check(v == 0.0, "traffic_stops_at_red", "v=%.1f" % v)
	# Ampel gruen -> freie Fahrt.
	jl.state["a"] = "green"
	v = tc._apply_rules(Vector2(-97.0, -58.2), Vector2(1, 0), 8.0)
	_check(v > 0.0, "traffic_goes_on_green", "v=%.1f" % v)
	# Stoppschild: voller Halt einmal pro Annäherung.
	v = tc._apply_rules(Vector2(90.5, -58.2), Vector2(1, 0), 8.0)
	_check(v == 0.0 and tc._stop_left > 0.0, "traffic_holds_at_stop_sign", "v=%.1f" % v)
	# Schuelerauto dicht voraus -> Vollbremsung (Auffahrschutz).
	var p := Node3D.new()
	root.add_child(p)
	p.global_position = Vector3(-90.0, 0.0, -58.2)
	tc.player = p
	v = tc._apply_rules(Vector2(-97.0, -58.2), Vector2(1, 0), 8.0)
	_check(v == 0.0, "traffic_brakes_for_student", "v=%.1f" % v)
	p.free()
	tc.free()


func _test_pedestrian() -> void:
	var ped := Pedestrian.new()
	root.add_child(ped)
	ped.global_position = Vector3(-40.0, 0.0, -53.5)   ## Bordstein
	ped._walking = true
	ped._target_z = -66.5
	var saw_on_road := false
	for i in range(55):
		ped._physics_process(0.2)
		if ped.on_road():
			saw_on_road = true
	_check(saw_on_road, "pedestrian_walks_across_road")
	_check(absf(ped.global_position.z + 66.5) < 0.05, "pedestrian_reaches_far_side",
		"z=%.2f" % ped.global_position.z)

	var inst := Instructor.new()
	inst.pedestrian = ped
	# Schueler wartet vor dem Zebrastreifen, Fussgaenger mittendrin.
	ped.global_position = Vector3(-40.0, 0.0, -60.0)
	inst._check_pedestrian(Vector2(-46.0, -60.0), 0.0)
	_check(inst._ped_waiting, "ped_waiting_registered")
	# Fussgaenger verlaesst die Fahrbahn -> Aufgabe erledigt.
	ped.global_position = Vector3(-40.0, 0.0, -66.5)
	inst._check_pedestrian(Vector2(-46.0, -60.0), 0.0)
	_check(bool(inst._tasks_done.get("ped", false)), "ped_yield_task_done")
	# Dichtes Vorbeifahren bei Fussgaenger auf der Bahn -> Ansage.
	var coached_msgs: Array = []
	inst.coached.connect(func(t, _l): coached_msgs.append(t))
	ped.global_position = Vector3(-40.0, 0.0, -60.0)
	inst._check_pedestrian(Vector2(-41.0, -60.0), 3.0)
	_check(coached_msgs.size() > 0, "ped_close_pass_coaches")
	ped.free()


func _test_exam_route() -> void:
	var ex := ExamRoute.new()
	ex.begin()
	_check(ex.active, "exam_active_after_begin")
	_check(ex.wps.size() >= 8, "exam_route_has_waypoints", "n=%d" % ex.wps.size())
	# Erste Anweisung gilt beim Start als gesprochen -> fernab keine Events.
	var evs: Array = ex.update(Vector2(0, 20))
	_check(evs.is_empty(), "exam_silent_when_far")
	# Ersten Wegpunkt erreichen -> "next", idx=1.
	evs = ex.update(Vector2(0, -54.0))
	var advanced := false
	for e in evs:
		if String(e["ev"]) == "next":
			advanced = true
	_check(advanced and ex.idx == 1, "exam_advances_on_reach")
	# In Ansage-Naehe des zweiten Wegpunkts -> "say".
	evs = ex.update(Vector2(-60.0, -61.8))
	var said := false
	for e in evs:
		if String(e["ev"]) == "say":
			said = true
	_check(said, "exam_says_next_instruction")
	# Vom Kurs ab -> offtrack-Warnung.
	evs = ex.update(Vector2(100.0, -61.8))
	var off := false
	for e in evs:
		if String(e["ev"]) == "offtrack":
			off = true
	_check(off, "exam_warns_offtrack")
	# Alle Wegpunkte abfahren -> done.
	var done := false
	var guard := 0
	while ex.active and guard < 40:
		var wp: Vector2 = ex.next_wp()
		for i in range(3):
			evs = ex.update(wp)
			for e in evs:
				if String(e["ev"]) == "done":
					done = true
		guard += 1
	_check(done, "exam_completes_route")
	ex.abort()
