extends SceneTree
## Was schickt das Spiel in jeder Fahrsituation WIRKLICH - mit den
## Standard-Einstellungen des Menues (Staerke 75 %, Daempfung MITTEL,
## Baender 100 %)?
##
## `tools/g29_ffb.py --demo` behauptet, "genau die Zahlen" zu spielen, die
## `ffb_model.gd` dort liefert (siehe Kommentar ueber `DEMO_STAGES`). Diese
## Datei macht daraus eine Messung: sie faehrt dieselben Situationen durch das
## Modell und druckt das Paket, das der Helfer bekommen wuerde. Die Zahlen in
## `DEMO_STAGES` stammen aus genau diesem Lauf.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_demo_stages.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

const KERB := {"surface": 1, "name": "Kerb", "rumble": 0.75, "rough": 0.55, "grip": 0.94}
const GRAVEL := {"surface": 2, "name": "Kies", "rumble": 0.45, "rough": 0.70, "grip": 0.46}
const ASPHALT := {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0}

var model


func _initialize() -> void:
	# Standard-Einstellungen: nichts von Hand setzen ausser auto_save aus.
	var s := Settings.new()
	s.auto_save = false
	model = Model.new()
	model.setup(s)
	print("---- FFB_DEMO (Standard: Staerke %.0f %%, Daempfung %.2f, Baender je %.0f %%) ----" % [
		s.gain * 100.0, s.damper, s.ontrack_effects * 100.0])
	_stage("Geradeaus, Schrittgeschwindigkeit", _ctx({
		"speed": 3.0, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.0,
		"lateral_g": 0.0, "downforce": 1.0, "throttle": 0.0}))
	_stage("Geradeaus 250 km/h", _ctx({
		"speed": 69.4, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.01,
		"lateral_g": 0.1, "downforce": 2.9, "throttle": 1.0}))
	_stage("Schneller Bogen, 3,2 g bei 250 km/h", _corner({"speed": 69.4}))
	_stage("Untersteuern: Vorderachse geht weg", _corner({
		"speed": 69.4, "slip_front": 0.32, "understeer": 0.85, "lateral_g": 2.4}))
	_stage("Kerb bei 120 km/h", _corner({"speed": 33.3, "surface": KERB}))
	_stage("Kies bei 120 km/h", _corner({"speed": 33.3, "surface": GRAVEL}))
	_stage("Gras bei 120 km/h", _corner({"speed": 33.3, "surface":
		{"surface": 3, "name": "Gras", "rumble": 0.30, "rough": 0.50, "grip": 0.30}}))
	_stage("Vollbremsung, Vorderraeder blockieren", _corner({
		"speed": 45.0, "brake": 0.95, "slip_front": 0.10, "steer_angle": -0.16}))
	_stage("Kuppe (Vorderachse hebt ab)", _corner({"speed": 69.4, "vertical_g": 0.30}))
	_stage("Bodenwelle", _corner({"speed": 60.0}), {"bump": 0.55})
	_stage("Raeder drehen durch (Traktion aus)", _corner({
		"speed": 45.0, "oversteer": 0.55, "throttle": 1.0, "traction_control": false,
		"slip_rear": 0.30}))
	_stage("Schaltstoss in der Kurve", _corner({"speed": 60.0}), {"shift": 0.45})
	_stage("Schaltstoss auf der Geraden (kein Lenkbefehl)", _ctx({
		"speed": 60.0, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.01,
		"lateral_g": 0.1, "throttle": 1.0}), {"shift": 0.45})
	_stage("Einschlag in die Wand (voll)", _corner({"speed": 50.0}), {"crash": 1.0})
	_stage("Einschlag auf der Geraden (kein Lenkbefehl)", _ctx({
		"speed": 50.0, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.01,
		"lateral_g": 0.1, "throttle": 0.8}), {"crash": 1.0})
	_stage("Unwucht nach mittlerem Schaden, 230 km/h", _ctx({
		"speed": 64.0, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.01,
		"lateral_g": 0.1, "downforce": 2.8, "throttle": 1.0, "damage": 0.44}))
	_stage("Rangieren am Lenkanschlag (Soft Lock)", _ctx({
		"speed": 2.0, "steer": 1.0, "steer_angle": 0.0, "slip_front": 0.0,
		"lateral_g": 0.0, "downforce": 1.0, "throttle": 0.2, "lock_pressure": 1.0}))
	_stage("Loslassen (Stillstand, kein Motor)", _ctx({
		"speed": 0.0, "steer": 0.0, "steer_angle": 0.0, "slip_front": 0.0,
		"lateral_g": 0.0, "downforce": 1.0, "throttle": 0.0}))
	print("---- ENDE FFB_DEMO ----")
	quit(0)


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"steer": 0.0, "steer_angle": 0.0, "slip_front": 0.0, "slip_rear": 0.0,
		"lateral_g": 0.0, "yaw_rate": 0.0, "speed": 30.0, "downforce": 2.6,
		"understeer": 0.0, "oversteer": 0.0, "brake": 0.0, "throttle": 0.7,
		"lock_pressure": 0.0, "vertical_g": 1.0, "damage": 0.0,
		"traction_control": true, "surface": ASPHALT,
	}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx


## Ein normaler Rechtsbogen (Lenkbefehl +1 = rechts).
func _corner(overrides: Dictionary = {}) -> Dictionary:
	return _ctx(_merged({
		"steer": 1.0, "steer_angle": -0.10, "slip_front": 0.075, "slip_rear": 0.03,
		"lateral_g": 3.2, "speed": 69.4, "downforce": 2.9, "throttle": 0.6,
	}, overrides))


func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate()
	for key in extra:
		out[key] = extra[key]
	return out


func _stage(label: String, ctx: Dictionary, poke: Dictionary = {}) -> void:
	for i in 60:
		model.update(1.0 / 90.0, ctx)
	if poke.has("shift"):
		model.poke("shift", float(poke["shift"]))
	if poke.has("crash"):
		model.poke("crash", float(poke["crash"]))
	if poke.has("bump"):
		model.poke("bump", float(poke["bump"]))
	var st: Dictionary = model.update(1.0 / 90.0, ctx)
	print("%-45s {%s}" % [label, _dict(st)])


## Genau die Felder, die im Paket an den Helfer stehen - copy-paste-faehig.
func _dict(st: Dictionary) -> String:
	var parts: Array = []
	for key in ["torque", "damper", "friction", "rumble", "rumble_hz", "pulse", "pulse_dir"]:
		parts.append("\"%s\": %.3f" % [key, float(st[key])])
	parts.append("\"source\": \"%s\"" % String(st["source"]))
	return ", ".join(parts)
