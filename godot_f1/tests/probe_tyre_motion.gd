extends SceneTree
## Tyre motion probe.
##
## The complaint is "the tyres flicker and do not move realistically". Both are
## measurable. This harness drives the real car, and for a run of consecutive
## frames it crops the region around each wheel out of the framebuffer and
## reports
##
##   * motion   - mean absolute pixel change between consecutive frames. ~0 means
##                the wheel is not visibly turning at all.
##   * speckle  - pixels that changed a lot while their neighbours did not. That
##                is the signature of aliasing and of z-fighting decals, and it
##                is what the eye reads as "flicker".
##   * roll     - the rolling angle the script applies per frame against the
##                angle the driven speed demands. They must agree.
##
## Run (needs a window, headless cannot rasterise 3D):
##   godot --path <project> --script res://tests/probe_tyre_motion.gd

const VIEW := Vector2i(1280, 720)
const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures/diag"
const CROP := 110          ## half size of the sampled square around a wheel
const FRAMES := 90         ## frames sampled once the car is at speed
## Pixels whose colour changes by more than this between two frames count as
## "flicker". A spinning wheel always changes pixels; what matters is whether
## the change is a coherent rotation or a stroboscope.
const FLICKER_DELTA := 36.0

var main: Node3D
var player
var cam: Camera3D
var frames: int = 0
var _sampled: int = 0
var _prev: Dictionary = {}          ## role -> PackedByteArray of the crop
var _prev_roll: float = 0.0
var _roll_samples: Array = []
var _speed_samples: Array = []
var _motion: Dictionary = {}        ## role -> Array of mean deltas
var _speckle: Dictionary = {}       ## role -> Array of speckle counts
var _changed: Dictionary = {}       ## role -> Array of changed-pixel fractions
var _saved: bool = false
var _orbit: Dictionary = {}         ## role -> Array of [physics_frame, angle, radius]
var _orbit_speed: Dictionary = {}   ## role -> Array of speed in m/s at that tick
var _last_phys: int = -1
var _steer_done: bool = false
var _raw_count: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	root.size = VIEW
	DisplayServer.window_set_size(VIEW)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)
	physics_frame.connect(_on_physics)


## Rolling angle measured from a real wheel detail, not from the value the
## script wrote: the decal has to physically orbit the axle.
func _on_physics() -> void:
	if player == null:
		return
	for role in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := player.get_node_or_null(NodePath(role)) as Node3D
		if w == null:
			continue
		# The rim now rides on its own carrier next to the physics wheel, so the
		# decal is looked up there.
		var vis := player.get_node_or_null(NodePath("Vis_" + role)) as Node3D
		var host: Node3D = vis if vis != null else w
		var decal := host.find_child("TyreDecalOut", true, false) as Node3D
		if decal == null:
			continue
		# Measure in the frame of the CAR - the only reference that does not
		# roll, so what is left is exactly what the eye sees.
		var rel: Vector3 = decal.global_position - host.global_position
		var local: Vector3 = player.global_transform.basis.inverse() * rel
		var ang: float = atan2(local.y, local.z)
		var rad: float = sqrt(local.y * local.y + local.z * local.z)
		if not _orbit.has(role):
			_orbit[role] = []
			_orbit_speed[role] = []
		_orbit[role].append([Engine.get_physics_frames(), ang, rad])
		_orbit_speed[role].append(float(player.get("speed_kmh")) / 3.6)


func _on_frame() -> void:
	frames += 1
	if frames == 20:
		var m = main.get("menu")
		if m and m.has_method("resume_game"):
			m.resume_game()
	if frames == 40:
		cam = main.get("cam")
		player = main.get("player")
		# Chase view: all four wheels have to be in the frame at once.
		if cam:
			cam.mode = 1
		if player:
			player.auto_drive = true
	if player == null or cam == null:
		return
	# The autopilot holds a steady line, so the only thing changing between two
	# frames is the rolling wheel.
	if _speed_kmh() < 120.0 and frames < 900:
		return
	_sample()


func _sample() -> void:
	_sampled += 1
	var img: Image = root.get_texture().get_image()
	var roll: float = float(player.get("_wheel_roll"))
	var speed: float = _speed_kmh() / 3.6
	_roll_samples.append(roll)
	_speed_samples.append(speed)
	for role in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := player.get_node_or_null(NodePath(role)) as Node3D
		if w == null:
			continue
		var rect: Rect2i = _crop_rect(img, w)
		if rect.size.x < 8:
			continue
		var crop: PackedByteArray = img.get_region(rect).get_data()
		if _prev.has(role):
			var stats: Dictionary = _compare(_prev[role], crop)
			if not _motion.has(role):
				_motion[role] = []
				_speckle[role] = []
				_changed[role] = []
			_motion[role].append(stats["motion"])
			_speckle[role].append(stats["speckle"])
			_changed[role].append(stats["changed"])
		_prev[role] = crop
	if _sampled >= 20 and not _saved:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		img.save_png("%s/tyre_motion_fast.png" % OUT_DIR)
		_saved = true
	if _sampled >= FRAMES:
		_report()
		quit(0)


func _speed_kmh() -> float:
	var v = player.get("speed_kmh")
	return 0.0 if v == null else float(v)


## Screen rectangle around one wheel, clamped into the frame.
func _crop_rect(img: Image, wheel: Node3D) -> Rect2i:
	var mi := wheel as MeshInstance3D
	var aabb: AABB
	if mi and mi.mesh:
		aabb = mi.global_transform * mi.get_aabb()
	else:
		var p: Vector3 = wheel.global_position
		aabb = AABB(p - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
	var x0: float = INF
	var x1: float = -INF
	var y0: float = INF
	var y1: float = -INF
	for i in 8:
		var corner: Vector3 = aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		if cam.is_position_behind(corner):
			return Rect2i()
		var p: Vector2 = cam.unproject_position(corner)
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var cx: int = int((x0 + x1) * 0.5)
	var cy: int = int((y0 + y1) * 0.5)
	var half: int = mini(CROP, int(maxf(x1 - x0, y1 - y0) * 0.6) + 20)
	var rx: int = clampi(cx - half, 0, VIEW.x - 2 * half)
	var ry: int = clampi(cy - half, 0, VIEW.y - 2 * half)
	return Rect2i(rx, ry, half * 2, half * 2)


## Mean absolute change, plus the count of isolated changes (speckle).
func _compare(a: PackedByteArray, b: PackedByteArray) -> Dictionary:
	if a.size() != b.size() or a.is_empty():
		return {"motion": 0.0, "speckle": 0, "changed": 0.0}
	var n: int = a.size() / 3
	var w: int = int(sqrt(float(n)))
	var diff := PackedFloat32Array()
	diff.resize(n)
	var total: float = 0.0
	var changed: int = 0
	for i in n:
		var o: int = i * 3
		var d: float = absf(float(a[o]) - float(b[o])) \
			+ absf(float(a[o + 1]) - float(b[o + 1])) \
			+ absf(float(a[o + 2]) - float(b[o + 2]))
		diff[i] = d
		total += d
		if d > FLICKER_DELTA:
			changed += 1
	var speckle: int = 0
	if w > 2:
		for y in range(1, w - 1):
			for x in range(1, w - 1):
				var i2: int = y * w + x
				if diff[i2] < 72.0:
					continue
				var nb: float = 0.0
				nb += diff[i2 - 1] + diff[i2 + 1] + diff[i2 - w] + diff[i2 + w]
				nb += diff[i2 - w - 1] + diff[i2 - w + 1] + diff[i2 + w - 1] + diff[i2 + w + 1]
				if nb / 8.0 < 24.0:
					speckle += 1
	return {
		"motion": total / float(maxi(n, 1)),
		"speckle": speckle,
		"changed": float(changed) / float(maxi(n, 1)) * 100.0,
	}


func _report() -> void:
	print("")
	print("tyre motion probe  -  %d frames at %.0f..%.0f km/h, %dx%d" % [
		_sampled, _speed_samples[0] * 3.6, _speed_samples[-1] * 3.6, VIEW.x, VIEW.y])
	print("")
	print("%-10s %9s %9s %9s %10s" % ["wheel", "changed %", "speckle %", "motion", "speckle mx"])
	print("------------------------------------------------------------------")
	for role in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		if not _motion.has(role):
			print("%-10s  not visible in this camera" % role)
			continue
		var m: Array = _motion[role]
		var s: Array = _speckle[role]
		var c: Array = _changed[role]
		var motion_avg: float = 0.0
		var speckle_avg: float = 0.0
		var changed_avg: float = 0.0
		var speckle_max: int = 0
		for i in m.size():
			motion_avg += float(m[i])
			speckle_avg += float(s[i])
			changed_avg += float(c[i])
			speckle_max = maxi(speckle_max, int(s[i]))
		motion_avg /= float(maxi(m.size(), 1))
		speckle_avg /= float(maxi(s.size(), 1))
		changed_avg /= float(maxi(c.size(), 1))
		var crop_px: float = float((CROP * 2) * (CROP * 2))
		print("%-10s %8.2f%% %8.3f%% %9.2f %10.1f" % [
			role, changed_avg, speckle_avg / crop_px * 100.0, motion_avg,
			float(speckle_max)])
	print("")
	_report_orbit()
	print("")


## Does the visible wheel detail really orbit the axle at the rate the speed
## demands? Measured on the decal's world position, one sample per physics tick.
func _report_orbit() -> void:
	print("visible roll (measured on the decal's orbit around the axle):")
	print("%-10s %12s %12s %8s %14s" % ["wheel", "measured", "wanted", "ratio", "orbit radius"])
	print("---------------------------------------------------------------------------")
	for role in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		if not _orbit.has(role) or _orbit[role].size() < 3:
			print("%-10s  no decal samples" % role)
			continue
		var samples: Array = _orbit[role]
		var speeds: Array = _orbit_speed[role]
		var turned: float = 0.0
		var wanted: float = 0.0
		var first: int = -1
		var last: int = -1
		var rmin: float = INF
		var rmax: float = 0.0
		for i in range(1, samples.size()):
			var s0: Array = samples[i - 1]
			var s1: Array = samples[i]
			var df: int = int(s1[0]) - int(s0[0])
			if df <= 0:
				continue
			if first < 0:
				first = int(s0[0])
			last = int(s1[0])
			var d: float = float(s1[1]) - float(s0[1])
			while d > PI:
				d -= TAU
			while d < -PI:
				d += TAU
			turned += d
			wanted += float(speeds[i]) / maxf(float(player.get("_wheel_radius_avg")), 0.1) \
				* (1.0 / float(Engine.physics_ticks_per_second)) * float(df)
			rmin = minf(rmin, float(s1[2]))
			rmax = maxf(rmax, float(s1[2]))
		var span: float = float(maxi(last - first, 1)) / float(Engine.physics_ticks_per_second)
		print("%-10s %9.1f rad/s %9.1f rad/s %8.3f %6.3f..%.3f m" % [
			role, turned / span, wanted / span, turned / maxf(wanted, 0.001), rmin, rmax])


func _finalize() -> void:
	pass
