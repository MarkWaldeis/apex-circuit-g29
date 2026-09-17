extends SceneTree
## Cockpit frame-metrics probe.
##
## Drives the real scene, switches to the helmet cam and reports where every
## cockpit part actually lands in the frame, in percent of the viewport, next to
## the values measured on the reference cockpit picture. It also fires a ray
## through a few sample pixels and names the mesh it hits, which is how a stray
## object in the sky gets identified instead of guessed at.
##
## Run (needs a window, headless cannot rasterise 3D):
##   godot --path <project> --script res://tests/probe_cockpit_metrics.gd

const VIEW := Vector2i(1920, 1080)
const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures/diag"

## Values read off the reference cockpit picture with a 10 % grid.
const REF := {
	"WheelModel": {"x0": 27.0, "x1": 68.0, "y0": 55.5, "y1": 100.0},
	"Dash": {"x0": 37.0, "x1": 64.0, "y0": 40.0, "y1": 53.0},
	"HaloBar": {"x0": 0.0, "x1": 100.0, "y0": 12.5, "y1": 19.0},
	"Mirror_L": {"x0": 0.0, "x1": 13.0, "y0": 38.0, "y1": 51.0},
	"Mirror_R": {"x0": 87.0, "x1": 100.0, "y0": 38.0, "y1": 51.0},
	"Hand_L": {"x0": 27.0, "x1": 42.0, "y0": 60.0, "y1": 82.0},
	"Hand_R": {"x0": 58.0, "x1": 73.0, "y0": 60.0, "y1": 82.0},
}

## Pixels to identify: (label, fraction of width, fraction of height).
const SAMPLES := [
	["sky-above-halo-centre", 0.50, 0.09],
	["halo-bar-centre", 0.50, 0.185],
	["through-wheel-centre", 0.50, 0.75],
	["left-mirror-glass", 0.055, 0.44],
	["track-ahead", 0.50, 0.33],
]

var main: Node3D
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	root.size = VIEW
	DisplayServer.window_set_size(VIEW)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames == 20:
		var m = main.get("menu")
		if m and m.has_method("resume_game"):
			m.resume_game()
	if frames < 120:
		return
	_report()
	_save("cockpit_metrics.png")
	quit(0)


func _save(file_name: String) -> void:
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/%s" % [OUT_DIR, file_name])
	print("saved %s/%s" % [OUT_DIR, file_name])


func _report() -> void:
	var cam: Camera3D = main.get("cam")
	if cam == null:
		print("no camera")
		return
	var cockpit: Node3D = cam.get("cockpit")
	print("viewport: %s   camera fov=%.1f   cockpit cam current=%s" % [
		str(root.size), cam.fov, str(cam.current)])
	print("")
	print("part            x0      x1      y0      y1     | reference      verdict")
	print("-------------------------------------------------------------------------------")
	var names := ["SteeringWheel/WheelModel", "SteeringWheel/Hand_L", "SteeringWheel/Hand_R",
		"Dash", "Halo/HaloBar", "Halo/HaloPod", "Mirror_L", "Mirror_R", "Tub",
		"SteeringWheel"]
	for path in names:
		var node: Node3D = _find(cockpit, path)
		if node == null:
			print("%-15s MISSING" % path)
			continue
		var r: Dictionary = _screen_rect(cam, node)
		var key: String = path.get_file()
		if key == "WheelModel":
			key = "WheelModel"
		var verdict: String = ""
		if REF.has(key):
			var ref: Dictionary = REF[key]
			verdict = "dx0 %+5.1f dx1 %+5.1f dy0 %+5.1f dy1 %+5.1f  ref x %.0f..%.0f y %.0f..%.0f" % [
				r["x0"] - float(ref["x0"]), r["x1"] - float(ref["x1"]),
				r["y0"] - float(ref["y0"]), r["y1"] - float(ref["y1"]),
				ref["x0"], ref["x1"], ref["y0"], ref["y1"]]
		print("%-15s %6.1f  %6.1f  %6.1f  %6.1f  | %s" % [
			key, r["x0"], r["x1"], r["y0"], r["y1"], verdict])
	print("")
	print("wheel width %.1f %% of frame (reference %.1f %%)" % [
		float(_screen_rect(cam, _find(cockpit, "SteeringWheel/WheelModel"))["x1"])
		- float(_screen_rect(cam, _find(cockpit, "SteeringWheel/WheelModel"))["x0"]),
		float(REF["WheelModel"]["x1"]) - float(REF["WheelModel"]["x0"])])
	print("")
	for s in SAMPLES:
		_identify(cam, float(s[2]), float(s[1]), String(s[0]))
	print("")
	_visibility_probe()


## Hide one candidate at a time and read the pixel back: that is what settles
## "which object is that shape in the sky" without guessing.
func _visibility_probe() -> void:
	var candidates := [
		"Player/Visual", "Player/CockpitCam/Cockpit/Halo",
		"Player/CockpitCam/Cockpit/Tub", "Player/CockpitCam/Cockpit/Dash",
		"Track",
	]
	print("colour probe (r,g,b) at the sample pixels:")
	var base: Image = _frame()
	print("  %-22s %s" % ["nothing hidden", _colours(base)])
	for path in candidates:
		var node: Node = main.get_node_or_null(NodePath(path))
		if node == null:
			print("  %-22s MISSING" % path)
			continue
		var was: bool = node.visible
		node.visible = false
		var img: Image = _frame()
		print("  %-22s %s" % ["hide " + path, _colours(img)])
		node.visible = was
	_frame()


func _frame() -> Image:
	RenderingServer.force_draw()
	return root.get_texture().get_image()


func _colours(img: Image) -> String:
	var out: Array = []
	for s in SAMPLES:
		var px := Vector2i(int(float(s[1]) * float(VIEW.x)), int(float(s[2]) * float(VIEW.y)))
		var c: Color = img.get_pixel(px.x, px.y)
		out.append("%d,%d,%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)])
	return " | ".join(out)


## What does the pixel at (fx, fy) of the frame actually show?
func _identify(cam: Camera3D, fy: float, fx: float, label: String) -> void:
	var px := Vector2(fx * float(VIEW.x), fy * float(VIEW.y))
	var origin: Vector3 = cam.project_ray_origin(px)
	var dir: Vector3 = cam.project_ray_normal(px)
	var hits: Array = []
	for mi in _all_meshes(main):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		var t: float = _ray_aabb(origin, dir, aabb)
		# A mesh whose box already contains the lens (the ground, the runoff,
		# the tub) reports t=0 and would always win. Only real entries count.
		if t > 0.02 and t < 400.0:
			hits.append({"t": t, "name": _path_of(mi, main)})
	hits.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var parts: Array = []
	for i in mini(4, hits.size()):
		parts.append("%s@%.1fm" % [String(hits[i]["name"]), float(hits[i]["t"])])
	print("pixel %-24s (%4.0f,%4.0f) -> %s" % [
		label, px.x, px.y, "none" if parts.is_empty() else ", ".join(parts)])


func _all_meshes(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi and mi.mesh and mi.is_visible_in_tree():
			out.append(mi)
		for c in n.get_children():
			stack.append(c)
	return out


func _path_of(node: Node, until: Node) -> String:
	var parts: Array = []
	var n: Node = node
	while n and n != until:
		parts.append(String(n.name))
		n = n.get_parent()
	parts.reverse()
	return "/".join(parts)


## Slab-method ray/AABB. Returns the entry distance or -1.
func _ray_aabb(o: Vector3, d: Vector3, b: AABB) -> float:
	var lo: float = 0.0
	var hi: float = INF
	for axis in 3:
		var dv: float = d[axis]
		var ov: float = o[axis]
		var bmin: float = b.position[axis]
		var bmax: float = bmin + b.size[axis]
		if absf(dv) < 1e-9:
			if ov < bmin or ov > bmax:
				return -1.0
			continue
		var t0: float = (bmin - ov) / dv
		var t1: float = (bmax - ov) / dv
		if t0 > t1:
			var tmp: float = t0
			t0 = t1
			t1 = tmp
		lo = maxf(lo, t0)
		hi = minf(hi, t1)
		if lo > hi:
			return -1.0
	return lo


func _find(parent: Node, path: String) -> Node3D:
	if parent == null:
		return null
	return parent.get_node_or_null(NodePath(path)) as Node3D


## Screen-space rectangle (percent of viewport) of every mesh under `node`.
func _screen_rect(cam: Camera3D, node: Node3D) -> Dictionary:
	var x0: float = INF
	var x1: float = -INF
	var y0: float = INF
	var y1: float = -INF
	var found: bool = false
	for mi in _all_meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		for i in 8:
			var corner: Vector3 = aabb.position + Vector3(
				aabb.size.x * float(i & 1),
				aabb.size.y * float((i >> 1) & 1),
				aabb.size.z * float((i >> 2) & 1))
			if cam.is_position_behind(corner):
				continue
			var p: Vector2 = cam.unproject_position(corner)
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
			found = true
	if not found:
		return {"x0": 0.0, "x1": 0.0, "y0": 0.0, "y1": 0.0}
	return {
		"x0": x0 / float(VIEW.x) * 100.0,
		"x1": x1 / float(VIEW.x) * 100.0,
		"y0": y0 / float(VIEW.y) * 100.0,
		"y1": y1 / float(VIEW.y) * 100.0,
	}
