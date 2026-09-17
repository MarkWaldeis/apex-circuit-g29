extends VehicleBody3D

@export var livery: String = "crimson"
@export var auto_drive: bool = false
@export var is_ai: bool = false
@export var max_steer: float = 0.48

var racing_line
var g29
var spawn_transform: Transform3D
var speed_kmh: float = 0.0
var last_steer: float = 0.0
var gear: int = 1
var rpm: float = 4200.0
var clutch_assist: bool = true
var _shift_cd: float = 0.0
## Visual wheel meshes, kept so the rims can steer and roll with the car.
var _wheel_meshes: Array = []
var _wheel_roll: float = 0.0
var _wheel_radius_avg: float = 0.365
## Below this height there is no track, apron or terrain left - the car is in
## the void and has to be put back on the line.
const VOID_Y := -3.0
var _rejoin_cd: float = 0.0
var rejoin_count: int = 0

const LIVERY_PATH := "res://assets/cars/car_%s.glb"
const RIG_PATH := "res://assets/cars/car_rig.json"
const LIVERY_SHADER := "res://assets/shaders/livery.gdshader"
const WHEEL_KEYS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

## Paint / accent per livery (the GLB itself carries no colour at all).
const LIVERIES := {
	"crimson": {"paint": Color(0.74, 0.035, 0.05), "accent": Color(1.0, 0.95, 0.92)},
	"silver": {"paint": Color(0.62, 0.65, 0.68), "accent": Color(0.02, 0.12, 0.42)},
	"navy": {"paint": Color(0.02, 0.05, 0.16), "accent": Color(0.92, 0.78, 0.08)},
	"papaya": {"paint": Color(0.92, 0.38, 0.08), "accent": Color(0.05, 0.05, 0.06)},
	"green": {"paint": Color(0.02, 0.22, 0.14), "accent": Color(0.95, 0.82, 0.12)},
	"azure": {"paint": Color(0.05, 0.28, 0.72), "accent": Color(0.95, 0.35, 0.55)},
}
const REST := 0.18
const IDLE_RPM := 4200.0
const REDLINE := 12500.0
const MAX_GEAR := 8
## Approximate sequential ratios. Index 0 unused (gear is 1..8).
const RATIOS := [0.0, 3.4, 2.7, 2.2, 1.85, 1.58, 1.38, 1.22, 1.08]
const POWER := 3200.0
const BRAKE_MAX := 110.0


func setup(line, wheel_input, start: Transform3D) -> void:
	racing_line = line
	g29 = wheel_input
	spawn_transform = start
	mass = 740.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Weight slightly towards the rear axle (nose is +Z), like a real F1 car.
	center_of_mass = Vector3(0.0, -0.10, -0.42)
	continuous_cd = true
	can_sleep = false
	_build_wheels_and_mesh()
	_build_chassis_collider()
	global_transform = start
	if g29 and not is_ai:
		if not g29.shift_up.is_connected(_on_shift_up):
			g29.shift_up.connect(_on_shift_up)
			g29.shift_down.connect(_on_shift_down)


func _build_chassis_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "Chassis"
	var box := BoxShape3D.new()
	# Hull box centred between the axles (front axle +1.43, rear axle -2.00).
	box.size = Vector3(1.8, 0.55, 3.9)
	col.shape = box
	col.position = Vector3(0.0, 0.60, -0.25)
	add_child(col)


func _build_wheels_and_mesh() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	var rig_radius: float = float(rig.get("wheel_radius", 0.365))
	var packed: PackedScene = load(LIVERY_PATH % livery)
	var visual: Node3D = packed.instantiate()
	visual.name = "Visual"
	add_child(visual)
	# The artwork is modelled nose-first along +Z, and VehicleBody3D pushes the
	# hull towards +Z for a positive engine_force, so the visual must stay
	# unrotated. Any yaw here makes the car drive tail-first (the "I drive
	# backwards" bug: nose pointing at the rear wing, cockpit over the engine).
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	_apply_livery(visual)

	# The wheel meshes are the only nodes with a translation in the GLB, so the
	# model itself tells us where the axles are. car_rig.json stays the fallback.
	var entries: Array = []
	for key in WHEEL_KEYS:
		var node := _find_token(visual, key)
		var pos := Vector3.ZERO
		var radius: float = rig_radius
		if node:
			pos = node.position
			radius = _mesh_radius(node, rig_radius)
		else:
			var loc: Array = rig["wheels"][key]["location"]
			# Blender (X right, Y forward, Z up) -> Godot (X, Z, -Y).
			pos = Vector3(float(loc[0]), float(loc[2]), -float(loc[1]))
		entries.append({"key": key, "pos": pos, "node": node, "radius": radius})

	# Front axle = nose side (+Z), left hand side = +X for a +Z/+Y body.
	entries.sort_custom(func(a, b): return a.pos.z > b.pos.z)
	_wheel_meshes.clear()
	var radius_sum: float = 0.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var is_front: bool = i < 2
		var is_left: bool = e.pos.x > 0.0
		var role: String = ("Wheel_F" if is_front else "Wheel_R") + ("L" if is_left else "R")
		var hub: Vector3 = e.pos
		var radius: float = e.radius
		radius_sum += radius
		var wheel := VehicleWheel3D.new()
		wheel.name = role
		wheel.position = hub + Vector3(0.0, REST, 0.0)
		# Formula 1: the front axle steers, the rear axle drives.
		wheel.use_as_steering = is_front
		wheel.use_as_traction = not is_front
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.18
		wheel.suspension_stiffness = 52.0
		wheel.suspension_max_force = 14000.0
		wheel.damping_compression = 0.82
		wheel.damping_relaxation = 0.92
		wheel.wheel_friction_slip = 7.8
		wheel.wheel_roll_influence = 0.08
		add_child(wheel)
		var mesh: Node3D = e.node
		if mesh:
			var old_parent := mesh.get_parent()
			if old_parent:
				old_parent.remove_child(mesh)
			wheel.add_child(mesh)
			mesh.owner = wheel
			# The wheel node marks the suspension mount, one rest length above
			# the hub - drop the rim back down onto the axle.
			mesh.position = Vector3(0.0, -REST, 0.0)
			mesh.rotation = Vector3.ZERO
			_add_wheel_details(mesh, hub.x, radius)
			_wheel_meshes.append({"mesh": mesh, "front": is_front})
	_wheel_radius_avg = radius_sum / maxf(float(entries.size()), 1.0)


func _paint_material() -> Material:
	var entry: Dictionary = LIVERIES.get(livery, LIVERIES["crimson"])
	var shader: Shader = load(LIVERY_SHADER)
	if shader:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("paint_color", entry["paint"])
		sm.set_shader_parameter("accent_color", entry["accent"])
		return sm
	# Fallback for a missing shader file: plain painted metal.
	var m := StandardMaterial3D.new()
	m.albedo_color = entry["paint"]
	m.metallic = 0.28
	m.roughness = 0.18
	m.clearcoat_enabled = true
	m.clearcoat = 0.85
	m.clearcoat_roughness = 0.06
	return m


func _apply_livery(node: Node) -> void:
	## The GLB exports a single "Paint_*" surface per body mesh without any base
	## colour, so the livery is applied on top of it here.
	var paint := _paint_material()
	_paint_walk(node, paint)


func _paint_walk(node: Node, paint: Material) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			var sname: String = src.resource_name if src else ""
			if "Paint" in sname or (src == null and mi.mesh.get_surface_count() == 1 and i == 0):
				mi.set_surface_override_material(i, paint)
	for c in node.get_children():
		_paint_walk(c, paint)


func _mesh_radius(node: Node3D, fallback: float) -> float:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return fallback
	var aabb: AABB = mi.mesh.get_aabb()
	# A wheel is a disc: two of the three extents describe its diameter.
	var sizes: Array = [aabb.size.x, aabb.size.y, aabb.size.z]
	sizes.sort()
	var r: float = float(sizes[2]) * 0.5
	if r < 0.15 or r > 0.7:
		return fallback
	return r


func _add_wheel_details(mesh: Node3D, _hub_x: float, radius: float) -> void:
	## F1 wheels are bare slicks, so a plain tyre looks like it does not turn.
	## A coloured sidewall band (the compound marking), a small decal and a star
	## of rim spokes make the rotation visible - and they are what a real wheel
	## looks like from the cockpit.
	var mi := mesh as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var aabb: AABB = mi.mesh.get_aabb()
	var half_width: float = maxf(aabb.size.x * 0.5, 0.12)
	var compound: Color = Color(0.85, 0.12, 0.14) if livery != "crimson" else Color(0.92, 0.78, 0.12)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = compound
	band_mat.roughness = 0.65
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.46, 0.47, 0.50)
	# A mirror-smooth rim sparkles frame to frame at speed: the highlight jumps
	# between pixels. Roughness 0.45 keeps the metal look without the flicker.
	rim_mat.metallic = 0.70
	rim_mat.roughness = 0.45
	var decal := StandardMaterial3D.new()
	decal.albedo_color = Color(0.86, 0.87, 0.88)
	decal.roughness = 0.5
	# Both faces get the details: from the cockpit the driver looks at the INNER
	# sidewall of the front wheels, while a chase or side camera sees the outer
	# one. Putting them on only one side made the wheels look featureless from
	# the cockpit - and a featureless slick looks like it never turns.
	for outward in [1.0, -1.0]:
		var face_x: float = outward * (half_width + 0.006)
		var side_name: String = "Out" if outward > 0.0 else "In"
		# sidewall band
		var ring := MeshInstance3D.new()
		ring.name = "CompoundBand" + side_name
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.66
		torus.outer_radius = radius * 0.82
		torus.rings = 20
		torus.ring_segments = 8
		ring.mesh = torus
		ring.material_override = band_mat
		ring.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		ring.position = Vector3(face_x, 0.0, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(ring)
		# rim spokes
		for i in 6:
			var a: float = TAU * float(i) / 6.0
			var spoke := MeshInstance3D.new()
			spoke.name = "Spoke%s%d" % [side_name, i]
			var box := BoxMesh.new()
			box.size = Vector3(0.012, radius * 0.92, 0.030)
			spoke.mesh = box
			spoke.material_override = rim_mat
			spoke.position = Vector3(face_x, cos(a) * radius * 0.44, sin(a) * radius * 0.44)
			spoke.rotation = Vector3(-a, 0.0, 0.0)
			spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.add_child(spoke)
		# a bright decal so even a slow turn is unmistakable
		var badge := MeshInstance3D.new()
		badge.name = "TyreDecal" + side_name
		var decal_box := BoxMesh.new()
		decal_box.size = Vector3(0.005, 0.045, 0.11)
		badge.mesh = decal_box
		badge.material_override = decal
		badge.position = Vector3(face_x, radius * 0.55, 0.0)
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(badge)


func wheel_roles() -> Dictionary:
	## Debug/test helper: role -> local hub position.
	var out: Dictionary = {}
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := get_node_or_null(name) as VehicleWheel3D
		if w:
			out[name] = w.position - Vector3(0.0, REST, 0.0)
	return out


func _animate_wheels(delta: float, forward_speed: float) -> void:
	_wheel_roll = fposmod(_wheel_roll + forward_speed * delta / maxf(_wheel_radius_avg, 0.1), TAU)
	for item in _wheel_meshes:
		var mesh: Node3D = item["mesh"]
		if mesh == null or not is_instance_valid(mesh):
			continue
		# Godot already yaws the VehicleWheel3D node itself by the steering
		# angle, and the rim is a child of that node. Adding the steering yaw
		# again here (with the opposite sign, as this used to) cancelled the
		# parent's yaw, which pinned the visible front wheels straight ahead no
		# matter how hard the driver turned. Only the rolling angle belongs here.
		mesh.rotation = Vector3(_wheel_roll, 0.0, 0.0)


func _find_token(node: Node, token: String) -> Node3D:
	if token in node.name and node is Node3D:
		return node as Node3D
	for c in node.get_children():
		var r := _find_token(c, token)
		if r:
			return r
	return null


func _unhandled_input(event: InputEvent) -> void:
	if is_ai:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_PERIOD:
			_on_shift_up()
		elif event.physical_keycode == KEY_Q or event.physical_keycode == KEY_COMMA:
			_on_shift_down()


func apply_throttle(amount: float) -> void:
	set_meta("script_throttle", clampf(amount, 0.0, 1.0))


func apply_brake(amount: float) -> void:
	## Scripted brake input, used by the headless tests.
	set_meta("script_brake", clampf(amount, 0.0, 1.0))


func _on_shift_up() -> void:
	if gear < MAX_GEAR and _shift_cd <= 0.0:
		gear += 1
		_shift_cd = 0.12


func _on_shift_down() -> void:
	if gear > 1 and _shift_cd <= 0.0:
		var next_rpm := _rpm_for_gear(gear - 1)
		if next_rpm < REDLINE + 400.0:
			gear -= 1
			_shift_cd = 0.12


func _physics_process(delta: float) -> void:
	var forward_vel: float = global_transform.basis.z.dot(linear_velocity)
	speed_kmh = linear_velocity.length() * 3.6
	var steer_in := 0.0
	var throttle_in := 0.0
	var brake_in := 0.0
	var clutch_in := 0.0

	if not is_ai and g29 and g29.has_driver_input():
		auto_drive = false
	if not is_ai and (
		Input.get_action_strength("throttle") > 0.15
		or Input.get_action_strength("brake") > 0.15
		or abs(Input.get_axis("steer_left", "steer_right")) > 0.25
	):
		auto_drive = false
	if not is_ai and Input.is_action_just_pressed("toggle_auto"):
		if g29 and g29.cal_phase > 0 and g29.cal_phase < 5:
			pass
		else:
			auto_drive = not auto_drive
	if not is_ai and Input.is_action_just_pressed("reset_car"):
		_reset()

	if auto_drive or is_ai:
		var ai: Dictionary = _auto_inputs()
		steer_in = ai.steer
		throttle_in = ai.throttle
		brake_in = ai.brake
		clutch_in = 0.0
		_ai_shift()
	else:
		steer_in = Input.get_axis("steer_left", "steer_right")
		throttle_in = Input.get_action_strength("throttle")
		brake_in = Input.get_action_strength("brake")
		if g29 and g29.connected:
			if abs(g29.steer) > 0.04:
				steer_in = g29.steer
			throttle_in = max(throttle_in, g29.throttle)
			brake_in = max(brake_in, g29.brake)
			clutch_in = g29.clutch
			if g29.clutch > 0.4:
				clutch_assist = false
		if has_meta("script_throttle"):
			throttle_in = float(get_meta("script_throttle"))
			clutch_in = 0.0
			clutch_assist = true
		if has_meta("headless_gas"):
			throttle_in = 0.85
			clutch_in = 0.0
			clutch_assist = true
		if has_meta("script_brake"):
			brake_in = float(get_meta("script_brake"))

	# Speed-sensitive steering: F1 lock-to-lock tightens at speed.
	var spd: float = abs(forward_vel)
	var steer_limit: float = max_steer * lerp(1.0, 0.22, clampf(spd / 70.0, 0.0, 1.0))
	# The driver side of the game is "positive = right": the G29 calibration
	# measures full lock to the right as +1, D / Right Arrow map to +1 and the
	# rim in the cockpit turns clockwise for +1. This hull, however, drives
	# along +Z - the opposite of Godot's own -Z vehicle forward - so a POSITIVE
	# VehicleWheel3D.steering pushes the nose towards +X, which is the driver's
	# LEFT. Mirror the command exactly once, here, so that turning the wheel to
	# the right really turns the car to the right.
	var steer_cmd: float = clampf(steer_in, -1.0, 1.0)
	steering = lerp(steering, -steer_cmd * steer_limit, clampf(delta * 10.0, 0.0, 1.0))
	last_steer = steer_cmd
	_animate_wheels(delta, forward_vel)

	var engage := 1.0 - clampf(clutch_in, 0.0, 1.0)
	if clutch_assist and clutch_in < 0.1:
		engage = 1.0
	if spd < 0.8 and throttle_in < 0.04 and clutch_in < 0.1:
		engage = 0.0

	var speed_rpm := _rpm_for_gear(gear)
	var rev_rpm: float = IDLE_RPM + throttle_in * (REDLINE - IDLE_RPM)
	if engage < 0.35:
		rpm = lerp(rpm, rev_rpm, clampf(delta * 7.0, 0.0, 1.0))
	else:
		rpm = lerp(rpm, speed_rpm, clampf(delta * 8.0, 0.0, 1.0))
	rpm = clampf(rpm, IDLE_RPM, REDLINE + 200.0)

	var torque := _torque_at(rpm) * throttle_in * engage
	_shift_cd = maxf(_shift_cd - delta, 0.0)
	if rpm >= 9000.0 and gear < MAX_GEAR and _shift_cd <= 0.0:
		gear += 1
		_shift_cd = 0.16
	if rpm >= REDLINE - 80.0:
		torque *= 0.12
	engine_force = torque * RATIOS[gear]
	# Engine braking when off-throttle in gear.
	if throttle_in < 0.05 and engage > 0.6 and spd > 8.0:
		engine_force = -min(spd * 18.0 * RATIOS[gear] * 0.15, 420.0)

	var brake_force: float = brake_in * BRAKE_MAX
	if brake_in > 0.08:
		engine_force = min(engine_force, 0.0)
	brake = brake_force

	_apply_aero(spd, brake_in, abs(steer_in))

	_rejoin_cd = maxf(_rejoin_cd - delta, 0.0)
	# Past the runoff apron there is no collision surface at all. Without this
	# the car free-falls for seconds on end (the lap-drive telemetry used to
	# show the player at y = -30 m still doing 175 km/h) and only came back by
	# tumbling into the "car is upside down" reset.
	if global_position.y < VOID_Y and _rejoin_cd <= 0.0:
		rejoin_to_line()
	if global_transform.basis.y.dot(Vector3.UP) < 0.25:
		_reset()


func _rpm_for_gear(g: int) -> float:
	var fwd: float = max(global_transform.basis.z.dot(linear_velocity), 0.0)
	return clampf(IDLE_RPM + fwd * RATIOS[g] * 95.0, IDLE_RPM, REDLINE)


func _torque_at(r: float) -> float:
	# Peak around 11k, drop to limiter.
	var n: float = clampf((r - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
	var curve: float = sin(n * PI)
	if n > 0.92:
		curve *= 0.35
	return POWER * max(curve, 0.12)


func _apply_aero(spd: float, brake_in: float, steer_amt: float) -> void:
	var down: float = 1.0 + 1.15 * pow(clampf(spd / 75.0, 0.0, 1.0), 2.0)
	if brake_in > 0.2:
		down *= 0.92
	if steer_amt > 0.35 and spd > 25.0:
		down *= lerp(1.0, 0.78, clampf((steer_amt - 0.35) * 2.0, 0.0, 1.0))
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: VehicleWheel3D = get_node_or_null(name)
		if w:
			var base := 8.4 if name.begins_with("Wheel_R") else 7.4
			w.wheel_friction_slip = base * down


func _ai_shift() -> void:
	if rpm > 11200.0 and gear < MAX_GEAR:
		gear += 1
	elif rpm < 7000.0 and gear > 1:
		gear -= 1


func _auto_inputs() -> Dictionary:
	var result := {"steer": 0.0, "throttle": 0.55, "brake": 0.0}
	if racing_line == null or racing_line.points.size() == 0:
		return result
	var speed: float = linear_velocity.length()
	var look: float = lerp(8.0, 30.0, clampf(speed / 55.0, 0.0, 1.0))
	var target: Vector3 = racing_line.point_ahead(global_position, look)
	var local: Vector3 = to_local(target)
	var angle: float = atan2(local.x, local.z)
	# Driver convention: positive = right. A target sitting on the car's local
	# +X is on the driver's LEFT (the nose is +Z), so it needs a negative
	# command. Without the minus the AI steers away from the racing line.
	result.steer = clampf(-angle / max_steer, -1.0, 1.0)
	var curve: float = racing_line.curvature_ahead(global_position, look)
	var throttle: float = 0.95
	throttle -= clampf(abs(angle) * 1.35, 0.0, 0.8)
	throttle -= clampf(curve * 0.85, 0.0, 0.7)
	result.throttle = clampf(throttle, 0.0, 1.0)
	if abs(angle) > 0.28 and speed > 16.0:
		result.brake = clampf((abs(angle) - 0.28) * 1.8 + curve * 0.5, 0.0, 0.95)
		result.throttle = 0.0
	elif curve > 0.35 and speed > 28.0:
		result.brake = clampf(curve * 0.55, 0.0, 0.7)
		result.throttle = min(result.throttle, 0.25)
	return result


func _reset() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_transform
	engine_force = 0.0
	brake = 10.0
	gear = 1
	rpm = IDLE_RPM
	clutch_assist = true


func rejoin_to_line() -> void:
	## Put the car back on the racing line facing the way round, keeping the
	## current gear. Used when a car has fallen out of the world.
	rejoin_count += 1
	_rejoin_cd = 0.5
	var target: Transform3D = spawn_transform
	if racing_line != null and racing_line.points.size() > 0:
		var i: int = racing_line.closest_index(global_position)
		var t: Vector3 = racing_line.tangents[i]
		t.y = 0.0
		if t.length() < 0.001:
			t = Vector3(0, 0, -1)
		# The car's forward axis is +Z, so the basis has to look along -t.
		var basis := Basis.looking_at(-t.normalized(), Vector3.UP)
		target = Transform3D(basis, racing_line.points[i] + Vector3(0.0, 0.35, 0.0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = target
	engine_force = 0.0
	brake = 0.0
	# Stationary on the line: a high gear at idle gives ~0.5 m/s^2 and the car
	# crawls away in 8th, so start the rejoin from first.
	gear = 1
	rpm = IDLE_RPM
	_shift_cd = 0.0
