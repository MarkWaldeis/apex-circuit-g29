extends SceneTree
## Die Kraftrichtung wird beim Fahren selbst gemessen (ffb_link.gd).
##
## Warum das noetig ist: bis Welle 4 stand die Richtung auf einer **Annahme**.
## Gemessen war nur die halbe Kette - eine positive DirectInput-Kraft faehrt die
## G29-Achse zum Minimum (tools/ffb_hw_probe.py). Ob "Achse runter" im Spiel
## links oder rechts ist, haengt daran, wie die DirectInput-Achse zur SDL-Achse
## steht, aus der das Spiel "rechts = +1" gelernt hat. Diese zweite Haelfte
## laesst sich messen, sobald der Fahrer das Lenkrad dreht: der Helfer schickt
## seinen Achsenwert mit jedem Lebenszeichen (10 Hz), das Spiel liest dieselbe
## Achse ueber SDL.
##
## Dieser Test prueft beide Faelle und - genauso wichtig - dass ohne Achsdaten
## **nichts** entschieden wird. Ein Werkzeug, das ohne Messung eine Richtung
## behauptet, waere schlimmer als gar keines.

const FfbLink = preload("res://scripts/ffb_link.gd")
const Settings = preload("res://scripts/ffb_settings.gd")

## Mitte der G29-Achse, gemessen 32767..33104 - hier bewusst nicht der
## Idealwert, damit kein fester Nullpunkt durchrutscht.
const CENTER := 33000
## ±27 % der Achse: weit ausserhalb der Totzone, wie ein echter Lenkeinschlag.
const OFF := 9000

const PROFILE := "user://ffb_direction_test.json"

var failed: int = 0
var seq: int = 0


## Ersatz-Lenkrad: liefert genau die Achsenwerte, die der Test vorgibt.
class FakeWheel extends RefCounted:
	var steer_axis: int = 0
	var values: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var live: bool = true

	func axis_snapshot() -> PackedFloat32Array:
		return values

	func has_axis_data() -> bool:
		return live


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1
		print("FAIL ", label, " ", detail)


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


## Eine Runde "Fahren": das Rad steht an `steer`, der Helfer meldet `raw`.
## Jeder Aufruf ist eine neue Antwort des Helfers (der Zeitstempel wandert),
## sonst waeren es dieselben Daten zwoelfmal gezaehlt.
func _feed(link, wheel, steer: float, raw: int, ticks: int = 12) -> void:
	wheel.values[0] = steer
	for _i in ticks:
		link.helper_wheel_raw = raw
		link.helper_wheel_ms = Time.get_ticks_msec() + seq
		seq += 1
		link.measure_direction(1.0 / 60.0)


## Mitte lernen: das Rad steht, der Helfer meldet den Ruhewert der Achse.
func _learn_center(link, wheel, raw: int = CENTER) -> void:
	wheel.values[0] = 0.0
	for _i in 14:
		link.helper_wheel_raw = raw
		link.helper_wheel_ms = Time.get_ticks_msec() + seq
		seq += 1
		link.measure_direction(1.0 / 60.0)


func _run() -> void:
	_without_data_nothing_is_claimed()
	_aligned_axis_needs_invert()
	_opposite_axis_needs_no_invert()
	_a_driver_choice_is_not_overwritten()
	_never_flip_in_the_middle_of_a_corner()

	if failed > 0:
		print("FFB_DIRECTION FAIL count=", failed)
		quit(1)
	else:
		print("FFB_DIRECTION PASS")
		quit(0)


func _without_data_nothing_is_claimed() -> void:
	var s = _settings(false, "auto")
	var wheel := FakeWheel.new()
	var link = _link(s, wheel)
	_check(bool(link.get("enabled")), "der_kanal_ist_offen", "enabled=%s" % link.get("enabled"))
	# Kein Achsenwert vom Helfer (Rad stromlos) - auch wenn der Fahrer lenkt.
	for _i in 60:
		wheel.values[0] = 0.4
		link.helper_wheel_raw = -1
		link.measure_direction(1.0 / 60.0)
	_check(int(link.get("direction_aligned")) == -1,
		"ohne_achsenwert_keine_entscheidung",
		"direction_aligned=%d" % int(link.get("direction_aligned")))
	_check(String(link.get("direction_note")) == "", "ohne_messung_keine_meldung",
		"note='%s'" % link.get("direction_note"))
	_check(bool(s.invert) == false, "ohne_messung_bleibt_die_richtung",
		"invert=%s" % s.invert)
	# Und ohne Lenkeinschlag erst recht nicht (Rad steht in der Mitte).
	_learn_center(link, wheel)
	_check(int(link.get("direction_aligned")) == -1,
		"in_der_mitte_keine_entscheidung",
		"direction_aligned=%d" % int(link.get("direction_aligned")))


func _aligned_axis_needs_invert() -> void:
	## DirectInput- und SDL-Achse laufen gleich: "Achse runter" ist links, die
	## positive Kraft faehrt dorthin - sie muss also umgedreht werden.
	var s = _settings(false, "auto")
	var wheel := FakeWheel.new()
	var link = _link(s, wheel)
	_learn_center(link, wheel)
	_feed(link, wheel, 0.4, CENTER + OFF)
	_check(int(link.get("direction_aligned")) == 1, "gleichlaeufig_erkannt",
		"direction_aligned=%d nach %d Stimmen" % [
			int(link.get("direction_aligned")), int(link.get("direction_samples"))])
	_check(bool(s.invert) == true, "gleichlaeufig_dreht_die_kraft_um",
		"invert=%s" % s.invert)
	_check(String(s.invert_source) == "gemessen", "die_herkunft_steht_in_der_datei",
		"invert_source=%s" % s.invert_source)
	_check(String(link.get("direction_note")).contains("umgekehrt"),
		"das_hud_sagt_es", "'%s'" % link.get("direction_note"))


func _opposite_axis_needs_no_invert() -> void:
	## Achsen gegenlaeufig: "Achse runter" ist rechts, die positive Kraft faehrt
	## dorthin - dann ist nichts umzudrehen.
	var s = _settings(true, "auto")
	var wheel := FakeWheel.new()
	var link = _link(s, wheel)
	_learn_center(link, wheel)
	_feed(link, wheel, 0.4, CENTER - OFF)
	_check(int(link.get("direction_aligned")) == 0, "gegenlaeufig_erkannt",
		"direction_aligned=%d" % int(link.get("direction_aligned")))
	_check(bool(s.invert) == false, "gegenlaeufig_laesst_die_kraft_in_ruhe",
		"invert=%s" % s.invert)
	_check(String(link.get("direction_note")).contains("normal"),
		"das_hud_sagt_es_auch_hier", "'%s'" % link.get("direction_note"))


func _a_driver_choice_is_not_overwritten() -> void:
	var s = _settings(true, "fahrer")
	var wheel := FakeWheel.new()
	var link = _link(s, wheel)
	_check(not bool(link.get("auto_direction")), "fahrerwahl_schaltet_die_automatik_aus",
		"auto_direction=%s" % link.get("auto_direction"))
	_learn_center(link, wheel)
	_feed(link, wheel, 0.4, CENTER - OFF)
	_check(int(link.get("direction_aligned")) == -1, "keine_messung_gegen_den_fahrer",
		"direction_aligned=%d" % int(link.get("direction_aligned")))
	_check(bool(s.invert) == true, "die_richtung_des_fahrers_bleibt",
		"invert=%s (vom Fahrer)" % s.invert)


func _never_flip_in_the_middle_of_a_corner() -> void:
	var s = _settings(false, "auto")
	var wheel := FakeWheel.new()
	var link = _link(s, wheel)
	_learn_center(link, wheel)
	# Im Bogen liegt Kraft am Rad: die Entscheidung faellt, aber sie wird nicht
	# angewandt - ein Vorzeichenwechsel dort waere ein Ruck.
	link.last_state = {"torque": 0.62}
	_feed(link, wheel, 0.4, CENTER + OFF)
	_check(int(link.get("direction_aligned")) == 1, "im_bogen_wird_gemessen",
		"direction_aligned=%d" % int(link.get("direction_aligned")))
	_check(bool(s.invert) == false, "im_bogen_kein_vorzeichenwechsel",
		"invert=%s bei Kraft %.2f" % [s.invert, float(link.last_state.get("torque"))])
	# Sobald das Rad leicht ist, wird es gesetzt.
	link.last_state = {"torque": 0.05}
	link.measure_direction(1.0 / 60.0)
	_check(bool(s.invert) == true, "auf_der_geraden_wird_es_gesetzt",
		"invert=%s" % s.invert)
	_check(String(link.get("direction_note")) != "", "und_gemeldet",
		"'%s'" % link.get("direction_note"))
