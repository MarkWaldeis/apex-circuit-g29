extends SceneTree
## Gating test: cockpit wheel on camera -Z, origins outside hull, look is forward.

const Poses = preload("res://scripts/camera_poses.gd")


func _initialize() -> void:
	var failed := 0
	if not Poses.wheel_is_in_front_of_lens():
		push_error("FAIL wheel z=%s must be < -0.2" % Poses.WHEEL_LOCAL.z)
		failed += 1
	else:
		print("PASS wheel_in_front z=", Poses.WHEEL_LOCAL.z)
	if not Poses.cockpit_looks_forward():
		push_error("FAIL cockpit look delta z=%s" % Poses.cockpit_look_delta().z)
		failed += 1
	else:
		print("PASS cockpit_looks_forward dz=", Poses.cockpit_look_delta().z)
	if not Poses.chase_looks_forward():
		push_error("FAIL chase look is not forward")
		failed += 1
	else:
		print("PASS chase_looks_forward")
	if not Poses.is_outside_hull(Poses.HELMET):
		# The helmet cam sits in the cockpit opening, so it may be inside the
		# hull box - what matters is that it is above the cockpit floor, still
		# between the axles and behind the front axle.
		var ok: bool = (Poses.HELMET.y > 1.0
			and Poses.HELMET.z > Poses.REAR_AXLE_Z
			and Poses.HELMET.z < Poses.FRONT_AXLE_Z)
		if not ok:
			push_error("FAIL helmet pose %s" % Poses.HELMET)
			failed += 1
		else:
			print("PASS helmet_in_cockpit ", Poses.HELMET)
	else:
		print("PASS helmet_above_hull ", Poses.HELMET)
	if Poses.CHASE_LOCAL.z > Poses.REAR_AXLE_Z:
		push_error("FAIL chase camera is not behind the car: %s" % Poses.CHASE_LOCAL)
		failed += 1
	else:
		print("PASS chase_behind_rear_axle ", Poses.CHASE_LOCAL)
	if not Poses.is_outside_hull(Poses.CHASE_LOCAL):
		push_error("FAIL chase origin inside hull %s" % Poses.CHASE_LOCAL)
		failed += 1
	else:
		print("PASS chase_outside_hull ", Poses.CHASE_LOCAL)
	if not Poses.is_outside_hull(Poses.HELI_LOCAL):
		push_error("FAIL heli origin inside hull %s" % Poses.HELI_LOCAL)
		failed += 1
	else:
		print("PASS heli_outside_hull ", Poses.HELI_LOCAL)
	if Poses.DASH_LOCAL.z >= -0.2:
		push_error("FAIL dash z=%s not in front of lens" % Poses.DASH_LOCAL.z)
		failed += 1
	else:
		print("PASS dash_in_front z=", Poses.DASH_LOCAL.z)
	if failed > 0:
		print("CAMERA_POSE FAIL count=", failed)
		quit(1)
	else:
		print("CAMERA_POSE PASS")
		quit(0)
