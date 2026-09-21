extends SceneTree
## Root-Diagnose 21.09.2026: sieht Godot/SDL die Lenkachse, *waehrend* der
## FFB-Helfer das Rad exklusiv haelt und eine Kraft anlegt?
##
## Fragen, die dieser Lauf beantwortet:
##   1. Kommen waehrend einer laufenden Kraft ueberhaupt Achsdaten an?
##   2. Bewegt sich die Achse bei 0.70 Kraft (die 0.35 des alten Tests waren
##      vielleicht unter der Haftreibung des Rades)?
##   3. Ist die Bewegung monoton zur Kraft (also automatisch auswertbar)?
##
## Ausgabe je 0.5 s: DIR t=.. raw=.. torque=.. data=..
## Fensterlauf (headless zaehlt Godot keine Joysticks auf):
##   powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 \
##       --script tests/probe_root_dir.gd

const PHASES := [
	{"torque": 0.0, "seconds": 2.0},
	{"torque": 0.7, "seconds": 4.0},
	{"torque": 0.0, "seconds": 2.0},
	{"torque": -0.7, "seconds": 4.0},
	{"torque": 0.0, "seconds": 2.0},
]

var main: Node3D
var g29
var ffb
var elapsed: float = 0.0
var phase: int = 0
var phase_elapsed: float = 0.0
var print_elapsed: float = 0.0
var last_raw: float = 0.0
var seen: Array = []


func _initialize() -> void:
	OS.set_environment("APEX_G29_PROFILE", "user://g29_profile_diag.json")
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	g29 = main.get("g29")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	var player = main.get("player")
	if player == null or g29 == null:
		print("DIR FAIL no player/wheel")
		quit(1)
		return
	player.auto_drive = true
	ffb = player.get("ffb")
	if ffb == null:
		print("DIR FAIL no ffb")
		quit(1)
		return
	for i in PHASES.size():
		seen.append([])
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	var dt: float = 1.0 / 90.0
	elapsed += dt
	phase_elapsed += dt
	print_elapsed += dt
	var current: Dictionary = PHASES[phase]
	ffb.force_torque_override = float(current["torque"])
	var snap: PackedFloat32Array = g29.axis_snapshot() if g29.has_method("axis_snapshot") else PackedFloat32Array()
	if snap.size() > 0:
		last_raw = float(snap[0])
		var bucket: Array = seen[phase]
		bucket.append(last_raw)
	if print_elapsed >= 0.5:
		print_elapsed = 0.0
		print("DIR t=%.1f phase=%d torque=%+.2f a0=%+.3f a1=%+.3f a2=%+.3f a3=%+.3f data=%s" % [
			elapsed, phase, float(current["torque"]),
			float(snap[0]) if snap.size() > 0 else 0.0,
			float(snap[1]) if snap.size() > 1 else 0.0,
			float(snap[2]) if snap.size() > 2 else 0.0,
			float(snap[3]) if snap.size() > 3 else 0.0,
			str(g29.has_axis_data() if g29.has_method("has_axis_data") else "?")])
	if phase_elapsed >= float(current["seconds"]):
		var bucket: Array = seen[phase]
		var lo: float = 9.0
		var hi: float = -9.0
		for v in bucket:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		print("DIR_MEAN phase=%d torque=%+.2f n=%d min=%+.3f max=%+.3f" % [
			phase, float(current["torque"]), bucket.size(),
			lo if bucket.size() > 0 else 0.0, hi if bucket.size() > 0 else 0.0])
		phase += 1
		phase_elapsed = 0.0
		if phase >= PHASES.size():
			ffb.force_torque_override = 0.0
			print("DIR done")
			quit(0)
