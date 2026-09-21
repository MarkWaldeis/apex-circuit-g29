extends SceneTree
## Die drei Ruettel-Baender wirken **einzeln** - das verspricht das Menue dem
## Fahrer ("den Kerb leiser stellen laesst das Kies-Mahlen stehen").
##
## Warum es diesen Test gibt: die Einstellungen selbst wurden geprueft
## (`test_ffb_settings.gd`: Werte, Stufen, Menue), und `ffb_model.gd` rechnet
## die Baender in einer Zeile - aber **kein** Test hat bisher gemessen, was
## passiert, wenn man *ein* Band zudreht: bleibt das andere stehen? Genau das
## ist die Zusage an den Fahrer, und genau das ist die Stelle, an der eine
## falsche Klammer alles still macht.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 `
##       --script tests/test_ffb_bands.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const ASPHALT := {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0}
const KERB := {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}
const GRAVEL := {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}
const GRASS := {"surface": 3, "name": "Gras", "rumble": 0.30, "rough": 0.50, "grip": 0.30}

var failed: int = 0


func _initialize() -> void:
	# Ein ruhiger Rechtsbogen bei 120 km/h: dieselbe Fahrt, nur die Oberflaeche
	# und die Band-Regler aendern sich.
	var base := {
		"steer": 1.0, "steer_angle": -0.10, "slip_front": 0.075, "slip_rear": 0.03,
		"lateral_g": 2.0, "speed": 33.3, "downforce": 1.8, "understeer": 0.0,
		"oversteer": 0.0, "brake": 0.0, "throttle": 0.6, "lock_pressure": 0.0,
		"traction_control": true, "damage": 0.0,
	}
	var full: Dictionary = _measure(base, 1.0, 1.0, 1.0)
	_print_row("alle Baender 100 %", full)
	_check(float(full["Kerb"]) > float(full["Kies"])
		and float(full["Kies"]) > float(full["Gras"])
		and float(full["Gras"]) > 0.0,
		"die_drei_oberflaechen_sind_verschieden_laut",
		"Kerb %.3f > Kies %.3f > Gras %.3f" % [
			float(full["Kerb"]), float(full["Kies"]), float(full["Gras"])])

	# 1. Kerb-Band zu: Kerb muss verstummen, Kies und Gras bleiben stehen.
	var no_kerb: Dictionary = _measure(base, 1.0, 0.0, 1.0)
	_print_row("Kerb-Band 0 %", no_kerb)
	_check(float(no_kerb["Kerb"]) <= 0.01, "kerb_ist_stumm_wenn_sein_band_zu_ist",
		"%.3f" % float(no_kerb["Kerb"]))
	_check(is_equal_approx(float(no_kerb["Kies"]), float(full["Kies"]))
		and is_equal_approx(float(no_kerb["Gras"]), float(full["Gras"])),
		"kerb_leiser_macht_kies_und_gras_nicht_leiser",
		"Kies %.3f statt %.3f, Gras %.3f statt %.3f" % [
			float(no_kerb["Kies"]), float(full["Kies"]),
			float(no_kerb["Gras"]), float(full["Gras"])])

	# 2. Off-Track-Band zu: Kies und Gras verstummen, Kerb bleibt.
	var no_off: Dictionary = _measure(base, 1.0, 1.0, 0.0)
	_print_row("Off-Track-Band 0 %", no_off)
	_check(float(no_off["Kies"]) <= 0.01 and float(no_off["Gras"]) <= 0.01,
		"kies_und_gras_sind_stumm_wenn_das_off_track_band_zu_ist",
		"Kies %.3f, Gras %.3f" % [float(no_off["Kies"]), float(no_off["Gras"])])
	_check(is_equal_approx(float(no_off["Kerb"]), float(full["Kerb"])),
		"kies_leiser_macht_den_kerb_nicht_leiser",
		"Kerb %.3f statt %.3f" % [float(no_off["Kerb"]), float(full["Kerb"])])

	# 3. On-Track-Band zu: die Asphalt-Textur verschwindet (sie ist ohnehin
	#    leise), Kerb und Kies bleiben.
	var asphalt_full: Dictionary = _measure(base, 1.0, 1.0, 1.0)
	var no_track: Dictionary = _measure(base, 0.0, 1.0, 1.0)
	_print_row("On-Track-Band 0 %", no_track)
	_check(float(no_track["Asphalt"]) <= 0.01,
		"asphalt_textur_ist_stumm_wenn_ihr_band_zu_ist",
		"%.3f" % float(no_track["Asphalt"]))
	_check(is_equal_approx(float(no_track["Kerb"]), float(asphalt_full["Kerb"]))
		and is_equal_approx(float(no_track["Kies"]), float(asphalt_full["Kies"])),
		"asphalt_leiser_macht_kerb_und_kies_nicht_leiser")

	# 4. Hauptschalter aus: alles stumm, und zwar unabhaengig von den Baendern.
	var off: Dictionary = _measure(base, 1.0, 1.0, 1.0, false)
	_print_row("Ruetteln AUS", off)
	_check(float(off["Kerb"]) <= 0.001 and float(off["Kies"]) <= 0.001
		and float(off["Gras"]) <= 0.001 and float(off["Asphalt"]) <= 0.001,
		"der_hauptschalter_macht_alles_stumm")

	if failed > 0:
		print("FFB_BANDS FAIL count=%d" % failed)
		quit(1)
	else:
		print("FFB_BANDS PASS")
		quit(0)


## Ein Lauf je Oberflaeche mit den gegebenen Band-Reglern; gibt die hoechste
## Ruettel-Amplitude zurueck, die das Modell fuer diese Oberflaeche liefert.
func _measure(base: Dictionary, ontrack: float, kerb: float, offtrack: float,
		effects: bool = true) -> Dictionary:
	var settings := Settings.new()
	settings.auto_save = false
	settings.gain = 1.0
	settings.damper = 1.0
	settings.invert = false
	settings.effects = effects
	settings.ontrack_effects = ontrack
	settings.kerb_effects = kerb
	settings.offtrack_effects = offtrack
	var model := Model.new()
	model.setup(settings)
	var out: Dictionary = {}
	for entry in [["Asphalt", ASPHALT], ["Kerb", KERB], ["Kies", GRAVEL], ["Gras", GRASS]]:
		var ctx: Dictionary = base.duplicate()
		ctx["surface"] = entry[1]
		var level: float = 0.0
		# Einschwingen abwarten: der Glaetter braucht ein paar Ticks.
		for i in 60:
			var state: Dictionary = model.update(1.0 / 90.0, ctx)
			level = maxf(level, float(state["rumble"]))
		out[entry[0]] = level
	return out


func _print_row(label: String, row: Dictionary) -> void:
	print("FFB_BANDS %-20s Asphalt %.3f  Kerb %.3f  Kies %.3f  Gras %.3f" % [
		label, float(row["Asphalt"]), float(row["Kerb"]),
		float(row["Kies"]), float(row["Gras"])])


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1
