extends SceneTree
## Loads the driver's REAL profile against the REAL wheel and reports what the
## game makes of it: are the stored points plausible, does the rest position
## match the live device, and do the pedals read idle while untouched?
## Run windowed: godot --path godot_f1 --resolution 320x200 --script tests/probe_g29_profile.gd

const G29 = preload("res://scripts/g29_input.gd")

var g
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	g = G29.new()
	g.auto_load_profile = true          # the real user://g29_profile.json
	root.add_child(g)
	print("PROFILE loaded=", g._profile_loaded, " gas_axis=", g.throttle_axis,
		" brake_axis=", g.brake_axis, " clutch_axis=", g.clutch_axis,
		" steer_axis=", g.steer_axis, " steer_invert=", g.steer_invert)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames % 60 != 0:
		return
	var t: float = float(frames) / 60.0
	print("PROFILE t=%.1fs Gas=%.0f%% Bremse=%.0f%% Kupplung=%.0f%% Lenkung=%+.2f have_data=%s" % [
		t, g.throttle * 100.0, g.brake * 100.0, g.clutch * 100.0, g.steer, g._have_data])
	if t >= 6.0:
		print("PROFILE points gas=%.2f..%.2f brake=%.2f..%.2f clutch=%.2f..%.2f steer_rest=%.3f span=%.3f" % [
			float(g._pedal_rest.get("throttle", 0.0)), float(g._pedal_press.get("throttle", 0.0)),
			float(g._pedal_rest.get("brake", 0.0)), float(g._pedal_press.get("brake", 0.0)),
			float(g._pedal_rest.get("clutch", 0.0)), float(g._pedal_press.get("clutch", 0.0)),
			g._steer_rest, g._steer_span])
		quit(0)
