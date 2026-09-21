extends SceneTree
## Gegenprobe zur automatischen Kraftrichtung (Welle 6, kritische Prüfung):
## Kann die Automatik sich widersprechen, im Bogen umschalten, auf Rauschen
## hereinfallen oder eine einmal getroffene Entscheidung wieder verlieren?
##
## Eigene Messungen, nicht die des Autors:
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_wave6_direction.gd

const FfbLink := preload("res://scripts/ffb_link.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const PROFILE := "user://ffb_wave6_direction.json"
const CENTER := 32767
const LEFT := 18000     ## deutlich unter der Mitte
const RIGHT := 47000    ## deutlich darueber

var failed: int = 0
var checks: int = 0
var seq: int = 0


class StubWheel:
	var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var steer_axis: int = 0
	func axis_snapshot() -> PackedFloat32Array: return values
	func has_axis_data() -> bool: return true


func _initialize() -> void:
	_run()
	quit(1 if failed > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _settings(invert: bool, source: String):
	var s = Settings.new()
	s.path = PROFILE
	s.auto_save = true
	s.invert = invert
	s.invert_source = source
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	return s


func _link(s, wheel):
	var link = FfbLink.new()
	link.setup(s, wheel)
	return link


func _feed(link, wheel, steer: float, raw: int, ticks: int = 12) -> void:
	wheel.values[0] = steer
	for i in ticks:
		link.helper_wheel_raw = raw
		link.helper_wheel_ms = Time.get_ticks_msec() + seq
		seq += 1
		link.measure_direction(1.0 / 60.0)


func _center(link, wheel, raw: int = CENTER) -> void:
	wheel.values[0] = 0.0
	for i in 14:
		link.helper_wheel_raw = raw
		link.helper_wheel_ms = Time.get_ticks_msec() + seq
		seq += 1
		link.measure_direction(1.0 / 60.0)


func _run() -> void:
	# --- 1. Eine einmal getroffene Entscheidung darf nicht kippen ----------
	var s = _settings(false, "standard")
	var w := StubWheel.new()
	var link = _link(s, w)
	_center(link, w)
	_feed(link, w, 0.6, RIGHT)                      # gleichlaeufig -> invert
	_check(int(link.get("direction_aligned")) == 1, "gleichlaeufig_erkannt",
		"direction_aligned=%d" % int(link.get("direction_aligned")))
	# Jetzt 30 widersprechende Messungen in die Gegenrichtung.
	_feed(link, w, -0.6, RIGHT, 30)
	_check(int(link.get("direction_aligned")) == 1 and bool(s.invert) == true,
		"eine_entscheidung_kippt_nicht_wieder",
		"direction_aligned=%d invert=%s" % [int(link.get("direction_aligned")), str(s.invert)])

	# --- 2. Widerspruechliche Stimmen ergeben keine Entscheidung ----------
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	for i in 8:
		# abwechselnd gleichlaeufig und gegenlaeufig - wie ein zitterndes Rad
		if i % 2 == 0:
			_feed(link, w, 0.6, RIGHT, 2)
		else:
			_feed(link, w, 0.6, LEFT, 2)
	_check(int(link.get("direction_aligned")) == -1, "widerspruch_ergibt_keine_entscheidung",
		"direction_aligned=%d nach 16 Stimmen" % int(link.get("direction_aligned")))

	# --- 3. Rauschen um die Mitte zaehlt nie als Lenkbewegung -------------
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	for i in 40:
		var jitter: float = 0.03 if i % 2 == 0 else -0.03
		_feed(link, w, jitter, CENTER + 120, 1)
	_check(int(link.get("direction_aligned")) == -1, "rauschen_um_die_mitte_zaehlt_nicht",
		"direction_aligned=%d" % int(link.get("direction_aligned")))

	# --- 4. Zu wenig Lenkeinschlag: keine Aussage ------------------------
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	_feed(link, w, 0.10, RIGHT, 30)                # 10 % - unter der Schwelle
	_check(int(link.get("direction_aligned")) == -1, "wenig_lenkeinschlag_keine_aussage",
		"direction_aligned=%d bei Lenkung 0.10" % int(link.get("direction_aligned")))

	# --- 5. Totes Rad / alter Wert: keine Aussage ------------------------
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	link.helper_wheel_raw = RIGHT
	link.helper_wheel_ms = Time.get_ticks_msec() - 5000   # uralt
	for i in 20:
		w.values[0] = 0.6
		link.measure_direction(1.0 / 60.0)
	_check(int(link.get("direction_aligned")) == -1, "alter_helferwert_zaehlt_nicht",
		"direction_aligned=%d" % int(link.get("direction_aligned")))

	# --- 6. Fahrerwahl bleibt, auch wenn die Messung das Gegenteil sagt ----
	s = _settings(true, "fahrer")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	_feed(link, w, 0.6, LEFT, 40)                  # wuerde "normal" ergeben
	_check(bool(s.invert) == true and int(link.get("direction_aligned")) == -1,
		"fahrerwahl_wird_nicht_ueberstimmt",
		"invert=%s aligned=%d" % [str(s.invert), int(link.get("direction_aligned"))])

	# --- 7. Gespeicherte Messung ueberlebt den Neustart -------------------
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	_feed(link, w, 0.6, RIGHT, 20)
	_check(String(s.invert_source) == "gemessen" and bool(s.invert) == true,
		"messung_wird_gespeichert",
		"invert=%s source=%s" % [str(s.invert), s.invert_source])
	var again = Settings.new()
	again.path = PROFILE
	again.load_profile()
	# Der WERT muss ueberleben. Die Herkunft wird beim Laden bewusst auf "auto"
	# reduziert (nur "fahrer" bleibt stehen): eine automatisch gemessene
	# Richtung wird in der naechsten Sitzung ohnehin nachgemessen - so folgt das
	# Spiel auch einem geaenderten G-HUB-Bereich. Geschuetzt ist die
	# Entscheidung des Fahrers, nicht die der Automatik.
	_check(bool(again.invert) == true, "messung_ueberlebt_den_neustart",
		"invert=%s source=%s (Herkunft wird beim Laden auf auto reduziert)" % [
			str(again.invert), again.invert_source])
	# Gegenprobe: die Fahrerwahl bleibt als solche stehen.
	var driver_choice = Settings.new()
	driver_choice.path = PROFILE
	driver_choice.invert = false
	driver_choice.invert_source = "fahrer"
	driver_choice.save_profile()
	var reloaded = Settings.new()
	reloaded.path = PROFILE
	reloaded.load_profile()
	_check(String(reloaded.invert_source) == "fahrer" and bool(reloaded.invert) == false,
		"fahrerwahl_ueberlebt_den_neustart",
		"invert=%s source=%s" % [str(reloaded.invert), reloaded.invert_source])

	# --- 8. Und wenn die Messung im Bogen fertig wird? --------------------
	# Die Kraft liegt an (Bogen): die Entscheidung darf erst gesetzt werden,
	# wenn das Rad wieder leicht ist - sonst gibt es einen Ruck im Scheitel.
	s = _settings(false, "standard")
	w = StubWheel.new()
	link = _link(s, w)
	_center(link, w)
	var corner: Dictionary = {
		"speed": 60.0, "steer": 0.6, "steer_angle": -0.10, "slip_front": 0.08,
		"lateral_g": 3.5, "downforce": 3.0}
	for i in 12:
		w.values[0] = 0.6
		link.helper_wheel_raw = RIGHT
		link.helper_wheel_ms = Time.get_ticks_msec() + seq
		seq += 1
		link.force_torque_override = 0.62          # Kraft im Bogen
		link.update(1.0 / 90.0, corner)
		link.measure_direction(1.0 / 60.0)
	var corner_force: float = absf(float(link.last_state.get("torque", 0.0)))
	_check(corner_force > 0.3, "im_bogen_liegt_wirklich_kraft_an",
		"Kraft im Bogen %.3f" % corner_force)
	_check(int(link.get("direction_aligned")) == 1 and bool(s.invert) == false,
		"im_bogen_wird_nicht_umgeschaltet",
		"aligned=%d invert=%s" % [int(link.get("direction_aligned")), str(s.invert)])
	# Jetzt geradeaus und leicht: dieselbe Entscheidung muss fallen.
	link.force_torque_override = 0.0
	for i in 6:
		link.update(1.0 / 90.0, {"speed": 60.0, "steer": 0.0, "lateral_g": 0.0})
		link.measure_direction(1.0 / 60.0)
	_check(bool(s.invert) == true, "auf_der_geraden_faellt_sie",
		"invert=%s note=%s" % [str(s.invert), String(link.get("direction_note"))])

	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	print("WAVE6_DIRECTION %s %d Pruefungen" % ["PASS" if failed == 0 else "FAIL", checks])
