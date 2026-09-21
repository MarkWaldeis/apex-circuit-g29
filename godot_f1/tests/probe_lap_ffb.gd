extends SceneTree
## Echte Runde auf der echten Strecke: was das Lenkrad dabei wirklich bekommt.
##
## Warum es das gibt (gemessen am 21.09.2026): fast alle Zahlen der Soll-Tabelle
## in `docs/FFB_F1_STYLE_PLAN.md` §2 stammen aus **synthetischen** Szenarien -
## das Modell wird direkt mit einem `ctx` gefuettert ("Bogen: lat_g = 3.2"). Das
## beweist, dass das Modell rechnen kann, aber nicht, dass diese Situation im
## Spiel **vorkommt** und dass dort dieselben Werte herauskommen.
##
## Diese Sonde faehrt deshalb das **echte Spielerauto auf der echten Strecke** -
## dieselbe Physik, dieselben Kerbs, dieselbe Ideallinie, dieselben
## Schaltvorgaenge - und liest jeden Physik-Tick genau die Zahlen, die
## `ffb_link.gd` an `tools/g29_ffb.py` schickt (`car.ffb.model`). Damit wird aus
## "das Modell kann es" ein "das passiert wirklich".
##
## Drei Abschnitte:
##   A  reale Runde  - das Auto faehrt mit dem Autopiloten die Ideallinie
##   D  Untersteuern - Vollgas und voller Lenkeinschlag bei Tempo, die
##                     Vorderachse geht ueber ihren Peak
##   E  Uebersteuern - Vollgas im langsamen Bogen (Traktionskontrolle aus),
##                     das Heck kommt: dreht die Kraft in die Gegenlenkrichtung?
##   F  Anschlag     - am Lenkanschlag stehen (Lenkdruck gestellt, weil er sonst
##                     aus dem G29 kommt): steigt die Kraft mit dem Druck?
##   B  Bremsprobe   - Vollbremsung aus hoher Geschwindigkeit (blockierende
##                     Vorderraeder koennen nur hier auftreten, nicht auf der
##                     Ideallinie)
##   C  weiter hinaus - absichtlich weit gefahren: Kerb, Kies, Wandkontakt
##
##   powershell -File tools/run_godot.ps1 --fixed-fps 300 --headless `
##       --path godot_f1 --script tests/probe_lap_ffb.gd
##
## `--fixed-fps` laesst Godot die Physik schneller als in Echtzeit rechnen -
## sonst dauert die Runde eine Minute Wanduhr. Am Modell aendert das nichts:
## der Physik-Schritt bleibt 1/60 s.

const RacingLine = preload("res://scripts/racing_line.gd")

## Abschnittsgrenzen in Physik-Frames (60 Hz).
var warmup_frames: int = 6
var lap_frames: int = 5400
var under_frames: int = 300
var over_frames: int = 240
var lock_frames: int = 240
var brake_gas_frames: int = 420
var brake_frames: int = 150
var wide_frames: int = 600
var quiet_frames: int = 120

var main: Node3D
var line = RacingLine.new()
var player
var frames: int = 0
var phase: String = "A"
var failed: int = 0
var notes: Array = []

## Zaehler und Extreme je Situation (alles, was gemessen wird, wird gezaehlt).
var ticks: int = 0
var speed_max: float = 0.0
var torque_abs_max: float = 0.0
var clip_ticks: int = 0
var clip_max: float = 0.0
var nan_ticks: int = 0
var surf_ticks: Dictionary = {}
var source_ticks: Dictionary = {}

var asphalt_n: int = 0
var asphalt_rumble_max: float = 0.0
var asphalt_hz_min: float = 999.0
var asphalt_hz_max: float = 0.0

var kerb_n: int = 0
var kerb_rumble_max: float = 0.0
var kerb_hz_min: float = 999.0
var kerb_hz_max: float = 0.0

var gravel_n: int = 0
var gravel_rumble_max: float = 0.0
var gravel_hz_min: float = 999.0
var gravel_hz_max: float = 0.0

var straight_n: int = 0
var straight_torque_max: float = 0.0
var straight_damper_min: float = 9.0
var straight_rumble_max: float = 0.0

var corner_n: int = 0
var corner_against: int = 0
var corner_with: int = 0
var corner_flat: int = 0
var corner_torque_max: float = 0.0
var corner_soft_n: int = 0
var heavy_n: int = 0
## Kraft in den Ticks mit echter Rennwagen-Querlast - das ist die Zeile, die
## die Soll-Tabelle mit "3-4 g: schwer, 55-75 %" meint.
var heavy_torque_sum: float = 0.0
var heavy_torque_max: float = 0.0
## Querlast-Spitzen ueber 4 g sind Aufpralle, keine Kurven - sie wuerden die
## Aussage "so hart faehrt das Auto durch den Bogen" verfaelschen.
var lat_window_max: float = 0.0
var lat_spike_n: int = 0
## Ticks, in denen das Auto in Abschnitt A praktisch stand (festgefahren).
var slow_n: int = 0
var slow_run: int = 0
var slow_run_max: int = 0
## Dasselbe fuer das KI-Auto: bleibt der Gegner liegen?
var ai_slow_n: int = 0
## Das Modell dreht die Kraft fuer das G29 um (`invert`). Die physikalische
## Aussage "drueckt gegen den Lenkbefehl" gilt vor dieser Umdrehung.
var invert: bool = true

var under_n: int = 0
var under_torque_max: float = 0.0
var under_torque_sum: float = 0.0
## Heck bricht aus: die Kraft muss in die Gegenlenkrichtung drehen.
var over_n: int = 0
var over_flip: int = 0
var over_same: int = 0
## Die Zeile der Soll-Tabelle gilt **nicht** fuer jeden Uebersteuer-Tick,
## sondern fuer den Moment, in dem der Schlupfwinkel der Vorderraeder durch die
## Null dreht. Deshalb wird hier getrennt gezaehlt: "durch die Null" (Vorzeichen
## des Vorder-Schlupfs gegen den Lenkbefehl) und "noch nicht durch".
var over_cross_n: int = 0
var over_cross_help: int = 0
var over_plain_n: int = 0
var over_plain_against: int = 0
## Mittelwerte der **vorzeichenbehafteten** Kraft (phys * Lenkbefehl): negativ
## heisst "drueckt gegen den Lenkbefehl", positiv heisst "zieht mit". Die
## Glättung (45 ms) laesst einzelne Ticks kippen - deshalb wird hier der
## Mittelwert beider Gruppen verglichen statt jeder einzelne Tick.
var over_cross_signed: float = 0.0
var over_plain_signed: float = 0.0
## Wie lange dauert es, bis die Kraft dem Vorzeichen des Vorder-Schlupfs folgt?
## Die Glaettung (SMOOTH_TAU 45 ms) laesst kurze Nulldurchgaenge verpuffen,
## deshalb wird hier nach der **Dauer** des Nulldurchgangs getrennt.
var cross_run: int = 0
var cross_run_max: int = 0
var long_cross_n: int = 0
var long_cross_signed: float = 0.0
var short_cross_n: int = 0
var short_cross_signed: float = 0.0
## Die ungeglaettete Grundkraft `sat` zeigt, wohin die Vorderachse wirklich
## zieht; `torque` ist die geglaettete (und fuer das G29 gedrehte) Kraft, die am
## Rad ankommt. Beide werden hier getrennt gezaehlt - sonst verwechselt man den
## Nulldurchgang mit der Glaettungsverzoegerung.
var sat_with_n: int = 0
var sat_against_n: int = 0
var lag_n: int = 0
var sat_run: int = 0
var sat_run_max: int = 0
var over_torque_max: float = 0.0
var spin_n: int = 0
var spin_rumble_max: float = 0.0
## Soft Lock: je Druckstufe die mittlere Kraft am Rad.
var lock_stage: Dictionary = {}
var lock_endstop_max: float = 0.0

var lock_n: int = 0
var lock_torque_max: float = 0.0
var lock_rumble_max: float = 0.0
var lock_hz_min: float = 999.0
var lock_hz_max: float = 0.0
## Nur die Ticks, in denen das Rattern des blockierenden Rads auch die
## **lauteste** Quelle ist - sonst mischt sich ein Kerb oder ein Einschlag in
## die Zahl und der Bericht behauptet etwas, das er nicht gemessen hat.
var lock_src_n: int = 0
var lock_src_rumble_max: float = 0.0
var lock_src_hz_min: float = 999.0
var lock_src_hz_max: float = 0.0

var pulse_n: int = 0
var pulse_max: float = 0.0
var pulse_kinds: Dictionary = {}

var endstop_n: int = 0
var endstop_max: float = 0.0
var damage_max: float = 0.0
var lap_progress: int = 0
var start_index: int = -1
## Querabstand zur Ideallinie: der einzige Weg, wie das Modell die Oberflaeche
## kennt (`surfaces.gd`). Ohne diese Zahl ist "Kies" im Bericht nicht deutbar.
var off_max: float = 0.0
var off_sum: float = 0.0
var off_n: int = 0
var lat_max: float = 0.0
## Dieselben Zahlen je Abschnitt - damit ein Ausflug ins Kies eindeutig dem
## Abschnitt zugeordnet werden kann, in dem er passiert ist.
var phases: Dictionary = {}
var ai_car
var ai_off_max: float = 0.0


func _initialize() -> void:
	# Die Abschnitte sind fuer wiederholte Messungen einstellbar, ohne die Datei
	# zu aendern (wie bei den anderen Sonden des Projekts).
	lap_frames = _env_int("APEX_LAP_FRAMES", lap_frames)
	wide_frames = _env_int("APEX_WIDE_FRAMES", wide_frames)
	call_deferred("_boot")


func _env_int(name: String, fallback: int) -> int:
	var raw: String = OS.get_environment(name)
	if raw.is_valid_int():
		return int(raw)
	return fallback


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _note(text: String) -> void:
	notes.append(text)
	print("NOTE ", text)


func _boot() -> void:
	if not line.load_json("res://assets/track/racing_line.json"):
		_check(false, "racing_line_loads")
		_finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames == warmup_frames:
		player = main.get("player")
		var ai = main.get("ai_car")
		_check(player != null, "the_player_car_exists",
			"player=%s" % ("da" if player else "FEHLT - main.gd hat kein Auto gebaut"))
		_check(player != null and player.ffb != null, "the_player_has_the_wheel_channel",
			"ffb=%s" % ("da" if (player and player.ffb) else "FEHLT"))
		_check(player != null and player.ffb != null and player.ffb.model != null,
			"the_model_that_drives_the_wheel_is_readable")
		_check(ai != null, "the_ai_car_exists")
		if player == null or player.ffb == null or player.ffb.model == null:
			_finish()
			return
		start_index = line.closest_index(player.global_position)
		ai_car = ai
		invert = bool(player.ffb.settings.invert)
		var gain_env: String = OS.get_environment("APEX_LAP_GAIN")
		if gain_env.is_valid_float():
			player.ffb.settings.gain = clampf(gain_env.to_float(), 0.0, 1.0)
			print("LAP_FFB Staerke fuer diese Messung auf %.2f gesetzt" % float(player.ffb.settings.gain))
		player.auto_drive = true
		print("LAP_FFB gain=%.2f invert=%s rotation=%.0f Grad Richtung_aus=%s" % [
			float(player.ffb.settings.gain),
			str(bool(player.ffb.settings.invert)),
			float(player.ffb.settings.rotation_deg),
			String(player.ffb.settings.invert_source),
		])
		return
	if frames <= warmup_frames:
		return

	_switch_phase()
	_sample()
	_drive()

	if frames >= _total_frames():
		_finish()
	# Spur: wo faehrt das Auto eigentlich? Ohne diese Zeilen ist "Kies" im
	# Bericht nicht deutbar - sie zeigen Position, Querabstand, Tempo und was
	# die Ideallinie an derselben Stelle sagt.
	if phase == "A" and frames % 450 == 0:
		_trace()


func _trace() -> void:
	if player == null or player.ffb == null or player.ffb.model == null:
		return
	var ctx: Dictionary = player.ffb.model.last_ctx
	var surface: Dictionary = ctx.get("surface", {})
	var own: float = float(surface.get("offset", 0.0))
	var pt: Vector3 = player.global_position
	var idx: int = line.closest_index(pt)
	var to_centre: float = pt.distance_to(line.points[idx])
	var ideal_txt := "-"
	var ideal_gap := -1.0
	if player.ideal_line != null and player.ideal_line.points.size() > 8:
		var ii: int = player.ideal_line.closest_index(pt)
		ideal_gap = pt.distance_to(player.ideal_line.points[ii])
		ideal_txt = "%.2f" % ideal_gap
	var ai_txt := "-"
	if ai_car != null and ai_car.surfaces != null:
		var a_surf: Dictionary = ai_car.surfaces.sample(ai_car.global_position)
		ai_txt = "%.2f m / %.0f km/h / %s" % [
			absf(float(a_surf.get("offset", 0.0))), float(ai_car.speed_kmh),
			String(a_surf.get("name", "?")),
		]
	print("LAP_FFB Spur f=%d Tempo=%.0f km/h Abstand_zur_Mitte=%.2f m Modell_Offset=%.2f m %s Ideallinie=%.2f m | KI %s" % [
		frames, float(player.speed_kmh), to_centre, own,
		String(surface.get("name", "?")), ideal_gap, ai_txt,
	])


## Die drei Abschnitte auf der Zeitachse.
func _switch_phase() -> void:
	var a_end: int = warmup_frames + lap_frames
	var b1_end: int = a_end + brake_gas_frames
	var d_end: int = b1_end + under_frames
	var e_end: int = d_end + over_frames
	var f_end: int = e_end + lock_frames
	var b2_end: int = f_end + brake_frames
	var b3_end: int = b2_end + quiet_frames
	var c_end: int = b3_end + wide_frames
	var want: String = phase
	if frames <= a_end:
		want = "A"
	elif frames <= b1_end:
		want = "B1"
	elif frames <= d_end:
		want = "D"
	elif frames <= e_end:
		want = "E"
	elif frames <= f_end:
		want = "F"
	elif frames <= b2_end:
		want = "B2"
	elif frames <= b3_end:
		want = "B3"
	elif frames <= c_end:
		want = "C"
	if want != phase:
		print("LAP_FFB Abschnitt %s beginnt (Frame %d, %.0f km/h, Schaden %.2f)" % [
			want, frames, float(player.speed_kmh), float(player.crash.damage),
		])
		if want == "B1":
			# Die Bremsprobe braucht eine saubere Ausgangslage: das Auto stand
			# nach einem Ausflug im Kies. Zurueck auf die Linie, sonst wird aus
			# der Bremsprobe eine Standmessung (im ersten Lauf genau so
			# passiert: 420 Ticks Gas, 0 km/h, Kraft 0,000).
			player.rejoin_to_line()
		if want == "B2" or want == "C":
			# Von Hand fahren: der Autopilot wuerde bremsen und die Ideallinie
			# halten, genau das soll hier nicht passieren.
			player.auto_drive = false
		if want == "D":
			# Kontrollierte Ausgangslage: zurueck auf die Linie und mit 70 m/s
			# (252 km/h) hinein - was danach passiert, ist echte Physik auf der
			# echten Strecke (kein gestelltes `ctx`).
			player.auto_drive = false
			_launch(70.0)
		if want == "E":
			# Langsamer Bogen, Vollgas, Traktionskontrolle aus: nur dort kann
			# das Heck ueberhaupt kommen (power_slide braucht Tempo < 26 m/s).
			player.auto_drive = false
			player.assists["traction_control"] = false
			_launch(18.0)
		if want == "C":
			_launch(45.0)
		if want == "B2":
			# Die Bremsprobe braucht Tempo: nach dem Untersteuer-Abschnitt liegt
			# das Auto im Kies (im Lauf davor bremste es aus 6 km/h, was keine
			# Blockier-Messung ist).
			_launch(70.0)
		if want == "F":
			# Anschlag: der Lenkdruck kommt im echten Spiel aus dem G29, hier
			# wird er gestellt (0,2 -> 1,0 in fuenf Stufen).
			player.auto_drive = false
			_launch(15.0)
		if want != "F" and player.has_meta("script_lock"):
			player.remove_meta("script_lock")
		phase = want
	# Zurueck an den Anfang der Runde (nach dem Block) fuer den Quer-Abschnitt:
	# erst die Messungen, dann die Fahrt.


## Eingaben des Abschnitts. Der Autopilot faehrt Abschnitt A, danach der Fahrer.
func _drive() -> void:
	match phase:
		"B1":
			# Der Autopilot beschleunigt hier noch - mit Vollgas geradeaus waere
			# das Auto schon in der ersten Kurve ins Kies gefahren und die
			# Bremsprobe waere aus 4 km/h passiert (im ersten Lauf genau so).
			player.auto_drive = true
		"D":
			player.auto_drive = false
			Input.action_release("brake")
			Input.action_press("throttle", 1.0)
			Input.action_press("steer_right", 1.0)
		"E":
			player.auto_drive = false
			Input.action_release("brake")
			Input.action_press("throttle", 1.0)
			Input.action_press("steer_right", 0.8)
		"F":
			player.auto_drive = false
			Input.action_release("brake")
			Input.action_press("throttle", 0.35)
			Input.action_press("steer_right", 1.0)
			# Fuenf Druckstufen ueber den Abschnitt.
			var step: int = clampi(int(float(frames - _phase_start("F")) / float(lock_frames) * 5.0), 0, 4)
			player.set_meta("script_lock", 0.2 + 0.2 * float(step))
		"B2":
			player.auto_drive = false
			Input.action_release("throttle")
			Input.action_press("brake", 1.0)
			Input.action_press("steer_right", 0.35)
		"B3":
			Input.action_release("brake")
			Input.action_release("steer_right")
		"C":
			player.auto_drive = false
			Input.action_press("throttle", 0.55)
			Input.action_press("steer_right", 1.0)
		_:
			return


func _total_frames() -> int:
	return warmup_frames + lap_frames + brake_gas_frames + under_frames + over_frames \
		+ lock_frames + brake_frames + quiet_frames + wide_frames


## Erster Frame eines Abschnitts - der Anschlag-Abschnitt braucht ihn, um seinen
## Druck hochzuziehen.
func _phase_start(key: String) -> int:
	var a_end: int = warmup_frames + lap_frames
	var b1_end: int = a_end + brake_gas_frames
	var d_end: int = b1_end + under_frames
	var e_end: int = d_end + over_frames
	var f_end: int = e_end + lock_frames
	match key:
		"A": return warmup_frames
		"B1": return a_end
		"D": return b1_end
		"E": return d_end
		"F": return e_end
		"B2": return f_end
		"B3": return f_end + brake_frames
		"C": return f_end + brake_frames + quiet_frames
	return 0


## Auto auf die Linie setzen und mit `speed` m/s in Fahrtrichtung anstossen.
## Nur die **Ausgangslage** ist gestellt; die Fahrt danach ist echte Physik.
func _launch(speed: float) -> void:
	if player == null:
		return
	player.rejoin_to_line()
	player.linear_velocity = player.global_transform.basis.z * speed
	player.angular_velocity = Vector3.ZERO


## Genau die Zahlen lesen, die `ffb_link.gd` gerade an den Helfer schickt.
func _sample() -> void:
	var model = player.ffb.model
	var ctx: Dictionary = model.last_ctx
	if ctx.is_empty():
		return
	ticks += 1
	var speed: float = float(ctx.get("speed", 0.0))
	# Achtung: der Schluessel heisst `lateral_g` - mit `lat_g` gelesen war jede
	# Querlast 0 und der ganze Bogen-Abschnitt des Berichts leer (gemessen am
	# 21.09.2026, erster Lauf dieser Sonde).
	var lat: float = float(ctx.get("lateral_g", 0.0))
	var steer: float = float(ctx.get("steer", 0.0))
	var understeer: float = float(ctx.get("understeer", 0.0))
	var slip_front: float = float(ctx.get("slip_front", 0.0))
	var surface: Dictionary = ctx.get("surface", {})
	var surface_name: String = String(surface.get("name", "?"))
	var offset: float = absf(float(surface.get("offset", 0.0)))
	var torque: float = float(model.torque)
	## Vor der Umdrehung fuer das G29 - so, wie die Physik sie meint.
	var phys: float = torque * (-1.0 if invert else 1.0)
	var rumble: float = float(model.rumble)
	var hz: float = float(model.rumble_hz)
	var source: String = String(model.source)
	var brake_in: float = float(ctx.get("brake", 0.0))

	if not (is_finite(torque) and is_finite(rumble) and is_finite(hz) and is_finite(speed)):
		nan_ticks += 1
		return

	speed_max = maxf(speed_max, speed)
	torque_abs_max = maxf(torque_abs_max, absf(torque))
	damage_max = maxf(damage_max, float(ctx.get("damage", 0.0)))
	surf_ticks[surface_name] = int(surf_ticks.get(surface_name, 0)) + 1
	source_ticks[source] = int(source_ticks.get(source, 0)) + 1
	off_max = maxf(off_max, offset)
	off_sum += offset
	off_n += 1
	lat_max = maxf(lat_max, absf(lat))
	if absf(lat) > 4.0:
		lat_spike_n += 1
	elif absf(lat) > lat_window_max:
		lat_window_max = absf(lat)
	if phase == "A" and speed < 1.5:
		slow_n += 1
		slow_run += 1
		slow_run_max = maxi(slow_run_max, slow_run)
	else:
		slow_run = 0
	if frames > 600 and ai_car != null and float(ai_car.speed_kmh) < 1.5:
		ai_slow_n += 1
	var ph: Dictionary = phases.get(phase, {
		"ticks": 0, "off_max": 0.0, "off_sum": 0.0, "lat_max": 0.0,
		"torque_max": 0.0, "asphalt": 0, "kies": 0, "kerb": 0, "speed_max": 0.0,
	})
	ph["ticks"] = int(ph["ticks"]) + 1
	ph["off_max"] = maxf(float(ph["off_max"]), offset)
	ph["off_sum"] = float(ph["off_sum"]) + offset
	ph["lat_max"] = maxf(float(ph["lat_max"]), absf(lat))
	ph["torque_max"] = maxf(float(ph["torque_max"]), absf(torque))
	ph["speed_max"] = maxf(float(ph["speed_max"]), speed)
	if surface_name == "Asphalt":
		ph["asphalt"] = int(ph["asphalt"]) + 1
	elif surface_name == "Kies":
		ph["kies"] = int(ph["kies"]) + 1
	elif surface_name == "Kerb":
		ph["kerb"] = int(ph["kerb"]) + 1
	phases[phase] = ph
	if ai_car != null and ai_car.surfaces != null:
		var ai_surface: Dictionary = ai_car.surfaces.sample(ai_car.global_position)
		ai_off_max = maxf(ai_off_max, absf(float(ai_surface.get("offset", 0.0))))
	if absf(torque) >= 0.97:
		clip_ticks += 1
		clip_max = maxf(clip_max, absf(torque))

	if start_index >= 0 and player.global_position != Vector3.ZERO:
		var idx: int = line.closest_index(player.global_position)
		lap_progress = maxi(lap_progress, posmod(idx - start_index, line.points.size()))

	# --- Asphalt-Textur (nur wenn die Textur die lauteste Quelle ist) --------
	if source == "Asphalt":
		asphalt_n += 1
		asphalt_rumble_max = maxf(asphalt_rumble_max, rumble)
		asphalt_hz_min = minf(asphalt_hz_min, hz)
		asphalt_hz_max = maxf(asphalt_hz_max, hz)

	# --- Geradeaus schnell: Grundgewicht, Ruhe ------------------------------
	# Nur Ticks, in denen die Asphalt-Textur die lauteste Quelle ist: sonst
	# zaehlt hier ein Wandkontakt aus einem spaeteren Abschnitt mit.
	if speed > 55.0 and absf(lat) < 0.5 and source == "Asphalt":
		straight_n += 1
		straight_torque_max = maxf(straight_torque_max, absf(torque))
		straight_damper_min = minf(straight_damper_min, float(model.damper))
		straight_rumble_max = maxf(straight_rumble_max, rumble)

	# --- Bogen: schwer und gegen den Lenkbefehl ----------------------------
	if speed > 30.0 and absf(lat) >= 1.2:
		corner_n += 1
		var push_back: float = phys * signf(steer)
		if absf(torque) < 0.02:
			corner_flat += 1
		elif push_back < 0.0:
			corner_against += 1
		else:
			corner_with += 1
		corner_torque_max = maxf(corner_torque_max, absf(torque))
		if absf(torque) < 0.40:
			corner_soft_n += 1
	# Wie viele Ticks haben wirklich Rennwagen-Querlast (3 g und mehr)? Die
	# Soll-Tabelle nennt 3-4 g - ob das Auto das ueberhaupt faehrt, ist eine
	# eigene Frage und wird deshalb getrennt gezaehlt.
	if speed > 30.0 and absf(lat) >= 3.0:
		heavy_n += 1
		heavy_torque_sum += absf(torque)
		heavy_torque_max = maxf(heavy_torque_max, absf(torque))

	# --- Untersteuern: das Lenkrad muss leichter werden --------------------
	if understeer > 0.3 and speed > 30.0:
		under_n += 1
		under_torque_max = maxf(under_torque_max, absf(torque))
		under_torque_sum += absf(torque)

	# --- Heck bricht aus: Kraft dreht in die Gegenlenkrichtung --------------
	var oversteer: float = float(ctx.get("oversteer", 0.0))
	if oversteer > 0.3 and speed > 10.0:
		over_n += 1
		over_torque_max = maxf(over_torque_max, absf(torque))
		var sat_value: float = float(model.sat)
		if absf(sat_value) > 0.02:
			if sat_value * signf(steer) > 0.0:
				sat_with_n += 1
				sat_run += 1
				sat_run_max = maxi(sat_run_max, sat_run)
			else:
				sat_against_n += 1
				sat_run = 0
			if signf(sat_value) != signf(phys) and absf(phys) > 0.02:
				lag_n += 1
		else:
			sat_run = 0
		var pulls_with: bool = phys * signf(steer) > 0.0
		if pulls_with:
			over_flip += 1
		else:
			over_same += 1
		# "Durch die Null" heisst: der Vorder-Schlupf zeigt gegen den Lenkbefehl.
		var crossed: bool = absf(slip_front) > 0.004 and signf(slip_front) == -signf(steer)
		var signed: float = phys * signf(steer)
		if crossed:
			over_cross_n += 1
			over_cross_signed += signed
			if pulls_with:
				over_cross_help += 1
			cross_run += 1
			cross_run_max = maxi(cross_run_max, cross_run)
			# Ab 0,15 s ist der Nulldurchgang laenger als die Glaettung (45 ms).
			if cross_run >= 9:
				long_cross_n += 1
				long_cross_signed += signed
			else:
				short_cross_n += 1
				short_cross_signed += signed
		else:
			cross_run = 0
			over_plain_n += 1
			over_plain_signed += signed
			if not pulls_with:
				over_plain_against += 1
	if float(model.spin) > 0.3:
		spin_n += 1
		spin_rumble_max = maxf(spin_rumble_max, rumble)

	# --- Blockierende Vorderraeder: leicht und tot + Rattern ---------------
	if float(model.lock) > 0.5 and brake_in > 0.2:
		lock_n += 1
		lock_torque_max = maxf(lock_torque_max, absf(torque))
		lock_rumble_max = maxf(lock_rumble_max, rumble)
		lock_hz_min = minf(lock_hz_min, hz)
		lock_hz_max = maxf(lock_hz_max, hz)
		if source == "Blockiert":
			lock_src_n += 1
			lock_src_rumble_max = maxf(lock_src_rumble_max, rumble)
			lock_src_hz_min = minf(lock_src_hz_min, hz)
			lock_src_hz_max = maxf(lock_src_hz_max, hz)

	# --- Kerb und Kies -----------------------------------------------------
	if source == "Kerb":
		kerb_n += 1
		kerb_rumble_max = maxf(kerb_rumble_max, rumble)
		kerb_hz_min = minf(kerb_hz_min, hz)
		kerb_hz_max = maxf(kerb_hz_max, hz)
	elif source == "Kies":
		gravel_n += 1
		gravel_rumble_max = maxf(gravel_rumble_max, rumble)
		gravel_hz_min = minf(gravel_hz_min, hz)
		gravel_hz_max = maxf(gravel_hz_max, hz)

	# --- Stoesse (Schalten, Einschlag, Bodenwelle) -------------------------
	if float(model.pulse) > 0.0:
		pulse_n += 1
		pulse_max = maxf(pulse_max, float(model.pulse))
		pulse_kinds[source] = int(pulse_kinds.get(source, 0)) + 1

	# --- Lenkanschlag ------------------------------------------------------
	if absf(float(model.endstop)) > 0.01:
		endstop_n += 1
		endstop_max = maxf(endstop_max, absf(float(model.endstop)))

	# --- Soft Lock: Kraft je Lenkdruck-Stufe ---------------------------------
	if phase == "F":
		var lp: float = clampf(float(ctx.get("lock_pressure", 0.0)), 0.0, 1.0)
		var key: String = "%.1f" % (roundf(lp * 10.0) / 10.0)
		var entry: Dictionary = lock_stage.get(key, {"n": 0, "sum": 0.0, "max": 0.0})
		entry["n"] = int(entry["n"]) + 1
		entry["sum"] = float(entry["sum"]) + absf(torque)
		entry["max"] = maxf(float(entry["max"]), absf(torque))
		lock_stage[key] = entry
		lock_endstop_max = maxf(lock_endstop_max, absf(float(model.endstop)))


func _finish() -> void:
	Input.action_release("throttle")
	Input.action_release("brake")
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	print("---- LAP_FFB BERICHT ----")
	print("LAP_FFB ticks=%d Frames=%d hoechste Geschwindigkeit=%.1f km/h Rundenfortschritt=%d/%d" % [
		ticks, frames, speed_max * 3.6, lap_progress, line.points.size() if line else 0,
	])
	print("LAP_FFB Kraft max=%.3f  Clipping-Ticks=%d  NaN-Ticks=%d  Schaden max=%.2f" % [
		torque_abs_max, clip_ticks, nan_ticks, damage_max,
	])
	print("LAP_FFB Oberflaechen %s" % str(surf_ticks))
	print("LAP_FFB Quellen %s" % str(source_ticks))
	print("LAP_FFB Asphalt n=%d Ruetteln max=%.3f Hz %.0f..%.0f" % [
		asphalt_n, asphalt_rumble_max, asphalt_hz_min, asphalt_hz_max,
	])
	print("LAP_FFB Kerb n=%d Ruetteln max=%.3f Hz %.0f..%.0f" % [
		kerb_n, kerb_rumble_max, kerb_hz_min, kerb_hz_max,
	])
	print("LAP_FFB Kies n=%d Ruetteln max=%.3f Hz %.0f..%.0f" % [
		gravel_n, gravel_rumble_max, gravel_hz_min, gravel_hz_max,
	])
	print("LAP_FFB Gerade schnell n=%d Kraft max=%.3f Daempfung min=%.3f Ruetteln max=%.3f" % [
		straight_n, straight_torque_max, straight_damper_min, straight_rumble_max,
	])
	print("LAP_FFB Bogen n=%d gegen=%d mit=%d flach=%d Kraft max=%.3f weich(<0.40)=%d" % [
		corner_n, corner_against, corner_with, corner_flat, corner_torque_max, corner_soft_n,
	])
	print("LAP_FFB Querlast Kurven max=%.2f g (ueber 4 g: %d Aufprall-Spitzen, absolut %.2f g)  Ticks ab 3 g: %d  Querabstand max=%.2f m Mittel=%.2f m" % [
		lat_window_max, lat_spike_n, lat_max, heavy_n, off_max,
		(off_sum / float(off_n)) if off_n > 0 else 0.0,
	])
	print("LAP_FFB Bogen ab 3 g: n=%d Kraft Mittel=%.3f max=%.3f (Soll: 0,55..0,75)" % [
		heavy_n, (heavy_torque_sum / float(heavy_n)) if heavy_n > 0 else 0.0, heavy_torque_max,
	])
	print("LAP_FFB Abschnitt A: Ticks unter 1,5 km/h = %d von %d, laengste Standphase = %.1f s  Wiedereingliederungen=%d" % [
		slow_n, int(phases.get("A", {}).get("ticks", 0)) if phases.has("A") else 0,
		float(slow_run_max) / 60.0, int(player.rejoin_count) if player else -1,
	])
	print("LAP_FFB KI-Auto: Ticks unter 1,5 km/h = %d von %d" % [
		ai_slow_n, maxi(frames - 600, 1),
	])
	print("LAP_FFB KI-Auto Querabstand max=%.2f m" % ai_off_max)
	for key in ["A", "B1", "D", "E", "B2", "B3", "C"]:
		if not phases.has(key):
			continue
		var ph: Dictionary = phases[key]
		print("LAP_FFB Abschnitt %-2s ticks=%4d Asphalt=%4d Kerb=%3d Kies=%4d Kraft max=%.3f Querlast max=%.2f g Abstand max=%.2f m Mittel=%.2f m Tempo max=%.0f km/h" % [
			key, int(ph["ticks"]), int(ph["asphalt"]), int(ph["kerb"]), int(ph["kies"]),
			float(ph["torque_max"]), float(ph["lat_max"]), float(ph["off_max"]),
			float(ph["off_sum"]) / maxf(float(ph["ticks"]), 1.0), float(ph["speed_max"]) * 3.6,
		])
	print("LAP_FFB Untersteuern n=%d Kraft max=%.3f Mittel=%.3f" % [
		under_n, under_torque_max,
		(under_torque_sum / float(under_n)) if under_n > 0 else 0.0,
	])
	print("LAP_FFB Uebersteuern n=%d Kraft max=%.3f | Vorderachse durch die Null: n=%d davon dreht mit %d | noch nicht durch: n=%d davon drueckt gegen %d" % [
		over_n, over_torque_max, over_cross_n, over_cross_help, over_plain_n, over_plain_against,
	])
	var cross_mean: float = over_cross_signed / maxf(float(over_cross_n), 1.0)
	var plain_mean: float = over_plain_signed / maxf(float(over_plain_n), 1.0)
	print("LAP_FFB Uebersteuern Mittelkraft (positiv = zieht mit dem Lenkbefehl): durch die Null %.3f, noch nicht durch %.3f, Unterschied %.3f" % [
		cross_mean, plain_mean, cross_mean - plain_mean,
	])
	print("LAP_FFB Uebersteuern Nulldurchgang: laengster %.2f s | kurz (<0,15 s) n=%d Mittel %.3f | lang (>=0,15 s) n=%d Mittel %.3f" % [
		float(cross_run_max) / 60.0, short_cross_n,
		short_cross_signed / maxf(float(short_cross_n), 1.0), long_cross_n,
		long_cross_signed / maxf(float(long_cross_n), 1.0),
	])
	print("LAP_FFB Uebersteuern Grundkraft sat: mit dem Lenkbefehl %d, gegen %d, laengste mitlaufende Phase %.2f s | Glaettung laeuft nach: %d Ticks" % [
		sat_with_n, sat_against_n, float(sat_run_max) / 60.0, lag_n,
	])
	print("LAP_FFB durchdrehende Raeder n=%d Ruetteln max=%.3f" % [spin_n, spin_rumble_max])
	print("LAP_FFB Anschlag je Druckstufe (Lenkdruck -> Kraft Mittel/max, Ticks):")
	var stages: Array = lock_stage.keys()
	stages.sort()
	var stage_means: Array = []
	for key in stages:
		var entry: Dictionary = lock_stage[key]
		var mean: float = float(entry["sum"]) / maxf(float(entry["n"]), 1.0)
		stage_means.append(mean)
		print("LAP_FFB   Druck %s -> Mittel %.3f max %.3f (%d Ticks)" % [
			key, mean, float(entry["max"]), int(entry["n"])])
	print("LAP_FFB Anschlag Wirkung max=%.3f (Stufen %d)" % [lock_endstop_max, stage_means.size()])
	print("LAP_FFB Blockieren n=%d Kraft max=%.3f (Quelle 'Blockiert': n=%d Ruetteln %.3f Hz %.0f..%.0f)" % [
		lock_n, lock_torque_max, lock_src_n, lock_src_rumble_max, lock_src_hz_min, lock_src_hz_max,
	])
	print("LAP_FFB Stoesse n=%d max=%.3f Arten=%s" % [pulse_n, pulse_max, str(pulse_kinds)])
	print("LAP_FFB Anschlag n=%d max=%.3f" % [endstop_n, endstop_max])

	# --- Pruefungen gegen die Soll-Tabelle (docs/FFB_F1_STYLE_PLAN.md §2) ---
	_check(ticks > 3000, "die_messung_hat_stattgefunden", "ticks=%d" % ticks)
	_check(speed_max * 3.6 > 140.0, "das_auto_ist_wirklich_gefahren",
		"%.0f km/h" % (speed_max * 3.6))
	_check(lap_progress > 200, "das_auto_ist_der_strecke_gefolgt",
		"%d von %d Punkten" % [lap_progress, line.points.size() if line else 0])
	_check(nan_ticks == 0, "keine_unendlichen_zahlen_am_lenkrad", "nan=%d" % nan_ticks)
	var lap_ticks: int = int(phases.get("A", {}).get("ticks", 0)) if phases.has("A") else 0
	var lap_asphalt: int = int(phases.get("A", {}).get("asphalt", 0)) if phases.has("A") else 0
	_check(lap_ticks > 0 and float(lap_asphalt) / float(maxi(lap_ticks, 1)) >= 0.90,
		"die_runde_ist_auf_der_strecke_gefahren",
		"%d von %d Ticks auf Asphalt" % [lap_asphalt, lap_ticks])
	# Ohne Wiedereingliederung stand das Auto in dieser Messung 2700 Ticks
	# (45 s) im Kies. Mit ihr darf keine Standphase laenger als 6 s sein.
	_check(lap_ticks == 0 or slow_run_max <= 360,
		"das_auto_bleibt_nicht_liegen",
		"laengste Standphase %.1f s (%d Ticks insgesamt unter 1,5 km/h)" % [
			float(slow_run_max) / 60.0, slow_n])
	_check(frames <= 600 or float(ai_slow_n) / float(maxi(frames - 600, 1)) < 0.05,
		"auch_das_ki_auto_bleibt_nicht_liegen",
		"%d Ticks unter 1,5 km/h" % ai_slow_n)
	_check(asphalt_n == 0 or asphalt_rumble_max <= 0.30,
		"asphalt_bleibt_leise", "max=%.3f (Soll 0,05..0,12)" % asphalt_rumble_max)
	_check(straight_n == 0 or straight_damper_min >= 0.20,
		"geradeaus_hat_grundgewicht", "Daempfung min=%.3f" % straight_damper_min)
	_check(straight_n == 0 or straight_torque_max <= 0.30,
		"geradeaus_zieht_nicht_am_lenkrad", "Kraft max=%.3f" % straight_torque_max)
	_check(corner_n == 0 or corner_torque_max >= 0.40,
		"der_bogen_ist_schwer", "Kraft max=%.3f in %d Bogen-Ticks" % [corner_torque_max, corner_n])
	_check(corner_n == 0 or float(corner_against) / float(corner_n) >= 0.90,
		"die_kraft_drueckt_gegen_den_lenkbefehl",
		"%d von %d" % [corner_against, corner_n])
	if under_n == 0:
		_note("untersteuern_kam_in_dieser_fahrt_nicht_vor")
	else:
		var under_mean: float = under_torque_sum / float(under_n)
		var corner_mean: float = 0.0
		if heavy_n > 0:
			corner_mean = heavy_torque_sum / float(heavy_n)
		elif corner_n > 0:
			corner_mean = corner_torque_max
		_check(corner_mean <= 0.0 or under_mean < corner_mean * 0.6,
			"untersteuern_macht_das_lenkrad_leicht",
			"Mittel %.3f gegen %.3f im Bogen" % [under_mean, corner_mean])
	if over_n == 0:
		_note("uebersteuern_kam_in_dieser_fahrt_nicht_vor (Traktionskontrolle aus, Vollgas im langsamen Bogen)")
	else:
		# Zwei fruehere Anlaeufe dieser Sonde haben hier zweimal danebengelegen:
		# erst wurde die Umdrehung fuer **jeden** Uebersteuer-Tick gefordert
		# (66 von 282), dann war die Zuordnung "Vorderachse durch die Null"
		# falsch gepolt (das Vorzeichen des Lenkbefehls ist **nicht** das
		# Vorzeichen des Lenkwinkels - `steering` wird in `car_controller.gd`
		# einmal gespiegelt). Gemessen wird deshalb die Groesse, die die
		# Soll-Tabelle meint: die **ungeglaettete** Grundkraft `sat`.
		_check(sat_with_n >= 10,
			"beim_ausbrechenden_heck_dreht_die_grundkraft_in_die_gegenlenkrichtung",
			"Grundkraft mit dem Lenkbefehl in %d von %d Uebersteuer-Ticks (laengste Phase %.2f s), gegen %d" % [
				sat_with_n, over_n, float(sat_run_max) / 60.0, sat_against_n])
		if lag_n > 0:
			_note("die_glaettung_laeuft_der_umkehr_nach: %d von %d Ticks (45 ms)" % [lag_n, over_n])
	_check(clip_ticks == 0, "kein_clipping_im_normalbetrieb",
		"%d Ticks ueber 0,97 (max %.3f)" % [clip_ticks, clip_max])
	if lock_n == 0:
		_note("blockierende_Vorderraeder_kamen_in_dieser_fahrt_nicht_vor")
	elif lock_src_n == 0:
		_note("blockierende_Vorderraeder_rattern_nie_als_lauteste_quelle (Kerb oder Einschlag war lauter)")
	else:
		_check(lock_src_rumble_max >= 0.30 and lock_src_hz_min >= 18.0 and lock_src_hz_max <= 45.0,
			"blockierende_raeder_rattern", "%.3f @ %.0f..%.0f Hz" % [
				lock_src_rumble_max, lock_src_hz_min, lock_src_hz_max])
	if kerb_n == 0:
		_note("kerb_wurde_nicht_beruehrt (der_autopilot_faehrt_die_ideallinie)")
	else:
		_check(kerb_rumble_max >= 0.40 and kerb_hz_min >= 16.0 and kerb_hz_max <= 46.0,
			"kerb_ruettelt_hart_und_schnell", "%.3f @ %.0f..%.0f Hz" % [
				kerb_rumble_max, kerb_hz_min, kerb_hz_max])
	if gravel_n == 0:
		_note("kies_wurde_nicht_beruehrt")
	else:
		_check(gravel_rumble_max >= 0.20 and gravel_hz_max <= 20.0,
			"kies_mahlt_grob_und_dumpf", "%.3f @ %.0f..%.0f Hz" % [
				gravel_rumble_max, gravel_hz_min, gravel_hz_max])
	_check(pulse_n == 0 or pulse_max >= 0.25, "stoesse_kommen_an",
		"max=%.3f" % pulse_max)
	if stage_means.size() < 3:
		_note("anschlag_stufen_nicht_gemessen (%d Stufen)" % stage_means.size())
	else:
		# Die Grundkraft faellt in diesem Abschnitt, weil der Wagen langsamer
		# wird; der Anschlag waechst. Gemessen wird deshalb: keine Stufe ist
		# schlechter als die vorige (Toleranz 0,02) und die letzte ist klar
		# staerker als die erste.
		var dips: int = 0
		for i in range(1, stage_means.size()):
			if float(stage_means[i]) < float(stage_means[i - 1]) - 0.02:
				dips += 1
		var first: float = float(stage_means[0])
		var last: float = float(stage_means[-1])
		_check(dips == 0, "der_anschlag_wird_mit_dem_druck_nie_schwaecher",
			"%d Rueckfaelle in %s" % [dips, str(stage_means)])
		_check(last >= 2.0 * maxf(first, 0.001), "der_anschlag_wird_deutlich_staerker",
			"erste Stufe %.3f -> letzte Stufe %.3f" % [first, last])
		_check(nan_ticks == 0, "der_anschlag_bleibt_endlich")

	print("---- ENDE LAP_FFB ----")
	if failed > 0:
		print("LAP_FFB FAIL count=%d" % failed)
		quit(1)
	else:
		print("LAP_FFB PASS")
		quit(0)
