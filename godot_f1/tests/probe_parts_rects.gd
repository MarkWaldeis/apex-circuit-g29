extends SceneTree
## Objective cockpit measurement: the exact screen rectangle of every cockpit
## group, measured by turning one group off at a time and diffing the rendered
## frame against a proven-stable baseline.
##
## The old wheel measurement in capture_cockpit.gd reported the whole frame
## (x=0..1919) because something else in the scene kept changing between the
## two pictures. This harness removes that failure mode: it freezes the car,
## the AI car, the cockpit camera and the mirror sub-viewports, then proves the
## baseline is stable by capturing two frames with nothing changed at all and
## requiring their difference to be exactly zero. Only then does it measure.
##
## Run in a window (headless has no rendered image):
##   godot --path godot_f1 --resolution 1920x1080 --script tests/probe_parts_rects.gd

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"
const SETTLE := 3          ## frames to wait after a visibility change

## Target frame positions read off the F1 cockpit reference picture (percent of
## frame width / height). tests/reference_landmarks.json documents how they were
## measured. A group is "in frame" when its rect is within one percent of these.
var targets := {
	"Halo": {"x0": 8.0, "x1": 92.0, "y0": 11.0, "y1": 21.5},
	"Wheel": {"x0": 27.0, "x1": 73.0, "y0": 53.0, "y1": 100.0},
	"Dash": {"x0": 34.0, "x1": 66.0, "y0": 39.0, "y1": 54.0},
	"Mirror_L": {"x0": 0.0, "x1": 15.0, "y0": 38.0, "y1": 52.0},
	"Mirror_R": {"x0": 85.0, "x1": 100.0, "y0": 38.0, "y1": 52.0},
}

var main: Node3D
var player
var cam
var frames: int = 0
var _base: Image
var _plan: Array = []
var _op: int = 0
var _settle: int = 0
var _results: Dictionary = {}
var _shot_index: int = 0
var _stability_diff: int = -1


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames == 40:
		_freeze_everything()
		return
	if frames < 60:
		return
	if _plan.is_empty():
		_plan = _build_plan()
		_settle = SETTLE
		return
	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_act()
		return
	if _op >= _plan.size():
		_report()
		quit(0)


## Freeze every source of change, so two consecutive frames are identical.
func _freeze_everything() -> void:
	var menu = main.get("menu")
	if menu and menu.has_method("resume_game"):
		menu.resume_game()
	player = main.get("player")
	cam = main.get("cam")
	var ai = main.get("ai_car")
	if player:
		player.freeze = true
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.set_physics_process(false)
		player.set_process(false)
		# The wheels roll from the body speed; with the body frozen that is
		# zero, but stop the wheel telemetry as well so nothing at all moves.
		player.engine_force = 0.0
		player.brake = 0.0
	if ai:
		ai.visible = false
		ai.freeze = true
		ai.set_physics_process(false)
		ai.set_process(false)
	if cam:
		# Stop the camera after its field of view has finished easing.
		cam.set_process(false)
		cam.set_physics_process(false)
		if cam.get("mirrors") != null:
			for m in cam.mirrors:
				if m:
					m.set_process(false)


func _groups() -> Array:
	## Named cockpit groups, resolved fresh every time so the harness keeps
	## working while the cockpit is being rebuilt.
	var out: Array = []
	var cockpit: Node = cam.get("cockpit")
	if cockpit == null:
		return out
	var named := {
		"Halo": ["Halo", "HaloRing"],
		"Dash": ["Dash"],
		"Tub": ["Tub"],
		"WheelModel": ["WheelModel"],
		"Hands": ["Hands"],
		"Mirror_L": ["Mirror_L"],
		"Mirror_R": ["Mirror_R"],
		"SteeringWheel": ["SteeringWheel"],
	}
	for key in named.keys():
		for candidate in named[key]:
			var n: Node = cockpit.get_node_or_null(candidate)
			if n:
				out.append({"name": key, "node": n})
				break
	return out


func _build_plan() -> Array:
	## Capture the baseline, prove it is stable, then one off/on pair per group.
	## A "set" step only changes visibility; the capture happens in the NEXT
	## step, so the rendered frame already contains the change. Taking the
	## picture in the same step as the change would only ever record the frame
	## from before it - which is exactly how the old harness ended up reporting
	## the whole frame as the wheel.
	var plan: Array = [
		{"set": null, "capture": "baseline"},
		{"set": null, "capture": "stability"},
	]
	for g in _groups():
		plan.append({"set": [g, false], "capture": "", "group": g})
		plan.append({"set": null, "capture": "measure", "group": g})
		plan.append({"set": [g, true], "capture": "", "group": g})
		plan.append({"set": null, "capture": "restore", "group": g})
	return plan


func _act() -> void:
	## Apply this step's visibility change, take the picture, evaluate it.
	if _op >= _plan.size():
		return
	var step: Dictionary = _plan[_op]
	if step["set"] != null:
		var pair: Array = step["set"]
		var g: Dictionary = pair[0]
		var node: Node = g["node"]
		if is_instance_valid(node):
			node.visible = bool(pair[1])
	match String(step["capture"]):
		"baseline":
			_base = _grab()
			_base.save_png(OUT_DIR + "/parts_baseline_a.png")
		"stability":
			var again: Image = _grab()
			again.save_png(OUT_DIR + "/parts_baseline_b.png")
			_stability_diff = _diff_count(_base, again)
			print("STABILITY two untouched frames differ in ", _stability_diff,
				" pixels -> ", "IDENTICAL" if _stability_diff == 0 else "UNSTABLE")
		"measure":
			var off: Image = _grab()
			_shot_index += 1
			var gname: String = step["group"]["name"]
			off.save_png(OUT_DIR + "/parts_%02d_%s_off.png" % [_shot_index, gname])
			_results[gname] = _rect_of_difference(_base, off)
		"restore":
			var back: Image = _grab()
			var gname2: String = step["group"]["name"]
			var d: int = _diff_count(_base, back)
			print("RESTORE %-12s -> %d pixels differ from the baseline" % [gname2, d])
	_op += 1
	_settle = SETTLE


func _rect_of_difference(a: Image, b: Image) -> Dictionary:
	## Raw-byte comparison: get_pixel() per pixel costs minutes at 1080p.
	var w: int = a.get_width()
	var h: int = a.get_height()
	var pa: PackedByteArray = _rgb_bytes(a)
	var pb: PackedByteArray = _rgb_bytes(b)
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	var count := 0
	for y in h:
		var row: int = y * w * 3
		for x in w:
			var i: int = row + x * 3
			var d: int = absi(pa[i] - pb[i]) + absi(pa[i + 1] - pb[i + 1]) + absi(pa[i + 2] - pb[i + 2])
			if d > 20:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				count += 1
	if max_x < 0:
		return {"found": false}
	return {
		"found": true,
		"x0": float(min_x) / float(w) * 100.0,
		"x1": float(max_x) / float(w) * 100.0,
		"y0": float(min_y) / float(h) * 100.0,
		"y1": float(max_y) / float(h) * 100.0,
		"px": count,
		"area": float(count) / float(w * h) * 100.0,
	}


func _diff_count(a: Image, b: Image) -> int:
	var pa: PackedByteArray = _rgb_bytes(a)
	var pb: PackedByteArray = _rgb_bytes(b)
	var w: int = a.get_width()
	var h: int = a.get_height()
	var count := 0
	var n: int = w * h * 3
	var i := 0
	while i < n:
		if absi(pa[i] - pb[i]) + absi(pa[i + 1] - pb[i + 1]) + absi(pa[i + 2] - pb[i + 2]) > 2:
			count += 1
		i += 3
	return count


func _rgb_bytes(img: Image) -> PackedByteArray:
	var copy := Image.new()
	copy.copy_from(img)
	copy.convert(Image.FORMAT_RGB8)
	return copy.get_data()


func _grab() -> Image:
	return get_root().get_viewport().get_texture().get_image()


func _report() -> void:
	print("")
	print("STABILITY_DIFF ", _stability_diff)
	print("PARTS name        x%          y%          area%   target x%      target y%")
	for key in _results.keys():
		var r: Dictionary = _results[key]
		var t: Dictionary = targets.get(key, {})
		if not r.get("found", false):
			print("PARTS %-12s NOT FOUND" % key)
			continue
		var tx := "%.0f..%.0f" % [t["x0"], t["x1"]] if t.has("x0") else "-"
		var ty := "%.0f..%.0f" % [t["y0"], t["y1"]] if t.has("y0") else "-"
		var dx := ""
		if t.has("x0"):
			dx = "  dx %+.1f %+.1f" % [r["x0"] - t["x0"], r["x1"] - t["x1"]]
		var dy := ""
		if t.has("y0"):
			dy = "  dy %+.1f %+.1f" % [r["y0"] - t["y0"], r["y1"] - t["y1"]]
		print("PARTS %-12s %5.1f..%5.1f %5.1f..%5.1f %6.2f   %-13s %-13s%s%s" % [
			key, r["x0"], r["x1"], r["y0"], r["y1"], r["area"], tx, ty, dx, dy])
