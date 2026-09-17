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

	var min_y := INF
	var max_y := -INF
	var lowest := ""
	var too_close := 0
	var closest := INF
	for node in look.get_children():
		var prop := node as Node3D
		if prop == null:
			continue
		var box: AABB = look._aabb(prop)
		var y: float = prop.global_position.y + box.position.y * prop.scale.y
		min_y = minf(min_y, y)
		if y > max_y:
			max_y = y
			lowest = prop.name
		# distance to the racing line (horizontal)
		var best := INF
		for p in line.points:
			best = minf(best, Vector2(p.x, p.z).distance_to(Vector2(prop.global_position.x, prop.global_position.z)))
		closest = minf(closest, best)
		if best < 9.0:
			too_close += 1
	print("PROBE props=", placed, " lowest_base_y=%.2f" % min_y, " highest_base_y=%.2f" % max_y,
		" (", lowest, ")")
	print("PROBE closest_prop_to_racing_line=%.2f m  inside_road=%d" % [closest, too_close])
	quit(0)
