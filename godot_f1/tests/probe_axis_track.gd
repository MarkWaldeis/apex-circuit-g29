extends SceneTree
## Achse ueber laengere Zeit mitschreiben - fuer die Frage, ob Spiel und
## Kraft-Helfer dasselbe Lenkrad gleichzeitig benutzen koennen.
##
## `tests/probe_axis_read.gd` laeuft 8 s; das genuegt nicht, wenn der Helfer
## erst *waehrend* des Spiels startet (die realistische Reihenfolge: der Fahrer
## startet das Spiel, dann den Helfer). Dieses Skript schreibt 30 s lang jede
## Sekunde die rohe Lenkachse und die Zahl der Achsenbewegungen.
##
## Fensterlauf (headless zaehlt Godot keine Joysticks auf):
##   powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 \
##       --script tests/probe_axis_track.gd
##
## Ausgabe: AXIS_TRACK t=.. device=.. a0=.. span=.. data=..

const SECONDS := 30.0

var main: Node3D
var g29
var elapsed: float = 0.0
var printed: int = 0
var minimum: float = INF
var maximum: float = -INF


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
		print("AXIS_TRACK FAIL kein G29Input")
		quit(1)
		return
	print("AXIS_TRACK device=%s connected=%s" % [
		str(g29.get("device_name")), str(g29.get("connected"))])
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	var snap: PackedFloat32Array = g29.axis_snapshot() if g29.has_method("axis_snapshot") else PackedFloat32Array()
	var a0: float = float(snap[0]) if snap.size() > 0 else 0.0
	minimum = minf(minimum, a0)
	maximum = maxf(maximum, a0)
	elapsed += 1.0 / 90.0
	if elapsed >= float(printed + 1):
		printed += 1
		print("AXIS_TRACK t=%02d device=%s a0=%+.3f span=%.3f data=%s" % [
			printed, str(g29.get("device_name")), a0, maximum - minimum,
			str(g29.has_axis_data() if g29.has_method("has_axis_data") else "?")])
	if elapsed >= SECONDS:
		print("AXIS_TRACK Ende span=%.3f data=%s" % [
			maximum - minimum,
			str(g29.has_axis_data() if g29.has_method("has_axis_data") else "?")])
		quit(0)
