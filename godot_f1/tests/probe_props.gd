extends SceneTree
## Diagnostic: are the trackside props actually standing on the ground, and do
## they stay clear of the racing surface? Run headless after any look.gd change.

const RacingLine = preload("res://scripts/racing_line.gd")
const Look = preload("res://scripts/look.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var line = RacingLine.new()
	line.load_json("res://assets/track/racing_line.json")
	var look := Look.new()
	world.add_child(look)
	var placed: int = look.build(line, world)

	var worst: Array = []
	var min_y := INF
	var max_y := -INF
	var lowest := ""
	var too_close := 0
	var closest := INF
	for node in look.get_children():
		var prop := node as Node3D
		if prop == null:
			continue
		var box: AABB = look._local_bounds(prop)
		# The instance origin is deliberately shifted so the artwork lands on the
		# intended spot, so measure the geometry, not the node origin.
		# global_transform already contains the instance scale - do not apply it
		# a second time.
		var world_min: Vector3 = prop.global_transform * box.position
		var world_centre: Vector3 = prop.global_transform * box.get_center()
		var y: float = world_min.y
		min_y = minf(min_y, y)
		if y > max_y:
			max_y = y
			lowest = prop.name
		# distance to the racing line (horizontal)
		var best := INF
		for p in line.points:
			best = minf(best, Vector2(p.x, p.z).distance_to(Vector2(world_centre.x, world_centre.z)))
		worst.append({"name": prop.name, "d": best, "pos": world_centre})
		closest = minf(closest, best)
		if best < 9.0:
			too_close += 1
	print("PROBE props=", placed, " lowest_base_y=%.2f" % min_y, " highest_base_y=%.2f" % max_y,
		" (", lowest, ")")
	print("PROBE closest_prop_to_racing_line=%.2f m  inside_road=%d" % [closest, too_close])
	worst.sort_custom(func(a, b): return a["d"] < b["d"])
	for i in mini(5, worst.size()):
		var w: Dictionary = worst[i]
		print("PROBE near_%d %s d=%.2f pos=%s" % [i, w["name"], w["d"], w["pos"]])
		var prop: Node3D = look.get_node_or_null(NodePath(String(w["name"])))
		if prop:
			var b: AABB = look._local_bounds(prop)
			print("    node=%s local_centre=%s scale=%s world_centre=%s" % [
				prop.position, b.get_center(), prop.scale, prop.global_transform * b.get_center()])
	quit(0)
