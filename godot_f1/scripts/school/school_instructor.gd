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
	{"id": "schleif", "name": "Kriechfahrt (Schleifpunkt halten)"},
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
	{"id": "ball", "name": "Ball: rechtzeitig bremsen"},
	{"id": "rad", "name": "Radfahrer sicher überholt"},
	{"id": "vorfahrt", "name": "Vorfahrt gewährt"},
	{"id": "rvl", "name": "Rechts vor links beachtet"},
	{"id": "nacht", "name": "Nachtfahrt mit Abblendlicht"},
	{"id": "nebel", "name": "Nebelfahrt mit Abblendlicht"},
	{"id": "baustelle", "name": "Baustelle: Tempo 30"},
	{"id": "spiel", "name": "Verkehrsberuhigt: Schritttempo"},
	{"id": "einfaden", "name": "Einfädeln auf die 100er-Straße"},
	{"id": "einbahn", "name": "Einbahnstraße in Fahrtrichtung"},
	{"id": "ueberhol", "name": "Lkw auf dem Ring überholt"},
	{"id": "rettung", "name": "Blaulicht: Platz gemacht"},
	{"id": "panne", "name": "Pannenstellung mit Warnblinker"},
	{"id": "pruefung", "name": "Prüfungsfahrt (Taste P)"},
]

var car
var surfaces
var cyclist
var lights          ## junction_lights.gd Instanz (kann null sein)
var pedestrians: Array = []  ## Fussgaenger an den Zebrastreifen
var rail                     ## rail_crossing.gd-Instanz (kann null sein)
var ball                     ## street_ball.gd-Instanz (kann null sein)
var balls: Array = []        ## weitere Baelle (z. B. Spielflaeche)
var exam = ExamRoute.new()   ## Pruefungsfahrt-Route (Taste P startet)
var cams := []               ## speed_cam.gd-Instanzen aus city_builder
var traffic := []            ## traffic_car.gd-Instanzen (Vorfahrt-Checks)
var school_bus               ## school_bus.gd-Instanz (§20-Halt am Bus)
var _ped_waiting := {}         ## Fussgaenger-id -> Schueler laesst passieren
var _ww_t: float = 0.0         ## Zeit gegen die Einbahnrichtung (Rate-Limit)
var _speed_over: float = 0.0
var _speed_limit: int = -1
var _speeding: bool = false
var _tasks_done := {}          ## id -> true
var _arm_track := {}           ## Haltelinie -> letzter Abstand (enter-Richtung)
var _stop_armed := {}          ## Haltelinie -> Stillstand erfuellt (Latch)
var _roundabout_in: bool = false

var _turn_yaw_acc: float = 0.0
var _turn_start := Vector3.ZERO
var _turning: bool = false
var _ind_used_turn: bool = false
var _rev_acc: float = 0.0
var _hill_ref := 0.0           ## tiefster Punkt seit Beginn der Bergfahrt
var _hill_armed: bool = false
var _hill_stop_t: float = 0.0  ## Standzeit am Hang ohne Handbremse
var _grinds_seen: int = 0
var _stalls_seen: int = 0
var _impact_seen: float = 0.0
var _offroad_t: float = 0.0
var _left_lane_t: float = 0.0
var _hb_t: float = 0.0
var _idle_rev_t: float = 0.0
var _rev_t: float = 0.0
var _coast_t: float = 0.0
var _blink_left_t: float = 0.0  ## Blinker laeuft ohne Lenkung (Vergessen)
var _neut_rev_t: float = 0.0    ## Gas gegeben ohne eingelegten Gang
var _coach_cd: float = 0.0
var _signs_seen := {}
var _door_cd: float = 0.0
var _idle_t: float = 0.0
var _cyc_cd: float = 0.0
var _cyc_armed := false      ## Ueberholvorgang laeuft
var _cyc_min := 999.0        ## kleinster Abstand waehrend des Ueberholens
var _was_still: bool = true
var _prio_cd: float = 0.0
var _weave_side: int = 0
var _weave_hits: Array = []
var _weave_cd: float = 0.0
var _park_stood: int = -1     ## Index der Parallelbucht, in der gestanden wurde
var _slalom_from: int = 0     ## korrekt passierte Pylonen von Westen
var _slalom_to: int = -1      ## ... und von Osten (-1 = noch nicht init)
var _slalom_armed := {}       ## Pylone -> darf wieder gezaehlt werden
var _in_circle := false       ## Schueler aktuell auf der Kreisverkehr-Insel
var _kreis_d: float = 1e9     ## letzter Abstand zum Kreismittelpunkt
var _haz_t := 0.0             ## Zeit Warnblinker im fliessenden Verkehr
var _panne_t := 0.0           ## Stillstand-Zeit in der Pannenzone
var night := false            ## wird von school_world gesetzt (Taste U)
var fog := false              ## wird von school_world gesetzt (Taste I)
var _night_dist := 0.0        ## gefahrene Meter bei Nacht mit Licht
var _fog_dist := 0.0          ## gefahrene Meter im Nebel mit Licht
var _night_cd := 0.0
var _km_driven := 0.0         ## Gesamtstrecke fuer die Zwischenbilanz (Z)
var _warn_cnt := 0            ## abgegebene Hinweise/Verwarnungen
var _ba_in := false           ## Schueler aktuell in der Baustellenzone
var _ba_clean := true         ## Durchfahrt ohne Tempoverstoss
var _sp_in := false           ## Schueler aktuell in der Spielflaeche
var _sp_clean := true         ## Durchfahrt mit Schritttempo
var _slip_t := 0.0            ## Zeit am Schleifpunkt in Kriechfahrt
var _clutch_ride := 0.0       ## getretene Kupplung bei Fahrt (Sekunden)
var _auf_armed := false       ## Schueler ist auf der Auffahrt Oststrasse
var _auf_slow := false        ## Auffahrt wurde zu langsam angefahren
var _einbahn_on := false      ## auf der Einbahnstrasse westwaerts unterwegs
var _ov_armed := false        ## Ueberholvorgang beobachtet
var _ov_tc = null             ## gerade ueberholtes KI-Fahrzeug
var _pullout_armed := false   ## stand still -> koennte anfahren
var _still_t: float = 0.0     ## Standzeit vor dem Anfahren
var rescue                    ## rescue_vehicle.gd-Instanz (kann null sein)
var door_car                  ## door_car.gd-Instanz: Dooring-Ueberraschung
var _door_open_cd: float = 0.0
var _door_praised := false
var _lt_cd: float = 0.0       ## Linksabbiegen bei Gegenverkehr
var _rescue_ann := false      ## Alarmfahrt schon angesagt
var _rescue_near := false     ## Schueler war waehrend der Fahrt in Reichweite


func setup(p_car, p_surfaces, p_lights = null) -> void:
	car = p_car
	surfaces = p_surfaces
	lights = p_lights
	for j in CityLayout.junctions().values():
		for arm in j.get("arms", []):
			var key := _arm_key(j, arm)
			_arm_track[key] = {"d": 999.0, "arm": arm, "junction": j}
			_stop_armed[key] = false


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
var _exam_log: Array = []    ## Beanstandungen mit Ort (Abschlussprotokoll)
var _gyaw0 := -999.0         ## generelle Blinkerpflicht: Gier-Referenz
var _gyaw_ok := false        ## Blinker war waehrend der Drehung an
var cam                    ## chase_camera.gd — fuer Schulterblick-Ersatz
var _rear_ok_at: float = -99.0  ## letzte Rückblick-Kamera > 0,5 s
var _rear_acc: float = 0.0


func _say(text: String, level: int) -> void:
	if exam.active and level >= 1:
		_exam_errs += 1
		var road := ""
		if surfaces != null and car != null:
			road = String(surfaces.road_at(car.global_position))
		_exam_log.append({"text": text, "road": road})
	coached.emit(text, level)


func _warn(text: String) -> void:
	if _coach_cd <= 0.0:
		_warn_cnt += 1
		_say(text, 1)
		_coach_cd = 3.0


func update(delta: float, _car = null, _s = null, _l = null) -> void:
	if car == null or surfaces == null:
		return
	_km_driven += car.linear_velocity.length() * delta
	_coach_cd = maxf(_coach_cd - delta, 0.0)
	# Rueckblick-Kamera (Modus 3): laeuft sie mindestens eine halbe
	# Sekunde, gilt der Schulterblick fuer die naechsten ~4 s als gemacht.
	if cam != null and int(cam.mode) == 3:
		_rear_acc += delta
		if _rear_acc >= 0.5:
			_rear_ok_at = Time.get_ticks_msec() / 1000.0
	else:
		_rear_acc = 0.0
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
	_check_engstelle_vorrang(p2, delta)
	_check_schulbus(p2, spd)
	_check_einbahn(pos, p2)
	_check_ueberhol(p2, spd)
	_check_lane_change(pos, spd, delta)
	_check_pullout(p2, spd, delta)
	_check_door_car(p2, spd, delta)
	_check_left_turn(p2, spd, delta)
	_check_priority(p2, spd, delta)
	_check_weave(pos, spd, delta)
	_check_stalls_and_shifts()
	_check_tasks(p2, spd, delta)
	_check_alaram_exercise(p2, spd, delta)
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


## Gefahrenbremsung: auf dem Uebungsplatz ruft der Fahrlehrer
## unvermutet "VOLLBREMSE!" — gemessen wird die Reaktionszeit bis zum
## ersten kraeftigen Pedaltritt plus Anhalteweg. Laueft nur, wenn der
## Schueler schon eine Weile zuegig auf dem Platz faehrt.
var _alarm_state: int = 0        ## 0 bereit, 1 angekuendigt, 2 misst
var _alarm_wait: float = 0.0   ## Zufalls-Verzoegerung bis zum Ruf
var _alarm_t0: float = 0.0     ## Zeitpunkt des Rufs
var _alarm_p0 := Vector2.ZERO  ## Ort beim Ruf (Anhalteweg)
var _alarm_v0: float = 0.0     ## Tempo beim Ruf
var _alarm_react: float = -1.0 ## Reaktionszeit bis Pedal > 0.6
var _alarm_cool: float = 25.0  ## Sperrzeit bis zur naechsten Uebung


func _check_alaram_exercise(p2: Vector2, spd: float, delta: float) -> void:
	_alarm_cool = maxf(_alarm_cool - delta, 0.0)
	var l: Dictionary = CityLayout.lot()["rect"]
	var on_lot: bool = p2.x > float(l["x0"]) and p2.x < float(l["x1"]) \
		and p2.y > float(l["z0"]) and p2.y < float(l["z1"])
	if exam.active or not on_lot:
		# Unterbrochen (Pruefung oder verlassener Platz) — zurueck auf Start.
		if _alarm_state > 0:
			_say("Uebung abgebrochen — wir wiederholen die Gefahrenbremsung spaeter.", 0)
		_alarm_state = 0
		return
	match _alarm_state:
		0:
			# Voraussetzung: ~30-54 km/h auf dem Platz — dann ist die Uebung
			# scharf (waehrend sie scharf ist, pausiert die Platz-Temporegel,
			# sonst wuerde das zuegige Anfahren selbst abgemahnt).
			if _alarm_cool <= 0.0 and spd > 8.5 and spd < 15.0:
				_alarm_state = 1
				_alarm_wait = randf_range(3.0, 7.0)
				_say("Gefahrenbremsung ueben: fahr weiter geradeaus — wenn ich rufe, VOLLBREMSUNG!", 0)
		1:
			if spd < 6.0:
				# Schueler ist schon von selbst langsam geworden.
				_alarm_state = 0
				_alarm_cool = 20.0
				_say("Zu langsam fuer die Uebung — wir versuchen es gleich nochmal.", 0)
				return
			if spd > 16.0:
				# Deutlich zu schnell — Uebung sinnlos, Temporegel greift wieder.
				_alarm_state = 0
				_alarm_cool = 20.0
				_say("Das ist schon zu flott fuer die Uebung — langsamer, dann geht es weiter.", 1)
				return
			_alarm_wait -= delta
			if _alarm_wait <= 0.0:
				_alarm_state = 2
				_alarm_t0 = Time.get_ticks_msec() / 1000.0
				_alarm_p0 = p2
				_alarm_v0 = spd
				_alarm_react = -1.0
				_say("VOLLBREMSE!", 2)
		2:
			if _alarm_react < 0.0 and float(car.get("brake_strength")) > 0.6:
				_alarm_react = maxf(
					Time.get_ticks_msec() / 1000.0 - _alarm_t0, 0.0)
			if spd < 0.25:
				_alarm_state = 0
				_alarm_cool = 90.0
				var weg := _alarm_p0.distance_to(p2)
				if _alarm_react < 0.0:
					_say("Zu spaet gebremst — auf die Bremse geht es sofort und mit Kraft.", 2)
				elif _alarm_react > 1.2:
					_say("Gefahrenbremsung: Reaktion %.1f s — zu langsam, Ziel < 1 s. Anhalteweg %.1f m aus %.0f km/h." % [_alarm_react, weg, _alarm_v0 * 3.6], 1)
				else:
					_say("Gefahrenbremsung: Reaktion %.1f s, Anhalteweg %.1f m aus %.0f km/h — gut!" % [_alarm_react, weg, _alarm_v0 * 3.6], 0)


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


## Ausscheren zum Ueberholen: wandert das Auto spuerbar nach links
## (lane_offset faellt), muessen Blinker links UND Schulterblick
## sitzen — die klassische Reihenfolge Spiegel-Schulterblick-Blinker.
var _lo_prev: float = 9999.0
var _lo_drift: float = 0.0
var _lane_cd: float = 0.0


func _check_lane_change(pos: Vector3, spd: float, delta: float) -> void:
	_lane_cd = maxf(_lane_cd - delta, 0.0)
	if spd < 5.0 or surfaces == null:
		_lo_prev = 9999.0
		return
	var lo: float = surfaces.lane_offset(pos, car.linear_velocity)
	if lo >= 9998.0:
		_lo_prev = 9999.0
		_lo_drift = 0.0
		return
	if _lo_prev < 9998.0:
		var dlo: float = lo - _lo_prev
		if dlo < 0.0:
			_lo_drift += dlo
		elif _lo_drift < 0.0:
			_lo_drift = minf(_lo_drift + dlo, 0.0)
		if _lo_drift < -1.4 and _lane_cd <= 0.0:
			_lane_cd = 15.0
			_lo_drift = 0.0
			var now := Time.get_ticks_msec() / 1000.0
			if not bool(car.get("indicator_left")):
				_warn("Vor dem Ausscheren links blinken — der Verkehr muss die Absicht sehen.")
			elif now - _rear_ok_at > 4.0:
				_warn("Schulterblick links vor dem Ausscheren — im toten Winkel kann einer fahren.")
	_lo_prev = lo


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
	"wild": "Wildwechsel — Tiere springen hier unvermittelt auf die Straße; vom Gas, bremsbereit, nicht ausweichen.",
	"spiel": "Verkehrsberuhigter Bereich — Schritttempo Pflicht, Kinder duerfen die ganze Strasse bespielen.",
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


## Theorie wiederholen (Taste F): das naechste Schild in ~10 m wird
## noch einmal erklaert — egal ob schon gesehen oder nicht.
func explain_nearest_sign(p2: Vector2) -> void:
	var best := 1e9
	var best_kind := ""
	for s in CityLayout.signs():
		var sp: Vector3 = s["pos"]
		var d := Vector2(sp.x - p2.x, sp.z - p2.y).length()
		if d < best:
			best = d
			best_kind = String(s["kind"])
	if best > 10.0:
		_say("Kein Schild in der Nähe — näher ranfahren, dann frag ich dich nicht.", 0)
		return
	var text := String(SIGN_LESSON.get(best_kind, "Ein Verkehrszeichen — genau hinsehen."))
	_say("Theorie: " + text, 0)


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
	# Ausrollen im Leerlauf: ohne eingelegten Gang gibt es keine
	# Motorbremsung und das Fahrzeug wird in Gefaelle immer schneller.
	if gear == 0 and spd > 6.0 and bool(car.get("motor_on")):
		_coast_t += delta
		if _coast_t > 2.5:
			_say("Im Leerlauf rollen ist unüblich — Gang einlegen, die Motorbremsung hilft.", 1)
			_coast_t = -8.0
	else:
		_coast_t = minf(_coast_t + delta, 0.0)
	# Gas im Leerlauf: der Motor heult, aber kein Gang ist drin —
	# Anfängerfehler, auf den sofort hingewiesen wird.
	if gear == 0 and bool(car.get("motor_on")) and float(car.get("rpm")) > 2200.0:
		_neut_rev_t += delta
		if _neut_rev_t > 1.2:
			_say("Gas ohne Gang — erst die Kupplung treten und den ersten Gang einlegen.", 1)
			_neut_rev_t = -6.0
	else:
		_neut_rev_t = minf(_neut_rev_t + delta, 0.0)
	# Vergessener Blinker: laeuft der Blinker weiter, ohne dass gelenkt
	# wird, glaubt der Verkehr eine Abbiegeabsicht — ausschalten!
	var ind_on := bool(car.get("indicator_left")) or bool(car.get("indicator_right"))
	var steering := absf(car.angular_velocity.y) > 0.4 or spd < 1.5
	if ind_on and not steering:
		_blink_left_t += delta
		if _blink_left_t > 7.0:
			_say("Der Blinker läuft noch — nach dem Abbiegen gleich ausschalten.", 1)
			_blink_left_t = -6.0
	else:
		_blink_left_t = 0.0


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


## Dooring: die Tuer des parkenden Autos schwingt auf — wer schnell
## vorbeifaegert, wird gewarnt; wer abgebremst hat, wird gelobt.
func _check_door_car(p2: Vector2, spd: float, delta: float) -> void:
	_door_open_cd = maxf(_door_open_cd - delta, 0.0)
	if door_car == null or not is_instance_valid(door_car):
		return
	if door_car.open_frac < 0.4:
		_door_praised = false
		return
	var d := p2.distance_to(Vector2(door_car.global_position.x,
		door_car.global_position.z))
	if d > 14.0 or d < 1.0 or _door_open_cd > 0.0:
		return
	if spd > 4.0:
		_warn("Achtung: Eine Autotür geht auf — weiträumig ausweichen oder anhalten!")
		_door_open_cd = 12.0
	elif not _door_praised:
		_door_praised = true
		_say("Gut reagiert — an der offenen Tür in Schrittgeschwindigkeit vorbei.", 0)


## Linksabbiegen vor Gegenverkehr: blinkt der Schueler links oder
## dreht bereits links ein, waehrend ein KI-Fahrzeug frontal in die
## Kreuzung einfaehrt, muss er warten — §9 Abs. 1.
func _check_left_turn(p2: Vector2, spd: float, delta: float) -> void:
	_lt_cd = maxf(_lt_cd - delta, 0.0)
	if _lt_cd > 0.0 or traffic.is_empty() or spd < 0.8:
		return
	if not bool(car.get("indicator_left")) and car.angular_velocity.y < 0.3:
		return
	for j in CityLayout.junctions().values():
		var c: Vector2 = j["center"]
		var dj := p2.distance_to(c)
		if dj > 16.0 or dj < 1.5:
			continue
		var fwd := Vector2(car.global_transform.basis.z.x,
			car.global_transform.basis.z.z)
		for tc in traffic:
			if not is_instance_valid(tc):
				continue
			var tdir := Vector2(tc.global_transform.basis.z.x,
				tc.global_transform.basis.z.z)
			if fwd.normalized().dot(tdir.normalized()) > -0.5:
				continue
			var tp := Vector2(tc.global_position.x, tc.global_position.z)
			var td := tp.distance_to(c)
			if td < 26.0 and td > 5.0 \
					and (c - tp).normalized().dot(tdir.normalized()) > 0.6 \
					and float(tc.get("speed_ms")) > 2.0:
				_say("Linksabbiegen: der Gegenverkehr hat Vorfahrt — erst warten, dann abbiegen.", 1)
				_lt_cd = 12.0
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
			# KI auf der Kreisbahn zaehlt bis zur Ringkante (~16 m).
			if tp.distance_to(c) > 17.0:
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
	if cyclist == null or not is_instance_valid(cyclist):
		return
	var d := p2.distance_to(cyclist.pos2())
	if _cyc_cd <= 0.0:
		if d < 1.7:
			_say("Viel zu dicht am Radfahrer — das ist gefährlich.", 2)
			_cyc_cd = 8.0
		elif d < 2.6 and spd > 3.0:
			_say("Seitenabstand zum Radfahrer — mindestens 1,5 m, sonst warten.", 1)
			_cyc_cd = 8.0
	# Ueberhol-Aufgabe: Radfahrer mit >= 1,8 m Abstand passieren.
	var fwd: Vector3 = car.global_transform.basis.z
	var rel: Vector3 = cyclist.global_position - car.global_position
	var ahead: bool = fwd.dot(rel) > 0.0
	if not _cyc_armed and ahead and d < 25.0 and spd > 3.0:
		_cyc_armed = true
		_cyc_min = d
	elif _cyc_armed:
		_cyc_min = minf(_cyc_min, d)
		if not ahead and rel.length() > 6.0:
			_cyc_armed = false
			if _cyc_min >= 1.8:
				_done("rad", "Radfahrer sicher überholt — schöner Abstand!")
			# zu dicht kam oben schon die Ermahnung


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
			_say("Person angefahren! In der Fahrschule: sofort anhalten. Schulterblick, Zebrastreifen und Radfahrer-Abstand sind Pflicht — das ist der schwerste Fehler überhaupt.", 2)
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
		# negativ = vor der Linie, positiv = drüber. Die Linie wirkt nur
		# im Einfahrtskorridor — jenseits von ~5 m quer zur Einfahrt ist
		# es eine andere Strasse (sonst feuern Phantom-Linien quer durch
		# die Karte: Parallelpassagen zaehlten als Stoppschild-Verstoss).
		var lat: float = absf((p2 - stop).dot(Vector2(-enter.y, enter.x)))
		var d: float = (p2 - stop).dot(enter)
		var prev: float = float(track["d"])
		if lat < 5.0 and prev <= 0.0 and d > 0.0 and spd > 1.0:
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
		if lat < 5.0 and d < 0.2 and d > -4.5 and spd < 0.12:
			if not _stop_still.has(key):
				_stop_still[key] = now_s
			if now_s - float(_stop_still[key]) > 0.9:
				_stop_armed[key] = true    ## Halt erfuellt: Latch bis zur Linie
		else:
			_stop_still.erase(key)
		if d < -12.0:
			_stop_armed.erase(key)      ## weit zurueckgesetzt -> neu anfahren
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
			if dyaw < -0.45:
				_check_shoulder(p2)
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
		# Im Kreisverkehr dreht sich die Karosserie staendig — das
		# ist kein Abbiegevorgang im Sinne der Blinkerpflicht.
		var on_ring := p2.distance_to(Vector2(200.0, -60.0)) < 17.0
		if spd > 4.0 and not _gyaw_ok and not on_ring \
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
	# Ringkante liegt bei r=16 — erst jenseits davon ist man wirklich
	# draussen und der Rechtsblinker kommt zu frueh, wenn man noch im
	# Kreis faegert.
	if _in_circle and d_k > 16.5:
		if _kreis_d <= 16.5 and not bool(car.get("indicator_right")):
			_warn("Beim Ausfahren aus dem Kreisverkehr rechts blinken!")
		_in_circle = false
	if d_k < 14.0:
		_in_circle = true
	_kreis_d = d_k


## Linksabbieger muessen Gegenverkehr durchlassen: faehrt beim Abbiegen
## noch ein KI-Auto auf der Gegenspur zur Kreuzung hin, wird gewarnt.
func _check_left_turn_oncoming(j: Dictionary, arm: Dictionary) -> void:
	# Gegenverkehr kommt dem Linksabbieger auf der ZIELGERADE
	# entgegen: er faehrt in Richtung des Links-Knickes weiter —
	# so greift die Regel auch an T-Kreuzungen (Zufahrt, yield_ost).
	var fwd3: Vector3 = car.global_transform.basis.z.normalized()
	var opp := Vector2(-fwd3.z, fwd3.x)      ## Linksabbieger-Zielachse
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
var _engstelle_cd := 0.0
var _bus_passed := false


## §20 StVO: an einem haltenden Bus mit Warnblinklicht darf nur
## Schrittgeschwindigkeit gefahren werden — hier in beiden Richtungen,
## weil die Schulstrasse eng ist. Zu schnell vorbei -> Verwarnung.
func _check_schulbus(p2: Vector2, spd: float) -> void:
	if school_bus == null or not is_instance_valid(school_bus):
		return
	var bp := Vector2(school_bus.global_position.x, school_bus.global_position.z)
	var near := p2.distance_to(bp) < 13.0
	if not near:
		_bus_passed = false
		return
	if bool(school_bus.get("hazards_on")) and spd > 2.8:
		_warn("Haltender Schulbus mit Warnblinker — nur Schritttempo vorbeifahren!")
	elif bool(school_bus.get("hazards_on")) and spd <= 2.8 and not _bus_passed:
		_bus_passed = true
		_say("Schulbus mit Warnblinker passiert — Schritttempo, richtig so.", 0)


## Einbahnstraße: nur westwärts (Richtung Weststraße) — wer die
## komplette Straße in Fahrtrichtung durchfaehrt, hat die Aufgabe.
## Gegen die Richtung meldet schon der Geisterfahrer-Check.
## Ueberholen auf dem 100er-Ring: folgt der Schueler einem KI-Fahrzeug
## dicht auf derselben Spur, wird der Vorgang beobachtet — liegt das
## KI-Fahrzeug danach wieder sicher hinten, gilt das Ueberholen.
func _check_ueberhol(p2: Vector2, spd: float) -> void:
	if traffic.is_empty():
		return
	var s_dir := Vector2(car.global_transform.basis.z.x,
		car.global_transform.basis.z.z).normalized()
	if s_dir == Vector2.ZERO:
		return
	var side_dir := Vector2(-s_dir.y, s_dir.x)
	if not _ov_armed:
		if not String(surfaces.road_at(car.global_position)).begins_with("Ring") \
				or spd < 6.0:
			return
		for tc in traffic:
			if not is_instance_valid(tc):
				continue
			var rel := Vector2(tc.global_position.x, tc.global_position.z) - p2
			var along := rel.dot(s_dir)
			var side := absf(rel.dot(side_dir))
			if along > 5.0 and along < 45.0 and side < 3.0:
				_ov_armed = true
				_ov_tc = tc
				_say("Langsamer vor dir — zum Überholen links blinken, Abstand halten, Sicht prüfen.", 0)
				break
		return
	if not is_instance_valid(_ov_tc):
		_ov_armed = false
		return
	var rel2 := Vector2(_ov_tc.global_position.x, _ov_tc.global_position.z) - p2
	var along2 := rel2.dot(s_dir)
	var side2 := absf(rel2.dot(side_dir))
	if along2 < -12.0:
		_ov_armed = false
		if side2 < 4.0:
			_done("ueberhol", "Überholvorgang sauber beendet — gute Arbeit.")
	elif absf(along2) > 75.0 or side2 > 25.0:
		_ov_armed = false    ## aus der Situation rausgefahren


## Anfahren nach dem Halt: kommt ein KI-Fahrzeug von hinten
## derselben Richtung, darf man nicht einfach auf die Fahrbahn
## — Schulterblick und Blinker sind Pflicht, sonst wird gemahnt.
func _check_pullout(p2: Vector2, spd: float, delta: float) -> void:
	if spd < 0.5:
		_still_t += delta
		if _still_t > 2.5:
			_pullout_armed = true
		return
	if not _pullout_armed or spd < 3.0:
		if spd > 1.5:
			_still_t = 0.0
		return
	_pullout_armed = false
	_still_t = 0.0
	var s_dir := Vector2(car.global_transform.basis.z.x,
		car.global_transform.basis.z.z).normalized()
	if s_dir == Vector2.ZERO:
		return
	var side_dir := Vector2(-s_dir.y, s_dir.x)
	var near := false
	for tc in traffic:
		if not is_instance_valid(tc):
			continue
		var rel := Vector2(tc.global_position.x, tc.global_position.z) - p2
		var along := rel.dot(s_dir)
		var side := absf(rel.dot(side_dir))
		if along > -22.0 and along < -1.0 and side < 3.5:
			near = true
			break
	if near:
		var blinked := bool(car.get("indicator_left"))
		if blinked:
			_say("Verkehr von hinten — mit Blinker gesehen, Schulterblick zählt trotzdem!", 0)
		else:
			_say("Anfahren bei Verkehr von hinten: erst Blinker, dann Schulterblick!", 1)


func _check_einbahn(pos: Vector3, p2: Vector2) -> void:
	var on_street := String(surfaces.road_at(pos)) == "Einbahnstraße"
	if on_street and car.linear_velocity.x < -1.5:
		_einbahn_on = true
	elif _einbahn_on and not on_street and p2.x < -90.0 \
			and p2.y > -126.0 and p2.y < -114.0:
		_einbahn_on = false
		_done("einbahn", "Einbahnstraße in Fahrtrichtung durchfahren — richtig so.")
	elif _einbahn_on and not on_street:
		_einbahn_on = false   ## rausgefahren ohne Durchfahrt


## Engstelle Kreis-Nordstrasse: die parkenden Autos stehen auf der
## Ostseite — die Nordfahrt traegt VZ 308 und muss Gegenverkehr in der
## Luecke erst durchlassen. Kommt ein KI-Auto suedwaerts entgegen,
## waehrend der Schueler nordwaerts auf die Luecke zufaellt: mahnen.
func _check_engstelle_vorrang(p2: Vector2, delta: float) -> void:
	_engstelle_cd = maxf(_engstelle_cd - delta, 0.0)
	var pv: Vector3 = car.linear_velocity
	# nur wenn der Schueler nordwaerts (-z) auf die Luecke zufaellt
	if pv.z > -0.8 or absf(p2.x - 200.0) > 7.0 or p2.y > -96.0 or p2.y < -120.0:
		return
	for tc in traffic:
		if not is_instance_valid(tc):
			continue
		var tp := Vector2(tc.global_position.x, tc.global_position.z)
		if absf(tp.x - 200.0) > 6.0 or tp.y > -98.0 or tp.y < -124.0:
			continue
		var tdir := Vector2(tc.global_transform.basis.z.x,
			tc.global_transform.basis.z.z)
		if tdir.y > 0.5 and _engstelle_cd <= 0.0:
			_warn("Engstelle: Gegenverkehr in der Lücke — hier warten (VZ 308).")
			_engstelle_cd = 12.0
			return


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
			if phase == "red":
				_say("Rotlicht! Bei Rot hält man an der Haltelinie — das ist ein Verstoß.", 2)
			elif phase == "amber":
				_say("Gelb gefahren — wer noch gefahrlos anhalten kann, hält. Fürs nächste Mal: früher vom Gas.", 1)
			else:
				_done("light", "Ampelkreuzung bei Grün — gut!")
		"stop":
			if not bool(_stop_armed.get(key, false)):
				_say("Stoppschild überfahren! STOP heißt: Fahrzeug zum Stillstand bringen, dann vorsichtig weiterfahren.", 2)
			else:
				_done("stop", "Sauber am Stoppschild angehalten — weiter so.")
			_stop_armed.erase(key)
		"yield":
			# Nur auf Wartepflicht-Armen werten: wer auf der freien
			# Vorfahrtstrasse durchfaehrt, macht alles richtig.
			if bool(arm.get("yield", false)):
				if spd > 6.0:
					_warn("Vorfahrt gewähren heißt abbremsen — nicht durchschießen.")
				else:
					var ki_nahe := false
					for tc in traffic:
						if is_instance_valid(tc) and Vector2(
								tc.global_position.x, tc.global_position.z
								).distance_to(Vector2(j["center"])) < 20.0:
							ki_nahe = true
					if ki_nahe:
						_done("vorfahrt", "Vorfahrt gewährt — Querverkehr durchgelassen. Genau so!")
					else:
						_done("vorfahrt", "Vorfahrt-Schild beachtet — langsam und geprüft weiter. Gut!")
		"rbl":
			if spd > 8.0:
				_warn("Rechts vor links: langsam reinfahren und rechts schauen.")
			else:
				_done("rvl", "Rechts vor links — langsam reingefahren, Blick nach rechts. Gut!")
		"roundabout":
			_roundabout_in = true


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
	# Schritttempo-Gebot: wer ueber den Platz ballert, wird abgemahnt —
	# nur innerhalb des Platzes (sonst gilt das Tempolimit der Strasse).
	var lr: Dictionary = lot["rect"]
	var on_lot := p2.x >= float(lr["x0"]) and p2.x <= float(lr["x1"]) \
		and p2.y >= float(lr["z0"]) and p2.y <= float(lr["z1"])
	if on_lot and spd * 3.6 > 30.0 and _alarm_state == 0:
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
		_brake_v0 = -1.0
	elif _brake_entry < 0.0 and spd * 3.6 > 25.0:
		_brake_entry = spd
		_brake_dec = 0.0
		_brake_peak = 0.0
		_brake_prev = spd
		_brake_v0 = -1.0
		_brake_t0 = Time.get_ticks_msec() / 1000.0
		_brake_p_start = p2
		_brake_t_v = -1.0
	elif _brake_entry > 0.0:
		_brake_dec = maxf(_brake_dec, (_brake_prev - spd) / maxf(delta, 0.001))
		_brake_peak = maxf(_brake_peak, float(car.get("brake_strength")))
		_brake_prev = spd
		# Bremsweg merken: Punkt + Tempo beim ersten kräftigen Pedaltritt.
		if _brake_v0 < 0.0 and _brake_peak > 0.5:
			_brake_v0 = spd
			_brake_p0 = p2
			_brake_t_v = Time.get_ticks_msec() / 1000.0
		if spd < 0.2:
			_brake_entry = -1.0
			if _brake_v0 > 0.0:
				var weg := _brake_p0.distance_to(p2)
				var anhalt := _brake_p_start.distance_to(p2)
				var react := maxf(_brake_t_v - _brake_t0, 0.0)
				var vergleich := ""
				if surfaces != null and bool(surfaces.get("wet")):
					_brake_wet = weg
					if _brake_dry > 0.0:
						vergleich = " — trocken waren es %.1f m: Nässe verlängert den Bremsweg!" % _brake_dry
				else:
					_brake_dry = weg
					if _brake_wet > 0.0:
						vergleich = " — nass waren es %.1f m." % _brake_wet
				var tempo_warn := ""
				if react > 1.0:
					tempo_warn = " — Reaktion zu spät, beim Gefahrenbremsen zählt jede Zehntel."
				elif react > 0.0:
					tempo_warn = " — gute Reaktionszeit."
				_say("Anhalteweg %.1f m (Reaktion %.1f s, Bremsweg %.1f m) aus %.0f km/h%s%s — Faustregel: Anhalteweg ≈ (v/10)² + (v/10)×3 Meter." % [
					anhalt, react, weg, _brake_v0 * 3.6, tempo_warn, vergleich], 0)
				_brake_v0 = -1.0
			if _brake_dec > 4.0 and _brake_peak > 0.55:
				_done("brake", "Gefahrbremsung geschafft — voller Tritt, gerade bleiben, Kupplung treten kurz vor dem Stillstand.")
			else:
				_say("Zu schwach gebremst — bei der Gefahrbremsung gehört das Pedal ganz durchgetreten.", 1)

	# Längsparken: still in einer Parallelbucht stehen — erst wenn das
	# Auto auch gerade und randnah steht, gilt die Uebung als gemacht.
	var bay_i := 0
	for bay in lot["parallel_bays"]:
		if bool(bay.get("occupied", false)):
			bay_i += 1
			continue
		var bp: Vector2 = bay["pos"]
		var rect := Rect2(bp.x - 2.3, bp.y - float(bay["len"]) * 0.5, 2.3, float(bay["len"]))
		if _in_rect(p2, rect) and spd < 0.25:
			_park_stood = bay_i
			var fwd_x := absf(car.global_transform.basis.z.x)
			if fwd_x > 0.4:
				_say("In der Parklücke, aber schief — das Auto noch gerade ausrichten.", 1)
			elif absf(p2.x - bp.x) > 1.2:
				_say("Parklücke getroffen — aber zu weit vom Rand: näher an den Bordstein.", 1)
			else:
				_done("parallel", "Längsparken geschafft — gerade und nah am Bordstein, vorbildlich. Auf der Strasse dabei vorher rechts blinken und Ausschau nach rückwärtigem Verkehr halten.")
			break
		bay_i += 1
	# Ausparken: rollt das Auto wieder los, ohne den Linksblinker zu
	# setzen, fehlt das wichtigste Signal an den fliessenden Verkehr.
	if _park_stood >= 0:
		var bay2: Dictionary = lot["parallel_bays"][_park_stood]
		var bp2: Vector2 = bay2["pos"]
		var rect2 := Rect2(bp2.x - 3.5, bp2.y - float(bay2["len"]) * 0.5 - 1.5, 3.5, float(bay2["len"]) + 3.0)
		if spd > 0.5 and _in_rect(p2, rect2):
			if not bool(car.get("indicator_left")):
				_warn("Beim Ausparken links blinken — der fliessende Verkehr muss sehen, dass du rausfährst.")
			_park_stood = -1
		elif not _in_rect(p2, rect2):
			_park_stood = -1
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

	# Querparken: still in einer freien Querbucht — auch hier zaehlt nur
	# ein sauber ausgerichteter Stand (Nasen-in-Buchten verlangen
	# Geraudstand, sonst steht man schief im Bild der Praxis).
	for bay in lot["perp_bays"]:
		if bool(bay.get("occupied", false)):
			continue
		var bp: Vector2 = bay["pos"]
		var rect := Rect2(bp.x - 1.2, bp.y - 4.9, 2.4, 4.8)
		if _in_rect(p2, rect) and spd < 0.25:
			if absf(car.global_transform.basis.z.x) > 0.45:
				_say("In der Bucht, aber schief — noch gerade einruecken.", 1)
			else:
				_done("perp", "Querparken geschafft — in der Lücke gerade ausgerichtet.")
			break

	# Berganfahren: auf der Rampe ohne Zurückrollen anfahren.
	var hill: Dictionary = lot["hill"]
	var hp: Vector2 = hill["pos"]
	var hill_rect := Rect2(hp.x - float(hill["w"]) * 0.5 - 1.0, hp.y - float(hill["run"]) * 0.5 - 7.0, float(hill["w"]) + 2.0, float(hill["run"]) + float(hill.get("down", 8.0)) + 22.0)
	# Wer am Hang haelt, sichert mit der Handbremse — nur Bremse oder
	# Kupplung allein laesst das Auto zurueckrollen.
	if _in_rect(p2, hill_rect) and spd < 0.2 \
			and not bool(car.get("handbrake_on")):
		_hill_stop_t += delta
		if _hill_stop_t > 2.5:
			_warn("Am Berg die Handbremse anziehen — Bremse oder Kupplung allein reicht nicht.")
			_hill_stop_t = -6.0
	else:
		_hill_stop_t = 0.0
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
	_check_deer(p2, spd)
	_check_rail(p2, spd)
	_check_ball(p2, spd)
	_check_engstelle(p2, spd)
	_check_panne(p2, spd, delta)
	_check_nacht(spd, delta)
	_check_nebel(spd, delta)
	_check_baustelle(p2, spd)
	_check_spiel(p2, spd)
	_check_schleif(spd, delta)
	_check_einfadeln(p2, spd)
	_check_rescue(spd)
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
					_exam_protocol()
	for c in cams:
		if is_instance_valid(c) and c.check(p2, spd * 3.6):
			_say("Geblitzt! %d km/h statt %d — das gibt Post." % [int(spd * 3.6), c.limit], 2)


## Taste P: Pruefungsfahrt starten (erneut = abbrechen).
func toggle_exam() -> void:
	if exam.active:
		exam.abort()
		_say("Prüfungsfahrt abgebrochen.", 0)
		_exam_protocol()
	else:
		exam.begin()
		_exam_errs = 0
		_exam_log.clear()
		_say("Prüfungsfahrt! " + String(exam.wps[0]["text"]), 0)


## Abschlussprotokoll: alle Beanstandungen der Pruefungsfahrt mit
## Straßennamen — wie das Pruefprotokoll in der echten Fuehrerschein-
## Pruefung. Laeuft als normale Fahrlehrer-Zeilen (level 0).
func _exam_protocol() -> void:
	if _exam_log.is_empty():
		_say("Protokoll: sauber gefahren — keine Beanstandungen.", 0)
		return
	var lines := []
	for e in _exam_log:
		var where := String(e["road"])
		if where == "":
			where = "im Gelaende"
		lines.append("- %s (%s)" % [String(e["text"]), where])
	_say("Fehlerliste:\n" + "\n".join(lines), 0)


## Schulterblick-Ersatz: beim Rechtsabbiegen mit echtem Verkehr in
## Reichweite wird erwartet, dass die Rueckblick-Kamera (Modus 3, Taste
## C) kurz vorher benutzt wurde — ein Ersatz fuer den Blick ueber die
## Schulter, den eine 3D-Personenperspektive nicht bietet.
func _check_shoulder(p2: Vector2) -> void:
	if cam == null:
		return
	var hazard := false
	if cyclist != null and is_instance_valid(cyclist) \
			and p2.distance_to(cyclist.pos2()) < 45.0:
		hazard = true
	for t in traffic:
		if is_instance_valid(t) \
				and p2.distance_to(Vector2(t.global_position.x, t.global_position.z)) < 45.0:
			hazard = true
	if hazard and Time.get_ticks_msec() / 1000.0 - _rear_ok_at > 4.0:
		_warn("Schulterblick vergessen — kurz vor dem Rechtsabbiegen den Rückblick (C) prüfen.")


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
				_say("Unfall! Person am Zebrastreifen angefahren — immer gucken.", 2)
		else:
			if bool(_ped_waiting.get(pid, false)) and d < 16.0:
				_ped_waiting[pid] = false
				_done("ped", "Fussgaenger passieren lassen — vorbildlich.")


## Wildwechsel am West-Ring: das Reh ist keine verkehrserzogene
## Figur — es springt unvermittelt. Warnung beim Annähern an die
## Querung, Treffer wird als schwerer Fehler gezählt.
var deer: Node3D = null
var _deer_warned := false
var _deer_hit := false


func _check_deer(p2: Vector2, spd: float) -> void:
	if deer == null or not is_instance_valid(deer):
		return
	var dp := Vector2(deer.global_position.x, deer.global_position.z)
	var d := p2.distance_to(dp)
	if bool(deer.on_road()):
		# Einmal pro Sprung warnen, wenn der Schueler nahe herankommt.
		if not _deer_warned and d < 55.0 and spd * 3.6 > 20.0:
			_deer_warned = true
			_say("Wildwechsel! Vom Gas — das Tier springt quer, bremsbereit bleiben.", 1)
		if d < 3.0 and spd > 1.0 and not _deer_hit:
			_deer_hit = true
			_say("Wildunfall! Bei Wildwechsel nie ausweichen — stark bremsen und spur halten.", 2)
	elif _deer_warned and d < 45.0 and spd * 3.6 < 25.0:
		# Schueler ist rechtzeitig langsam geworden — Lektion gegessen.
		_deer_warned = false
		_say("Wildwechsel passiert — vorsichtig, das klappt.", 0)
	elif d > 60.0:
		_deer_warned = false
	if _deer_hit and d > 30.0:
		_deer_hit = false   ## erst zuruecksetzen, wenn die Stelle weit weg ist


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
	# Wer bei geschlossener Schranke die Andreaskreuz-Linie erreicht,
	# muss halten — die Warnung kommt erst kurz vor den Schranken,
	# nicht schon beim gehoerigen Abbremsen davor.
	elif rail.is_closed() and absf(d.x) < 6.5 and absf(d.y) < 6.0 and spd > 2.0:
		_warn("Schranken geschlossen — vor dem Andreaskreuz anhalten!")


func _check_ball(p2: Vector2, spd: float) -> void:
	var all: Array = balls.duplicate()
	if ball != null:
		all.append(ball)
	for b in all:
		if not is_instance_valid(b) or not b.is_rolling() or not b.on_road():
			continue
		var bp := Vector2(b.global_position.x, b.global_position.z)
		var d := p2.distance_to(bp)
		if d > 22.0:
			continue
		if d < 1.6 and spd > 1.0:
			_warn("Den Ball überfahren — ein Kind könnte folgen, immer abbremsen!")
		elif spd * 3.6 > 20.0:
			_warn("Ball auf der Fahrbahn — Kinder könnten folgen, bremsen!")
		elif spd < 2.0:
			_done("ball", "Ball gesehen und angehalten — vorbildlich vorausschauend.")
		elif spd < 5.5:
			_done("ball", "Ball gesehen und in Schritttempo vorbei — genau richtig.")


## Zwischenbilanz (Taste Z): Fahrlehrer zieht ein Zwischenfazit —
## Strecke, Abwuerger, Beanstandungen und der naechste Schritt.
func report() -> void:
	var done := 0
	var next := "bereit für die Prüfungsfahrt (P)!"
	for t in TASKS:
		if _tasks_done.get(String(t["id"]), false):
			done += 1
		elif next == "bereit für die Prüfungsfahrt (P)!":
			next = "nächste Übung: " + String(t["name"])
	_say("Zwischenbilanz — %.1f km · %d× abgewürgt · %d Hinweise · Aufgaben %d/%d · %s" % [
		_km_driven / 1000.0, _stalls_seen, _warn_cnt, done, TASKS.size(), next], 0)


func _check_nacht(spd: float, delta: float) -> void:
	# Nachtfahrt-Uebung: 150 m im Dunkeln mit Abblendlicht unterwegs
	# sein — wer ohne Licht faehrt, bekommt den Hinweis.
	_night_cd = maxf(_night_cd - delta, 0.0)
	if not night or _tasks_done.get("nacht", false):
		_night_dist = 0.0
		return
	if bool(car.get("headlights_on")):
		_night_dist += spd * delta
		if _night_dist > 150.0:
			_done("nacht", "Nachtfahrt mit Abblendlicht — Abstand und Tempo anpassen!")
	elif spd > 3.0 and _night_cd <= 0.0:
		_warn("Bei Dunkelheit Abblendlicht an — Taste L.")
		_night_cd = 8.0


func _check_einfadeln(p2: Vector2, spd: float) -> void:
	# Auffahrt Oststrasse (x=100) -> Ring Nord (z=-240): im fliessenden
	# Verkehr braucht man Anlauf — unter ~58 km/h einfaedein bremsen
	# den Verkehr aus.
	var auf_ost := p2.x > 93.0 and p2.x < 107.0 and p2.y < -205.0 and p2.y > -238.0
	if auf_ost:
		if spd > 13.0:
			_auf_armed = true
		elif p2.y > -222.0:
			_auf_slow = true
	elif _auf_armed and p2.y < -236.5 and absf(p2.x - 100.0) > 8.0:
		_auf_armed = false
		if spd > 16.0:
			_done("einfaden", "Einfädeln — auf der Auffahrt beschleunigt und flüssig eingeordnet!")
			_auf_slow = false
		elif _auf_slow or spd > 8.0:
			_warn("Beim Einfädeln Gas geben — auf dem Streifen kommt man auf Tempo.")
			_auf_slow = false
	elif p2.y > -200.0:
		_auf_armed = false
		_auf_slow = false


func _check_rescue(spd: float) -> void:
	if rescue == null:
		return
	if not rescue.alarm:
		_rescue_ann = false
		if _rescue_near and not bool(_tasks_done.get("rettung", false)):
			_warn("Bei Blaulicht und Martinshorn machst du frei — nach rechts ran und anhalten.")
		_rescue_near = false
		return
	var dist: float = car.global_position.distance_to(rescue.global_position)
	if dist < 60.0:
		_rescue_near = true
		if not _rescue_ann:
			_rescue_ann = true
			_say("Blaulicht im Rückspiegel! Rechts ranfahren und frei machen.", 0)
	if _rescue_near and dist < 30.0 and spd < 4.0:
		# Spurversatz auch beim Stehen werten: Fahrzeugfront als
		# Referenzrichtung, wenn lane_offset zu langsam ist.
		var vel: Vector3 = car.linear_velocity
		if vel.length() < 2.0:
			vel = car.global_transform.basis.z * 3.0
		var off: float = surfaces.lane_offset(car.global_position, vel)
		# Abseits der Fahrbahn (Standstreifen/Seitenstreifen) zaehlt
		# ebenfalls als frei gemacht.
		var aside: bool = surfaces.road_at(car.global_position) == ""
		if (off > 1.2 and off < 9000.0) or aside:
			_done("rettung", "Platz gemacht — der Rettungswagen kommt durch!")


func _check_schleif(spd: float, delta: float) -> void:
	if not car.has_method("_clutch_pedal"):
		return
	var pedal: float = car._clutch_pedal()
	# Getretene Kupplung bei Fahrt: der linke Fuß gehoert nach dem
	# Schalten weg vom Pedal — sonst verschliesst die Kupplung.
	if pedal > 0.6 and spd > 4.0:
		_clutch_ride += delta
		if _clutch_ride > 3.0:
			_clutch_ride = -8.0
			_warn("Kupplungspedal loslassen beim Fahren — der Fuß kommt weg, sonst schleift die Kupplung.")
	elif _clutch_ride > 0.0:
		_clutch_ride = 0.0
	else:
		_clutch_ride = minf(_clutch_ride + delta, 0.0)
	# Kriechfahrt: Kupplung im Schleifpunkt halten und das Auto langsam
	# rollen lassen — drei Sekunden Kriechen ohne Abwuergen zaehlen.
	if _tasks_done.get("schleif", false) or bool(car.get("stalled")):
		return
	var kriechend: bool = pedal > 0.25 and pedal < 0.85 \
		and spd > 0.3 and spd < 2.2 and int(car.gear) == 1
	if kriechend:
		_slip_t += delta
		if _slip_t > 3.0:
			_done("schleif", "Schleifpunkt gehalten — so kriecht man durch Parkplätze und Staus.")
	else:
		_slip_t = 0.0


func _check_baustelle(p2: Vector2, spd: float) -> void:
	# Baustelle auf der Ring Sued: einmal sauber mit Tempo 30 durch.
	var z: Dictionary = CityLayout.baustelle()
	var inz: bool = Rect2(z["zone"]).has_point(p2)
	if inz and not _ba_in:
		_ba_in = true
		_ba_clean = true
	elif inz:
		if spd * 3.6 > float(z["limit"]) + 4.0:
			_ba_clean = false
			_warn("Baustelle — Tempo %d, Kegel beachten!" % int(z["limit"]))
	elif _ba_in:
		_ba_in = false
		if _ba_clean:
			_done("baustelle", "Baustelle mit Tempo 30 durch — Hand am Rad, Kegel im Blick.")


## Verkehrsberuhigter Bereich auf der Schulstrasse West: einmal sauber
## mit Schritttempo durch — der ganze Strassenraum ist Spielflaeche.
func _check_spiel(p2: Vector2, spd: float) -> void:
	var z: Dictionary = CityLayout.spiel()
	var inz: bool = Rect2(z["rect"]).has_point(p2)
	if inz and not _sp_in:
		_sp_in = true
		_sp_clean = true
		_say("Verkehrsberuhigter Bereich — Schritttempo, Kinder duerfen überall spielen.", 0)
	elif inz:
		if spd * 3.6 > float(z["limit"]) + 5.0:
			_sp_clean = false
			_warn("Schritttempo! Hier spielen Kinder — nur kriechen.")
	elif _sp_in:
		_sp_in = false
		if _sp_clean:
			_done("spiel", "Verkehrsberuhigter Bereich mit Schritttempo — vorsichtig, das ist richtig.")


func _check_nebel(spd: float, delta: float) -> void:
	# Nebelfahrt: 150 m bei Sicht unter 100 m mit Abblendlicht.
	if not fog or _tasks_done.get("nebel", false):
		_fog_dist = 0.0
		return
	if bool(car.get("headlights_on")):
		_fog_dist += spd * delta
		if _fog_dist > 150.0:
			_done("nebel", "Nebelfahrt mit Abblendlicht — Abstand verdoppeln, Blick bleibt nah.")
	elif spd > 3.0 and _night_cd <= 0.0:
		_warn("Im Nebel Abblendlicht an — Taste L.")
		_night_cd = 8.0


func _check_panne(p2: Vector2, spd: float, delta: float) -> void:
	# Pannen-Uebung auf der Schulstrasse: anhalten am Rand und den
	# Warnblinker an — so wie es der Fahrlehrer vormacht.
	var z := CityLayout.pannen_zone()
	if z.has_point(p2) and spd < 0.4:
		_panne_t += delta
		if bool(car.get("hazard")):
			if _panne_t > 4.0:
				_done("panne", "Pannenstellung — Warnblinker an, sicher am Rand. Gut!")
		elif _panne_t > 2.5:
			_warn("Bei einer Panne den Warnblinker einschalten!")
	else:
		_panne_t = 0.0


func _check_engstelle(p2: Vector2, spd: float) -> void:
	# Zone um die parkenden Autos: hier gilt Rechtsfahrgebot + Maßtempo.
	var cs: Array = CityLayout.street_ball()["cars"]
	var z0: float = minf(cs[0].y, cs[1].y) - 1.0
	var z1: float = maxf(cs[0].y, cs[1].y) + 1.0
	if absf(p2.x - 200.0) < 4.5 and p2.y > z0 and p2.y < z1 and spd * 3.6 > 25.0:
		_warn("Engstelle — langsam durchfahren und Gegenverkehr beachten!")


var _brake_entry: float = -1.0
var _brake_dec: float = 0.0
var _brake_peak: float = 0.0
var _brake_prev: float = 0.0
var _brake_v0: float = -1.0       ## Tempo beim Bremsbeginn (Bremsweg-Messung)
var _brake_p0 := Vector2.ZERO     ## Ort beim Bremsbeginn
var _brake_t0: float = 0.0        ## Zeitpunkt des Einfahrens in die Bremsbahn
var _brake_p_start := Vector2.ZERO  ## Ort des Einfahrens (Anhalteweg-Messung)
var _brake_t_v: float = -1.0      ## Zeitpunkt des ersten kräftigen Tritts
var _brake_dry := -1.0            ## letzter gemessener Bremsweg trocken
var _brake_wet := -1.0            ## letzter gemessener Bremsweg nass
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
	# Einfahrt in den Kreis gilt als aktiv, sobald man auf der
	# Kreisbahn steht — die Ringkante liegt bei r=16.
	elif d < 16.5 and spd > 2.0:
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
