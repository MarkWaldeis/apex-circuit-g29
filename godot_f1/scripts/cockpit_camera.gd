extends Camera3D
## Default view: helmet cam above the cockpit, looking down the nose (+Z).
##
## Everything here is built in CAMERA space: the lens looks along its own -Z, so
## a prop that has to be visible in the frame needs a negative local z. The
## cockpit wheel turns with the real wheel (g29.steer) and the shift lights
## follow the engine rpm.

const Poses = preload("res://scripts/camera_poses.gd")

const TILT := deg_to_rad(-22.0)
const LED_COUNT := 12

var target: Node3D
var g29
var mode: int = 0 ## 0 cockpit, 1 chase, 2 heli
var wheel_visual: Node3D
var dash: Node3D
var cockpit: Node3D
var _leds: Array = []
var _wheel_rot: float = 0.0
var _props_shown: int = -1


func setup(car: Node3D, wheel_input) -> void:
	target = car
	g29 = wheel_input
	current = true
	far = 2200.0
	near = 0.05
	fov = 72.0
	doppler_tracking = Camera3D.DOPPLER_TRACKING_DISABLED
	_build_cockpit()
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_cycle"):
		mode = (mode + 1) % 3
		_set_cockpit_props_visible(mode == 0)


func _process(_delta: float) -> void:
	if target == null:
		return
	# Keep the cockpit props in sync with the mode even when something else
	# (menu, test harness) switches the camera.
	if _props_shown != mode:
		_props_shown = mode
		_set_cockpit_props_visible(mode == 0)
	match mode:
		0:
			_snap()
		1:
			var xf: Transform3D = target.global_transform
			global_position = xf * Poses.CHASE_LOCAL
			look_at(xf * Poses.CHASE_LOOK_LOCAL, Vector3.UP)
			fov = 62.0
		2:
			var xf2: Transform3D = target.global_transform
			global_position = xf2 * Poses.HELI_LOCAL
			look_at(xf2.origin, Vector3.UP)
			fov = 55.0
	if target.get("rpm") != null:
		set_rpm(float(target.rpm))


func _snap() -> void:
	var xf: Transform3D = target.global_transform
	var steer_amt: float = 0.0
	if g29:
		steer_amt = g29.steer
	elif target.get("last_steer") != null:
		steer_amt = float(target.last_steer)
	var look: Vector3 = Poses.LOOK
	look.x += steer_amt * 1.2
	global_position = xf * Poses.HELMET
	look_at(xf * look, Vector3.UP)
	fov = 72.0
	# Spin the rim around its own normal, then keep the driver's tilt. Godot
	# applies Euler rotations as Y * X * Z, so z turns inside the wheel plane.
	_wheel_rot = lerpf(_wheel_rot, -steer_amt * Poses.WHEEL_TURN, 0.35)
	if wheel_visual:
		wheel_visual.rotation = Vector3(TILT, 0.0, _wheel_rot)


func set_rpm(rpm: float) -> void:
	if _leds.is_empty():
		return
	var n: float = clampf((rpm - 6000.0) / (12500.0 - 6000.0), 0.0, 1.0)
	var lit: int = int(round(n * float(_leds.size())))
	for i in _leds.size():
		var led: MeshInstance3D = _leds[i]
		var mat: StandardMaterial3D = led.material_override
		if i < lit:
			var c: Color = Color(0.15, 0.85, 0.30) if i < 6 else (
				Color(0.95, 0.75, 0.10) if i < 9 else Color(0.95, 0.10, 0.10))
			mat.albedo_color = c
			mat.emission_enabled = true
			mat.emission = c
			mat.emission_energy_multiplier = 2.4
		else:
			mat.albedo_color = Color(0.05, 0.05, 0.06)
			mat.emission_enabled = false


func _set_cockpit_props_visible(v: bool) -> void:
	if cockpit:
		cockpit.visible = v
	if dash:
		dash.visible = v


func _mat(color: Color, rough: float, metal: float, emissive: Color = Color(0, 0, 0, 0), energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emissive.a > 0.0:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _build_cockpit() -> void:
	var carbon := _mat(Color(0.035, 0.035, 0.04), 0.45, 0.15)
	var rubber := _mat(Color(0.07, 0.07, 0.08), 0.62, 0.02)
	cockpit = Node3D.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)

	# --- steering wheel -----------------------------------------------------
	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = Poses.WHEEL_LOCAL
	pivot.rotation = Vector3(TILT, 0.0, 0.0)
	cockpit.add_child(pivot)
	wheel_visual = pivot

	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.105
	torus.outer_radius = 0.148
	torus.rings = 32
	torus.ring_segments = 14
	rim.mesh = torus
	rim.material_override = rubber
	pivot.add_child(rim)

	for i in 3:
		_box(pivot, Vector3(0.075, 0.014, 0.055), Vector3.ZERO, Vector3(0, 0, float(i) * 120.0),
			carbon, "Spoke%d" % i)
	_box(pivot, Vector3(0.17, 0.105, 0.035), Vector3.ZERO, Vector3.ZERO, carbon, "Hub")
	_box(pivot, Vector3(0.095, 0.048, 0.005), Vector3(0.0, 0.0, 0.022), Vector3.ZERO,
		_mat(Color(0.02, 0.04, 0.08), 0.3, 0.0, Color(0.05, 0.16, 0.34)), "Display")
	# Grips on both sides of the rim.
	_box(pivot, Vector3(0.028, 0.115, 0.030), Vector3(-0.145, 0.0, 0.0), Vector3.ZERO, rubber, "GripL")
	_box(pivot, Vector3(0.028, 0.115, 0.030), Vector3(0.145, 0.0, 0.0), Vector3.ZERO, rubber, "GripR")

	# --- shift lights across the top of the wheel ---------------------------
	for i in LED_COUNT:
		var lit := _box(pivot, Vector3(0.012, 0.010, 0.006), Vector3.ZERO, Vector3.ZERO,
			_mat(Color(0.05, 0.05, 0.06), 0.35, 0.0), "Led%d" % i)
		var a: float = lerpf(deg_to_rad(158.0), deg_to_rad(22.0), float(i) / float(LED_COUNT - 1))
		lit.position = Vector3(cos(a) * 0.175, sin(a) * 0.175, 0.0)
		_leds.append(lit)

	# --- dashboard, screen and side panels ----------------------------------
	dash = Node3D.new()
	dash.name = "Dash"
	cockpit.add_child(dash)
	_box(dash, Vector3(0.32, 0.035, 0.15), Poses.DASH_LOCAL, Vector3(24, 0, 0), carbon, "DashPlate")
	_box(dash, Vector3(0.21, 0.012, 0.075), Poses.DASH_LOCAL + Vector3(0.0, 0.027, -0.01), Vector3(24, 0, 0),
		_mat(Color(0.02, 0.03, 0.05), 0.25, 0.0, Color(0.04, 0.13, 0.26), 1.1), "DashScreen")
	_box(dash, Vector3(0.07, 0.34, 0.46), Vector3(-0.34, -0.26, -0.20), Vector3(-6, 6, 0), carbon, "PanelL")
	_box(dash, Vector3(0.07, 0.34, 0.46), Vector3(0.34, -0.26, -0.20), Vector3(-6, -6, 0), carbon, "PanelR")
	# Halo: the centre pillar in the driver's line of sight plus the top bar.
	_box(dash, Vector3(0.035, 0.32, 0.04), Vector3(0.0, -0.17, -1.05), Vector3(-14, 0, 0), carbon, "HaloPillar")
	_box(dash, Vector3(1.05, 0.030, 0.05), Vector3(0.0, 0.32, -1.35), Vector3(-6, 0, 0), carbon, "HaloBar")
	_box(dash, Vector3(0.085, 0.055, 0.018), Vector3(-0.31, -0.10, -1.00), Vector3(0, 14, 0), carbon, "MirrorL")
	_box(dash, Vector3(0.085, 0.055, 0.018), Vector3(0.31, -0.10, -1.00), Vector3(0, -14, 0), carbon, "MirrorR")
