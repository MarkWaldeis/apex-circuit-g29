extends SceneTree
## Diagnose: steht in der Nähe jedes Streckenpunkts wirklich nur EINE Wand,
## und wie weit ist sie von der Ideallinie weg? Die Strecke faltet sich bei
## Start/Ziel, deshalb kann die Wand eines anderen Streckenteils genau dort
## landen, wo man sie nicht erwartet.
##
##   godot --headless --path godot_f1 --script tests/probe_barrier_geometry.gd

const RacingLine = preload("res://scripts/racing_line.gd")
const Surfaces = preload("res://scripts/surfaces.gd")

var line = RacingLine.new()
var main: Node3D


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	line.load_json("res://assets/track/racing_line.json")
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	var barriers: Node3D = main.get_node_or_null("Barriers")
	if barriers == null:
		print("PROBE no Barriers node")
		quit(1)
		return
	var boxes: Array = []
	for c in barriers.get_children():
		boxes.append(c.global_position)
	print("PROBE boxes=%d" % boxes.size())
	for i in [150, 300, 600, 900, 1200, 1380]:
		var here: Vector3 = line.points[i]
		var left: Vector3 = line.left_at(i)
		var near: Array = []
		for p in boxes:
			var d: float = Vector2(p.x, p.z).distance_to(Vector2(here.x, here.z))
			if d < 26.0:
				var offset: float = left.dot(p - here)
				near.append([d, offset])
		near.sort_custom(func(a, b): return a[0] < b[0])
		# signed offset of each near box: positive = the wall on the LEFT side
		var line_desc: Array = []
		for e in near.slice(0, 4):
			line_desc.append("d=%.1f off=%+.1f" % [e[0], e[1]])
		print("PROBE i=%d near boxes %d: %s" % [i, near.size(), ", ".join(line_desc)])
	# Wie nah kommt ein Auto an i=300, das 15,6 m links fährt, an die
	# nächste Box (egal welcher Streckenteil)?
	var idx := 300
	var here2: Vector3 = line.points[idx]
	var left2: Vector3 = line.left_at(idx)
	var probe: Vector3 = here2 + left2 * 15.6
	var best := INF
	var best_off := 0.0
	var best_len := 0.0
	for c in barriers.get_children():
		var d: float = Vector2(c.global_position.x, c.global_position.z).distance_to(
			Vector2(probe.x, probe.z))
		if d < best:
			best = d
			best_off = left2.dot(c.global_position - here2)
			best_len = float(c.shape.size.z)
	print("PROBE at i=%d offset 15.6: nearest box centre %.2f m away, lateral %+.2f m, box length %.1f"
		% [idx, best, best_off, best_len])
	quit(0)
