extends RefCounted
## Solid walls where the circuit's barriers stand.
##
## The exported track carries the barrier artwork (`COL_BarrierInner` /
## `COL_BarrierOuter`) but no physics at all, so today a car can drive straight
## through them. 16 m from the centre line (BARRIER_OFFSET), 1.15 m tall and
## ~8 m long boxes overlap into a continuous wall that follows the line.
##
## OWNER: agent CRASH.

const Surfaces = preload("res://scripts/surfaces.gd")

const STEP := 6             ## line points between two boxes (6 x 1.15 m ≈ 6.9 m)
const BOX_LENGTH := 9.0     ## slightly longer than the step, so there are no gaps
const BOX_THICKNESS := 0.6
const BOX_HEIGHT := 1.15
const Y_CENTER := 0.55      ## wall centre above the road surface
## A wall has to stay this far away from the racing surface of EVERY part of
## the circuit, not just from its own. Half the road is 6 m.
const CLEARANCE := 7.0


## Builds both walls and returns how many boxes were created.
static func build(parent: Node3D, line, layer: int = 1) -> int:
	if line == null or line.points.size() < 8:
		push_warning("Barriers: no racing line")
		return 0
	var body := StaticBody3D.new()
	body.name = "Barriers"
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	var n: int = line.points.size()
	var made := 0
	var skipped := 0
	for side in [1.0, -1.0]:
		var i := 0
		while i < n:
			var t: Vector3 = line.flat_tangent(i)
			var left: Vector3 = line.left_at(i)
			var pos: Vector3 = line.points[i] + left * (side * Surfaces.BARRIER_OFFSET)
			# The circuit folds back on itself at the start/finish: the T9 exit
			# runs right beside the main straight, so the T9 wall would be
			# placed ON the main straight and the car would hit it while
			# driving away from the grid (measured: a box 3.8 m from the
			# player at the start). Anything that ends up on another part of
			# the track is dropped instead of being turned into a physics wall.
			if _distance_to_line(line, pos) < CLEARANCE:
				skipped += 1
				i += STEP
				continue
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(BOX_THICKNESS, BOX_HEIGHT, BOX_LENGTH)
			col.shape = box
			var basis := Basis.looking_at(-t, Vector3.UP)
			col.transform = Transform3D(basis, pos + Vector3(0.0, Y_CENTER, 0.0))
			col.set_meta("barrier_side", side)
			body.add_child(col)
			made += 1
			i += STEP
	print("Barriers ", made, " boxes, ", skipped, " skipped (would sit on the track)")
	return made


## Shortest horizontal distance from `pos` to any point of the racing line.
##
## No index window is excluded on purpose: the wall stands 16 m off its own
## stretch, so its own points are never the close ones - but the lap's end (T9)
## and its start (main straight) sit right next to each other in index space,
## which is exactly the trap this test has to catch.
static func _distance_to_line(line, pos: Vector3) -> float:
	var n: int = line.points.size()
	var best := INF
	var here := Vector2(pos.x, pos.z)
	for j in n:
		var p: Vector3 = line.points[j]
		var d: float = here.distance_squared_to(Vector2(p.x, p.z))
		if d < best:
			best = d
	return sqrt(best)
