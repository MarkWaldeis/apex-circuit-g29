extends SceneTree
## Gegenprobe des Roots zum Realismus-Agenten: Was kann die Rechnung in
## `ffb_model.gd` widerlegen?
##
## Der Test sucht nicht nach Bestaetigung, sondern nach Gegenbeispielen zu den
## Behauptungen aus `docs/FFB_F1_STYLE_PLAN.md` Abschnitt 2:
##   A Kraft zieht immer gegen den Lenkbefehl (Richtungsprobe, beide Wege)
##   B Anschlag wird mit dem Druck monoton staerker
##   C kein Clipping im Normalbetrieb (Gitter ueber Tempo, Last, Abtrieb, Schlupf)
##   D Rüttelbaender: Kerb schnell, Kies grob, Asphalt leise, Frequenz mit Tempo
##   E Fuzz: alle Kanaele bleiben gueltig, keine NaN
##   F unten leicht, oben schwer
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_review_root.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

var model
var settings
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	settings = Settings.new()
	settings.auto_save = false
	settings.gain = 1.0
	settings.damper = 1.0
	# Die Gegenprobe prueft die innere Vorzeichenwelt des Modells; die
	# gemessene Hardware-Umdrehung (`invert`) wird hier bewusst ausgeschaltet.
	settings.invert = false
	model = Model.new()
	model.setup(settings)
	_direction_probe()
	_endstop_probe()
	_clipping_probe()
	_rumble_probe()
	_fuzz_probe()
	_weight_probe()
	_limiter_probe()
	_extremes_probe()
	if failed > 0:
		print("REVIEW_ROOT FAIL count=%d von %d" % [failed, checks])
		quit(1)
	else:
		print("REVIEW_ROOT PASS %d Pruefungen" % checks)
		quit(0)


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"steer": 1.0,
		"steer_angle": -0.10,
		"slip_front": 0.075,
		"slip_rear": 0.03,
		"lateral_g": 3.2,
		"yaw_rate": -0.35,
		"speed": 62.0,
		"downforce": 2.6,
		"understeer": 0.05,
		"oversteer": 0.0,
		"brake": 0.0,
		"throttle": 0.8,
		"lock_pressure": 0.0,
		"damage": 0.0,
		"traction_control": true,
		"surface": {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0},
	}
	for key in overrides:
		d[key] = overrides[key]
	return d


func _settle(ctx: Dictionary, ticks: int = 60) -> Dictionary:
	var out: Dictionary = {}
	for i in ticks:
		out = model.update(1.0 / 90.0, ctx)
	return out


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


## A: Beide Wege der Richtungsbestimmung (Schraeglauf und Lenkwinkel) muessen
## dasselbe Vorzeichen ergeben - sonst springt die Kraft an der Nulllinie.
func _direction_probe() -> void:
	var right: float = float(_settle(_ctx())["torque"])
	var left: float = float(_settle(_ctx({
		"steer": -1.0, "steer_angle": 0.10, "slip_front": -0.075,
		"lateral_g": -3.2, "yaw_rate": 0.35}))["torque"])
	_check(right < -0.3 and left > 0.3, "gegenprobe_richtung_beide_wege",
		"rechts %+.3f, links %+.3f" % [right, left])
	# Ohne Schraeglauf (nur Lenkwinkel) darf die Richtung nicht kippen.
	var fallback_right: float = float(_settle(_ctx({"slip_front": 0.0}))["torque"])
	_check(fallback_right < -0.05, "gegenprobe_richtung_ohne_schraeglauf",
		"nur Lenkwinkel %+.3f" % fallback_right)
	# Und bei fast geradem Rad darf nichts hin und her springen.
	var prev: float = 0.0
	var max_step: float = 0.0
	for i in 240:
		var steer: float = sin(float(i) * 0.25) * 0.02
		var state: Dictionary = model.update(1.0 / 90.0, _ctx({
			"steer": steer, "steer_angle": -0.0006 * float(i % 7),
			"slip_front": 0.001 * float(i % 5)}))
		if i == 0:
			# Der erste Tick traegt noch die Glattung aus der Kurve davor -
			# gemessen wird das Zappeln im eingeschwungenen Zustand.
			prev = float(state["torque"])
			continue
		max_step = maxf(max_step, absf(float(state["torque"]) - prev))
		prev = float(state["torque"])
	_check(max_step < 0.15, "gegenprobe_kein_zappeln_an_der_nulllinie",
		"groesster Sprung %.3f" % max_step)


## B: Der Anschlag muss mit dem Druck monoton zurueckdraengen.
func _endstop_probe() -> void:
	var previous: float = 0.0
	var monotone: bool = true
	var detail: String = ""
	var free: float = 0.0
	for i in 21:
		var pressure: float = float(i) / 20.0
		var state: Dictionary = _settle(_ctx({"lock_pressure": pressure, "steer": 0.9}))
		var torque: float = float(state["torque"])
		if i == 0:
			previous = torque
			free = torque
			detail = "Druck 0 -> %+.3f" % torque
			continue
		if torque > previous + 0.001:
			monotone = false
			detail += " | Bruch bei %.2f (%+.3f nach %+.3f)" % [pressure, torque, previous]
		previous = torque
	detail += " | Druck 1 -> %+.3f" % previous
	_check(monotone and previous <= free - 0.10, "gegenprobe_anschlag_monoton", detail)
	# Der Lenkbefehl selbst darf am Anschlag nicht groesser werden: das Spiel
	# begrenzt ihn in `g29_input.gd`; hier wird geprueft, dass das Modell den
	# Druck nur als Kraft kennt (steer bleibt steer).
	var state: Dictionary = _settle(_ctx({"lock_pressure": 1.0, "steer": 0.9}))
	_check(absf(float(state["torque"])) <= 1.001 and float(state["endstop"]) < 0.0,
		"gegenprobe_anschlag_drueckt_gegen_die_lenkrichtung",
		"torque %+.3f, endstop %+.3f" % [float(state["torque"]), float(state["endstop"])])


## C: Im Normalbetrieb (ohne Kerb, ohne Schaden, ohne Anschlag) darf die Kraft
## die 0,97 nie erreichen.
func _clipping_probe() -> void:
	var worst: float = 0.0
	var worst_at: String = ""
	var clip_ticks: int = 0
	var ticks: int = 0
	for speed in [10.0, 30.0, 55.0, 75.0, 90.0]:
		for lat in [-4.5, -2.0, 0.0, 2.0, 4.5]:
			for slip in [-0.12, -0.05, 0.0, 0.05, 0.12]:
				for df in [1.2, 2.5, 3.8]:
					var state: Dictionary = _settle(_ctx({
						"speed": speed, "lateral_g": lat, "slip_front": slip,
						"slip_rear": slip * 0.4, "downforce": df,
						"steer": signf(lat) if absf(lat) > 0.1 else 0.0,
						"steer_angle": -0.09 * signf(lat),
						"understeer": clampf(absf(slip) * 2.0, 0.0, 0.9)}), 30)
					var t: float = absf(float(state["torque"]))
					ticks += 1
					if t > worst:
						worst = t
						worst_at = "%.0f m/s, %.1f g, Schlupf %+.2f, Abtrieb %.1f" % [speed, lat, slip, df]
					if t >= 0.97:
						clip_ticks += 1
	_check(clip_ticks == 0, "gegenprobe_kein_clipping_im_normalbetrieb",
		"%d von %d Punkten ueber 0,97, groesste Kraft %.3f bei %s" % [clip_ticks, ticks, worst, worst_at])


## D: Die Rüttelbaender muessen stimmen - Kerb schnell, Kies grob, Asphalt leise.
func _rumble_probe() -> void:
	var kerb: Dictionary = _settle(_ctx({"speed": 33.0, "surface": {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}}))
	var gravel: Dictionary = _settle(_ctx({"speed": 28.0, "surface": {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}}))
	var grass: Dictionary = _settle(_ctx({"speed": 20.0, "surface": {"surface": 3, "name": "Gras", "rumble": 0.30, "rough": 0.65, "grip": 0.30}}))
	var asphalt: Dictionary = _settle(_ctx({"speed": 70.0}))
	_check(float(kerb["rumble_hz"]) > float(gravel["rumble_hz"])
		and float(gravel["rumble_hz"]) > float(grass["rumble_hz"]),
		"gegenprobe_ruettelbaender_kerb_kies_gras",
		"Kerb %.0f Hz > Kies %.0f Hz > Gras %.0f Hz" % [
			float(kerb["rumble_hz"]), float(gravel["rumble_hz"]), float(grass["rumble_hz"])])
	_check(float(kerb["rumble"]) > float(gravel["rumble"]) and float(asphalt["rumble"]) < 0.15,
		"gegenprobe_kerb_staerker_als_kies_asphalt_leise",
		"Kerb %.2f, Kies %.2f, Asphalt %.2f" % [
			float(kerb["rumble"]), float(gravel["rumble"]), float(asphalt["rumble"])])
	var slow_kerb: Dictionary = _settle(_ctx({"speed": 12.0, "surface": {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}}))
	_check(float(kerb["rumble_hz"]) > float(slow_kerb["rumble_hz"]) + 5.0,
		"gegenprobe_kerb_frequenz_steigt_mit_tempo",
		"12 m/s %.0f Hz -> 33 m/s %.0f Hz" % [float(slow_kerb["rumble_hz"]), float(kerb["rumble_hz"])])
	# Unwucht durch Schaden: nie schneller als die Radumdrehung, nie negativ.
	var bad: Dictionary = _settle(_ctx({"damage": 0.8, "speed": 80.0}))
	_check(float(bad["rumble"]) > 0.4 and float(bad["rumble_hz"]) <= 31.0
		and String(bad["source"]) == "Unwucht",
		"gegenprobe_schaden_als_unwucht",
		"%.2f @ %.0f Hz (%s)" % [float(bad["rumble"]), float(bad["rumble_hz"]), str(bad["source"])])


## E: Fuzz - nichts darf NaN werden oder den Bereich verlassen.
func _fuzz_probe() -> void:
	var seed_value: int = 20260921
	seed(seed_value)
	var worst: float = 0.0
	var bad_ticks: int = 0
	for i in 2000:
		var state: Dictionary = model.update(1.0 / 90.0, _ctx({
			"speed": 120.0 * randf(),
			"lateral_g": -8.0 + 16.0 * randf(),
			"slip_front": -0.6 + 1.2 * randf(),
			"slip_rear": -0.6 + 1.2 * randf(),
			"steer": -1.0 + 2.0 * randf(),
			"steer_angle": -0.2 + 0.4 * randf(),
			"understeer": randf(),
			"oversteer": randf(),
			"brake": randf(),
			"throttle": randf(),
			"lock_pressure": randf(),
			"damage": randf(),
			"downforce": 1.0 + 4.0 * randf(),
			"surface": {"surface": randi() % 5, "name": "x", "rumble": randf(), "rough": randf(), "grip": randf()},
		}))
		if randf() < 0.05:
			model.poke("crash", randf())
		for key in ["torque", "damper", "friction", "rumble", "pulse", "clip",
				"sat", "trail", "lock", "spin", "flat", "endstop"]:
			var v: float = float(state.get(key, 0.0))
			if not is_finite(v):
				bad_ticks += 1
			worst = maxf(worst, absf(v))
	_check(bad_ticks == 0 and worst <= 1.001, "gegenprobe_fuzz_bleibt_gueltig",
		"%d ungueltige Werte, groesster Betrag %.3f" % [bad_ticks, worst])


## F: Unten leicht, oben schwer - und im Stand nichts erfunden.
func _weight_probe() -> void:
	var slow: float = absf(float(_settle(_ctx({"speed": 12.0, "lateral_g": 0.6, "downforce": 1.05, "slip_front": 0.02}))["torque"]))
	var fast: float = absf(float(_settle(_ctx({"speed": 83.0, "lateral_g": 3.9, "downforce": 3.6, "slip_front": 0.08}))["torque"]))
	_check(fast > 0.60 and slow < 0.30, "gegenprobe_unten_leicht_oben_schwer",
		"12 m/s %.3f -> 83 m/s/3,9 g %.3f" % [slow, fast])
	var still: Dictionary = _settle(_ctx({"speed": 0.0, "lateral_g": 0.0, "slip_front": 0.0, "downforce": 1.0}))
	_check(is_zero_approx(float(still["torque"])) and float(still["rumble"]) < 0.05,
		"gegenprobe_im_stand_keine_erfundene_kraft",
		"torque %+.4f, Ruetteln %.3f" % [float(still["torque"]), float(still["rumble"])])


## G: Die weiche Begrenzung muss stetig sein (kein Knick-Stoss am Lenkrad) und
## oben wirklich deckeln.
func _limiter_probe() -> void:
	var worst_step: float = 0.0
	var previous: float = model._soft_limit(-1.2)
	var x: float = -1.2
	while x <= 1.2001:
		var value: float = model._soft_limit(x)
		worst_step = maxf(worst_step, absf(value - previous))
		previous = value
		x += 0.001
	_check(worst_step < 0.006, "gegenprobe_weiche_begrenzung_stetig",
		"groesster Schritt pro 0,001 Eingabe: %.5f" % worst_step)
	var knee: float = model.SOFT_KNEE
	_check(is_equal_approx(model._soft_limit(knee), knee)
		and is_equal_approx(model._soft_limit(50.0), model.SOFT_CEIL)
		and is_equal_approx(model._soft_limit(-50.0), -model.SOFT_CEIL),
		"gegenprobe_weiche_begrenzung_deckelt",
		"Knick %.2f -> %.3f, oben %.2f -> %.3f" % [
			knee, model._soft_limit(knee), 50.0, model._soft_limit(50.0)])


## H: Extreme Szenarien. Ein Einschlag liegt auf dem Stoss-Kanal und darf die
## Grundkraft **nicht** veraendern: der Helfer setzt den Stoss aus `pulse` auf
## die Kraft, steckte er zusaetzlich in `torque`, kaeme er doppelt an. Ein
## Kerb in der schnellsten Kurve darf alles tun, ausser den gueltigen Bereich
## zu verlassen.
func _extremes_probe() -> void:
	var corner: Dictionary = {"speed": 60.0, "lateral_g": 4.0, "downforce": 3.4}
	var base: float = absf(float(_settle(_ctx(corner))["torque"]))
	model.poke("crash", 1.0)
	var hit: Dictionary = model.update(1.0 / 90.0, _ctx(corner))
	var hit_torque: float = absf(float(hit["torque"]))
	var after: Dictionary = {}
	for i in 120:
		after = model.update(1.0 / 90.0, _ctx(corner))
	var after_torque: float = absf(float(after["torque"]))
	# In einer 4-g-Kurve liegt die Grundkraft schon nahe der weichen Grenze
	# (0.89 von 0.90). Der Einschlag kommt deshalb als voller Stoss auf seinem
	# eigenen Kanal an, die Grundkraft bleibt unveraendert - und nach 1,3 s ist
	# beides wieder bei null.
	_check(hit_torque <= 1.001 and absf(hit_torque - base) < 0.05
		and float(hit["pulse"]) > 0.9 and absf(float(hit["pulse_dir"])) <= 1.001
		and absf(after_torque - base) < 0.05 and float(after["pulse"]) == 0.0,
		"gegenprobe_einschlag_klingt_wieder_ab",
		"Grundkraft %.3f -> im Einschlag %.3f (Stoss %.2f, Grundkraft unveraendert) -> nach 1,3 s %.3f (Stoss %.2f)" % [
			base, hit_torque, float(hit["pulse"]), after_torque, float(after["pulse"])])

	var kerb: Dictionary = _settle(_ctx({
		"speed": 90.0, "lateral_g": 4.5, "downforce": 3.8, "slip_front": 0.12,
		"brake": 0.9, "damage": 0.5,
		"surface": {"surface": 1, "name": "Kerb", "rumble": 1.0, "rough": 1.0, "grip": 0.9}}))
	var worst: float = 0.0
	for key in ["torque", "damper", "friction", "rumble", "clip"]:
		worst = maxf(worst, absf(float(kerb[key])))
	_check(worst <= 1.001 and is_finite(worst), "gegenprobe_kerb_in_grenzlast_bleibt_im_bereich",
		"groesster Betrag %.3f (%s @ %.0f Hz)" % [worst, str(kerb["source"]), float(kerb["rumble_hz"])])

	# Die Unwucht darf nicht einrasten: ohne Schaden ist sie wieder weg.
	var damaged: Dictionary = _settle(_ctx({"damage": 0.6}))
	var healed: Dictionary = _settle(_ctx({"damage": 0.0}))
	_check(float(damaged["rumble"]) > 0.4 and float(healed["rumble"]) < 0.15,
		"gegenprobe_unwucht_faellt_ohne_schaden_zurueck",
		"mit Schaden %.2f (%s) -> ohne %.2f (%s)" % [
			float(damaged["rumble"]), str(damaged["source"]),
			float(healed["rumble"]), str(healed["source"])])
