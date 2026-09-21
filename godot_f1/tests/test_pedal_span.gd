extends SceneTree
## Regressionstest: eine Kalibrierung mit unmoeglicher Pedal-Spannweite darf
## das Pedal nicht deckeln.
##
## Gefunden am 21.09.2026 im echten Fahrer-Profil
## (`user://g29_profile.json`):
##
##     "throttle_rest": 0.0, "throttle_press": -1.88281071186066
##
## Eine SDL-Achse laeuft von -1.0 bis +1.0. Eine Spannweite von 1.88 ist
## deshalb nie erreichbar: `clampf(dev / span, 0, 1)` bleibt bei
## 1.0 / 1.8828 = 0.531 stehen, und der Zweig "laengeren Weg lernen" kann
## nicht greifen, weil |dev| hoechstens 1.0 wird. Ergebnis: **Vollgas war
## unmoeglich**, das Auto hing bei 53 % Gaspedal.
##
## Die Werte stammen aus einer Kette von zwei Fehlern: ein Lauf am 17.09.
## schrieb Ruhepositionen von 1.0 statt 0.0 in das Profil
## (`g29_profile.json.polluted.bak`), und die Ruhe-Korrektur in
## `_anchor_auto_rest()` verschob danach den Presspunkt mit demselben
## Abstand, statt die unplausible Spannweite zu verwerfen.

const G29 = preload("res://scripts/g29_input.gd")

## Genau der Stand aus dem Fahrer-Profil.
const BAD := "user://g29_pedal_span_bad.json"
## Zum Vergleich: eine plausible Kalibrierung darf weiter benutzt werden.
const GOOD := "user://g29_pedal_span_good.json"
## Und ein Pedal ueber die ganze Achse (Ruhe +1.0, Druck -1.0) ebenfalls.
const FULL := "user://g29_pedal_span_full.json"

var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1
		print("FAIL ", label, " ", detail)


func _write(path: String, throttle_rest: float, throttle_press: float,
		brake_rest: float, brake_press: float) -> void:
	var data := {
		"version": 2,
		"device": "SIM WHEEL",
		"steer_axis": 0,
		"throttle_axis": 2,
		"brake_axis": 3,
		"clutch_axis": 1,
		"steer_invert": false,
		"steer_deadzone": 0.03,
		"steer_rest": 0.0,
		"steer_span": 1.0,
		"throttle_rest": throttle_rest,
		"throttle_press": throttle_press,
		"brake_rest": brake_rest,
		"brake_press": brake_press,
		"clutch_rest": 1.0,
		"clutch_press": 0.0,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _wheel(path: String):
	var g = G29.new()
	g.profile_path = path
	g.auto_load_profile = true
	g.enable_sim()
	root.add_child(g)
	return g


## G29-Ruhelage: Gas und Bremse auf 0.0, Kupplung oben auf 1.0.
func _released(g) -> void:
	for i in 8:
		g.sim_set(i, 0.0)
	g.sim_set(g.clutch_axis, 1.0)
	g.step(0.02)
	g.step(0.02)


func _run() -> void:
	_sanity_check_the_profile_really_caps_the_throttle()
	_control_a_plausible_calibration_still_counts()
	_control_a_full_axis_pedal_still_counts()

	if failed > 0:
		print("PEDAL_SPAN FAIL count=", failed)
		quit(1)
	else:
		print("PEDAL_SPAN PASS")
		quit(0)


func _sanity_check_the_profile_really_caps_the_throttle() -> void:
	_write(BAD, 0.0, -1.88281071186066, 0.0, -0.563454627990723)
	var g = _wheel(BAD)
	_released(g)

	g.sim_set(g.throttle_axis, -1.0)
	g.step(0.02)
	var gas: float = float(g.throttle)
	_check(gas >= 0.98, "vollgas_ist_mit_dem_kaputten_profil_erreichbar",
		"Gaspedal ganz gedrueckt -> %.2f (kaputt: 0.53)" % gas)

	g.sim_set(g.throttle_axis, 0.0)
	g.sim_set(g.brake_axis, -1.0)
	g.step(0.02)
	var brake: float = float(g.brake)
	_check(brake >= 0.98, "volla_bremse_ist_erreichbar",
		"Bremse ganz gedrueckt -> %.2f" % brake)

	# Ein Pedal, das mit -0.5 dasteht, muss ungefaehr halb gedrueckt sein -
	# die verworfenen Werte duerfen nicht durch eine Notkennlinie ersetzt
	# werden, die jedes Pedal sofort auf 100 % legt.
	g.sim_set(g.brake_axis, 0.0)
	g.sim_set(g.throttle_axis, -0.5)
	g.step(0.02)
	var half: float = float(g.throttle)
	_check(half > 0.3 and half < 0.75, "halbes_pedal_ist_ungefaehr_halb",
		"Gaspedal auf -0.50 -> %.2f" % half)

	# Und der Unsinn darf nicht wieder in die Datei zurueckgeschrieben werden.
	for i in 200:
		g.step(0.02)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ProjectSettings.globalize_path(BAD)))
	var press: float = 0.0
	if typeof(parsed) == TYPE_DICTIONARY:
		press = float((parsed as Dictionary).get("throttle_press", 0.0))
	_check(absf(press) <= 1.05, "die_unmoegliche_spannweite_wird_nicht_gespeichert",
		"throttle_press in der Datei: %.2f" % press)

	g.queue_free()


func _control_a_plausible_calibration_still_counts() -> void:
	## Gegenprobe: eine Kalibrierung, die auf die Achse passt, muss weiterhin
	## genau so wirken wie eingetragen - sonst haette der Fix die manuelle
	## Kalibrierung des Fahrers einfach abgeschaltet.
	_write(GOOD, 0.0, -1.0, 0.0, -1.0)
	var g = _wheel(GOOD)
	_released(g)

	g.sim_set(g.throttle_axis, -0.5)
	g.step(0.02)
	var half: float = float(g.throttle)
	_check(half > 0.45 and half < 0.55, "gespeicherte_kalibrierung_wird_benutzt",
		"Gaspedal auf -0.50 mit Kalibrierung 0.0 .. -1.0 -> %.2f" % half)

	g.sim_set(g.throttle_axis, -1.0)
	g.step(0.02)
	_check(float(g.throttle) >= 0.98, "vollgas_mit_plausibler_kalibrierung",
		"Gaspedal ganz gedrueckt -> %.2f" % float(g.throttle))
	g.queue_free()


func _control_a_full_axis_pedal_still_counts() -> void:
	## Gegenprobe zur Achspruefung: Ruhe +1.0 und Druck -1.0 ist eine gueltige
	## Bauart (klassisches DirectInput-Pedal, siehe
	## `tests/test_input_mapping.gd` -> `_pedal_polarities`). Die Pruefung darf
	## sie nicht verwerfen - nur Punkte *neben* der Achse sind unmoeglich.
	_write(FULL, 1.0, -1.0, 1.0, -1.0)
	var g = _wheel(FULL)
	for i in 8:
		g.sim_set(i, 0.0)
	g.sim_set(g.clutch_axis, 1.0)
	g.sim_set(g.throttle_axis, 1.0)
	g.sim_set(g.brake_axis, 1.0)
	g.step(0.02)
	g.step(0.02)
	_check(float(g.throttle) < 0.02, "ganze_achse_ruhe_ist_null",
		"Achse +1.00 -> %.2f" % float(g.throttle))
	g.sim_set(g.throttle_axis, 0.0)
	g.step(0.02)
	_check(absf(float(g.throttle) - 0.5) < 0.05, "ganze_achse_halb_ist_halb",
		"Achse 0.00 -> %.2f" % float(g.throttle))
	g.sim_set(g.throttle_axis, -1.0)
	g.step(0.02)
	_check(float(g.throttle) >= 0.98, "ganze_achse_druck_ist_voll",
		"Achse -1.00 -> %.2f" % float(g.throttle))
	g.queue_free()
