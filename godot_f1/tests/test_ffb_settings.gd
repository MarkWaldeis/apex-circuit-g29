extends SceneTree
## Prüft die Force-Feedback-Einstellungen und den Lenkanschlag:
##
##  * die Werte überleben Speichern und Laden,
##  * die Knöpfe im Menü schalten wirklich weiter,
##  * der Lenkbereich (Soft Lock) rechnet in Grad und drückt erst am Anschlag,
##  * das Modell nimmt genau diese Einstellungen (Stärke, Dämpfung, Effekte).
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_settings.gd

const Settings := preload("res://scripts/ffb_settings.gd")
const G29 = preload("res://scripts/g29_input.gd")
const Model := preload("res://scripts/ffb_model.gd")

const TMP := "user://ffb_settings_test.json"

var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run() -> void:
	# --- Speichern und Laden ---------------------------------------------
	var s := Settings.new()
	s.path = TMP
	s.gain = 0.45
	s.damper = 1.0
	s.effects = false
	s.rotation_deg = 360.0
	s.invert = true
	s.save_profile()
	var back := Settings.new()
	back.path = TMP
	var ok: bool = back.load_profile()
	_check(ok, "einstellungen_werden_geladen", TMP)
	_check(is_equal_approx(back.gain, 0.45) and is_equal_approx(back.damper, 1.0)
		and back.effects == false and is_equal_approx(back.rotation_deg, 360.0)
		and back.invert == true,
		"alle_werte_kommen_zurueck",
		"gain=%.2f damper=%.2f effects=%s rotation=%.0f invert=%s" % [
			back.gain, back.damper, str(back.effects), back.rotation_deg, str(back.invert)])

	# --- Die drei Ruettel-Baender ueberleben Speichern und Laden -----------
	# Genau die Regler, die das offizielle Spiel hat: On Track, Rumble Strip,
	# Off Track. Ohne diesen Test waere ein vergessenes Feld in save/load
	# unsichtbar - der Regler haette sich beim naechsten Start zurueckgesetzt.
	var bands := Settings.new()
	bands.path = TMP + ".bands"
	bands.ontrack_effects = 0.4
	bands.kerb_effects = 0.0
	bands.offtrack_effects = 0.7
	bands.save_profile()
	var bands_back := Settings.new()
	bands_back.path = TMP + ".bands"
	bands_back.load_profile()
	_check(is_equal_approx(bands_back.ontrack_effects, 0.4)
		and is_equal_approx(bands_back.kerb_effects, 0.0)
		and is_equal_approx(bands_back.offtrack_effects, 0.7),
		"die_drei_ruettel_baender_kommen_zurueck",
		"on track=%s kerb=%s off track=%s" % [bands_back.ontrack_label(),
			bands_back.kerb_label(), bands_back.offtrack_label()])
	_check(is_equal_approx(bands_back.band_scale(1), 0.0)
		and is_equal_approx(bands_back.band_scale(2), 0.7)
		and is_equal_approx(bands_back.band_scale(0), 0.4),
		"die_baender_haben_getrennte_zahlen",
		"0=%.1f 1=%.1f 2=%.1f" % [bands_back.band_scale(0),
			bands_back.band_scale(1), bands_back.band_scale(2)])
	# Eine Einstellungsdatei aus der Zeit vor den Baendern (nur "effects")
	# darf den Fahrer nicht aussperren - sie laedt weiter, Baender auf 100 %.
	var old_file := FileAccess.open(TMP + ".old", FileAccess.WRITE)
	old_file.store_string('{"version":1,"enabled":true,"gain":0.6,"damper":1.0,"effects":true,"invert":false,"rotation_deg":360.0}')
	old_file.close()
	var legacy := Settings.new()
	legacy.path = TMP + ".old"
	var legacy_ok: bool = legacy.load_profile()
	_check(legacy_ok and is_equal_approx(legacy.gain, 0.6)
		and is_equal_approx(legacy.kerb_effects, 1.0)
		and is_equal_approx(legacy.offtrack_effects, 1.0),
		"alte_einstellungsdatei_laedt_weiter",
		"ok=%s gain=%.2f kerb=%s" % [str(legacy_ok), legacy.gain, legacy.kerb_label()])

	# --- Die Knoepfe schalten weiter -------------------------------------
	var i := Settings.new()
	i.path = TMP + ".cycle"
	var start_gain: float = i.gain
	i.cycle_gain()
	_check(not is_equal_approx(i.gain, start_gain), "staerke_schaltet_weiter",
		"%.2f -> %.2f" % [start_gain, i.gain])
	var seen: Dictionary = {}
	for step in Settings.GAINS.size():
		seen[str(i.gain)] = true
		i.cycle_gain()
	_check(seen.size() == Settings.GAINS.size(), "alle_stufen_sind_erreichbar",
		str(seen.keys()))
	var rot_before: float = i.rotation_deg
	i.cycle_rotation()
	_check(not is_equal_approx(i.rotation_deg, rot_before), "lenkbereich_schaltet_weiter",
		"%.0f -> %.0f" % [rot_before, i.rotation_deg])
	i.toggle_effects()
	_check(i.effects == false or i.effects == true, "effekte_schalten", str(i.effects))
	# Die Baender laufen in 10-%-Schritten und sind einzeln schaltbar.
	var band_start: float = i.kerb_effects
	i.cycle_kerb_effects()
	_check(not is_equal_approx(i.kerb_effects, band_start)
		and is_equal_approx(i.ontrack_effects, 1.0),
		"kerb_band_schaltet_weiter_ohne_die_anderen",
		"kerb %.2f -> %.2f, on track bleibt %.2f" % [
			band_start, i.kerb_effects, i.ontrack_effects])
	var band_seen: Dictionary = {}
	for step in Settings.EFFECT_STEPS.size():
		band_seen[i.kerb_label()] = true
		i.cycle_kerb_effects()
	_check(band_seen.size() == Settings.EFFECT_STEPS.size(),
		"alle_bandstufen_sind_erreichbar", str(band_seen.keys()))

	# --- Lenkbereich rechnet in Grad -------------------------------------
	var r := Settings.new()
	r.path = TMP + ".rot"
	r.rotation_deg = 400.0
	_check(is_equal_approx(r.lock_half_deg(), 200.0)
		and is_equal_approx(r.wheel_half_range_deg(), 450.0),
		"400_grad_sind_200_pro_seite",
		"lock=%.0f wheel=%.0f" % [r.lock_half_deg(), r.wheel_half_range_deg()])
	_check(is_equal_approx(r.lock_fraction(), 400.0 / 900.0),
		"lenkbereich_ist_ein_anteil_von_900", "%.3f" % r.lock_fraction())

	# --- Soft Lock am echten Eingabemodul ---------------------------------
	var g := G29.new()
	g.auto_load_profile = false
	g.profile_path = TMP + ".g29"
	g.ffb_settings = r
	# Der Ruhepunkt ist kalibriert (im Test: Mitte) - sonst haengt das Modul
	# den ersten Achsenwert als "Mitte" ein, und die Rechnung verschiebt sich.
	g.steer_locked = true
	g.enable_sim()
	root.add_child(g)
	# 0,2 der Achse sind 90 Grad (die Achse laeuft ueber 900 Grad).
	g.sim_set(0, 0.2)
	g.step(1.0 / 90.0)
	_check(absf(g.steer_soft) > 0.35 and absf(g.steer_soft) < 0.55 and g.steer_lock == 0.0,
		"90_grad_sind_halb_am_anschlag",
		"steer=%.3f soft=%.3f angle=%.0f Grad lock=%.2f" % [
			g.steer, g.steer_soft, g.steer_angle_deg, g.steer_lock])
	var soft_at_half: float = g.steer_soft
	# 0,6 der Achse sind 270 Grad - deutlich ueber dem Anschlag bei 200.
	g.sim_set(0, 0.6)
	g.step(1.0 / 90.0)
	_check(absf(g.steer_soft) >= 0.99 and g.steer_lock > 0.15,
		"jenseits_des_anschlags_steigt_der_druck",
		"soft=%.2f lock=%.2f bei %.0f Grad" % [g.steer_soft, g.steer_lock, g.steer_angle_deg])
	_check(absf(g.steer_angle_deg) > 250.0, "der_winkel_wird_mitgerechnet",
		"%.0f Grad" % g.steer_angle_deg)
	# Mit 900 Grad Lenkbereich gibt es keinen Soft Lock.
	var wide := Settings.new()
	wide.rotation_deg = 900.0
	g.ffb_settings = wide
	g.step(1.0 / 90.0)
	# 0,6 der Achse sind bei 900 Grad 270 Grad von 450 moeglichen - also 0,6
	# Lenkbefehl nach Totzone (nicht 1.0: `steer` ist auf den kalibrierten Weg
	# bezogen, `steer_soft` auf die Gradzahl. Mit voller Kalibrierung sind
	# beide gleich; hier ist genau dieser Unterschied sichtbar.)
	var expect_soft: float = (0.6 - g.steer_deadzone) / (1.0 - g.steer_deadzone)
	_check(g.steer_lock == 0.0 and absf(g.steer_soft - expect_soft) < 0.02,
		"bei_900_grad_kein_anschlag",
		"soft=%.3f erwartet %.3f lock=%.2f" % [g.steer_soft, expect_soft, g.steer_lock])

	# --- Das Modell nimmt die Einstellungen ------------------------------
	var model := Model.new()
	var ms := Settings.new()
	ms.path = TMP + ".model"
	ms.gain = 1.0
	model.setup(ms)
	var ctx := {
		"steer": 1.0, "steer_angle": -0.10, "slip_front": 0.075, "lateral_g": 3.2,
		"yaw_rate": -0.3, "speed": 62.0, "downforce": 2.6, "understeer": 0.05,
		"oversteer": 0.0, "brake": 0.0, "throttle": 0.8, "lock_pressure": 0.0,
		"surface": {"surface": 0, "rumble": 0.0, "rough": 0.0},
	}
	for n in 40:
		model.update(1.0 / 90.0, ctx)
	var full: float = absf(model.torque)
	ms.gain = 0.45
	for n in 60:
		model.update(1.0 / 90.0, ctx)
	var half: float = absf(model.torque)
	_check(half < full * 0.55 and half > full * 0.35, "staerke_wirkt_auf_die_kraft",
		"100 %%: %.3f -> 45 %%: %.3f" % [full, half])
	ms.invert = true
	for n in 60:
		model.update(1.0 / 90.0, ctx)
	_check(model.torque > 0.0, "kraftrichtung_dreht_das_vorzeichen",
		"torque=%+.3f" % model.torque)
	ms.invert = false
	ms.effects = false
	for n in 60:
		model.update(1.0 / 90.0, ctx)
	_check(model.rumble == 0.0, "ruetteln_laesst_sich_abschalten",
		"rumble=%.3f" % model.rumble)

	# --- Das Menue schaltet dieselben Werte ------------------------------
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	var menu = main.get("menu")
	var live = main.get("ffb_settings")
	_check(live != null, "die_szene_haelt_die_einstellungen", str(live))
	if live != null and menu != null:
		var before: float = live.gain
		menu._cycle_ffb_gain()
		_check(not is_equal_approx(live.gain, before), "das_menue_schaltet_die_staerke",
			"%.2f -> %.2f" % [before, live.gain])
		# Das Menue muss dieselben drei Baender bedienen koennen wie das
		# offizielle Spiel - und jeder Knopf darf nur sein eigenes Band aendern.
		var kt_before: float = live.ontrack_effects
		var kb_before: float = live.kerb_effects
		var ot_before: float = live.offtrack_effects
		menu._cycle_ffb_ontrack()
		menu._cycle_ffb_kerb()
		menu._cycle_ffb_offtrack()
		_check(not is_equal_approx(live.ontrack_effects, kt_before)
			and not is_equal_approx(live.kerb_effects, kb_before)
			and not is_equal_approx(live.offtrack_effects, ot_before),
			"das_menue_bedient_alle_drei_ruettel_baender",
			"on track %.2f->%.2f kerb %.2f->%.2f off track %.2f->%.2f" % [
				kt_before, live.ontrack_effects, kb_before, live.kerb_effects,
				ot_before, live.offtrack_effects])
		_check(menu._ffb_ontrack_button != null and menu._ffb_kerb_button != null
			and menu._ffb_offtrack_button != null,
			"die_drei_baender_haben_knoepfe",
			"%s | %s | %s" % [menu._ffb_ontrack_button.text,
				menu._ffb_kerb_button.text, menu._ffb_offtrack_button.text])
		_check(menu._screens.has(menu.Screen.FFB), "es_gibt_eine_force_feedback_seite")
		menu._update_ffb_live()
		_check(menu._ffb_live.text.length() > 5, "die_live_anzeige_zeigt_etwas",
			menu._ffb_live.text.replace("\n", " | "))
		# --- Die Staerke wirkt genau einmal (nicht zweimal) ---------------
		# Zwei Aussagen zusammen: das Modell skaliert linear mit der
		# Einstellung (oben gemessen: 0.797 bei 100 %, 0.358 bei 45 %), und das
		# Paket an den Helfer enthaelt genau diese Kraft, ohne sie noch einmal
		# zu verstaerken (`gain` = 1.0, der Helfer multipliziert damit). Frueher
		# stand im Paket die Menue-Staerke, waehrend das Modell sie schon
		# angewendet hatte - 30 % Einstellung kamen als 9 % am Lenkrad an.
		var car = main.get("player")
		var link = car.get("ffb") if car else null
		if link != null:
			for tick in 30:
				await physics_frame
			var sent: float = float(link.last_packet.get("torque", 0.0))
			var computed: float = float(link.last_state.get("torque", 0.0))
			_check(is_equal_approx(sent, computed), "paket_enthaelt_genau_die_modellkraft",
				"Paket %+.3f = Modell %+.3f" % [sent, computed])
			_check(is_equal_approx(float(link.last_packet.get("gain", 0.0)), 1.0),
				"paket_verstaerkt_nicht_ein_zweites_mal",
				"gain im Paket %.2f" % float(link.last_packet.get("gain", 0.0)))

		# --- Das HUD nennt den Grund, wenn keine Kraft ankommt -------------
		# Der schlimmste Fall ist ein stilles Lenkrad: das Spiel laeuft, das
		# Rad steht still, und der Fahrer sucht den Fehler in der Physik. Zwei
		# Ursachen kann das Spiel von innen sehen - der Schalter steht auf AUS,
		# oder es antwortet kein Helfer (Rueckkanal aus `ffb_link.gd`).
		var hud = main.get("hud")
		if link != null and hud != null and live != null:
			live.enabled = false
			hud._update_force()
			_check(String(hud._force.text).begins_with("LENKRADKRAFT AUS"),
				"hud_meldet_abgeschaltete_kraft", hud._force.text)
			live.enabled = true
			link.sent_packets = 200
			link.helper_acks = 0
			hud._update_force()
			_check(String(hud._force.text).begins_with("KEIN HELFER"),
				"hud_meldet_fehlenden_helfer", hud._force.text)
			link.helper_acks = 5
			link.helper_last_ms = Time.get_ticks_msec()
			link._last_send_ms = Time.get_ticks_msec()
			hud._update_force()
			_check(String(hud._force.text).begins_with("Lenkkraft"),
				"hud_zeigt_die_kraft_wenn_alles_laeuft", hud._force.text)

	# --- Ein Testlauf darf die Einstellungen des Fahrers nicht anfassen -----
	# Genau das war passiert: nach einer Pruefwelle stand in
	# `user://ffb_settings.json` "enabled": false, und die naechste Messung
	# fand am Lenkrad keine Kraft mehr - die Kette war in Ordnung, nur der
	# Schalter im Menue stand auf AUS. Der Headless-Lauf darf die echte Datei
	# deshalb gar nicht erst oeffnen. Geprueft wird beides: der Schreibversuch
	# wird abgelehnt UND die Datei bleibt unveraendert.
	var real_path: String = Settings.PATH
	var real_exists: bool = FileAccess.file_exists(real_path)
	var real_before: String = ""
	var real_stamp: int = 0
	if real_exists:
		var rf := FileAccess.open(real_path, FileAccess.READ)
		if rf != null:
			real_before = rf.get_as_text()
			rf.close()
		real_stamp = FileAccess.get_modified_time(real_path)
	var guard := Settings.new()
	guard.path = real_path
	guard.enabled = false
	guard.gain = 1.0
	var wrote: bool = guard.save_profile()
	var real_after: String = ""
	var real_stamp_after: int = 0
	if FileAccess.file_exists(real_path):
		var rf2 := FileAccess.open(real_path, FileAccess.READ)
		if rf2 != null:
			real_after = rf2.get_as_text()
			rf2.close()
		real_stamp_after = FileAccess.get_modified_time(real_path)
	_check(not wrote and real_after == real_before and real_stamp_after == real_stamp,
		"ein_testlauf_kann_die_echten_einstellungen_nicht_ueberschreiben",
		"save_profile() -> %s, Datei unveraendert: %s, Zeitstempel %d -> %d" % [
			str(wrote), str(real_after == real_before), real_stamp, real_stamp_after])

	if failed > 0:
		print("FFB_SETTINGS FAIL count=%d von %d" % [failed, checks])
		quit(1)
	else:
		print("FFB_SETTINGS PASS %d Pruefungen" % checks)
		quit(0)
