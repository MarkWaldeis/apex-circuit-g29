extends SceneTree
## Framing solver: projects cockpit landmarks through a real Camera3D and
## numerically solves the layout constants (wheel distance + height, pitch) so
## the in-game view matches the reference cockpit picture.
##
## Reference measurements, read off a 10 % grid over the F1 2022 cockpit shot:
##   horizon (sky/ground boundary)   y = 30 %
##   wheel grips left / right edge   x = 27 % / 68 %   (width 41 %)
##   wheel top edge                  y = 55.5 %
##   wheel LED strip                 y = 56 .. 58 %
##   halo top bar                    y = 12.5 .. 19 %   (centre 15.75 %)
##   mirror glass centre             x = 5.8 % / 94 %, y = 44.5 %
##   dash panel                      x = 37 .. 64 %, y = 40 .. 53 %
##   hands grip the rim at 9 and 3 o'clock, roughly y = 60 .. 82 %

const VIEW := Vector2i(1920, 1080)
const ASPECT := 16.0 / 9.0

const HORIZON_Y := 30.0
const WHEEL_LEFT_X := 29.5
const WHEEL_TOP_Y := 55.5
const HALO_BAR_Y := 15.75
const MIRROR_Y := 44.5

var cam: Camera3D


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	root.size = VIEW
	var world := Node3D.new()
	root.add_child(world)
	cam = Camera3D.new()
	cam.near = 0.04
	cam.far = 2200.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	world.add_child(cam)
	cam.current = true

	for fov in [50.0, 54.0, 58.0, 62.0, 66.0]:
		_solve(fov, 1.29)
	for eye_y in [1.05, 1.12, 1.20, 1.29]:
		_solve(54.0, eye_y)
	quit(0)


func _place(eye: Vector3, look: Vector3) -> void:
	cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)


func _pct(local: Vector3) -> Vector2:
	var px: Vector2 = cam.unproject_position(cam.global_transform * local)
	return Vector2(px.x / float(VIEW.x) * 100.0, px.y / float(VIEW.y) * 100.0)


func _pct_world(world: Vector3) -> Vector2:
	var px: Vector2 = cam.unproject_position(world)
	return Vector2(px.x / float(VIEW.x) * 100.0, px.y / float(VIEW.y) * 100.0)


func _horizon_pct() -> float:
	## A point 200 m ahead *at eye height along the world horizontal* sits on the
	## horizon, so the row it projects to depends on the camera's pitch only.
	var xf: Transform3D = cam.global_transform
	var fwd: Vector3 = -xf.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.001:
		return 50.0
	var target: Vector3 = xf.origin + flat.normalized() * 200.0
	var px: Vector2 = cam.unproject_position(target)
	return px.y / float(VIEW.y) * 100.0


func _solve(fov: float, eye_y: float) -> void:
	cam.fov = fov
	var eye := Vector3(0.0, eye_y, 0.05)

	# 1) pitch (downward tilt in degrees) so the horizon lands where the
	#    reference has it. Looking further down pushes the horizon up (smaller y).
	var lo := -30.0
	var hi := 30.0
	for _i in 40:
		var mid: float = (lo + hi) * 0.5
		_place(eye, Vector3(0.0, eye.y - 16.0 * tan(deg_to_rad(mid)), eye.z + 16.0))
		if _horizon_pct() > HORIZON_Y:
			lo = mid
		else:
			hi = mid
	var pitch: float = (lo + hi) * 0.5
	var look_final := Vector3(0.0, eye.y - 16.0 * tan(deg_to_rad(pitch)), eye.z + 16.0)
	_place(eye, look_final)
	var horizon: float = _horizon_pct()

	# 2) wheel: solve height (top edge) and distance (width) against the reference
	var tilt := deg_to_rad(-24.0)
	var half_w := 0.15
	var half_h := 0.102
	var lo_z := 0.20
	var hi_z := 1.20
	var z_final := 0.0
	for _i in 40:
		var z: float = (lo_z + hi_z) * 0.5
		var y := _solve_wheel_height(z, tilt, half_h, WHEEL_TOP_Y)
		if _pct(Vector3(-half_w, y, -z)).x < WHEEL_LEFT_X:
			lo_z = z
		else:
			hi_z = z
	z_final = (lo_z + hi_z) * 0.5
	var y_final := _solve_wheel_height(z_final, tilt, half_h, WHEEL_TOP_Y)
	var centre := Vector3(0.0, y_final, -z_final)
	var left_x: float = _pct(Vector3(-half_w, y_final, -z_final)).x
	var right_x: float = _pct(Vector3(half_w, y_final, -z_final)).x
	var top_y: float = _pct(centre + Vector3(0.0, half_h * cos(tilt), half_h * sin(tilt))).y
	var bottom_y: float = _pct(centre + Vector3(0.0, -half_h * cos(tilt), half_h * sin(tilt))).y

	# 3) halo bar at a chosen distance, solved for the reference row
	var halo_z := 0.50
	var halo_y := _solve_row(HALO_BAR_Y, halo_z)
	var halo_half: float = halo_z * tan(deg_to_rad(fov * 0.5)) * ASPECT * 1.02
	var halo_thick: float = halo_z * tan(deg_to_rad(fov * 0.5)) * 2.0 * 0.065
	var halo_left: float = _pct(Vector3(-halo_half, halo_y, -halo_z)).x

	# 4) mirror pods at the frame edge, solved for the reference row
	var mirror_z := 0.46
	var mirror_y := _solve_row(MIRROR_Y, mirror_z)
	var mirror_x: float = mirror_z * tan(deg_to_rad(fov * 0.5)) * ASPECT * 0.884

	# 5) dash panel, solved for the reference rows
	var dash_z := 0.55
	var dash_y := _solve_row(46.5, dash_z)
	var dash_half: float = dash_z * tan(deg_to_rad(fov * 0.5)) * ASPECT * 0.27

	# 6) where do the car's own front tyres land? The car sits at the origin
	#    with an identity basis in this probe, so car space == world space.
	var front := _pct_world(Vector3(-0.86, 0.365, 1.434))
	var front_top := _pct_world(Vector3(-0.86, 0.73, 1.434))

	print("=== fov=%.0f eye_y=%.2f  pitch=%.2f deg  horizon=%.1f%%" % [fov, eye_y, pitch, horizon])
	print("  LOOK = Vector3(0.0, %.3f, %.1f)" % [look_final.y, look_final.z])
	print("  wheel centre z=-%.3f  y=%.3f   -> edges x %.1f%%..%.1f%%  top %.1f%%  bottom %.1f%%" % [
		z_final, y_final, left_x, right_x, top_y, bottom_y])
	print("  halo  z=-%.2f y=%.3f half-width=%.3f thick=%.3f -> x=%.1f%%  y=%.1f%%" % [
		halo_z, halo_y, halo_half, halo_thick, halo_left, HALO_BAR_Y])
	print("  mirror z=-%.2f y=%.3f x=+/-%.3f -> y=%.1f%%" % [mirror_z, mirror_y, mirror_x, MIRROR_Y])
	print("  dash  z=-%.2f y=%.3f half-width=%.3f -> y=%.1f%%" % [dash_z, dash_y, dash_half, 46.5])
	print("  front tyre hub x=%.1f%% y=%.1f%%   top y=%.1f%%" % [front.x, front.y, front_top.y])


func _solve_wheel_height(z: float, tilt: float, half_h: float, target_top: float) -> float:
	## Bisect the wheel's centre height so its top edge lands on the target row.
	var lo := -1.0
	var hi := 0.6
	var y := 0.0
	for _i in 40:
		y = (lo + hi) * 0.5
		var top := Vector3(0.0, y + half_h * cos(tilt), -z + half_h * sin(tilt))
		if _pct(top).y < target_top:
			hi = y
		else:
			lo = y
	return y


func _solve_row(target_y: float, z: float) -> float:
	## Bisect the height at which a point at depth z projects onto row target_y.
	## y is measured from the lens: larger y = higher on screen = smaller row.
	var lo := -1.0
	var hi := 1.0
	var y := 0.0
	for _i in 40:
		y = (lo + hi) * 0.5
		if _pct(Vector3(0.0, y, -z)).y > target_y:
			lo = y
		else:
			hi = y
	return y
