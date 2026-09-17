extends SceneTree
## End-to-end check of the real input module against the real wheel:
## prints, in German-friendly numbers, what the module makes of the live axes.
## Run windowed (headless does not enumerate joysticks):
##   godot --path godot_f1 --resolution 320x200 --script tests/probe_g29_module.gd

const G29 = preload("res://scripts/g29_input.gd")

var g
var frames: int = 0
const STEPS := 12   ## ~6 seconds at 60 Hz


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	g = G29.new()
	# never touch the user's saved profile from a diagnostic
	g.auto_load_profile = false
	g.profile_path = "user://g29_probe_profile.json"
	root.add_child(g)
	print("G29_MODULE connected=", g.connected, " name=", g.device_name)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames % 30 != 0:
		return
	if frames / 30 > STEPS:
		print("G29_MODULE done")
		quit(0)
		return
	var raw: PackedFloat32Array = g.axis_snapshot()
	var raw_txt := ""
	for i in 4:
		raw_txt += " a%d=%+.2f" % [i, raw[i]]
	print("G29_MODULE t=%.1fs Gas=%.0f%% Bremse=%.0f%% Kupplung=%.0f%% Lenkung=%+.2f  live=%s%s" % [
		float(frames) / 60.0, g.throttle * 100.0, g.brake * 100.0, g.clutch * 100.0,
		g.steer, g.axes_live, raw_txt])
