extends SceneTree
## Welle 9: Welche Quelle ist am Lenkrad wirklich die lauteste - und was
## passiert einem Stoss, wenn kein Lenkbefehl anliegt?
##
## Zwei Behauptungen aus dem Code/Dokument werden hier nachgerechnet, statt
## geglaubt zu werden:
##
##   1. "Der Kerb bleibt immer das lauteste Geraeusch am Lenkrad." Der
##      Kommentar in `ffb_model.gd` sagte das - gemessen stimmt es nur oberhalb
##      einer bestimmten Geschwindigkeit, weil die Unwucht nach einem Einschlag
##      *dauerhaft* anliegt (es gibt im Spiel keine Werkstatt) und der Kerb
##      seine Amplitude erst mit dem Tempo aufbaut.
##   2. "Ein Schaltstoss ist ein harter Anschlag." Auf der Geraden setzt
##      `g29_input.gd` die Lenkung per Totzone auf genau 0.0; der Stoss bekam
##      dadurch das Vorzeichen 0 und kam am Lenkrad als **0,000** an (gemessen
##      in `tools/g29_ffb.py --check`). Diese Datei zeigt, welche Werte das
##      Modell in dieser Situation liefert - der Helfer macht daraus seit dem
##      Fix ein Klopfen.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_wave9_loudness.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const KERB := {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}
const GRAVEL := {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}

var model


func _initialize() -> void:
	var s := Settings.new()
	s.auto_save = false
	s.invert = false
	model = Model.new()
	model.setup(s)
	print("---- FFB_LAUTSTAERKE ----")
	_sweep()
	_who_leads()
	_pulse_without_steering()
	print("---- ENDE FFB_LAUTSTAERKE ----")
	quit(0)


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"steer": -0.5, "steer_angle": -0.09, "slip_front": 0.07, "slip_rear": 0.05,
		"lateral_g": 3.0, "yaw_rate": 0.1, "speed": 30.0, "downforce": 2.6,
		"understeer": 0.0, "oversteer": 0.0, "brake": 0.0, "throttle": 0.7,
		"lock_pressure": 0.0, "vertical_g": 1.0, "damage": 0.0,
		"traction_control": true,
		"surface": {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0},
	}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx


func _settle(ctx: Dictionary, ticks: int = 40) -> Dictionary:
	var out: Dictionary = {}
	for i in ticks:
		out = model.update(1.0 / 90.0, ctx)
	return out


## Kerb gegen Wrack-Unwucht bei gleichem Tempo: wer gewinnt?
func _sweep() -> void:
	print("Tempo   Kerb             Wrack (Schaden 1,0)   Gewinner")
	for kmh in [40.0, 80.0, 108.0, 140.0, 162.0, 200.0, 250.0]:
		var v: float = kmh / 3.6
		var kerb: Dictionary = _settle(_ctx({"speed": v, "surface": KERB, "damage": 0.0}))
		var wreck: Dictionary = _settle(_ctx({"speed": v, "surface": KERB, "damage": 1.0}))
		print("%5.0f   %.3f @ %2.0f Hz    %.3f @ %2.0f Hz        %s" % [
			kmh, float(kerb["rumble"]), float(kerb["rumble_hz"]),
			float(wreck["rumble"]), float(wreck["rumble_hz"]),
			String(wreck["source"])])
	# Und die saubere Trennung auf blankem Asphalt: dort gibt es keinen Kerb,
	# der die Unwucht uebertoenen koennte.
	var road: Dictionary = _settle(_ctx({"speed": 30.0, "surface":
		{"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0}}))
	var road_wreck: Dictionary = _settle(_ctx({"speed": 30.0, "damage": 1.0, "surface":
		{"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0}}))
	print("Asphalt 108 km/h: heil %.3f (%s) -> Wrack %.3f (%s)" % [
		float(road["rumble"]), String(road["source"]),
		float(road_wreck["rumble"]), String(road_wreck["source"])])
	print("Kies 108 km/h: %s" % _one_line(30.0, GRAVEL, 1.0))


func _one_line(v: float, surface: Dictionary, damage: float) -> String:
	var st: Dictionary = _settle(_ctx({"speed": v, "surface": surface, "damage": damage}))
	return "%.3f @ %.0f Hz (%s)" % [float(st["rumble"]), float(st["rumble_hz"]), String(st["source"])]


## Wer fuehrt auf welcher Oberflaeche, wenn das Rad ein Wrack ist?
##
## Die Regel: **die Oberflaeche, die man befaehrt, uebertoent die Unwucht nie.**
## Auf Asphalt gibt es keine Oberflaechenquelle - dort ist die Unwucht das
## einzige Signal und damit deutlich zu spueren.
func _who_leads() -> void:
	print("108 km/h, Schaden 1,0 (Wrack) - wer fuehrt?")
	for entry in [["Asphalt", _ctx({})["surface"]], ["Kerb", KERB], ["Kies", GRAVEL],
			["Gras", {"surface": 3, "name": "Gras", "rumble": 0.30, "rough": 0.50, "grip": 0.30}]]:
		var st: Dictionary = _settle(_ctx({"speed": 30.0, "surface": entry[1], "damage": 1.0}))
		print("  %-8s %.3f @ %2.0f Hz   Quelle %s" % [
			entry[0], float(st["rumble"]), float(st["rumble_hz"]), String(st["source"])])


## Ein Stoss, wenn kein Lenkbefehl anliegt: was liefert das Modell?
func _pulse_without_steering() -> void:
	var straight: Dictionary = _ctx({
		"steer": 0.0, "steer_angle": 0.0, "slip_front": 0.01, "lateral_g": 0.1,
		"speed": 55.0, "throttle": 1.0})
	_settle(straight)
	model.poke("crash", 1.0)
	var hit: Dictionary = model.update(1.0 / 90.0, straight)
	print("Einschlag bei stehendem Rad (steer 0.0): pulse %.2f, pulse_dir %+.2f, Quelle %s" % [
		float(hit["pulse"]), float(hit["pulse_dir"]), String(hit["source"])])
	_settle(straight)
	model.poke("shift", 0.45)
	var shift: Dictionary = model.update(1.0 / 90.0, straight)
	print("Schalten bei stehendem Rad (steer 0.0): pulse %.2f, pulse_dir %+.2f, Quelle %s" % [
		float(shift["pulse"]), float(shift["pulse_dir"]), String(shift["source"])])
	# Zum Vergleich: in der Kurve traegt der Stoss das Vorzeichen des
	# Lenkbefehls (gegen den Lenkbefehl) - die Regel, die vorher auch auf der
	# Geraden galt und dort auf 0 fiel.
	var corner: Dictionary = _ctx({"steer": -0.5})
	_settle(corner)
	model.poke("shift", 0.45)
	var in_corner: Dictionary = model.update(1.0 / 90.0, corner)
	print("Schalten in der Kurve (steer -0.5): pulse %.2f, pulse_dir %+.2f" % [
		float(in_corner["pulse"]), float(in_corner["pulse_dir"])])
