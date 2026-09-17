extends RefCounted
## The line the driver should actually drive, plus the speed that belongs to it.
##
## OWNER: agent LINE. Right now this is a working skeleton: it follows the
## centre line and computes a first speed profile from its curvature, which is
## enough for the display and the AI to work while the real ideal line (apex
## clipping inside the corridor) is built. The API is fixed:
## docs/DRIVE_FEEL_PLAN.md.

const THROTTLE := 0
const LIFT := 1
const BRAKE := 2

const DEFAULT_PARAMS := {
	"lat_accel": 34.0,     ## m/s^2 of cornering grip the ideal line may use
	"brake_decel": 42.0,   ## m/s^2 the brakes can deliver
	"accel": 12.0,         ## m/s^2 the engine can deliver out of a corner
	"corridor": 4.6,       ## how far off the centre the line may move
}

var points: PackedVector3Array = PackedVector3Array()
var offsets: PackedFloat32Array = PackedFloat32Array()
var curvature: PackedFloat32Array = PackedFloat32Array()
var target_speed: PackedFloat32Array = PackedFloat32Array()
var phase: PackedInt32Array = PackedInt32Array()
var source_point_count: int = 0
var params: Dictionary = DEFAULT_PARAMS.duplicate()


func build(line, overrides: Dictionary = {}) -> bool:
	params = DEFAULT_PARAMS.duplicate()
	for k in overrides.keys():
		params[k] = overrides[k]
	if line == null or line.points.size() < 32:
		push_warning("IdealLine: racing line missing")
		return false
	source_point_count = line.points.size()
	points = PackedVector3Array()
	offsets = PackedFloat32Array()
	curvature = PackedFloat32Array()
	target_speed = PackedFloat32Array()
	phase = PackedInt32Array()
	var n: int = line.points.size()
	for i in n:
		points.append(line.points[i])
		offsets.append(0.0)
		curvature.append(_curvature(line, i))
	_speed_profile(line)
	print("IdealLine pts=%d max_k=%.4f" % [points.size(), _max_abs(curvature)])
	return true


func _curvature(line, i: int) -> float:
	var n: int = line.points.size()
	var a: Vector3 = line.flat_tangent(wrapi(i - 6, 0, n))
	var b: Vector3 = line.flat_tangent(wrapi(i + 6, 0, n))
	var ds: float = maxf(
		absf(line.s[wrapi(i + 6, 0, n)] - line.s[wrapi(i, 0, n)])
		+ absf(line.s[wrapi(i, 0, n)] - line.s[wrapi(i - 6, 0, n)]), 0.0001)
	return a.signed_angle_to(b, Vector3.UP) / ds


func _speed_profile(line) -> void:
	var n := points.size()
	target_speed.resize(n)
	phase.resize(n)
	var vmax: float = 96.0
	var lat: float = float(params["lat_accel"])
	for i in n:
		var k: float = absf(curvature[i])
		var v: float = vmax if k < 0.00005 else sqrt(lat / k)
		target_speed[i] = minf(v, vmax)
	_braking_pass(line)
	_accel_pass(line)
	for i in n:
		var nxt2: int = (i + 2) % n
		var need: float = target_speed[i] - target_speed[nxt2]
		if need > 1.2:
			phase[i] = BRAKE
		elif need > 0.15:
			phase[i] = LIFT
		else:
			phase[i] = THROTTLE


func _braking_pass(line) -> void:
	## Walk backwards so the car is already slow enough at every apex.
	var n := points.size()
	var brake: float = float(params["brake_decel"])
	for step in n:
		var i: int = n - 1 - step
		var nxt: int = (i + 1) % n
		var ds: float = maxf(line.s[nxt] - line.s[i], 0.2)
		target_speed[i] = minf(target_speed[i],
			sqrt(target_speed[nxt] * target_speed[nxt] + 2.0 * brake * ds))


func _accel_pass(line) -> void:
	## A straight must not stay limited by the corner before it.
	var n := points.size()
	var accel: float = float(params["accel"])
	for step in n:
		var i: int = step % n
		var prv: int = (i - 1 + n) % n
		var ds: float = maxf(line.s[i] - line.s[prv], 0.2)
		target_speed[i] = minf(target_speed[i],
			sqrt(target_speed[prv] * target_speed[prv] + 2.0 * accel * ds))


func _max_abs(values: PackedFloat32Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, absf(v))
	return m


func sample_ahead(pos: Vector3, look: float, hint: int = -1) -> Dictionary:
	var n := points.size()
	if n < 8:
		return {}
	var index: int = hint
	if index < 0:
		index = closest_index(pos)
	var scaled: float = float(index) * float(n) / maxf(float(source_point_count), 1.0)
	var ahead: float = look * float(n) / maxf(float(source_point_count), 1.0) / 1.15
	var i: int = wrapi(int(round(scaled + ahead)), 0, n)
	return {
		"point": points[i],
		"index": i,
		"tangent": tangent_at(i),
		"target_speed": target_speed[i],
		"phase": phase[i],
	}


func closest_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func closest_index_near(pos: Vector3, hint: int, span: int = 64) -> int:
	var n := points.size()
	if n == 0:
		return 0
	if hint < 0 or hint >= n:
		return closest_index(pos)
	var best := hint
	var best_d: float = points[hint].distance_squared_to(pos)
	for k in range(1, span + 1):
		var a: int = wrapi(hint + k, 0, n)
		var d_a: float = points[a].distance_squared_to(pos)
		if d_a < best_d:
			best_d = d_a
			best = a
		var b: int = wrapi(hint - k, 0, n)
		var d_b: float = points[b].distance_squared_to(pos)
		if d_b < best_d:
			best_d = d_b
			best = b
	if posmod(best - hint, n) >= span or posmod(hint - best, n) >= span:
		return closest_index(pos)
	return best


func tangent_at(i: int) -> Vector3:
	var n := points.size()
	var t: Vector3 = points[wrapi(i + 1, 0, n)] - points[wrapi(i - 1, 0, n)]
	t.y = 0.0
	if t.length() < 0.001:
		return Vector3(0, 0, -1)
	return t.normalized()


func braking_distance(index: int) -> float:
	var n := points.size()
	var total := 0.0
	var i := wrapi(index, 0, n)
	for _step in 400:
		var nxt: int = (i + 1) % n
		if phase[nxt] != BRAKE:
			break
		total += points[i].distance_to(points[nxt])
		i = nxt
	return total
