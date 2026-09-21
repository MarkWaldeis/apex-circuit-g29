extends SceneTree
## Prüft das Lenkrad-Gefühl als Rechnung: jede Zeile aus Abschnitt 2 von
## docs/FFB_F1_STYLE_PLAN.md muss messbar stimmen.
##
## Die Szene wird dafür nicht gebraucht - `ffb_model.gd` ist eine reine
## Funktion von Telemetrie auf Kraft. Genau deshalb lässt es sich hier
## punktgenau prüfen: dieselbe Kurve, einmal mit Untersteuern, einmal ohne.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_model.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

var model
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	var settings := Settings.new()
	settings.auto_save = false
	settings.gain = 1.0
	settings.damper = 1.0
	# Hier wird die INNERE Vorzeichenwelt des Modells geprueft (+ = drueckt nach
	# rechts). Die Hardware-Umdrehung (`invert`, gemessen am G29) gehoert nicht
	# dazu und wird in `test_ffb_settings.gd` geprueft.
	settings.invert = false
	model = Model.new()
	model.setup(settings)
	_run()


## Ein normaler Rechtsbogen: Lenkbefehl +1 (rechts), Vorderreifen arbeiten.
func _corner(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"steer": 1.0,
		"steer_angle": -0.10,     ## Physik: + = links, rechts ist also negativ
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
		"traction_control": true,
		"surface": {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0},
		"damage": 0.0,
	}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx


func _steady(ctx: Dictionary, ticks: int = 40) -> Dictionary:
	var out: Dictionary = {}
	for i in ticks:
		out = model.update(1.0 / 90.0, ctx)
	return out


## Ein Modell mit eigener Einstellung (fuer die Ruettel-Baender): faehrt 40
## Ticks im Bogen auf der uebergebenen Oberflaeche und gibt den Endzustand
## zurueck. Eigene Funktion, weil sie ein anderes Modell als das Hauptmodell
## benutzt - sonst wuerde die Bandprobe die Einstellungen der anderen
## Pruefungen veraendern.
func _band_rumble(band_model, surface: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for i in 40:
		out = band_model.update(1.0 / 90.0, _corner({"surface": surface}))
	return out


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run() -> void:
	# --- 1. Grundlast waechst mit dem Tempo -------------------------------
	# Mit dem Abtrieb, den der Wagen bei diesem Tempo wirklich hat
	# (tyre_model: 1 + 3.2 * (v/83.3)^2, weich gerechnet).
	var slow: float = absf(float(_steady(_corner({"speed": 15.0, "downforce": 1.10}))["torque"]))
	var fast: float = absf(float(_steady(_corner({"speed": 70.0, "downforce": 3.26}))["torque"]))
	_check(fast > slow * 1.5, "grundlast_waechst_mit_dem_tempo",
		"15 m/s %.3f -> 70 m/s %.3f" % [slow, fast])

	# --- 2. und mit der Querlast ------------------------------------------
	var light: float = absf(float(_steady(_corner({"lateral_g": 1.0}))["torque"]))
	var heavy: float = absf(float(_steady(_corner({"lateral_g": 3.5}))["torque"]))
	_check(heavy > light * 1.25, "grundlast_waechst_mit_der_querlast",
		"1 g %.3f -> 3.5 g %.3f" % [light, heavy])

	# --- 3. Das Lenkrad zieht GEGEN den Lenkbefehl ------------------------
	var right: Dictionary = _steady(_corner())
	_check(float(right["torque"]) < -0.05, "kraft_zieht_gegen_den_lenkbefehl",
		"Rechtsbogen torque=%+.3f (negativ = drueckt nach links)" % float(right["torque"]))

	# --- 4. Untersteuern macht das Lenkrad leicht -------------------------
	var grip: float = absf(float(_steady(_corner({"slip_front": 0.09, "understeer": 0.05}))["torque"]))
	var push: float = absf(float(_steady(_corner({"slip_front": 0.32, "understeer": 0.85}))["torque"]))
	_check(push < grip * 0.70, "untersteuern_macht_das_lenkrad_leicht",
		"%.3f -> %.3f (%.0f %% weniger)" % [grip, push, 100.0 * (1.0 - push / maxf(grip, 0.001))])

	# --- 5. Uebersteuern dreht das Vorzeichen -----------------------------
	var left_slip: float = float(_steady(_corner({"slip_front": 0.06}))["torque"])
	var right_slip: float = float(_steady(_corner({"slip_front": -0.06}))["torque"])
	_check(left_slip * right_slip < 0.0, "uebersteuern_dreht_das_vorzeichen",
		"slip +0.06 -> %+.3f, slip -0.06 -> %+.3f" % [left_slip, right_slip])

	# --- 6. Blockierende Vorderraeder: leicht + Rattern -------------------
	var brake_ctx: Dictionary = _corner({"brake": 0.95, "slip_front": 0.10, "steer_angle": -0.16, "speed": 45.0})
	var braking: Dictionary = _steady(brake_ctx)
	# Der Plan (Kriterium 4) verlangt: unter 20 % der Bogenkraft - ein
	# blockierendes Vorderrad hat keinen Nachlauf mehr.
	_check(absf(float(braking["torque"])) < grip * 0.20, "blockieren_macht_das_lenkrad_leicht",
		"%.3f statt %.3f (%.0f %%)" % [absf(float(braking["torque"])), grip,
			100.0 * absf(float(braking["torque"])) / maxf(grip, 0.001)])
	_check(float(braking["rumble"]) > 0.25 and float(braking["rumble_hz"]) > 20.0
		and float(braking["rumble_hz"]) < 35.0,
		"blockieren_rattern_mit_20_bis_35_hz",
		"%.2f @ %.0f Hz (%s)" % [float(braking["rumble"]), float(braking["rumble_hz"]), str(braking["source"])])

	# --- 6b. Anbremsen darf das Lenkrad NICHT tot machen ------------------
	# Vor der Kurve voll geradeaus bremsen: die Vorderachse wird belastet, das
	# Lenkrad schwer - erst der volle Tritt mit Schraeglauf blockiert. Ohne
	# diese Trennung waere jedes Bremsen ein taubes Lenkrad.
	var straight: Dictionary = {"brake": 0.90, "slip_front": 0.02, "steer_angle": -0.005}
	var trail: Dictionary = {"brake": 0.45, "slip_front": 0.10, "steer_angle": -0.16}
	var straight_roll: float = absf(float(_steady(_corner(straight))["torque"]))
	var trail_roll: float = absf(float(_steady(_corner(trail))["torque"]))
	var straight_ratio: float = straight_roll / maxf(absf(float(_steady(_corner(
		{"slip_front": 0.02, "steer_angle": -0.005}))["torque"])), 0.001)
	var trail_ratio: float = trail_roll / maxf(absf(float(_steady(_corner(
		{"slip_front": 0.10, "steer_angle": -0.16}))["torque"])), 0.001)
	_check(straight_ratio > 0.45 and trail_ratio > 0.60,
		"bremsen_allein_macht_das_lenkrad_nicht_tot",
		"geradeaus %.0f %% (%.3f), Trail-Braking %.0f %% (%.3f) der Kraft ohne Bremse" % [
			straight_ratio * 100.0, straight_roll, trail_ratio * 100.0, trail_roll])

	# --- 6c. Kuppe und Bodenwelle ----------------------------------------
	# Ueber einer Kuppe hebt die Vorderachse ab und das Lenkrad wird kurz
	# leicht ("it lightens over a crest as the front unloads"); eine gestauchte
	# Feder (Bodenwelle) gibt einen kurzen Stoss auf dem Puls-Kanal.
	var over_crest: float = absf(float(_steady(_corner({"vertical_g": 0.30}))["torque"]))
	_check(over_crest < grip * 0.75, "kuppe_macht_das_lenkrad_leicht",
		"1,0 g %.3f -> 0,30 g %.3f (%.0f %% weniger)" % [
			grip, over_crest, 100.0 * (1.0 - over_crest / maxf(grip, 0.001))])
	var flat_ground: float = absf(float(_steady(_corner({"vertical_g": 1.0, "brake": 0.0}))["torque"]))
	_check(absf(flat_ground - grip) < 0.02, "normale_last_aendert_nichts",
		"1,0 g %.3f gegen Bogen %.3f" % [flat_ground, grip])
	_steady(_corner())
	model.poke("bump", 0.55)
	var bumped: Dictionary = model.update(1.0 / 90.0, _corner())
	_check(float(bumped["pulse"]) > 0.3, "bodenwelle_gibt_einen_stoss",
		"pulse=%.2f" % float(bumped["pulse"]))

	# --- 7. Kerb ruettelt, Asphalt nicht ----------------------------------
	var kerb_ctx: Dictionary = _corner({"surface": {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}})
	var kerb: Dictionary = _steady(kerb_ctx)
	_check(float(kerb["rumble"]) > 0.5, "kerb_ruettelt_stark",
		"%.2f @ %.0f Hz" % [float(kerb["rumble"]), float(kerb["rumble_hz"])])
	_check(String(kerb["source"]) == "Kerb", "kerb_ist_die_quelle", str(kerb["source"]))

	var flat: Dictionary = _steady(_corner())
	_check(float(flat["rumble"]) < 0.15, "asphalt_ist_ruhig",
		"%.2f @ %.0f Hz (%s)" % [float(flat["rumble"]), float(flat["rumble_hz"]), str(flat["source"])])

	# --- 8. Frequenz steigt mit dem Tempo (Kerb) --------------------------
	var kerb_slow: Dictionary = _steady(_corner({"surface": kerb_ctx["surface"], "speed": 12.0}))
	var kerb_fast: Dictionary = _steady(_corner({"surface": kerb_ctx["surface"], "speed": 70.0}))
	_check(float(kerb_fast["rumble_hz"]) > float(kerb_slow["rumble_hz"]) + 5.0,
		"kerb_wird_mit_dem_tempo_schneller",
		"%.0f Hz -> %.0f Hz" % [float(kerb_slow["rumble_hz"]), float(kerb_fast["rumble_hz"])])

	# --- 9. Gras/Kies: grob und langsamer als der Kerb --------------------
	var gravel: Dictionary = _steady(_corner({"surface": {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}}))
	_check(float(gravel["rumble_hz"]) < float(kerb["rumble_hz"]) - 8.0
		and float(gravel["rumble"]) > 0.15 and float(gravel["rumble"]) < float(kerb["rumble"]),
		"kies_ist_grober_und_schwaecher_als_der_kerb",
		"Kies %.2f @ %.0f Hz vs Kerb %.2f @ %.0f Hz" % [
			float(gravel["rumble"]), float(gravel["rumble_hz"]),
			float(kerb["rumble"]), float(kerb["rumble_hz"])])

	# --- 10. Schalten ist ein Stoss, keine Dauerlast ----------------------
	_steady(_corner())
	model.poke("shift", 0.4)
	var shifted: Dictionary = model.update(1.0 / 90.0, _corner())
	_check(float(shifted["pulse"]) > 0.3, "schalten_gibt_einen_stoss",
		"pulse=%.2f" % float(shifted["pulse"]))
	var quiet: Dictionary = {}
	for i in 45:
		quiet = model.update(1.0 / 90.0, _corner())
	_check(float(quiet["pulse"]) == 0.0, "stoss_klingt_wieder_ab",
		"pulse=%.2f nach 0.5 s" % float(quiet["pulse"]))

	# --- 11. Einschlag skaliert und bleibt im Bereich ---------------------
	var before_hit: float = absf(float(_steady(_corner())["torque"]))
	model.poke("crash", 1.0)
	var hit: Dictionary = model.update(1.0 / 90.0, _corner())
	_check(float(hit["pulse"]) > 0.95, "einschlag_ist_ein_voller_stoss",
		"pulse=%.2f" % float(hit["pulse"]))
	# Ein Ereignis gehoert auf EINEN Weg: der Stoss faehrt auf dem
	# `pulse`-Kanal (der Helfer setzt ihn sofort auf die Kraft, ohne Rampe).
	# Steckte er zusaetzlich in `torque`, kaeme er beim Helfer ein zweites Mal
	# drauf - gemessen waren das 111 % eines Schaltstosses.
	_check(absf(absf(float(hit["torque"])) - before_hit) < 0.05,
		"einschlag_laesst_die_grundkraft_unveraendert",
		"Grundkraft %.3f -> %.3f, Stoss nur im Puls-Kanal %.2f" % [
			before_hit, absf(float(hit["torque"])), float(hit["pulse"])])
	_check(absf(float(hit["torque"])) <= 1.001 and absf(float(hit["pulse_dir"])) <= 1.001,
		"einschlag_bleibt_im_bereich",
		"torque=%+.3f Stossrichtung %+.2f" % [float(hit["torque"]), float(hit["pulse_dir"])])
	# Der Schlag sitzt nicht nur auf der Kraft: das Lenkrad schuettelt kurz
	# nach (Quelle "Aufprall") und beruhigt sich danach wieder.
	_check(float(hit["rumble"]) > 0.5 and String(hit["source"]) == "Aufprall",
		"einschlag_schuettelt_nach",
		"%.2f @ %.0f Hz (%s)" % [float(hit["rumble"]), float(hit["rumble_hz"]), str(hit["source"])])
	var settled: Dictionary = {}
	for i in 40:
		settled = model.update(1.0 / 90.0, _corner())
	_check(String(settled["source"]) == "Asphalt" and float(settled["rumble"]) < 0.2,
		"einschlag_beruhigt_sich_wieder",
		"nach 0,45 s %.2f (%s)" % [float(settled["rumble"]), str(settled["source"])])

	# --- 12. Soft Lock drueckt zurueck ------------------------------------
	var free: float = float(_steady(_corner({"steer": 0.9, "lock_pressure": 0.0}))["torque"])
	var wall: float = float(_steady(_corner({"steer": 0.9, "lock_pressure": 1.0}))["torque"])
	# Am Anschlag ist die Kraft entweder deutlich groesser oder sie liegt schon
	# voll an der Grenze des Lenkrads - in beiden Faellen drueckt sie zurueck.
	_check(wall < 0.0 and (wall < free - 0.15 or absf(wall) >= 0.99),
		"soft_lock_drueckt_zurueck",
		"frei %+.3f -> am Anschlag %+.3f" % [free, wall])

	# --- 13. Im Stand keine erfundene Kraft -------------------------------
	var still: float = absf(float(_steady(_corner({"speed": 0.0, "lateral_g": 0.0, "slip_front": 0.0}))["torque"]))
	_check(still < 0.05, "im_stand_keine_erfundene_zentrierung", "%.3f" % still)

	# --- 14. Keine Spruenge (Zahnradantrieb) ------------------------------
	var prev: float = 0.0
	var max_step: float = 0.0
	var ctx: Dictionary = _corner()
	for i in 360:
		ctx = _corner({
			"speed": 20.0 + 45.0 * sin(float(i) * 0.05),
			"lateral_g": 1.0 + 2.2 * absf(sin(float(i) * 0.03)),
			"slip_front": 0.03 + 0.09 * absf(sin(float(i) * 0.07)),
			"steer_angle": -0.02 - 0.10 * absf(sin(float(i) * 0.02)),
		})
		var state: Dictionary = model.update(1.0 / 90.0, ctx)
		max_step = maxf(max_step, absf(float(state["torque"]) - prev))
		prev = float(state["torque"])
	_check(max_step < 0.15, "keine_spruenge_zwischen_zwei_ticks",
		"groesster Sprung %.3f" % max_step)

	# --- 15. Alles bleibt im gueltigen Bereich ----------------------------
	var worst: float = 0.0
	for i in 500:
		var state: Dictionary = model.update(1.0 / 90.0, _corner({
			"speed": 0.0 + 90.0 * randf(),
			"lateral_g": -6.0 + 12.0 * randf(),
			"slip_front": -0.4 + 0.8 * randf(),
			"slip_rear": -0.4 + 0.8 * randf(),
			"understeer": randf(),
			"oversteer": randf(),
			"brake": randf(),
			"throttle": randf(),
			"lock_pressure": randf(),
			"downforce": 1.0 + 3.0 * randf(),
			"surface": {"surface": randi() % 4, "name": "x", "rumble": randf(), "rough": randf(), "grip": 0.3 + 0.7 * randf()},
		}))
		worst = maxf(worst, absf(float(state["torque"])))
		for key in ["damper", "friction", "rumble", "pulse"]:
			worst = maxf(worst, absf(float(state[key])))
	_check(worst <= 1.001, "alle_kanaele_bleiben_zwischen_0_und_1", "max %.3f" % worst)

	# --- 16. Ausgeschaltet ist aus ----------------------------------------
	model.settings.enabled = false
	var off: Dictionary = _steady(_corner({"lock_pressure": 1.0}))
	_check(absf(float(off["torque"])) < 0.001 and float(off["rumble"]) < 0.001
		and float(off["damper"]) < 0.001,
		"ausgeschaltet_geht_nichts_ans_lenkrad",
		"torque=%+.3f damper=%.3f rumble=%.3f" % [
			float(off["torque"]), float(off["damper"]), float(off["rumble"])])
	model.settings.enabled = true

	# --- 17. Schaden bleibt als Unwucht am Lenkrad -------------------------
	# Ein Einschlag oder ein Platter darf nicht nur einmal stossen: das Rad ist
	# danach nicht mehr rund, das Lenkrad ruettelt weiter (wie im offiziellen
	# Spiel), und zwar schneller, wenn der Wagen schneller faehrt.
	var clean: Dictionary = _steady(_corner({"damage": 0.0}))
	var damaged: Dictionary = _steady(_corner({"damage": 0.30, "speed": 20.0}))
	var damaged_fast: Dictionary = _steady(_corner({"damage": 0.30, "speed": 62.0}))
	# Dauerprobe (probe_wave6_feel.gd): ein einzelner Streifer darf das Lenkrad
	# nicht fuer den Rest der Sitzung laut machen. Gemessen gilt jetzt:
	# Schaden 0,22 -> 0,19 | 0,44 -> 0,38 | 0,66 -> 0,64 | 1,0 -> 0,75.
	# Die alte Behauptung "der Kerb bleibt immer lauter" war falsch (gemessen:
	# Kerb 0,588 bei 108 km/h gegen ein Wrack mit 0,750, siehe Abschnitt 19).
	var mild: float = float(_steady(_corner({"damage": 0.22}))["rumble"])
	var medium: float = float(_steady(_corner({"damage": 0.44}))["rumble"])
	var badly: float = float(_steady(_corner({"damage": 0.66}))["rumble"])
	var wrecked: float = float(_steady(_corner({"damage": 1.0}))["rumble"])
	_check(float(damaged["rumble"]) > float(clean["rumble"]) + 0.05
		and String(damaged["source"]) == "Unwucht",
		"schaden_ruettelt_am_lenkrad",
		"ohne %.2f (%s) -> mit Schaden %.2f @ %.0f Hz (%s)" % [
			float(clean["rumble"]), str(clean["source"]),
			float(damaged["rumble"]), float(damaged["rumble_hz"]), str(damaged["source"])])
	_check(mild < 0.25 and medium > mild + 0.10 and badly > medium + 0.10
		and wrecked > badly + 0.05 and wrecked < 0.85,
		"unwucht_waechst_mit_dem_schaden_ohne_zu_saettigen",
		"Streifer %.2f < mittel %.2f < schwer %.2f < Wrack %.2f (Kerb 0.85)" % [
			mild, medium, badly, wrecked])
	_check(float(damaged_fast["rumble_hz"]) > float(damaged["rumble_hz"]) + 3.0,
		"unwucht_wird_mit_dem_tempo_schneller",
		"%.0f Hz -> %.0f Hz" % [float(damaged["rumble_hz"]), float(damaged_fast["rumble_hz"])])

	# --- Die drei Ruettel-Baender des offiziellen Spiels -------------------
	# F1 24/25 hat getrennte Regler fuer On Track (Asphalt-Textur), Rumble Strip
	# (Kerb) und Off Track (Gras/Kies). Sie muessen einzeln wirken: dreht man
	# den Kerb auf 0, darf das Kies-Mahlen NICHT mitverschwinden (sonst waere es
	# kein Band, sondern nur ein zweiter Hauptschalter).
	var band_settings := Settings.new()
	band_settings.auto_save = false
	band_settings.gain = 1.0
	band_settings.damper = 1.0
	band_settings.invert = false
	var band_model := Model.new()
	band_model.setup(band_settings)
	var surf_kerb: Dictionary = {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}
	var surf_gravel: Dictionary = {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}
	var surf_road: Dictionary = {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0}
	var band_kerb_on: float = float(_band_rumble(band_model, surf_kerb)["rumble"])
	var band_gravel_on: float = float(_band_rumble(band_model, surf_gravel)["rumble"])
	var band_road_on: float = float(_band_rumble(band_model, surf_road)["rumble"])
	band_settings.kerb_effects = 0.0
	var kerb_off: Dictionary = _band_rumble(band_model, surf_kerb)
	var gravel_with_kerb_off: float = float(_band_rumble(band_model, surf_gravel)["rumble"])
	_check(float(kerb_off["rumble"]) < 0.01 and String(kerb_off["source"]) == "-",
		"kerb_band_auf_null_schaltet_den_kerb_ab",
		"vorher %.2f -> jetzt %.2f (%s)" % [band_kerb_on, float(kerb_off["rumble"]), str(kerb_off["source"])])
	_check(gravel_with_kerb_off > 0.15,
		"kerb_band_auf_null_laesst_das_kies_stehen",
		"Kies %.2f (unveraendert, war %.2f)" % [gravel_with_kerb_off, band_gravel_on])
	band_settings.kerb_effects = 1.0
	band_settings.offtrack_effects = 0.0
	var gravel_off: Dictionary = _band_rumble(band_model, surf_gravel)
	_check(float(gravel_off["rumble"]) < 0.01
		and float(_band_rumble(band_model, surf_kerb)["rumble"]) > 0.5,
		"off_track_band_auf_null_laesst_den_kerb_stehen",
		"Kies %.2f (%s), Kerb %.2f" % [float(gravel_off["rumble"]), str(gravel_off["source"]),
			float(_band_rumble(band_model, surf_kerb)["rumble"])])
	band_settings.offtrack_effects = 1.0
	band_settings.ontrack_effects = 0.0
	var road_off: Dictionary = _band_rumble(band_model, surf_road)
	_check(band_road_on > 0.03 and float(road_off["rumble"]) < 0.005
		and String(road_off["source"]) == "-",
		"on_track_band_auf_null_schaltet_die_asphalt_textur_ab",
		"Asphalt-Textur %.3f -> %.3f (%s)" % [band_road_on, float(road_off["rumble"]), str(road_off["source"])])
	band_settings.ontrack_effects = 1.0

	# --- 18. Ein Stoss ohne Lenkbefehl darf nicht verschwinden ------------
	# `g29_input.gd` setzt die Lenkung per Totzone auf der Geraden auf genau
	# 0.0. Der Stoss bekam damit das Vorzeichen `-signf(0.0)` = 0, und der
	# Helfer machte daraus gemessen **0,000 Kraft**: Schaltstoss, Bodenwelle
	# und ein gerader Einschlag waren am Lenkrad nicht zu spueren, waehrend HUD
	# und Kamera sie zeigten. Der Helfer legt ein vorzeichenloses Ereignis
	# seitdem als Klopfen an (30 Hz, `tools/g29_ffb.py`); diese Pruefung haelt
	# die Eingangsseite fest - auf der Geraden darf das Vorzeichen **0** sein
	# (nichts erfunden), in der Kurve traegt es den Lenkbefehl.
	var straight_ctx: Dictionary = _corner({"steer": 0.0, "steer_angle": 0.0})
	_steady(straight_ctx)
	model.poke("crash", 1.0)
	var straight_hit: Dictionary = model.update(1.0 / 90.0, straight_ctx)
	_check(float(straight_hit["pulse"]) > 0.95
		and absf(float(straight_hit["pulse_dir"])) <= 0.001,
		"stoss_ohne_lenkbefehl_hat_kein_vorzeichen",
		"steer 0.0 -> pulse %.2f, Richtung %+.2f, Quelle %s (der Helfer klopft)" % [
			float(straight_hit["pulse"]), float(straight_hit["pulse_dir"]),
			String(straight_hit["source"])])
	_steady(_corner())
	model.poke("shift", 0.45)
	var corner_shift: Dictionary = model.update(1.0 / 90.0, _corner())
	_check(float(corner_shift["pulse"]) > 0.3
		and absf(float(corner_shift["pulse_dir"]) + 1.0) < 0.01,
		"stoss_in_der_kurve_laeuft_gegen_den_lenkbefehl",
		"Lenkbefehl +1.0 (rechts) -> pulse %.2f, Stoss %+.2f (nach links)" % [
			float(corner_shift["pulse"]), float(corner_shift["pulse_dir"])])

	# --- 19. Die Oberflaeche fuehrt, die Unwucht bleibt auf dem Asphalt ----
	# Gemessen (probe_wave9_loudness.gd, 108 km/h, Schaden 1,0): ohne die
	# Begrenzung im Modell stand auf Kies und auf dem Kerb `Quelle Unwucht,
	# 0,750 @ 19 Hz` - das Off-Track-Band des offiziellen Spiels war damit
	# fuer den Rest der Sitzung nicht mehr zu spueren (es gibt keine
	# Werkstatt). Mit der Begrenzung: Kerb 0,588 @ 29 Hz, Kies 0,300 @ 13 Hz.
	var wreck_kerb: Dictionary = _steady(_corner({
		"speed": 30.0, "damage": 1.0, "surface": surf_kerb}))
	var wreck_gravel: Dictionary = _steady(_corner({
		"speed": 30.0, "damage": 1.0, "surface": surf_gravel}))
	_check(String(wreck_kerb["source"]) == "Kerb" and float(wreck_kerb["rumble"]) < 0.70,
		"der_kerb_bleibt_das_lauteste_auf_dem_kerb",
		"Kerb mit Wrack %.3f @ %.0f Hz (%s), vorher 0,750 @ 19 Hz (Unwucht)" % [
			float(wreck_kerb["rumble"]), float(wreck_kerb["rumble_hz"]),
			String(wreck_kerb["source"])])
	_check(String(wreck_gravel["source"]) == "Kies" and float(wreck_gravel["rumble"]) < 0.40,
		"das_kies_mahlen_bleibt_auch_mit_wrack_hoerbar",
		"Kies mit Wrack %.3f @ %.0f Hz (%s), vorher 0,750 @ 19 Hz (Unwucht)" % [
			float(wreck_gravel["rumble"]), float(wreck_gravel["rumble_hz"]),
			String(wreck_gravel["source"])])
	var wreck_road: Dictionary = _steady(_corner({"speed": 30.0, "damage": 1.0}))
	_check(String(wreck_road["source"]) == "Unwucht" and float(wreck_road["rumble"]) > 0.6,
		"auf_asphalt_bleibt_die_unwucht_deutlich_zu_spueren",
		"Asphalt mit Wrack %.3f @ %.0f Hz (%s)" % [
			float(wreck_road["rumble"]), float(wreck_road["rumble_hz"]),
			String(wreck_road["source"])])

	if failed > 0:
		print("FFB_MODEL FAIL count=%d von %d" % [failed, checks])
		quit(1)
	else:
		print("FFB_MODEL PASS %d Pruefungen" % checks)
		quit(0)
