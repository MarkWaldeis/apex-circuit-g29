extends SceneTree
## Gating test: the car has to face the way it actually drives.
##
## The exported GLB is modelled nose-first along +Z (front wing low and 2.3 m
## wide at +z, rear wing ~1 m high at -z) and VehicleBody3D pushes the hull
## towards +Z for a positive engine_force. So:
##   1. the visual must not carry any extra yaw,
##   2. the steering axle must be the front one (+z), the driven axle the rear,
##   3. the physics wheels must sit exactly where the GLB puts them, and
##   4. the rims must hang at axle height, not one suspension travel too high.

const F1Car = preload("res://scripts/car_controller.gd")
const Poses = preload("res://scripts/camera_poses.gd")
const CAR_PATH := "res://assets/cars/car_crimson.glb"
const REST := 0.18

var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _run() -> void:
	var glb_wheels := _glb_wheel_positions()
	_check(glb_wheels.size() == 4, "glb_has_four_wheels", str(glb_wheels.size()))

	# --- 1. the artwork faces forward ---------------------------------------
	var nose := _nose_direction_from_mesh()
	_check(nose["front_wing_z"] > 0.0, "front_wing_on_plus_z", "wing at z=%.2f" % nose["front_wing_z"])
	_check(nose["front_wing_width"] > 1.8 and nose["front_wing_height"] < 0.5,
		"front_wing_is_wide_and_low", "w=%.2f h=%.2f" % [nose["front_wing_width"], nose["front_wing_height"]])
	_check(nose["rear_wing_height"] > 0.8, "rear_wing_is_high", "h=%.2f" % nose["rear_wing_height"])

	var world := Node3D.new()
	root.add_child(world)
	var car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	car.is_ai = false
	world.add_child(car)
	var start := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), Vector3(0, 0.2, 0))
	car.setup(null, null, start)

	var visual: Node3D = car.get_node_or_null("Visual")
	_check(visual != null, "has_visual")
	if visual:
		# Nose direction of the artwork in vehicle space must stay +Z.
		var nose_dir: Vector3 = visual.global_transform.basis.z.normalized()
		var car_fwd: Vector3 = car.global_transform.basis.z.normalized()
		_check(nose_dir.dot(car_fwd) > 0.999, "visual_not_flipped",
			"nose . forward = %.3f" % nose_dir.dot(car_fwd))

	# --- 2./3. axles match the model ----------------------------------------
	var roles: Dictionary = car.wheel_roles()
	_check(roles.size() == 4, "four_physics_wheels", str(roles.keys()))
	var front_z := -INF
	var rear_z := INF
	for key in ["Wheel_FL", "Wheel_FR"]:
		if roles.has(key):
			front_z = maxf(front_z, float(roles[key].z))
	for key in ["Wheel_RL", "Wheel_RR"]:
		if roles.has(key):
			rear_z = minf(rear_z, float(roles[key].z))
	_check(front_z > 0.0, "steering_axle_on_plus_z", "z=%.3f" % front_z)
	_check(rear_z < 0.0, "driven_axle_on_minus_z", "z=%.3f" % rear_z)
	_check(absf(front_z - Poses.FRONT_AXLE_Z) < 0.02, "front_axle_matches_glb",
		"z=%.3f expected %.3f" % [front_z, Poses.FRONT_AXLE_Z])
	_check(absf(rear_z - Poses.REAR_AXLE_Z) < 0.02, "rear_axle_matches_glb",
		"z=%.3f expected %.3f" % [rear_z, Poses.REAR_AXLE_Z])
	for key in roles.keys():
		var mine: Vector3 = roles[key]
		var best: float = INF
		for other in glb_wheels.values():
			best = minf(best, mine.distance_to(other))
		_check(best < 0.02, "wheel_%s_sits_on_a_glb_hub" % key, "err=%.4f" % best)

	# --- drive train: front steers, rear drives ------------------------------
	for key in ["Wheel_FL", "Wheel_FR"]:
		var w := car.get_node_or_null(key)
		_check(w != null and w.use_as_steering and not w.use_as_traction, "front_wheel_steers_%s" % key)
	for key in ["Wheel_RL", "Wheel_RR"]:
		var w2 := car.get_node_or_null(key)
		_check(w2 != null and w2.use_as_traction and not w2.use_as_steering, "rear_wheel_drives_%s" % key)

	# --- 4. rims sit on the axle --------------------------------------------
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel := car.get_node_or_null(key)
		if wheel == null or wheel.get_child_count() == 0:
			_check(false, "rim_child_%s" % key)
			continue
		var rim: Node3D = wheel.get_child(0)
		_check(absf(rim.position.y + REST) < 0.001, "rim_at_axle_height_%s" % key,
			"dy=%.3f" % (rim.position.y + REST))

	# --- 5. the visible rims steer and roll ---------------------------------
	car.steering = 0.40
	car._animate_wheels(0.05, 20.0)
	var rim_rear: Node3D = null
	for key in ["Wheel_FL", "Wheel_FR"]:
		var wf := car.get_node_or_null(key)
		var rim_f: Node3D = wf.get_child(0) if wf and wf.get_child_count() > 0 else null
		_check(rim_f != null and absf(rim_f.rotation.y + 0.40) < 0.01,
			"front_rim_steers_%s" % key, "yaw=%.3f" % (rim_f.rotation.y if rim_f else 0.0))
	for key in ["Wheel_RL", "Wheel_RR"]:
		var wr := car.get_node_or_null(key)
		var rim_r: Node3D = wr.get_child(0) if wr and wr.get_child_count() > 0 else null
		rim_rear = rim_r
		_check(rim_r != null and absf(rim_r.rotation.y) < 0.001, "rear_rim_does_not_steer_%s" % key)
	_check(rim_rear != null and absf(rim_rear.rotation.x) > 0.01, "rims_roll_with_speed")

	# --- cockpit camera lives in the cockpit, not over the rear wing ---------
	_check(Poses.HELMET.z > Poses.REAR_AXLE_Z and Poses.HELMET.z < Poses.FRONT_AXLE_Z,
		"helmet_between_axles", "z=%.2f" % Poses.HELMET.z)
	_check(Poses.cockpit_looks_forward() and Poses.wheel_is_in_front_of_lens(),
		"cockpit_sees_forward_down_the_nose")

	if failed > 0:
		print("CAR_ORIENTATION FAIL count=", failed)
		quit(1)
	else:
		print("CAR_ORIENTATION PASS")
		quit(0)


func _glb_wheel_positions() -> Dictionary:
	var out: Dictionary = {}
	var packed: PackedScene = load(CAR_PATH)
	if packed == null:
		return out
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var n := _find_token(inst, key)
		if n:
			out[key] = n.position
	inst.queue_free()
	return out


func _nose_direction_from_mesh() -> Dictionary:
	## Slice the body mesh along z: the front wing is the widest, lowest slice at
	## one end, the rear wing the tall one at the other.
	var result := {"front_wing_z": 0.0, "front_wing_width": 0.0, "front_wing_height": 0.0,
		"rear_wing_height": 0.0}
	var packed: PackedScene = load(CAR_PATH)
	if packed == null:
		return result
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var body := _find_token(inst, "Body") as MeshInstance3D
	if body == null or body.mesh == null:
		inst.queue_free()
		return result
	var arrays: Array = (body.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var z_min := INF
	var z_max := -INF
	for v in verts:
		z_min = minf(z_min, v.z)
		z_max = maxf(z_max, v.z)
	var span: float = maxf(z_max - z_min, 0.001)
	var slices := 22
	var best_wide := {"score": -1.0, "z": 0.0, "w": 0.0, "h": 0.0}
	var tall := {"h": -1.0, "z": 0.0}
	for s in slices:
		var lo: float = z_min + span * float(s) / float(slices)
		var hi: float = z_min + span * float(s + 1) / float(slices)
		var max_abs_x := 0.0
		var max_y := -INF
		var count := 0
		for v in verts:
			if v.z < lo or v.z > hi:
				continue
			count += 1
			max_abs_x = maxf(max_abs_x, absf(v.x))
			max_y = maxf(max_y, v.y)
		if count == 0:
			continue
		var z_mid: float = (lo + hi) * 0.5
		# "wing score": wide but low -> front wing.
		var score: float = max_abs_x * 2.0 - max_y
		if score > best_wide["score"]:
			best_wide = {"score": score, "z": z_mid, "w": max_abs_x * 2.0, "h": max_y}
		if max_y > tall["h"]:
			tall = {"h": max_y, "z": z_mid}
	result["front_wing_z"] = best_wide["z"]
	result["front_wing_width"] = best_wide["w"]
	result["front_wing_height"] = best_wide["h"]
	result["rear_wing_height"] = tall["h"]
	inst.queue_free()
	return result


func _find_token(node: Node, token: String) -> Node3D:
	if token in node.name and node is Node3D:
		return node as Node3D
	for c in node.get_children():
		var r := _find_token(c, token)
		if r:
			return r
	return null
