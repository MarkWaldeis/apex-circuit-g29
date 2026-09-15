extends VehicleBody3D

@export var livery: String = "crimson"
@export var auto_drive: bool = true
@export var is_ai: bool = false
@export var engine_power: float = 1600.0
@export var brake_power: float = 52.0
@export var max_steer: float = 0.38
@export var max_speed: float = 62.0

var racing_line
var g29
var spawn_transform: Transform3D
var speed_kmh: float = 0.0
var last_steer: float = 0.0

const LIVERY_PATH := "res://assets/cars/car_%s.glb"
const RIG_PATH := "res://assets/cars/car_rig.json"
const REST := 0.18


func setup(line, wheel_input, start: Transform3D) -> void:
	racing_line = line
	g29 = wheel_input
	spawn_transform = start
	mass = 740.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# +Z is vehicle forward (Godot VehicleBody3D). Bias COM slightly rearward.
	center_of_mass = Vector3(0, -0.12, -0.18)
	continuous_cd = true
	can_sleep = false
	_build_wheels_and_mesh()
	_build_chassis_collider()
	global_transform = start


func _build_chassis_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "Chassis"
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 0.5, 3.8)
	col.shape = box
	col.position = Vector3(0.0, 0.55, 0.15)
	add_child(col)


func _build_wheels_and_mesh() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	var radius: float = float(rig.get("wheel_radius", 0.365))
	var wheels: Dictionary = rig["wheels"]

	var packed: PackedScene = load(LIVERY_PATH % livery)
	var visual: Node3D = packed.instantiate()
	visual.name = "Visual"
	add_child(visual)

	# Godot VehicleBody3D thrust is +Z. The GLB nose is -Z (Blender +Y).
	# Map blender (x, y, z) with +Y forward to Godot (x, z, y) = (right, up, forward).
	var specs := [
		["Wheel_FL", false, true],
		["Wheel_FR", false, true],
		["Wheel_RL", true, false],
		["Wheel_RR", true, false],
	]
	for spec in specs:
		var key: String = spec[0]
		var src: Dictionary = wheels[key]
		var loc: Array = src["location"]
		var wheel := VehicleWheel3D.new()
		wheel.name = key
		var hub := Vector3(float(loc[0]), float(loc[2]), float(loc[1]))
		wheel.position = hub + Vector3(0.0, REST, 0.0)
		wheel.use_as_traction = spec[1]
		wheel.use_as_steering = spec[2]
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.18
		wheel.suspension_stiffness = 48.0
		wheel.suspension_max_force = 12000.0
		wheel.damping_compression = 0.8
		wheel.damping_relaxation = 0.9
		wheel.wheel_friction_slip = 8.5
		wheel.wheel_roll_influence = 0.1
		add_child(wheel)
		var mesh := _find_token(visual, key)
		if mesh:
			mesh.reparent(wheel)
			mesh.position = Vector3.ZERO
			mesh.rotation = Vector3.ZERO

	# Rotate remaining body so the nose matches +Z forward.
	visual.rotate_y(PI)
	visual.position.y = 0.03


func _find_token(node: Node, token: String) -> Node3D:
	if token in node.name and node is Node3D:
		return node as Node3D
	for c in node.get_children():
		var r := _find_token(c, token)
		if r:
			return r
	return null


func _physics_process(delta: float) -> void:
	speed_kmh = linear_velocity.length() * 3.6
	var steer_in := 0.0
	var throttle_in := 0.0
	var brake_in := 0.0

	if not is_ai and g29 and g29.has_driver_input():
		auto_drive = false
	if not is_ai and (
		Input.get_action_strength("throttle") > 0.15
		or Input.get_action_strength("brake") > 0.15
		or abs(Input.get_axis("steer_left", "steer_right")) > 0.25
	):
		auto_drive = false

	if not is_ai and Input.is_action_just_pressed("toggle_auto"):
		auto_drive = not auto_drive
	if not is_ai and Input.is_action_just_pressed("reset_car"):
		_reset()

	if auto_drive or is_ai:
		var ai: Dictionary = _auto_inputs()
		steer_in = ai.steer
		throttle_in = ai.throttle
		brake_in = ai.brake
	else:
		steer_in = Input.get_axis("steer_left", "steer_right")
		throttle_in = Input.get_action_strength("throttle")
		brake_in = Input.get_action_strength("brake")
		if g29 and g29.connected:
			if abs(g29.steer) > 0.06:
				steer_in = g29.steer
			if g29.throttle > 0.04:
				throttle_in = g29.throttle
			if g29.brake > 0.04:
				brake_in = g29.brake

	var speed_factor: float = clampf(1.0 - linear_velocity.length() / max_speed, 0.22, 1.0)
	var steer_limit: float = max_steer * lerp(0.32, 1.0, speed_factor)
	steering = lerp(steering, clampf(steer_in, -1.0, 1.0) * steer_limit, clampf(delta * 8.0, 0.0, 1.0))
	last_steer = steering

	if linear_velocity.length() > max_speed and throttle_in > 0.0:
		throttle_in = 0.0
	engine_force = throttle_in * engine_power
	brake = brake_in * brake_power

	if global_transform.basis.y.dot(Vector3.UP) < 0.25:
		_reset()


func _auto_inputs() -> Dictionary:
	var result := {"steer": 0.0, "throttle": 0.55, "brake": 0.0}
	if racing_line == null or racing_line.points.size() == 0:
		return result
	var speed: float = linear_velocity.length()
	var look: float = lerp(9.0, 26.0, clampf(speed / 50.0, 0.0, 1.0))
	var target: Vector3 = racing_line.point_ahead(global_position, look)
	var local: Vector3 = to_local(target)
	# +Z forward: target ahead has +z; right has +x.
	var angle: float = atan2(local.x, local.z)
	result.steer = clampf(angle / max_steer, -1.0, 1.0)
	var curve: float = racing_line.curvature_ahead(global_position, look)
	var throttle: float = 0.88
	throttle -= clampf(abs(angle) * 1.2, 0.0, 0.75)
	throttle -= clampf(curve * 0.6, 0.0, 0.55)
	if speed > 52.0:
		throttle *= 0.6
	result.throttle = clampf(throttle, 0.08, 1.0)
	if abs(angle) > 0.5 and speed > 18.0:
		result.brake = clampf((abs(angle) - 0.5) * 1.5, 0.0, 0.75)
		result.throttle = 0.0
	return result


func _reset() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_transform
	engine_force = 0.0
	brake = 8.0
