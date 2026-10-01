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
var lights          ## junction_lights.gd Instanz (kann null sein)
var pedestrian      ## Fussgaenger am Zebrastreifen (kann null sein)
var exam = ExamRoute.new()   ## Pruefungsfahrt-Route (Taste P startet)
var _ped_waiting := false
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
var _offroad_t: float = 0.0
var _coach_cd: float = 0.0


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


func _say(text: String, level: int) -> void:
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
	_check_wrong_way(pos)
	_check_offroad(pos, delta)
	_check_stalls_and_shifts()
	_check_tasks(p2, spd, delta)
	if _coach_cd <= 0.0 and _coach_t_upcoming():
		pass


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


func _check_wrong_way(pos: Vector3) -> void:
	var road: String = surfaces.wrong_way(pos, car.linear_velocity)
	if road != "":
		_say("Einbahnstraße! Du fährst gegen die Fahrtrichtung — wende.", 2)


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
		# Wer vor der Linie anhält, merkt es sich (Stopschild-Pflicht).
		if d < 0.2 and d > -4.5 and spd < 0.3:
			_stop_armed[key] = Time.get_ticks_msec() / 1000.0
		track["d"] = d


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
			if spd > 6.0:
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
	# Rückwärtsfahren: 10 m im Rückwärtsgang.
	if gear == -1:
		_rev_acc += absf(forward) * delta
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
	# Gefahrbremsung: auf der Bremsbahn von >25 km/h auf 0 mit Vollbremsung.
	var bl: Dictionary = lot["brake_lane"]
	var bla: Vector2 = bl["from"]
	var blb: Vector2 = bl["to"]
	var lane_rect := Rect2(min(bla.x, blb.x) - 1, min(bla.y, blb.y) - 3, absf(blb.x - bla.x) + 2, 6)
	var in_lane := _in_rect(p2, lane_rect)
	if not in_lane:
		_brake_entry = -1.0
	elif _brake_entry < 0.0 and spd * 3.6 > 25.0:
		_brake_entry = spd
	elif _brake_entry > 0.0 and spd < 0.2:
		_brake_entry = -1.0
		_done("brake", "Gefahrbremsung geschafft — voller Tritt, gerade bleiben, Kupplung treten kurz vor dem Stillstand.")

	# Längsparken: still in einer Parallelbucht stehen.
	for bay in lot["parallel_bays"]:
		if bool(bay.get("occupied", false)):
			continue
		var bp: Vector2 = bay["pos"]
		var rect := Rect2(bp.x - 2.3, bp.y - float(bay["len"]) * 0.5, 2.3, float(bay["len"]))
		if _in_rect(p2, rect) and spd < 0.25:
			_done("parallel", "Längsparken geschafft — Rückwärts rein, Räder gerade, fertig.")
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
	var hill_rect := Rect2(hp.x - float(hill["w"]) * 0.5 - 1.0, hp.y - float(hill["run"]) - 3.0, float(hill["w"]) + 2.0, float(hill["run"]) + 9.0)
	if _in_rect(p2, hill_rect):
		if not _hill_armed and spd < 0.5:
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
	_check_pedestrian(p2, spd)
	if exam.active:
		for ev in exam.update(p2):
			match String(ev["ev"]):
				"say":
					_say(String(ev["text"]), 0)
				"offtrack":
					_warn("Sie sind vom Kurs ab — wenden Sie und folgen Sie der Anweisung.")
				"done":
					_done("pruefung", "Prüfungsfahrt absolviert — bestanden!")


## Taste P: Pruefungsfahrt starten (erneut = abbrechen).
func toggle_exam() -> void:
	if exam.active:
		exam.abort()
		_say("Prüfungsfahrt abgebrochen.", 0)
	else:
		exam.begin()
		_say("Prüfungsfahrt! " + String(exam.wps[0]["text"]), 0)


func _check_pedestrian(p2: Vector2, spd: float) -> void:
	if pedestrian == null:
		return
	var ped_p := Vector2(pedestrian.global_position.x, pedestrian.global_position.z)
	var d := p2.distance_to(ped_p)
	if pedestrian.on_road():
		if d < 12.0 and spd * 3.6 < 5.0:
			_ped_waiting = true        ## Schueler steht und laesst passieren
		if d < 3.5 and spd > 0.8:
			_warn("Fussgaenger auf dem Zebrastreifen — anhalten, Vorrang!")
		if d < 1.4 and spd > 1.0:
			_say("Unfall! Person am Zebrastreifen angefahren — immer gucken.", 2)
	else:
		if _ped_waiting and d < 16.0:
			_ped_waiting = false
			_done("ped", "Fussgaenger passieren lassen — vorbildlich.")


var _brake_entry: float = -1.0
var _brake_at: float = 0.0


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


func _coach_t_upcoming() -> bool:
	return false
