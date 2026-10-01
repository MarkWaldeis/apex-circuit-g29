extends SceneTree
## Unit gate for the school world's logic modules — no scene needed:
##   * h_gearbox: Kupplung, Schleifpunkt, Abwürgen, Automatik
##   * junction_lights: deutscher Lichtzyklus (rot → rot+gelb → grün …)
##   * school_surfaces: Untergrund, Tempolimits, Einbahnstraße
##   * city_layout: konsistente Daten (Haltelinien liegen auf Straßen)

const HGearbox = preload("res://scripts/school/h_gearbox.gd")
const JunctionLights = preload("res://scripts/school/junction_lights.gd")
const Surfaces = preload("res://scripts/school/school_surfaces.gd")
const Layout = preload("res://scripts/school/city_layout.gd")

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
	if failed > 0:
		print("SCHOOL_UNITS FAIL count=", failed)
		quit(1)
	else:
		print("SCHOOL_UNITS PASS")


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
