extends SceneTree
## Liest nur die Lenkradachsen - ohne Kraft, ohne Fahren.
##
## Damit laesst sich von aussen pruefen, ob Godot/SDL die Achse ueberhaupt
## sieht: erst mit freiem Lenkrad, dann mit laufendem FFB-Helfer (der das Rad
## exklusiv per DirectInput haelt). Fensterlauf, weil headless keine Joysticks
## aufgezaehlt werden:
##
##   powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 `
##       --script tests/probe_axis_read.gd
##
## Ausgabe je Sekunde: AXIS_READ t=.. a0=.. a1=.. a2=.. a3=.. data=..

const SECONDS := 8.0

var main: Node3D
var g29
var elapsed: float = 0.0
var printed: int = 0
var minima: Array = []
var maxima: Array = []


func _initialize() -> void:
	# Diagnoselauf: das echte Profil des Fahrers bleibt unberuehrt.
	OS.set_environment("APEX_G29_PROFILE", "user://g29_profile_diag.json")
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	g29 = main.get("g29")
	if g29 == null:
		print("AXIS_READ FAIL kein G29Input")
		quit(1)
		return
	print("AXIS_READ device=", g29.get("device_name"), " connected=", g29.get("connected"))
	for i in 4:
		minima.append(INF)
		maxima.append(-INF)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	var snap: PackedFloat32Array = g29.axis_snapshot() if g29.has_method("axis_snapshot") else PackedFloat32Array()
	if snap.size() >= 4:
		for i in 4:
			minima[i] = minf(float(minima[i]), snap[i])
			maxima[i] = maxf(float(maxima[i]), snap[i])
	elapsed += 1.0 / 90.0
	if elapsed >= float(printed + 1):
		printed += 1
		print("AXIS_READ t=%d a0=%+.3f a1=%+.3f a2=%+.3f a3=%+.3f data=%s" % [
			printed,
			snap[0] if snap.size() > 0 else 0.0,
			snap[1] if snap.size() > 1 else 0.0,
			snap[2] if snap.size() > 2 else 0.0,
			snap[3] if snap.size() > 3 else 0.0,
			str(g29.has_axis_data() if g29.has_method("has_axis_data") else "?")])
	if elapsed >= SECONDS:
		print("AXIS_READ Spanne a0 %.3f..%.3f a1 %.3f..%.3f a2 %.3f..%.3f a3 %.3f..%.3f data=%s" % [
			float(minima[0]), float(maxima[0]), float(minima[1]), float(maxima[1]),
			float(minima[2]), float(maxima[2]), float(minima[3]), float(maxima[3]),
			str(g29.has_axis_data() if g29.has_method("has_axis_data") else "?")])
		quit(0)
