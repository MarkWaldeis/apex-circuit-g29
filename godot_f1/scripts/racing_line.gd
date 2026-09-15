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
