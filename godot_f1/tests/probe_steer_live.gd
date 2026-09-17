extends SceneTree
## Hardware probe: while `tools/g29_ffb.py` holds the wheel and drives it with
## force, does the game still READ that wheel? Prints the range of the steering
## value the game sees.
##
##   powershell -File tools/ffb_live_check.ps1

const FRAMES := 360

var main: Node3D
var frames: int = 0
var mn: float = 0.0
var mx: float = 0.0
var samples: int = 0
var axis_reports: int = 0
var last_axis: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var g29 = main.get("g29")
	if g29:
		var s: float = float(g29.get("steer"))
		mn = minf(mn, s)
		mx = maxf(mx, s)
		samples += 1
		var raw = g29.get("axis_reports")
		if raw != null:
			var n: int = int(raw)
			if n != last_axis:
				last_axis = n
				axis_reports = n
	if frames >= FRAMES:
		var g = main.get("g29")
		print("STEER_LIVE samples=%d min=%.3f max=%.3f span=%.3f connected=%s live=%s reports=%d" % [
			samples, mn, mx, mx - mn,
			str(g.get("connected")) if g else "?",
			str(g.get("axes_live")) if g else "?",
			axis_reports])
		if mx - mn > 0.12:
			print("STEER_LIVE PASS the game reads the wheel while force feedback is active")
		else:
			print("STEER_LIVE WARN the wheel did not move (or the game lost the device)")
		quit(0)
