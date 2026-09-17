extends SceneTree
## Measures the imported steering-wheel GLB exactly as the cockpit camera sees
## it: subtree bounds, node scale, material names and the resulting on-screen
## footprint for a given lens distance / FOV / wheel width.

const MODELS := [
	"res://assets/props/steering_wheel.glb",
	"res://assets/props/cockpit_wheel.glb",
]
const WANT_WIDTH := 0.30
const LENS_DISTANCE := 0.42
const FOV_DEG := 72.0


func _initialize() -> void:
	for path in MODELS:
		_report(path)
	quit(0)


func _local_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [{"node": node, "xf": Transform3D.IDENTITY}]
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var n: Node3D = item["node"]
		var xf: Transform3D = item["xf"]
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			var box: AABB = xf * mi.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
		for c in n.get_children():
			var c3 := c as Node3D
			if c3:
				stack.append({"node": c3, "xf": xf * c3.transform})
	return out


func _report(path: String) -> void:
	print("=== ", path)
	var packed: PackedScene = load(path)
	if packed == null:
		print("  LOAD FAILED")
		return
	var inst: Node3D = packed.instantiate()
	var root3 := inst as Node3D
	print("  root=", root3.name, " class=", root3.get_class(),
		" scale=", root3.scale, " pos=", root3.position, " rot=", root3.rotation_degrees)
	var b: AABB = _local_bounds(inst)
	print("  bounds min=", b.position, " size=", b.size, " centre=", b.get_center())
	var s: float = WANT_WIDTH / maxf(b.size.x, 0.0001)
	print("  scale for width ", WANT_WIDTH, " = ", s,
		" -> height ", b.size.y * s, " depth ", b.size.z * s)
	var half_h: float = LENS_DISTANCE * tan(deg_to_rad(FOV_DEG * 0.5))
	var half_w: float = half_h * (16.0 / 9.0)
	print("  visible at ", LENS_DISTANCE, " m: height ", half_h * 2.0, " width ", half_w * 2.0)
	print("  wheel would span ", snappedf(b.size.x * s / (half_w * 2.0) * 100.0, 0.1),
		" % of width, ", snappedf(b.size.y * s / (half_h * 2.0) * 100.0, 0.1), " % of height")
	_dump(inst, "  ")
	inst.free()


func _dump(node: Node, indent: String) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var mats: Array = []
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(i)
			mats.append(m.resource_name if m else "<none>")
		print(indent, mi.name, " surfs=", mi.mesh.get_surface_count(), " mats=", mats)
	for c in node.get_children():
		_dump(c, indent + "  ")
