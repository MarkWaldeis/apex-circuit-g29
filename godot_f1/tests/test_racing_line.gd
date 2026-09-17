extends SceneTree
## Abnahme der Ideallinie: rechnet sie wirklich eine Linie, mit der man
## schneller ist als auf der Mittellinie?
##
## Gemessen wird gegen die echte Strecke (assets/track/racing_line.json), nicht
## gegen eine Attrappe: Korridor, Kruemmung, Scheitel auf der Innenseite,
## Bremsprofil und die Phasen fuer die Anzeige.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_racing_line.gd

const RacingLine = preload("res://scripts/racing_line.gd")
const IdealLine = preload("res://scripts/ideal_line.gd")

const LINE_PATH := "res://assets/track/racing_line.json"

var failed: int = 0


func _initialize() -> void:
	var line = RacingLine.new()
	if not line.load_json(LINE_PATH):
		print("RACING_LINE FAIL could not load the centre line")
		quit(1)
		return
	var ideal = IdealLine.new()
	if not ideal.build(line):
		print("RACING_LINE FAIL could not build the ideal line")
		quit(1)
		return
	# Die Mittellinie mit demselben Fahrzeugmodell: nur so laesst sich sagen,
	# ob die Ideallinie wirklich schneller ist.
	var centre = IdealLine.new()
	centre.build(line, {"corridor": 0.0})
	_run(line, ideal, centre)


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run(line, ideal, centre) -> void:
	var n: int = ideal.points.size()
	_check(n == line.points.size(), "same_point_count", "%d" % n)

	# --- Korridor -----------------------------------------------------------
	var max_offset := 0.0
	var worst_side := 0.0
	for i in n:
		max_offset = maxf(max_offset, absf(ideal.offsets[i]))
		worst_side = maxf(worst_side, ideal.points[i].distance_to(line.points[i]))
	var limit: float = ideal.offset_limit()
	_check(max_offset <= limit + 0.001, "line_stays_inside_the_corridor",
		"max|offset|=%.2f m (Grenze %.1f)" % [max_offset, limit])
	# Fahrbahn halb 6.0 m + Kerb 0.85 m: die Linie darf nie auf dem Gras landen.
	_check(worst_side < 6.5, "every_point_is_on_asphalt_or_kerb",
		"worst=%.2f m von der Mitte" % worst_side)

	# --- ist es wirklich eine Ideallinie? -----------------------------------
	# Was zaehlt, ist die Rundenzeit mit demselben Fahrzeugmodell: die
	# Ideallinie muss schneller sein als die Mittellinie. Kruemmungsenergie
	# wird zusaetzlich berichtet, ist aber nicht das Kriterium.
	var time_ideal: float = _lap_time(ideal)
	var time_centre: float = _lap_time(centre)
	var gain_s: float = time_centre - time_ideal
	print("  Rundenzeit: Mitte %.2f s, Ideallinie %.2f s (%.2f s schneller)" % [
		time_centre, time_ideal, gain_s])
	_check(gain_s >= 0.3, "ideal_line_is_faster_than_the_centre_line",
		"%.2f s auf %.0f m" % [gain_s, ideal.length])
	var ideal_energy: float = _curvature_energy(ideal)
	var centre_energy: float = _curvature_energy(centre)
	_check(ideal_energy < centre_energy, "ideal_line_has_less_curvature_energy",
		"J %.3f -> %.3f" % [centre_energy, ideal_energy])

	# --- Scheitel auf der Innenseite ----------------------------------------
	var apex := 0
	var apex_k := 0.0
	for i in n:
		# Kruemmung der Mittellinie ueber die Laenge gemessen (siehe
		# ideal_line.gd::_centre_curvature) - eine Messung ueber "6 Punkte"
		# findet am Rundenende eine Kurve, die nur ein Abtastfehler ist.
		var k: float = absf(ideal._centre_k[i])
		if k > apex_k:
			apex_k = k
			apex = i
	var apex_centre_k: float = ideal._centre_k[apex]
	var apex_offset: float = ideal.offsets[apex]
	var inward: bool = signf(apex_offset) == signf(apex_centre_k)
	# Der Scheitel muss innen liegen (Vorzeichen), und die Linie muss die Kurve
	# aussen anfahren - das ist die Signatur einer Ideallinie.
	_check(inward and absf(apex_offset) >= 1.2, "apex_is_clipped_on_the_inside",
		"Index %d: k=%.4f, offset=%+.2f m" % [apex, apex_centre_k, apex_offset])
	var entry: int = wrapi(apex - 30, 0, n)
	var exit_i: int = wrapi(apex + 30, 0, n)
	var entry_offset: float = ideal.offsets[entry]
	var exit_offset: float = ideal.offsets[exit_i]
	_check(signf(entry_offset) != signf(apex_offset) or absf(entry_offset) < absf(apex_offset),
		"corner_is_entered_from_the_outside",
		"Zufahrt %+.2f m, Scheitel %+.2f m, Ausfahrt %+.2f m" % [
			entry_offset, apex_offset, exit_offset])
	for step in [60, 40, 20, 0, -20, -40, -60]:
		var idx: int = wrapi(apex + step, 0, n)
		print("  Linie bei Scheitel%+d: offset=%+.2f m, k=%.4f, v=%.1f km/h" % [
			step, ideal.offsets[idx], ideal.curvature[idx], ideal.target_speed[idx] * 3.6])

	# --- Laenge -------------------------------------------------------------
	_check(ideal.length > 1500.0 and ideal.length < 1800.0, "lap_length_plausible",
		"%.1f m (Mitte %.1f m)" % [ideal.length, line.length])

	# --- Geschwindigkeit ----------------------------------------------------
	var v_over := 0
	var v_floor := 0
	var worst_v := 0.0
	var brake_break := 0
	var worst_brake := 0.0
	var a_lat: float = float(ideal.params["lat_accel"])
	var a_brake: float = float(ideal.params["brake_decel"])
	var v_min: float = float(ideal.params["v_min"])
	for i in n:
		var k: float = absf(ideal.curvature[i])
		var v_curve: float = 96.0 if k < 1e-6 else sqrt(a_lat / k)
		if ideal.target_speed[i] > v_curve + 0.05:
			# Unterhalb von v_min ist die Untergrenze des Modells der Grund,
			# nicht ein Fehler im Profil.
			if v_curve < v_min:
				v_floor += 1
			else:
				v_over += 1
				worst_v = maxf(worst_v, ideal.target_speed[i] - v_curve)
		var after: int = (i + 1) % n
		var reach: float = sqrt(ideal.target_speed[after] * ideal.target_speed[after]
			+ 2.0 * a_brake * ideal.segments[i]) + 0.05
		if ideal.target_speed[i] > reach:
			brake_break += 1
			worst_brake = maxf(worst_brake, ideal.target_speed[i] - reach)
	_check(v_over == 0, "corner_speed_never_exceeds_the_grip_limit",
		"violations=%d (davon %d unter der Modell-Untergrenze %.0f m/s) worst=%.2f m/s" % [
			v_over, v_floor, v_min, worst_v])
	_check(brake_break == 0, "braking_profile_is_physically_reachable",
		"violations=%d worst=%.2f m/s" % [brake_break, worst_brake])

	# --- Phasen -------------------------------------------------------------
	var counts := [0, 0, 0]
	for p in ideal.phase:
		counts[p] += 1
	_check(counts[0] > 0 and counts[1] > 0 and counts[2] > 0,
		"all_three_phases_exist",
		"gas=%d lupfen=%d bremsen=%d" % [counts[0], counts[1], counts[2]])
	# Jede rote Zone muss lang genug sein, sonst flackert die Anzeige.
	var zones: Array = []
	var i := 0
	while i < n:
		if ideal.phase[i] == IdealLine.BRAKE:
			var start := i
			var span := 0.0
			while i < n and ideal.phase[i] == IdealLine.BRAKE:
				span += ideal.segments[i]
				i += 1
			zones.append({"start": start, "length": span})
		else:
			i += 1
	var shortest := INF
	for z in zones:
		shortest = minf(shortest, float(z["length"]))
	_check(zones.size() >= 3, "the_track_has_several_braking_zones",
		"%d Zonen" % zones.size())
	_check(shortest >= 24.0, "no_braking_zone_is_shorter_than_25_m",
		"kuerzeste=%.1f m" % shortest)

	# --- Bremsweg zur Physik ------------------------------------------------
	# Eine rote Zone muss dort anfangen, wo die Verzoegerung wirklich anfaellt,
	# und vor der Kurve wieder enden.
	var bad_zone := 0
	for z in zones:
		var start: int = int(z["start"])
		var before: int = (start - 1 + n) % n
		# Ende der Zone exakt suchen (nicht ueber die Laenge schaetzen).
		var after: int = start
		for _step in n:
			if ideal.phase[after] != IdealLine.BRAKE:
				break
			after = (after + 1) % n
		if ideal.target_speed[before] <= ideal.target_speed[after] + 1.0:
			bad_zone += 1
	_check(bad_zone == 0, "every_braking_zone_really_slows_the_car_down",
		"Zonen ohne Verzoegerung=%d" % bad_zone)
	# Der Startpunkt der Zone muss aus der Geschwindigkeit davor erreichbar sein.
	var start_err := 0.0
	for z in zones:
		var start: int = int(z["start"])
		var before: int = (start - 1 + n) % n
		var reachable: float = ideal.target_speed[before]
		var travelled := 0.0
		var i2 := before
		for _step in 200:
			i2 = (i2 + 1) % n
			travelled += ideal.segments[(i2 - 1 + n) % n]
			if ideal.phase[i2] != IdealLine.BRAKE:
				break
		var v_end: float = ideal.target_speed[i2]
		var needed: float = (reachable * reachable - v_end * v_end) / (2.0 * a_brake)
		start_err = maxf(start_err, (needed - travelled) / maxf(needed, 1.0))
	_check(start_err < 0.5, "braking_zone_starts_early_enough",
		"schlechteste Zone nutzt %.0f%% des verfuegbaren Weges" % ((1.0 - start_err) * 100.0))

	# --- Beispiel fuer den Bericht ------------------------------------------
	print("IDEAL_LINE summary length=%.1f m max|offset|=%.2f m J=%.3f (Mitte %.3f) Zonen=%d" % [
		ideal.length, max_offset, ideal_energy, centre_energy, zones.size()])
	for z in zones.slice(0, mini(4, zones.size())):
		var start: int = int(z["start"])
		var v_before: float = ideal.target_speed[(start - 1 + n) % n]
		var v_after: float = ideal.target_speed[(start + int(float(z["length"]) / 1.15) + n) % n]
		print("  Bremszone ab Index %d: %.1f m lang, %.1f -> %.1f km/h" % [
			start, float(z["length"]), v_before * 3.6, v_after * 3.6])

	if failed > 0:
		print("RACING_LINE FAIL count=", failed)
		quit(1)
	else:
		print("RACING_LINE PASS")
		quit(0)


## Rundenzeit, die dieses Profil mit seinem eigenen Fahrzeugmodell ergibt.
func _lap_time(model) -> float:
	var n: int = model.points.size()
	var t := 0.0
	for i in n:
		var v: float = maxf(model.target_speed[i], 1.0)
		t += model.segments[i] / v
	return t


## Kruemmungsenergie J = Summe k^2 * ds: je kleiner, desto weniger Querkraft
## kostet die Runde.
func _curvature_energy(model) -> float:
	var n: int = model.points.size()
	var j := 0.0
	for i in n:
		var k: float = model.curvature[i]
		j += k * k * model.segments[i]
	return j
