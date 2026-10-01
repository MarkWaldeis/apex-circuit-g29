extends RefCounted
## Der Fahrlehrer: beobachtet das Auto, meldet Verstöße und hakt die
## Übungsliste ab. Liest die Welt aus city_layout.gd / school_surfaces.gd
## und den Ampelstand aus junction_lights.gd.
##
## `update(delta, car, surfaces, lights)` jeden Physik-Tick aufrufen.
## Meldungen kommen über das Signal `coached(text, level)` —
## level 0 = Lob/Hinweis, 1 = Ermahnung, 2 = Verstoß.

signal coached(text: String, level: int)

const CityLayout = preload("res://scripts/school/city_layout.gd")
const ExamRoute = preload("res://scripts/school/exam_route.gd")

## Übungsliste — die komplette Fahrschul-Grundausbildung.
const TASKS := [
	{"id": "start", "name": "Anfahren (1. Gang, Schleifpunkt)"},
	{"id": "shift", "name": "Hochschalten 1 → 2"},
	{"id": "brake", "name": "Gefahrbremsung"},
	{"id": "parallel", "name": "Längsparken"},
	{"id": "perp", "name": "Querparken"},
	{"id": "slalom", "name": "Slalom um die Pylonen"},
	{"id": "reverse", "name": "Rückwärtsfahren (10 m)"},
	{"id": "turn", "name": "Wenden"},
	{"id": "roundabout", "name": "Kreisverkehr"},
	{"id": "hill", "name": "Berganfahren"},
	{"id": "stop", "name": "Halt am Stoppschild"},
	{"id": "light", "name": "Ampelkreuzung bei Grün"},
	{"id": "zebra", "name": "Zebrastreifen langsam"},
	{"id": "ped", "name": "Fussgaenger passieren lassen"},
	{"id": "pruefung", "name": "Prüfungsfahrt (Taste P)"},
]

var car
var surfaces
var cyclist
var lights          ## junction_lights.gd Instanz (kann null sein)
var pedestrians: Array = []  ## Fussgaenger an den Zebrastreifen
var rail                     ## rail_crossing.gd-Instanz (kann null sein)
var exam = ExamRoute.new()   ## Pruefungsfahrt-Route (Taste P startet)
var cams := []               ## speed_cam.gd-Instanzen aus city_builder
var traffic := []            ## traffic_car.gd-Instanzen (Vorfahrt-Checks)
var _ped_waiting := {}         ## Fussgaenger-id -> Schueler laesst passieren
var _ww_t: float = 0.0         ## Zeit gegen die Einbahnrichtung (Rate-Limit)
var _speed_over: float = 0.0
var _speed_limit: int = -1
var _speeding: bool = false
var _tasks_done := {}          ## id -> true
var _arm_track := {}           ## Haltelinie -> letzter Abstand (enter-Richtung)
var _stop_armed := {}          ## Haltelinie -> letzte Stillstand-Zeit vorher
var _roundabout_in: bool = false
var _roundabout_arm: int = -1
var _turn_yaw_acc: float = 0.0
var _turn_start := Vector3.ZERO
var _turning: bool = false
var _ind_used_turn: bool = false
var _rev_acc: float = 0.0
var _hill_ref := 0.0           ## tiefster Punkt seit Beginn der Bergfahrt
var _hill_armed: bool = false
var _grinds_seen: int = 0
var _stalls_seen: int = 0
var _impact_seen: float = 0.0
var _offroad_t: float = 0.0
var _left_lane_t: float = 0.0
var _hb_t: float = 0.0
var _idle_rev_t: float = 0.0
var _rev_t: float = 0.0
var _coach_cd: float = 0.0
var _signs_seen := {}
var _door_cd: float = 0.0
var _idle_t: float = 0.0
var _cyc_cd: float = 0.0
var _was_still: bool = true
var _prio_cd: float = 0.0
var _weave_side: int = 0
var _weave_hits: Array = []
var _weave_cd: float = 0.0
var _slalom_from: int = 0     ## korrekt passierte Pylonen von Westen
var _slalom_to: int = -1      ## ... und von Osten (-1 = noch nicht init)
var _slalom_armed := {}       ## Pylone -> darf wieder gezaehlt werden
var _in_circle := false       ## Schueler aktuell auf der Kreisverkehr-Insel
var _kreis_d: float = 1e9     ## letzter Abstand zum Kreismittelpunkt
var _haz_t := 0.0             ## Zeit Warnblinker im fliessenden Verkehr


func setup(p_car, p_surfaces, p_lights = null) -> void:
	car = p_car
	surfaces = p_surfaces
	lights = p_lights
	for j in CityLayout.junctions().values():
		for arm in j.get("arms", []):
			var key := _arm_key(j, arm)
			_arm_track[key] = {"d": 999.0, "arm": arm, "junction": j}
			_stop_armed[key] = -999.0


func _arm_key(junction: Dictionary, arm: Dictionary) -> String:
	var c: Vector2 = junction["center"]
	var p: Vector2 = arm["pos"]
	return "%s:%d:%d" % [String(junction["kind"]), int(p.x - c.x), int(p.y - c.y)]


func current_limit() -> int:
	return _speed_limit


func is_speeding() -> bool:
	return _speeding


func task_board() -> String:
	var done := 0
	var lines := []
	for t in TASKS:
		var ok: bool = _tasks_done.get(t["id"], false)
		if ok:
			done += 1
		lines.append(("✔ " if ok else "○ ") + String(t["name"]))
	return "%d/%d\n%s" % [done, TASKS.size(), "\n".join(lines)]


func _done(id: String, praise: String) -> void:
	if _tasks_done.get(id, false):
		return
	_tasks_done[id] = true
	_say(praise, 0)


var _exam_errs := 0          ## Warnungen waehrend einer Pruefungsfahrt
var _gyaw0 := -999.0         ## generelle Blinkerpflicht: Gier-Referenz
var _gyaw_ok := false        ## Blinker war waehrend der Drehung an


func _say(text: String, level: int) -> void:
	if exam.active and level >= 1:
		_exam_errs += 1
	coached.emit(text, level)


func _warn(text: String) -> void:
	if _coach_cd <= 0.0:
		_say(text, 1)
		_coach_cd = 3.0


func update(delta: float, _car = null, _s = null, _l = null) -> void:
	if car == null or surfaces == null:
		return
	_coach_cd = maxf(_coach_cd - delta, 0.0)
	var pos: Vector3 = car.global_position
	var spd: float = linear_speed()
	var p2 := Vector2(pos.x, pos.z)

	_check_speed(spd, p2, delta)
	_check_junctions(p2, spd)
	_check_signs(p2)
	_check_wrong_way(pos, delta)
	_check_offroad(pos, delta)
	_check_habits(spd, delta)
	_check_door_zone(p2, spd, delta)
	_check_cyclist(p2, spd, delta)
	_check_following(p2, spd, delta)
	_check_priority(p2, spd, delta)
	_check_weave(pos, spd, delta)
	_check_stalls_and_shifts()
	_check_tasks(p2, spd, delta)
	# Warnblinker im fliessenden Verkehr ist kein zulaessiges Blinken.
	if bool(car.get("hazard")) and spd > 6.0:
		_haz_t += delta
		if _haz_t > 2.5:
			_warn("Warnblinker ausschalten — nur für Pannen und Gefahrensituationen.")
			_haz_t = -6.0
	elif not bool(car.get("hazard")):
		_haz_t = 0.0
	else:
		_haz_t = minf(_haz_t + delta * 0.5, 0.0)
	_coach_idle(spd, delta)


func linear_speed() -> float:
	if car == null:
		return 0.0
	return car.linear_velocity.length()


# ---------------------------------------------------------------- Verstöße

func _check_speed(spd: float, p2: Vector2, delta: float) -> void:
	_speed_limit = surfaces.limit_at(Vector3(p2.x, 0, p2.y)) if surfaces else -1
	var kmh := spd * 3.6
	_speeding = _speed_limit > 0 and kmh > float(_speed_limit) + 4.0
	if _speeding:
		_speed_over += delta
		if _speed_over > 1.2:
			_say("Zu schnell! Hier gilt %d km/h — runter vom Gas." % _speed_limit, 2)
			_speed_over = -4.0
	else:
		_speed_over = maxf(_speed_over - delta, 0.0)


# Fahrlehrer erklärt Verkehrszeichen: beim Heranfahren an ein Schild
# (unter ~30 m) sagt er einmal pro Schildart, was es bedeutet.
const SIGN_LESSON := {
	"stop": "Stoppschild — das Fahrzeug muss zum Stillstand kommen, dann vorsichtig weiter.",
	"yield": "Vorfahrt gewähren — den Querverkehr durchlassen, dann darf man weiter.",
	"rbl": "Rechts vor links — wer von rechts kommt, fährt zuerst. Langsam reinfahren.",
	"one_way": "Einbahnstraße — nur in Pfeilrichtung erlaubt.",
	"no_entry": "Einfahrt verboten — von dieser Seite führt kein Weg rein.",
	"limit": "Tempolimit — ab hier gilt die Zahl auf dem Schild als Höchsttempo.",
	"limit_end": "Tempolimit aufgehoben — wieder normale Geschwindigkeit erlaubt.",
	"roundabout": "Kreisverkehr — wer im Kreis fährt, hat Vorfahrt. Beim Rausfahren blinken.",
	"priority": "Vorfahrtstraße — auf dieser Straße hat man Vorfahrt, Querstraßen müssen warten.",
	"zebra": "Zebrastreifen — Fußgänger haben Vorrang, rechtzeitig abbremsen.",
	"parking": "Parkplatz — hier werden die Einpark-Übungen gemacht.",
}

func _check_signs(p2: Vector2) -> void:
	if _coach_cd > 0.0:
		return
	var vel := Vector2(car.linear_velocity.x, car.linear_velocity.z)
	for s in CityLayout.signs():
		var kind := String(s["kind"])
		if _signs_seen.get(kind, false):
			continue
		var sp: Vector3 = s["pos"]
		var to := Vector2(sp.x, sp.z) - p2
		var dist := to.length()
		if dist > 30.0 or dist < 2.0:
			continue
		if vel.length() > 0.5 and to.normalized().dot(vel.normalized()) < 0.35:
			continue
		_signs_seen[kind] = true
		_say(String(SIGN_LESSON.get(kind, "Da vorne ein Verkehrszeichen.")) , 0)
		_coach_cd = 5.0
		return


func _check_wrong_way(pos: Vector3, delta: float) -> void:
	var road: String = surfaces.wrong_way(pos, car.linear_velocity)
	if road != "":
		_ww_t += delta
		if _ww_t > 0.3:
			_say("Einbahnstraße! Du fährst gegen die Fahrtrichtung — wende.", 2)
			_ww_t = -5.0
	else:
		_ww_t = minf(_ww_t + delta * 2.0, 0.0)
	# Rechtsfahrgebot: anhaltend links der Mitte = Gegenverkehr.
	var left: String = surfaces.left_lane(pos, car.linear_velocity)
	if left != "":
		_left_lane_t += delta
		if _left_lane_t > 1.2:
			_say("Links der Mittellinie! Auf zweispurigen Straßen wird rechts gefahren — Gegenverkehr.", 2)
			_left_lane_t = -4.0
	else:
		_left_lane_t = minf(_left_lane_t + delta * 2.0, 0.0)


func _check_offroad(pos: Vector3, delta: float) -> void:
	var surf: Dictionary = surfaces.sample(pos)
	var kind := String(surf.get("surface", "asphalt"))
	if kind == "grass" and linear_speed() > 4.0:
		_offroad_t += delta
		if _offroad_t > 1.4:
			_warn("Du bist von der Straße ab — zurück auf die Fahrbahn.")
			_offroad_t = -4.0
	else:
		_offroad_t = maxf(_offroad_t - delta, 0.0)


func _check_habits(spd: float, delta: float) -> void:
	var gear: int = int(car.gear)
	var rpm: float = float(car.rpm)
	# Anfahren: geht das Auto aus dem Stand los, gehört der 1. Gang dran
	# (der 2. geht mit Gefühl noch — ab dem 3. wird es gequält).
	if spd < 0.3:
		_was_still = true
	elif _was_still and spd > 0.8:
		_was_still = false
		if gear >= 3 and bool(car.get("motor_on")):
			_warn("Anfahren im %d. Gang quält Motor und Kupplung — nimm den ersten." % gear)
	# Handbremse vergessen: Auto rollt trotz angezogener Bremse.
	if bool(car.get("handbrake_on")) and spd > 1.5:
		_hb_t += delta
		if _hb_t > 0.8:
			_say("Handbremse ist noch angezogen — erst lösen, dann fahren (Leertaste).", 1)
			_hb_t = -6.0
	else:
		_hb_t = minf(_hb_t + delta, 0.0)
	# Leerlauf-Gas: heulender Motor im Stand bringt nichts.
	if gear == 0 and rpm > 2800.0:
		_idle_rev_t += delta
		if _idle_rev_t > 1.2:
			_say("Im Leerlauf braucht es kein Gas — das schont den Motor und die Nerven.", 1)
			_idle_rev_t = -6.0
	else:
		_idle_rev_t = minf(_idle_rev_t + delta, 0.0)
	# Drehzahl-Coaching: zu lange im niedrigen Gang bei hoher Drehzahl.
	if gear >= 1 and gear <= 3 and rpm > 3800.0 and spd > 3.0:
		_rev_t += delta
		if _rev_t > 1.5:
			_say("Die Drehzahl steht schon hoch — einen Gang höher schalten.", 0)
			_rev_t = -8.0
	else:
		_rev_t = minf(_rev_t + delta, 0.0)


# Belegte Parkbuchten: an parkenden Autos vorbeifahren heißt Tür-Zone —
# schnell und dicht vorbei ist ein Verstoß.
func _check_door_zone(p2: Vector2, spd: float, delta: float) -> void:
	_door_cd = maxf(_door_cd - delta, 0.0)
	if _door_cd > 0.0 or spd < 4.0 or spd > 20.0:
		return
	var lot: Dictionary = CityLayout.lot()
	for bay in lot["parallel_bays"] + lot["perp_bays"]:
		if not bool(bay.get("occupied", false)):
			continue
		var bp: Vector2 = bay["pos"]
		if p2.distance_to(bp) < 3.0:
			_say("Sicherheitsabstand! An einem parkenden Auto vorbei — eine Tür kann aufgehen.", 1)
			_door_cd = 9.0
			return


# Radfahrer-Seitenabstand: Überholen erst ab ~1,5 m Seitenabstand.
# Vorfahrt missachtet: der Schueler faehrt in eine Kreuzung ein, waehrend
# ein KI-Auto naeher kommt, das er haette durchlassen muessen.
func _check_priority(p2: Vector2, spd: float, delta: float) -> void:
	_prio_cd = maxf(_prio_cd - delta, 0.0)
	if _prio_cd > 0.0 or traffic.is_empty() or spd < 2.0:
		return
	var s_dir := Vector2(car.global_transform.basis.z.x, car.global_transform.basis.z.z).normalized()
	for j in CityLayout.junctions().values():
		var kind := String(j["kind"])
		if kind != "rbl" and kind != "yield" and kind != "roundabout":
			continue
		var c: Vector2 = j["center"]
		var dc := p2.distance_to(c)
		if kind == "roundabout":
			# Beim Einfahren zaehlt nur der Bereich kurz vor dem Ring.
			if dc > 22.0 or dc < 11.5:
				continue
		elif dc > 9.0:
			continue
		var to_c := (c - p2).normalized()
		if to_c.dot(s_dir) < 0.3:
			continue   # durchquert die Kreuzung nicht (mehr)
		var s_arm := _nearest_arm(j, p2)
		for tc in traffic:
			if not is_instance_valid(tc):
				continue
			var tp := Vector2(tc.global_position.x, tc.global_position.z)
			if tp.distance_to(c) > 14.0:
				continue
			var t_dir := Vector2(tc.global_transform.basis.z.x, tc.global_transform.basis.z.z).normalized()
			if (c - tp).normalized().dot(t_dir) < 0.4:
				continue   # KI faehrt von der Kreuzung weg
			var t_arm := _nearest_arm(j, tp)
			if t_arm == s_arm:
				continue   # gleiche Einfahrt: Auffahren, kein Vorfahrt-Fall
			var bad := false
			if kind == "yield":
				# Schueler sitzt auf dem Yield-Arm (wartepflichtig).
				var e: Vector2 = s_arm["enter"]
				bad = bool(s_arm.get("yield", false)) and s_dir.dot(e.normalized()) > 0.5
			elif kind == "roundabout":
				# Faehrt der Schueler gerade auf den Ring zu, muss er den
				# Verkehr im Kreis durchlassen.
				var d_t := tp.distance_to(c)
				bad = d_t < 15.0 and to_c.dot(s_dir) > 0.4
			else:
				# rbl: KI kommt dem Schueler von rechts.
				var right := Vector2(-s_dir.y, s_dir.x)
				bad = t_dir.dot(-right) > 0.45
			if bad:
				if kind == "roundabout":
					_say("Im Kreisverkehr hat der Ringverkehr Vorfahrt — erst einfahren, wenn die Luecke frei ist.", 2)
				else:
					_say("Vorfahrt missachtet — der Gegenverkehr hatte Vorfahrt. In der Pruefung waere das vorbei.", 2)
				_prio_cd = 20.0
				return


func _nearest_arm(j: Dictionary, p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 999.0
	for arm in j.get("arms", []):
		var d: float = (arm["pos"] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = arm
	return best


# Schlangenlinien: wer staendig ueber die Mittellinie pendelt, haelt
# die Spur nicht. Vier echte Spurwechsel in ~18 s = Coaching noetig.
func _check_weave(pos: Vector3, spd: float, delta: float) -> void:
	_weave_cd = maxf(_weave_cd - delta, 0.0)
	if _weave_cd > 0.0 or spd < 8.0:
		return
	var lat: float = surfaces.lane_offset(pos, car.linear_velocity)
	if lat > 9000.0 or absf(lat) < 1.2:
		return
	var side := 1 if lat > 0.0 else -1
	if _weave_side != 0 and side != _weave_side:
		_weave_hits.append(Time.get_ticks_msec() / 1000.0)
	_weave_side = side
	var now := Time.get_ticks_msec() / 1000.0
	while not _weave_hits.is_empty() and now - float(_weave_hits[0]) > 18.0:
		_weave_hits.pop_front()
	if _weave_hits.size() >= 4:
		_say("Schlangenlinien — ruhig in der Spur bleiben, Lenkrad loslassen hilft.", 1)
		_weave_cd = 30.0
		_weave_hits.clear()


func _check_cyclist(p2: Vector2, spd: float, delta: float) -> void:
	_cyc_cd = maxf(_cyc_cd - delta, 0.0)
	if cyclist == null or not is_instance_valid(cyclist) or _cyc_cd > 0.0:
		return
	var d := p2.distance_to(cyclist.pos2())
	if d < 1.7:
		_say("Viel zu dicht am Radfahrer — das ist gefährlich.", 2)
		_cyc_cd = 8.0
	elif d < 2.6 and spd > 3.0:
		_say("Seitenabstand zum Radfahrer — mindestens 1,5 m, sonst warten.", 1)
		_cyc_cd = 8.0


func _check_stalls_and_shifts() -> void:
	var gb = car.get("gearbox")
	if gb == null:
		return
	var stalls := int(gb.stalls)
	if stalls > _stalls_seen:
		_stalls_seen = stalls
		_say("Abgewürgt! Kupplung treten, Motor startet von selbst — beim Anfahren die Kupplung langsamer kommen lassen und etwas mehr Gas.", 2)
	var grinds := int(gb.grinds)
	if grinds > _grinds_seen:
		_grinds_seen = grinds
		_say("Gang knirscht — die Kupplung muss ganz durchgetreten sein, bevor du schaltest.", 2)
	if float(car.get("clutch_heat")) > 2.0:
		_warn("Kupplung zu lange schleifen lassen — ein bisschen Schleifpunkt ist gut, eine halbe Minute ruiniert sie.")
	var imp: float = float(car.get("_last_impact_v"))
	if imp > _impact_seen:
		_impact_seen = imp
		var hit := String(car.get("_last_impact_name"))
		if hit == "Hutchen":
			_warn("Pylone umgefahren — im Slalom zählt jedes Hütchen.")
		elif hit in ["Pedestrian", "Cyclist", "Fussgaenger", "Radfahrer"]:
			_say("Person angefahren! In der Fahrschule: sofort anhalten. Schulblick, Zebrastreifen und Radfahrer-Abstand sind Pflicht — das ist der schwerste Fehler überhaupt.", 2)
		elif imp > 45.0:
			_say("Crash mit %.0f km/h — so eine Prüfungsfahrt ist vorbei, zum Glück nur Übung." % imp, 2)
		else:
			_say("Blechschaden (%.0f km/h) — Abstand und Geschwindigkeit anpassen." % imp, 2)


func _check_junctions(p2: Vector2, spd: float) -> void:
	for key in _arm_track.keys():
		var track: Dictionary = _arm_track[key]
		var arm: Dictionary = track["arm"]
		var j: Dictionary = track["junction"]
		var enter: Vector2 = arm["enter"]
		var stop: Vector2 = arm["pos"]
		# Vorzeichenabstand zur Haltelinie entlang der Fahrtrichtung:
		# negativ = vor der Linie, positiv = drüber.
		var d: float = (p2 - stop).dot(enter)
		var prev: float = float(track["d"])
		if prev <= 0.0 and d > 0.0 and spd > 1.0:
			_on_stop_line_crossed(j, arm, key, spd)
			# Blinker-Merker: beim Abbiegen an einer Kreuzung Blinker erwarten.
			# Ausnahme Kreisverkehr: Einfahren ist BLINKFREI, erst das
			# Ausfahren braucht den Rechtsblinker (eigener Check unten).
			if String(j["kind"]) != "roundabout":
				_jturn[key] = {
				"yaw0": car.global_transform.basis.get_euler().y,
					"t0": Time.get_ticks_msec() / 1000.0,
					"j": j,
					"arm": arm,
				}
		# Wer vor der Linie wirklich steht, merkt es sich (Stopschild-Pflicht):
		# Schleichen zählt nicht — erst nach ~1 s echtem Stillstand gilt es als Halt.
		var now_s := Time.get_ticks_msec() / 1000.0
		if d < 0.2 and d > -4.5 and spd < 0.12:
			if not _stop_still.has(key):
				_stop_still[key] = now_s
			if now_s - float(_stop_still[key]) > 0.9:
				_stop_armed[key] = now_s
		else:
			_stop_still.erase(key)
		track["d"] = d
	# Blinker-Pflicht auswerten: ~1,5 s nach dem Haltelinien-Schnitt die Drehung messen.
	var now_j := Time.get_ticks_msec() / 1000.0
	for key in _jturn.keys():
		var tr: Dictionary = _jturn[key]
		if bool(car.get("indicator_left")):
			tr["l"] = true
		if bool(car.get("indicator_right")):
			tr["r"] = true
		if now_j - float(tr["t0"]) > 1.5:
			var dyaw := wrapf(car.global_transform.basis.get_euler().y - float(tr["yaw0"]), -PI, PI)
			if dyaw > 0.45 and not bool(tr.get("l", false)):
				_warn("Abbiegen ohne Blinker — vor dem Abbiegen links blinken.")
			elif dyaw < -0.45 and not bool(tr.get("r", false)):
				_warn("Abbiegen ohne Blinker — vor dem Abbiegen rechts blinken.")
			if dyaw > 0.45:
				_check_left_turn_oncoming(tr["j"], tr["arm"])
			_jturn.erase(key)
	# Generelle Blinkerpflicht ohne Haltelinie (Zufahrt, Ring-Anschluss,
	# Einmuendung): deutliche Gierdrehung im fliessenden Verkehr ohne
	# Blinker -> Hinweis. Langsame Platzrunden (Wenden, Parken) bleiben frei.
	var yaw_now: float = car.global_transform.basis.get_euler().y
	if bool(car.get("indicator_left")) or bool(car.get("indicator_right")) \
			or bool(car.get("hazard")):
		_gyaw_ok = true
	if _gyaw0 < -900.0:
		_gyaw0 = yaw_now
	var dgy := wrapf(yaw_now - _gyaw0, -PI, PI)
	if absf(dgy) < 0.05:
		_gyaw0 = yaw_now
		_gyaw_ok = false
	elif absf(dgy) > 0.45:
		if spd > 4.0 and not _gyaw_ok \
				and String(surfaces.sample(car.global_position).get("surface", "asphalt")) != "grass":
			_warn("Abbiegen ohne Blinker — rechtzeitig blinken.")
		_gyaw0 = yaw_now
		_gyaw_ok = false

	# Kreisverkehr: beim Ausfahren wird rechts geblinkt — Einfahren ohne
	# Blinker ist sogar Pflicht. Wechsel Insel -> Ausfahrtsarm ohne
	# Rechtsblinker -> Hinweis. Hysterese gegen Flattern, _kreis_d-Guard
	# gegen Fehlmeldung nach Teleport/Reset.
	var k: Dictionary = CityLayout.junctions()["kreis"]
	var d_k: float = p2.distance_to(k["center"])
	if _in_circle and d_k > 13.5:
		if _kreis_d <= 13.5 and not bool(car.get("indicator_right")):
			_warn("Beim Ausfahren aus dem Kreisverkehr rechts blinken!")
		_in_circle = false
	if d_k < 11.5:
		_in_circle = true
	_kreis_d = d_k


## Linksabbieger muessen Gegenverkehr durchlassen: faehrt beim Abbiegen
## noch ein KI-Auto auf der Gegenspur zur Kreuzung hin, wird gewarnt.
func _check_left_turn_oncoming(j: Dictionary, arm: Dictionary) -> void:
	var opp: Vector2 = -Vector2(arm["enter"])   # Gegenrichtung der Einfahrt
	var opp3 := Vector3(opp.x, 0.0, opp.y)
	var center: Vector2 = j["center"]
	for t in traffic:
		if not is_instance_valid(t):
			continue
		var t_dir := Vector3(t.global_transform.basis.z.x, 0.0,
			t.global_transform.basis.z.z).normalized()
		if t_dir.dot(opp3) < 0.7:
			continue   # faehrt nicht auf der Gegenspur
		var tp := Vector2(t.global_position.x, t.global_position.z)
		if tp.distance_to(center) > 45.0 or (center - tp).dot(opp) <= 0.0:
			continue   # zu weit weg oder schon an der Kreuzung vorbei
		_warn("Linksabbiegen: Gegenverkehr kommt — durchlassen!")
		return


var _follow_t := 0.0


## Sicherheitsabstand: halber Tacho — klebt der Schueler laenger als ~2 s
## hinter einem KI-Auto in derselben Spur, gibts einen Hinweis.
func _check_following(p2: Vector2, spd: float, delta: float) -> void:
	if traffic.is_empty() or spd < 5.0:
		_follow_t = 0.0
		return
	var s_dir := Vector2(car.global_transform.basis.z.x,
		car.global_transform.basis.z.z).normalized()
	var want: float = spd * 3.6 * 0.5            ## Meter = halbe km/h
	var too_close := false
	for tc in traffic:
		if not is_instance_valid(tc):
			continue
		var rel := Vector2(tc.global_position.x, tc.global_position.z) - p2
		var along := rel.dot(s_dir)
		var side := absf(rel.dot(Vector2(-s_dir.y, s_dir.x)))
		if along > 1.0 and along < want and side < 2.4:
			too_close = true
	if too_close:
		_follow_t += delta
		if _follow_t > 2.0:
			_warn("Zu dicht aufgefahren — halber Tacho: bei %d km/h etwa %d m Abstand." % [int(spd * 3.6), int(spd * 3.6 * 0.5)])
			_follow_t = -6.0
	else:
		_follow_t = minf(_follow_t + delta * 0.5, 0.0)


func _on_stop_line_crossed(j: Dictionary, arm: Dictionary, key: String, spd: float) -> void:
	var kind := String(j["kind"])
	match kind:
		"light":
			var phase: String = lights.phase_of(String(arm["arm"])) if lights else "green"
			if phase in ["red", "amber", "red_amber"]:
				_say("Rotlicht! Bei Rot hält man an der Haltelinie — das ist ein Verstoß.", 2)
			else:
				_done("light", "Ampelkreuzung bei Grün — gut!")
		"stop":
			var last_stop: float = float(_stop_armed.get(key, -999.0))
			var now := Time.get_ticks_msec() / 1000.0
			if now - last_stop > 2.0:
				_say("Stoppschild überfahren! STOP heißt: Fahrzeug zum Stillstand bringen, dann vorsichtig weiterfahren.", 2)
			else:
				_done("stop", "Sauber am Stoppschild angehalten — weiter so.")
		"yield":
			# Nur auf Wartepflicht-Armen meckern: wer auf der freien
			# Vorfahrtstrasse durchfaehrt, macht alles richtig.
			if spd > 6.0 and bool(arm.get("yield", false)):
				_warn("Vorfahrt gewähren heißt abbremsen — nicht durchschießen.")
		"rbl":
			if spd > 8.0:
				_warn("Rechts vor links: langsam reinfahren und rechts schauen.")
		"roundabout":
			_roundabout_in = true
			_roundabout_arm = int(arm.get("lane", _roundabout_arm))


func _check_tasks(p2: Vector2, spd: float, delta: float) -> void:
	var gb = car.get("gearbox")
	if gb == null:
		return
	var gear: int = int(car.gear)
	var forward: float = car.linear_velocity.dot(car.global_transform.basis.z)

	# Anfahren: im 1. Gang ohne Abwürgen über 3 m/s hinaus.
	if gear == 1 and forward > 3.0 and not bool(car.get("stalled")):
		_done("start", "Anfahren geschafft — Kupplung im Schleifpunkt halten fühlt sich so an.")
	# Hochschalten 1 -> 2 (oder höher) unter Fahrt.
	if gear >= 2 and forward > 4.0 and not bool(car.get("stalled")):
		_done("shift", "Sauber geschaltet — Kupplung ganz durch, Gang rein, langsam kommen lassen.")
	# Rückwärtsfahren: 10 m im Rückwärtsgang (nur reale Rückwärtsbewegung zählt).
	if gear == -1:
		if forward < -0.2:
			_rev_acc += -forward * delta
			if _rev_acc > 10.0:
				_done("reverse", "Rückwärtsfahren geübt — Schulterblick nicht vergessen.")
	else:
		_rev_acc = maxf(_rev_acc - delta * 2.0, 0.0)

	# Wenden: ~180° Heading-Wechsel auf kleinem Raum.
	var yaw: float = car.global_transform.basis.get_euler().y
	if not _turning:
		if spd > 1.0 and spd < 8.0:
			_turning = true
			_turn_yaw_acc = 0.0
			_turn_start = car.global_position
			_ind_used_turn = bool(car.get("indicator_left")) or bool(car.get("indicator_right")) or bool(car.get("hazard"))
	else:
		_turn_yaw_acc += car.angular_velocity.y * delta
		if bool(car.get("indicator_left")) or bool(car.get("indicator_right")) or bool(car.get("hazard")):
			_ind_used_turn = true
		if absf(_turn_yaw_acc) > 2.8 and spd < 8.0:
			_turning = false
			if _turn_start.distance_to(car.global_position) < 18.0:
				_done("turn", "Gewendet — " + ("Blinker war an, gut." if _ind_used_turn else "nächstes Mal blinken."))
		elif spd > 14.0 or _turn_start.distance_to(car.global_position) > 60.0:
			_turning = false

	_check_lot_tasks(p2, spd, forward, delta)
	_check_roundabout(p2, spd)


func _check_lot_tasks(p2: Vector2, spd: float, forward: float, delta: float) -> void:
	var lot: Dictionary = CityLayout.lot()
	# Schritttempo-Gebot: wer ueber den Platz ballert, wird abgemahnt.
	if spd * 3.6 > 30.0:
		_warn("Auf dem Übungsplatz gilt Schritttempo — deutlich langsamer fahren.")
	# Gefahrbremsung: auf der Bremsbahn von >25 km/h auf 0 mit Vollbremsung.
	var bl: Dictionary = lot["brake_lane"]
	var bla: Vector2 = bl["from"]
	var blb: Vector2 = bl["to"]
	var lane_rect := Rect2(min(bla.x, blb.x) - 1, min(bla.y, blb.y) - 3, absf(blb.x - bla.x) + 2, 6)
	var in_lane := _in_rect(p2, lane_rect)
	if not in_lane:
		_brake_entry = -1.0
		_brake_dec = 0.0
		_brake_peak = 0.0
	elif _brake_entry < 0.0 and spd * 3.6 > 25.0:
		_brake_entry = spd
		_brake_dec = 0.0
		_brake_peak = 0.0
		_brake_prev = spd
	elif _brake_entry > 0.0:
		_brake_dec = maxf(_brake_dec, (_brake_prev - spd) / maxf(delta, 0.001))
		_brake_peak = maxf(_brake_peak, float(car.get("brake_strength")))
		_brake_prev = spd
		if spd < 0.2:
			_brake_entry = -1.0
			if _brake_dec > 4.0 and _brake_peak > 0.55:
				_done("brake", "Gefahrbremsung geschafft — voller Tritt, gerade bleiben, Kupplung treten kurz vor dem Stillstand.")
			else:
				_say("Zu schwach gebremst — bei der Gefahrbremsung gehört das Pedal ganz durchgetreten.", 1)

	# Längsparken: still in einer Parallelbucht stehen.
	for bay in lot["parallel_bays"]:
		if bool(bay.get("occupied", false)):
			continue
		var bp: Vector2 = bay["pos"]
		var rect := Rect2(bp.x - 2.3, bp.y - float(bay["len"]) * 0.5, 2.3, float(bay["len"]))
		if _in_rect(p2, rect) and spd < 0.25:
			_done("parallel", "Längsparken geschafft — Rückwärts rein, Räder gerade, fertig.")
	# Slalom: die Pylonen der Reihe nach auf der richtigen Seite passieren
	# (von links oder rechts — die Richtung ist frei). Falsche Seite = Reset.
	var cones: Array = lot["slalom"]
	if _slalom_to < 0:
		_slalom_to = cones.size()
	for i in cones.size():
		var cone: Vector2 = cones[i]
		var dc := p2.distance_to(cone)
		if dc > 4.5:
			_slalom_armed[i] = true
		elif dc < 3.0 and absf(p2.x - cone.x) < 2.6 and bool(_slalom_armed.get(i, true)):
			_slalom_armed[i] = false
			var need := signf(64.0 - cone.y)
			var have := signf(p2.y - cone.y)
			if not (have == need and absf(p2.y - cone.y) > 0.6):
				_slalom_from = 0
				_slalom_to = cones.size()
				_warn("Pylone auf der falschen Seite passiert — Slalom heißt abwechselnd rechts, links.")
			elif i == _slalom_from:
				_slalom_from = i + 1
			elif i == _slalom_to - 1:
				_slalom_to = i
			if _slalom_from >= _slalom_to:
				_done("slalom", "Slalom sauber — flüssig ums Hütchen, ohne zu streifen.")

	# Querparken: still in einer freien Querbucht.
	for bay in lot["perp_bays"]:
		if bool(bay.get("occupied", false)):
			continue
		var bp: Vector2 = bay["pos"]
		var rect := Rect2(bp.x - 1.2, bp.y - 4.9, 2.4, 4.8)
		if _in_rect(p2, rect) and spd < 0.25:
			_done("perp", "Querparken geschafft — in der Lücke gerade ausgerichtet.")

	# Berganfahren: auf der Rampe ohne Zurückrollen anfahren.
	var hill: Dictionary = lot["hill"]
	var hp: Vector2 = hill["pos"]
	var hill_rect := Rect2(hp.x - float(hill["w"]) * 0.5 - 1.0, hp.y - float(hill["run"]) * 0.5 - 7.0, float(hill["w"]) + 2.0, float(hill["run"]) + float(hill.get("down", 8.0)) + 22.0)
	if _in_rect(p2, hill_rect):
		if not _hill_armed and spd < 0.5 \
				and p2.y > hp.y - float(hill["run"]) * 0.5 - 3.0 \
				and p2.y < hp.y + 1.0:
			# Nur wer AN der Rampe haelt, bekommt die Bergwertung — Anhalten
			# auf der flachen Zufahrt zaehlt nicht.
			_hill_armed = true
			_hill_ref = p2.y
		elif _hill_armed:
			_hill_ref = minf(_hill_ref, p2.y)
			if spd > 1.5 and p2.y > _hill_ref + 4.0:
				_hill_armed = false
				_done("hill", "Berganfahren geschafft — Handbremse, Schleifpunkt, sanft lösen.")
			elif p2.y < _hill_ref - 0.5 and absf(forward) < 0.3:
				_warn("Rollt rückwärts am Berg — Handbremse nutzen und Schleifpunkt finden.")
				_hill_armed = false
	else:
		_hill_armed = false

	# Zebrastreifen: langsam genug drüber.
	for z in CityLayout.zebras():
		var zp: Vector2 = z["pos"]
		if absf(p2.x - zp.x) < 4.0 and absf(p2.y - zp.y) < 4.0 and spd * 3.6 < 30.0 and spd > 0.5:
			_done("zebra", "Zebrastreifen langsam — Fußgänger zuerst.")
		# Halten auf/vor dem Zebrastreifen (5 m) ist verboten — ausser ein
		# Fussgaenger zwingt sowieso zum Anhalten.
		if absf(p2.x - zp.x) < 10.0 and absf(p2.y - zp.y) < 4.6 and spd < 0.4:
			var ped_near := false
			for pd in pedestrians:
				if is_instance_valid(pd) \
						and Vector2(pd.global_position.x, pd.global_position.z).distance_to(zp) < 14.0:
					ped_near = true
			if not ped_near:
				_warn("Nicht auf dem Zebrastreifen halten — 5 m Abstand einhalten.")
	_check_pedestrian(p2, spd)
	_check_rail(p2, spd)
	if exam.active:
		for ev in exam.update(p2):
			match String(ev["ev"]):
				"say":
					_say(String(ev["text"]), 0)
				"offtrack":
					_warn("Sie sind vom Kurs ab — wenden Sie und folgen Sie der Anweisung.")
				"done":
					# Haekchen nur bei bestandener Fahrt — ein durchgefallener
					# Lauf bekommt die Ansage, aber keinen Listenpunkt.
					if _exam_errs <= 2:
						_done("pruefung", "Prüfungsfahrt bestanden — %d Beanstandung(en)!" % _exam_errs)
					else:
						_say("Prüfungsfahrt beendet — %d Beanstandung(en): nicht bestanden!" % _exam_errs, 2)
	for c in cams:
		if is_instance_valid(c) and c.check(p2, spd * 3.6):
			_say("Geblitzt! %d km/h statt %d — das gibt Post." % [int(spd * 3.6), c.limit], 2)


## Taste P: Pruefungsfahrt starten (erneut = abbrechen).
func toggle_exam() -> void:
	if exam.active:
		exam.abort()
		_say("Prüfungsfahrt abgebrochen.", 0)
	else:
		exam.begin()
		_exam_errs = 0
		_say("Prüfungsfahrt! " + String(exam.wps[0]["text"]), 0)


func _check_pedestrian(p2: Vector2, spd: float) -> void:
	for pedestrian in pedestrians:
		if not is_instance_valid(pedestrian):
			continue
		var ped_p := Vector2(pedestrian.global_position.x, pedestrian.global_position.z)
		var d := p2.distance_to(ped_p)
		var pid: int = pedestrian.get_instance_id()
		if pedestrian.on_road():
			if d < 12.0 and spd * 3.6 < 5.0:
				_ped_waiting[pid] = true   ## Schueler steht und laesst passieren
			if d < 3.5 and spd > 0.8:
				_warn("Fussgaenger auf dem Zebrastreifen — anhalten, Vorrang!")
			if d < 1.4 and spd > 1.0:
				_warn("Unfall! Person am Zebrastreifen angefahren — immer gucken.")
		else:
			if bool(_ped_waiting.get(pid, false)) and d < 16.0:
				_ped_waiting[pid] = false
				_done("ped", "Fussgaenger passieren lassen — vorbildlich.")


func _check_rail(p2: Vector2, spd: float) -> void:
	if rail == null:
		return
	var d: Vector2 = p2 - rail.center
	# Auf den Gleisen darf man nie stehen bleiben — bei geschlossener
	# Schranke erst recht nicht.
	if absf(d.y) < 3.6 and absf(d.x) < 4.5:
		if rail.is_closed():
			_warn("Bahnübergang geschlossen — Gleise sofort räumen!")
		elif spd < 0.6:
			_warn("Nicht auf den Gleisen halten — Bahnübergang frei machen!")
	# Wer bei geschlossener Schranke auf die Querung zufaehrt, muss
	# vor dem Andreaskreuz halten.
	elif rail.is_closed() and absf(d.x) < 6.5 and absf(d.y) < 13.0 and spd > 2.0:
		_warn("Schranken geschlossen — vor dem Andreaskreuz anhalten!")


var _brake_entry: float = -1.0
var _brake_at: float = 0.0
var _brake_dec: float = 0.0
var _brake_peak: float = 0.0
var _brake_prev: float = 0.0
var _stop_still := {}
var _jturn := {}


func _check_roundabout(p2: Vector2, spd: float) -> void:
	var j: Dictionary = CityLayout.junctions()["kreis"]
	var c: Vector2 = j["center"]
	var d := p2.distance_to(c)
	if _roundabout_in:
		# Raus aus dem Kreis: Abstand > äußerer Ringrand.
		if d > 17.5:
			_roundabout_in = false
			if bool(car.get("indicator_right")):
				_done("roundabout", "Kreisverkehr mit Blinker raus — richtig so!")
			else:
				_done("roundabout", "Kreisverkehr durchfahren — beim Rausfahren blinken.")
				_warn("Beim Verlassen des Kreisverkehrs rechts blinken — sonst denkt der Kreis wartet auf dich.")
	elif d < float(j["island_r"]) + 2.0 and spd > 2.0:
		_roundabout_in = true


func _in_rect(p: Vector2, r: Rect2) -> bool:
	return p.x >= r.position.x and p.x <= r.position.x + r.size.x \
		and p.y >= r.position.y and p.y <= r.position.y + r.size.y


# Steht der Schüler länger im Still, deutet der Fahrlehrer die nächste
# offene Übung an (Teleport-Taste T bringt direkt zur Station).
func _coach_idle(spd: float, delta: float) -> void:
	if spd < 0.4:
		_idle_t += delta
	else:
		_idle_t = 0.0
	if _idle_t > 25.0:
		_idle_t = -45.0
		if _coach_cd > 0.0:
			return
		for t in TASKS:
			if not _tasks_done.get(t["id"], false):
				_say("Tipp: %s wartet noch — mit Taste T springst du direkt zur Station." % String(t["name"]), 0)
				_coach_cd = 6.0
				return
