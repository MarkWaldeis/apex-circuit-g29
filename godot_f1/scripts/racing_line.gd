extends RefCounted

const BlenderXform = preload("res://scripts/blender_xform.gd")

var points: PackedVector3Array = PackedVector3Array()
var tangents: PackedVector3Array = PackedVector3Array()
var s: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0


func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Racing line missing: " + path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Racing line JSON invalid")
		return false
	var data: Dictionary = parsed
	length = float(data.get("length", 0.0))
	points.clear()
	tangents.clear()
	s.clear()
	for item in data.get("points", []):
		var p: Dictionary = item
		points.append(BlenderXform.vec(float(p.x), float(p.y), float(p.z)))
		var t := BlenderXform.vec(float(p.tx), float(p.ty), float(p.tz))
		if t.length() < 0.0001:
			t = Vector3(0, 0, -1)
		tangents.append(t.normalized())
		s.append(float(p.s))
	if points.size() < 8:
		push_error("Racing line too short")
		return false
	if length <= 0.0:
		length = s[s.size() - 1]
	print("RacingLine loaded %s pts, %.1f m" % [points.size(), length])
	return true


func closest_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func point_at_s(dist: float) -> Vector3:
	var target := fposmod(dist, length)
	var n := s.size()
	for i in n:
		var i2 := (i + 1) % n
		var s1: float = s[i]
		var s2: float = s[i2]
		if i2 == 0:
			s2 = length
		if target >= s1 and target <= s2:
			var span: float = max(s2 - s1, 0.0001)
			var u: float = (target - s1) / span
			return points[i].lerp(points[i2], u)
	return points[0]


func tangent_at_index(i: int) -> Vector3:
	return tangents[wrapi(i, 0, tangents.size())]


func point_ahead(pos: Vector3, look_ahead: float) -> Vector3:
	var i := closest_index(pos)
	return point_at_s(s[i] + look_ahead)


func curvature_ahead(pos: Vector3, look_ahead: float) -> float:
	var i := closest_index(pos)
	var a: Vector3 = tangents[i]
	var j := wrapi(i + 12, 0, tangents.size())
	var b: Vector3 = tangents[j]
	return abs(a.signed_angle_to(b, Vector3.UP))


## --- shared geometry helpers ------------------------------------------------
##
## Everything that has to know "where am I on the track, and how far to the
## side" (surface model, ideal line, AI, displays) goes through these, so the
## convention is defined in exactly one place.
##
## The line in `racing_line.json` is the geometric CENTRE of the 12 m road; it
## is not an ideal line. Lateral offsets are therefore measured from the centre
## and, later, compared against the road/kerb/runoff widths.

## Nearest point to `pos`, searched only in a window around `hint`.
##
## The full search is 1440 points and this runs for every car on every physics
## tick, so the window matters. If the best hit sits on the edge of the window
## the car has moved further than the window is wide and the honest full search
## runs instead.
func closest_index_near(pos: Vector3, hint: int, span: int = 64) -> int:
	var n := points.size()
	if n == 0:
		return 0
	if hint < 0 or hint >= n:
		return closest_index(pos)
	var best := hint
	var best_d: float = points[hint].distance_squared_to(pos)
	for k in range(1, span + 1):
		var ahead := wrapi(hint + k, 0, n)
		var d_ahead: float = points[ahead].distance_squared_to(pos)
		if d_ahead < best_d:
			best_d = d_ahead
			best = ahead
		var behind := wrapi(hint - k, 0, n)
		var d_behind: float = points[behind].distance_squared_to(pos)
		if d_behind < best_d:
			best_d = d_behind
			best = behind
	if posmod(best - hint, n) >= span or posmod(hint - best, n) >= span:
		return closest_index(pos)
	return best


## Tangent at `i`, flattened to the ground plane and normalised.
func flat_tangent(i: int) -> Vector3:
	var t: Vector3 = tangents[wrapi(i, 0, tangents.size())]
	t.y = 0.0
	if t.length() < 0.001:
		t = Vector3(0, 0, -1)
	return t.normalized()


## Unit vector pointing to the driver's LEFT when travelling along the line.
func left_at(i: int) -> Vector3:
	return Vector3.UP.cross(flat_tangent(i)).normalized()


## Signed lateral distance of `pos` from the line at point `i`.
## Positive = the car sits to the LEFT of its direction of travel.
func offset_at(pos: Vector3, i: int) -> float:
	var j := wrapi(i, 0, points.size())
	return (pos - points[j]).dot(left_at(j))


## One call that returns everything the callers need: where on the line we are,
## how far to the side, and the local direction frame.
func frame_at(pos: Vector3, hint: int = -1) -> Dictionary:
	var i := closest_index_near(pos, hint) if hint >= 0 else closest_index(pos)
	var local_offset := offset_at(pos, i)
	var flat := pos - points[i]
	flat.y = 0.0
	var along := flat.dot(flat_tangent(i))
	return {
		"index": i,
		"offset": local_offset,
		"tangent": flat_tangent(i),
		"left": left_at(i),
		"along": along,
		"s": s[i] + along,
	}


## Total curvature (1/m) of the centre line around point `i`.
##
## Used to compare the ideal line against the centre line and to sanity check
## that the ideal line is really smoother.
func curvature_at(i: int, window: int = 8) -> float:
	var n := points.size()
	var a: Vector3 = flat_tangent(wrapi(i - window, 0, n))
	var b: Vector3 = flat_tangent(wrapi(i + window, 0, n))
	var ds: float = maxf(
		absf(s[wrapi(i + window, 0, n)] - s[wrapi(i, 0, n)])
		+ absf(s[wrapi(i, 0, n)] - s[wrapi(i - window, 0, n)]),
		0.0001)
	return a.signed_angle_to(b, Vector3.UP) / ds
