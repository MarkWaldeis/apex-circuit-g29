extends SceneTree
## Diagnostic: where does the imported GLB actually put the car's nose in
## Godot space, and where is the cockpit relative to the wheels?

const CAR_PATH := "res://assets/cars/car_crimson.glb"
const RIG_PATH := "res://assets/cars/car_rig.json"


func _initialize() -> void:
	# global_position is only valid once the instance is really in the tree, so
	# measure deferred - reading it here printed (0, 0, 0) for every wheel and
	# made the probe claim the wrong nose side.
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(CAR_PATH)
	if packed == null:
		push_error("PROBE cannot load %s" % CAR_PATH)
		quit(1)
		return
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	print("PROBE root children:")
	for c in inst.get_children():
		print("  ", c.name, " type=", c.get_class())
	var visual: Node3D = inst.get_child(0) if inst.get_child_count() > 0 else null
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var n := _find_token(inst, key)
		if n == null:
			print("PROBE ", key, " MISSING")
			continue
		var p: Vector3 = n.global_position
		print("PROBE ", key, " pos=", p, " -> nose side is ", ("-Z" if p.z < 0.0 else "+Z"))
	var body := _find_token(inst, "Body")
	if body is MeshInstance3D and body.mesh:
		var aabb: AABB = body.mesh.get_aabb()
		print("PROBE body local aabb=", aabb, " end=", aabb.end, " size=", aabb.size)
	# Cockpit / driver head sits between the front and rear wheels, closer to the
	# front on an F1 car; the cockpit camera must land over that region.
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	print("PROBE rig wheels (blender space y): FL=", rig["wheels"]["Wheel_FL"]["location"][1],
		" RL=", rig["wheels"]["Wheel_RL"]["location"][1])
	print("PROBE aabb_min=", rig["aabb_min"], " aabb_max=", rig["aabb_max"])
	quit(0)


func _find_token(node: Node, token: String) -> Node3D:
	if token in node.name and node is Node3D:
		return node as Node3D
	for c in node.get_children():
		var r := _find_token(c, token)
		if r:
			return r
	return null
