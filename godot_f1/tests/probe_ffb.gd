extends SceneTree
## Messprotokoll für das Lenkrad-Gefühl.
##
## Das ist kein Bestanden/Nicht-bestanden-Test, sondern die Messung, auf die
## sich Plan und Prüfbericht berufen: Was bekommt das Lenkrad auf einer echten
## Runde, auf dem Kerb, auf Kies und unter einer Vollbremsung wirklich?
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_ffb.gd

const FRAME_HZ := 90.0

var main: Node3D
var car
var line
var frames: int = 0
var phase: int = 0
var phase_t: float = 0.0
var hint: int = -1

var cruise: Array = []      ## {speed, torque, damper, rumble, hz, oversteer, steer, source}
var kerb: Array = []
var gravel: Array = []
var braking: Array = []
var sliding: Array = []
var slow: Array = []        ## Schrittgeschwindigkeit: Grundreibung statt Kraft


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	car = main.get("player")
	line = main.get("line")
	if car == null or car.get("ffb") == null:
		print("FFB_PROBE SKIP no player car with force feedback")
		quit(0)
		return
	# Der Wagen faehrt selbst; gemessen wird, was dabei am Lenkrad ankommt.
	car.auto_drive = true
	car.remove_meta("headless_gas")
	# Nicht aus der Boxengasse messen: der Wagen startet schon auf der Geraden
	# mit Tempo, damit die schnellen Kurven in der Messung wirklich vorkommen.
	_place(0.0, 70.0)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	phase_t += 1.0 / FRAME_HZ
	match phase:
		0:
			_collect(cruise)
			if phase_t >= 20.0:
				_next(1)
		1:
			_place(6.45, 33.0)
			_collect(kerb)
			if phase_t >= 2.5:
				_next(2)
		2:
			_place(10.0, 28.0)
			_collect(gravel)
			if phase_t >= 2.5:
				_next(3)
		3:
			_place(0.0, 55.0)
			# Vollbremsung in der Kurve: die Vorderraeder arbeiten am
			# Friction-Circle-Limit - das Lenkrad muss leicht werden.
			car.auto_drive = false
			Input.action_press("steer_right", 1.0)
			car.set_meta("script_brake", 1.0)
			car.set_meta("script_throttle", 0.0)
			_collect(braking)
			if phase_t >= 2.0:
				car.remove_meta("script_brake")
				car.remove_meta("script_throttle")
				Input.action_release("steer_right")
				_next(4)
		4:
			# Heck bricht aus: der Wagen dreht, waehrend er geradeaus will.
			# Das ist die Situation, in der das Lenkrad in den Slide zieht.
			_slide(0.0, 40.0)
			# Der Fahrer hat noch nicht reagiert: gemessen wird, wohin das
			# Lenkrad von selbst will - naemlich in die Gegenlenkrichtung.
			car.auto_drive = false
			_collect(sliding)
			if phase_t >= 2.0:
				car.auto_drive = true
				_next(5)
		5:
			# Schrittgeschwindigkeit: hier darf keine erfundene Zentrierung
			# druecken, nur echte Reibung. Der Wagen faehrt selbst an, deshalb
			# zaehlen nur die Ticks unter 60 km/h.
			if phase_t < 0.1:
				_place(0.0, 2.5)
			if car.speed_kmh < 60.0:
				_collect(slow)
			if phase_t >= 1.5:
				_next(6)
		6:
			_report()


func _next(next_phase: int) -> void:
	phase = next_phase
	phase_t = 0.0
	print("FFB_PROBE Phase %d beginnt (%.0f s gefahren)" % [phase, float(frames) / FRAME_HZ])


## Setzt den Wagen auf einen festen Querabstand zur Ideallinie und haelt ihn
## dort - so wird aus "Kerb" eine reproduzierbare Messung statt Zufall.
func _place(offset: float, speed: float) -> void:
	if line == null:
		return
	if hint < 0:
		hint = line.closest_index(car.global_position)
	hint = line.closest_index_near(car.global_position, hint)
	var p: Vector3 = line.points[hint]
	var left: Vector3 = line.left_at(hint)
	var t: Vector3 = line.flat_tangent(hint)
	var fwd: Vector3 = car.global_transform.basis.z
	if t.dot(fwd) < 0.0:
		t = -t
	var basis := Basis.looking_at(-t, Vector3.UP)
	car.global_transform = Transform3D(basis, p + left * offset + Vector3(0, 0.2, 0))
	car.linear_velocity = t * speed
	car.angular_velocity = Vector3.ZERO


## Setzt den Wagen in einen echten Slide: Quergeschwindigkeit plus Gierrate.
## Der Reifen rechnet daraus den Uebersteuer-Grad, den das Lenkrad zu spueren
## bekommt - dieselbe Physik wie im Rennen, nur reproduzierbar.
func _slide(offset: float, speed: float) -> void:
	if line == null:
		return
	if hint < 0:
		hint = line.closest_index(car.global_position)
	hint = line.closest_index_near(car.global_position, hint)
	var p: Vector3 = line.points[hint]
	var left: Vector3 = line.left_at(hint)
	var t: Vector3 = line.flat_tangent(hint)
	if t.dot(car.global_transform.basis.z) < 0.0:
		t = -t
	var basis := Basis.looking_at(-t, Vector3.UP)
	car.global_transform = Transform3D(basis, p + left * offset + Vector3(0, 0.2, 0))
	# Nach rechts rutschen, waehrend das Auto nach links giert: damit dreht der
	# Schraeglauf der Vorderraeder durch die Null - die Kraft kehrt sich um.
	car.linear_velocity = t * speed - left * 10.0
	car.angular_velocity = Vector3(0, 2.6, 0)


func _collect(into: Array) -> void:
	var st: Dictionary = car.ffb.last_state
	var ctx: Dictionary = car.ffb.model.last_ctx if car.ffb.model else {}
	into.append({
		"speed": car.speed_kmh,
		"torque": float(st.get("torque", 0.0)),
		"damper": float(st.get("damper", 0.0)),
		"rumble": float(st.get("rumble", 0.0)),
		"hz": float(st.get("rumble_hz", 0.0)),
		"clip": float(st.get("clip", 0.0)),
		"source": String(st.get("source", "-")),
		"oversteer": float(car.tyres.oversteer),
		"understeer": float(car.tyres.understeer),
		"lat_g": float(ctx.get("lateral_g", 0.0)),
		"vert_g": float(ctx.get("vertical_g", 1.0)),
		"steer": float(car.last_steer),
		"yaw": float(car.angular_velocity.y),
	})


func _stat(rows: Array, key: String) -> Dictionary:
	var values: Array = []
	for row in rows:
		values.append(absf(float(row[key])))
	if values.is_empty():
		return {"n": 0, "mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	values.sort()
	var sum: float = 0.0
	for v in values:
		sum += v
	return {
		"n": values.size(),
		"mean": sum / float(values.size()),
		"p50": float(values[values.size() / 2]),
		"p95": float(values[mini(values.size() - 1, int(float(values.size()) * 0.95))]),
		"max": float(values[values.size() - 1]),
	}


func _source_counts(rows: Array) -> Dictionary:
	var counts: Dictionary = {}
	for row in rows:
		var key: String = String(row["source"])
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _opposes(rows: Array) -> Dictionary:
	## Kriterium 2/3 aus dem Plan: normal zieht die Kraft gegen den Lenkbefehl.
	## Bricht das Heck aus, dreht sie mit - hier wird gezaehlt, wie oft was
	## passiert, getrennt nach ruhiger Fahrt und Uebersteuern.
	var calm_oppose: int = 0
	var calm_ticks: int = 0
	var slide_oppose: int = 0
	var slide_ticks: int = 0
	for row in rows:
		var torque: float = float(row["torque"])
		var steer: float = float(row["steer"])
		if absf(torque) < 0.01 or absf(steer) < 0.05:
			continue
		var opposes: bool = signf(torque) != signf(steer)
		if float(row["oversteer"]) > 0.25:
			slide_ticks += 1
			if opposes:
				slide_oppose += 1
		elif float(row["oversteer"]) < 0.1:
			calm_ticks += 1
			if opposes:
				calm_oppose += 1
	return {
		"calm_oppose": calm_oppose, "calm": calm_ticks,
		"slide_oppose": slide_oppose, "slide": slide_ticks,
	}


func _report() -> void:
	print("---- FFB_MESSUNG ----")
	_line("Runde (8 s, KI auf der Linie)", cruise)
	_line("Kerb (Querabstand 6,45 m)", kerb)
	_line("Kies (10 m)", gravel)
	_line("Vollbremsung aus 200 km/h", braking)
	_line("Ausbrechendes Heck", sliding)
	_line("Schrittgeschwindigkeit (< 60 km/h)", slow)

	# Die Gerade bei Tempo: der Plan verlangt "spuerbares Grundgewicht, ruhig,
	# kein Zappeln". Gemessen wird deshalb nicht nur die Kraft, sondern auch,
	# wie stark sie von Tick zu Tick springt - Zappeln ist genau diese Zahl.
	var straight: Array = []
	for row in cruise:
		if float(row["speed"]) > 180.0 and absf(float(row["lat_g"])) < 0.6:
			straight.append(row)
	var straight_stat: Dictionary = _stat(straight, "torque")
	var straight_rumble: Dictionary = _stat(straight, "rumble")
	var straight_damp: float = 0.0
	var jitter: float = 0.0
	var prev: float = 0.0
	for i in straight.size():
		var row: Dictionary = straight[i]
		straight_damp += float(row["damper"])
		if i > 0:
			jitter += absf(float(row["torque"]) - prev)
		prev = float(row["torque"])
	var s_n: int = maxi(straight.size(), 1)
	print("Gerade bei Tempo (> 180 km/h, |Querlast| < 0,6 g) n=%d: Kraft Mittel %.3f Spitze %.3f, "
		% [straight.size(), float(straight_stat["mean"]), float(straight_stat["max"])]
		+ "Daempfung %.3f, Ruetteln Mittel %.3f, Sprung pro Tick %.4f"
		% [straight_damp / float(s_n), float(straight_rumble["mean"]), jitter / float(s_n)])

	var cruise_stats: Dictionary = _stat(cruise, "torque")
	var clip_ticks: int = 0
	var over_ticks: int = 0
	for row in cruise:
		if float(row["clip"]) > 0.15:
			over_ticks += 1
		if absf(float(row["torque"])) > 0.97:
			clip_ticks += 1
	var n: int = maxi(cruise.size(), 1)
	print("Clipping in der Runde: %d von %d Ticks ueber 0,97 (%.1f %%), davon "
		% [clip_ticks, cruise.size(), 100.0 * float(clip_ticks) / float(n)]
		+ "%d Ticks als 'am Anschlag' gezaehlt" % over_ticks)
	print("Kraft in der Runde: Mittel %.3f, Median %.3f, p95 %.3f, Spitze %.3f"
		% [float(cruise_stats["mean"]), float(cruise_stats["p50"]),
			float(cruise_stats["p95"]), float(cruise_stats["max"])])

	var slow_damp: float = 0.0
	var slow_n: int = 0
	var fast_damp: float = 0.0
	var fast_n: int = 0
	for row in cruise + slow:
		if float(row["speed"]) < 60.0:
			slow_damp += float(row["damper"])
			slow_n += 1
		elif float(row["speed"]) > 200.0:
			fast_damp += float(row["damper"])
			fast_n += 1
	print("Daempfung: < 60 km/h %.3f (n=%d), > 200 km/h %.3f (n=%d)"
		% [slow_damp / maxf(float(slow_n), 1.0), slow_n,
			fast_damp / maxf(float(fast_n), 1.0), fast_n])
	print("Quellen in der Runde: ", _source_counts(cruise))
	print("Quellen auf dem Kerb: ", _source_counts(kerb))
	print("Quellen auf Kies: ", _source_counts(gravel))
	print("Quellen unter der Bremse: ", _source_counts(braking))

	# Kuppe (Entlastung) und Bodenwelle (Stauchung): beides kommt aus der
	# senkrechten Last, die `car_controller.gd` aus der Physik mitgibt. Ueber
	# einer Kuppe wird das Lenkrad leicht, eine gestauchte Feder gibt einen
	# kurzen Stoss (Quelle "Bodenwelle").
	var vg_min: float = 9.0
	var vg_max: float = 0.0
	var vg_sum: float = 0.0
	var crest_ticks: int = 0
	var bump_ticks: int = 0
	for row in cruise:
		var g: float = float(row["vert_g"])
		vg_min = minf(vg_min, g)
		vg_max = maxf(vg_max, g)
		vg_sum += g
		if g < 0.80:
			crest_ticks += 1
		if g > 1.35:
			bump_ticks += 1
	print("Senkrechte Last: min %.2f g, max %.2f g, Mittel %.2f g | unter 0,80 g (Kuppe) %d Ticks, ueber 1,35 g (Bodenwelle) %d Ticks"
		% [vg_min, vg_max, vg_sum / maxf(float(cruise.size()), 1.0), crest_ticks, bump_ticks])

	var opp: Dictionary = _opposes(cruise)
	print("Kraft gegen Lenkbefehl: ruhig %d/%d (%.0f %%), im Uebersteuern %d/%d (%.0f %%)"
		% [int(opp["calm_oppose"]), int(opp["calm"]),
			100.0 * float(opp["calm_oppose"]) / maxf(float(opp["calm"]), 1.0),
			int(opp["slide_oppose"]), int(opp["slide"]),
			100.0 * float(opp["slide_oppose"]) / maxf(float(opp["slide"]), 1.0)])
	var slide_opp: Dictionary = _opposes(sliding)
	var slide_stat: Dictionary = _stat(sliding, "torque")
	var slide_over: Dictionary = _stat(sliding, "oversteer")
	# Gegenlenkrichtung: dreht der Wagen nach links (Gierrate +), greift der
	# Fahrer nach rechts - und genau dahin soll das Lenkrad von selbst ziehen.
	var with_counter: int = 0
	var ticks: int = 0
	for row in sliding:
		var torque: float = float(row["torque"])
		var yaw: float = float(row["yaw"])
		if absf(torque) < 0.01 or absf(yaw) < 0.2:
			continue
		ticks += 1
		if signf(torque) == signf(yaw):
			with_counter += 1
	print("Slide-Szenario: Uebersteuer-Mass Mittel %.2f, Kraft Mittel %.3f, "
		% [float(slide_over["mean"]), float(slide_stat["mean"])]
		+ "Kraft in Gegenlenkrichtung %d/%d (%.0f %%)"
		% [with_counter, ticks, 100.0 * float(with_counter) / maxf(float(ticks), 1.0)])

	var base: Dictionary = _stat(cruise, "torque")
	var brake_stat: Dictionary = _stat(braking, "torque")
	var brake_rumble: Dictionary = _stat(braking, "rumble")
	print("Vollbremsung: Kraft %.3f gegen Runde %.3f (%.0f %%), Ruetteln %.2f"
		% [float(brake_stat["mean"]), float(base["mean"]),
			100.0 * float(brake_stat["mean"]) / maxf(float(base["mean"]), 0.001),
			float(brake_rumble["max"])])
	print("---- ENDE FFB_MESSUNG ----")
	quit(0)


func _line(label: String, rows: Array) -> void:
	var t: Dictionary = _stat(rows, "torque")
	var r: Dictionary = _stat(rows, "rumble")
	var hz_min: float = 999.0
	var hz_max: float = 0.0
	for row in rows:
		if float(row["rumble"]) > 0.05:
			hz_min = minf(hz_min, float(row["hz"]))
			hz_max = maxf(hz_max, float(row["hz"]))
	print("%-30s n=%4d  Kraft Mittel %.3f Spitze %.3f | Ruetteln Mittel %.2f Spitze %.2f | Hz %s"
		% [label, int(t["n"]), float(t["mean"]), float(t["max"]),
			float(r["mean"]), float(r["max"]),
			"-" if hz_max <= 0.0 else "%.0f..%.0f" % [hz_min, hz_max]])
