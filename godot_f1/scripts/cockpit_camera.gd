extends Camera3D
## Helmet cam in the cockpit opening, looking down the nose (+Z).
##
## Everything here is built in CAMERA space: the lens looks along its own -Z, so
## a prop that has to be visible in the frame needs a negative local z. The
## layout is not eyeballed - camera_poses.gd documents the frame positions the
## reference cockpit picture has, and tests/test_cockpit_framing.gd locks them.
##
## What the driver sees:
##   * the real Formula steering wheel (a 3D model) on a raked column,
##   * two gloved hands gripping the rim at 9 and 3 o'clock that turn with it,
##   * a dashboard with gear, speed and a shift-light bar,
##   * the halo hoop overhead and two mirrors that really show the road behind.

const Poses = preload("res://scripts/camera_poses.gd")
const CockpitMirror = preload("res://scripts/cockpit_mirror.gd")

const WHEEL_MODEL := "res://assets/props/steering_wheel.glb"
const LED_COUNT := 14
const DASH_LED_COUNT := 12

var target: Node3D
var g29
var mode: int = 0 ## 0 cockpit, 1 chase, 2 heli
var wheel_visual: Node3D
var dash: Node3D
var cockpit: Node3D
var wheel_model: Node3D
var mirrors: Array = []
var _gear_label: Label3D
var _speed_label: Label3D
var _dash_leds: Array = []
var _leds: Array = []
var _wheel_rot: float = 0.0
var _props_shown: int = -1
var _fov: float = 54.0


func setup(car: Node3D, wheel_input) -> void:
	target = car
	g29 = wheel_input
	current = true
	far = 2200.0
	near = 0.03
	fov = Poses.FOV_COCKPIT
	_fov = Poses.FOV_COCKPIT
	doppler_tracking = Camera3D.DOPPLER_TRACKING_DISABLED
	_build_cockpit()
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_cycle"):
		mode = (mode + 1) % 3
		_set_cockpit_props_visible(mode == 0)


func _process(delta: float) -> void:
	if target == null:
		return
	# Keep the cockpit props in sync with the mode even when something else
	# (menu, test harness) switches the camera.
	if _props_shown != mode:
		_props_shown = mode
		_set_cockpit_props_visible(mode == 0)
	match mode:
		0:
			_snap(delta)
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
	if _gear_label:
		var gear = target.get("gear")
		var kmh = target.get("speed_kmh")
		if gear != null and kmh != null:
			_gear_label.text = "%d" % int(gear)
			_speed_label.text = "%d\nKM/H" % int(round(float(kmh)))


func _snap(delta: float = 0.0) -> void:
	## Rigid helmet cam: bolted to the car, so the halo, the mirrors and the dash
	## stay where they belong while the wheel in front of the driver turns.
	var xf: Transform3D = target.global_transform
	global_transform = xf * Poses.cockpit_transform()
	# A little more field of view at speed - the only camera cue that does not
	# move the cockpit props around.
	var speed: float = 0.0
	if target.get("speed_kmh") != null:
		speed = float(target.speed_kmh)
	var want_fov: float = Poses.FOV_COCKPIT + clampf(speed / 320.0, 0.0, 1.0) * 4.0
	_fov = lerpf(_fov, want_fov, clampf(delta * 1.5, 0.0, 1.0))
	fov = _fov

	var steer_amt: float = 0.0
	if g29:
		steer_amt = g29.steer
	elif target.get("last_steer") != null:
		steer_amt = float(target.last_steer)
	# Turn the wheel inside its own plane: Godot applies Euler rotations as
	# Y * X * Z, so the z rotation happens before the column tilt.
	_wheel_rot = lerpf(_wheel_rot, -steer_amt * Poses.WHEEL_TURN, 0.35)
	if wheel_visual:
		wheel_visual.rotation = Vector3(Poses.WHEEL_TILT, 0.0, _wheel_rot)


func set_rpm(rpm: float) -> void:
	if _leds.is_empty():
		return
	var n: float = clampf((rpm - 6000.0) / (12500.0 - 6000.0), 0.0, 1.0)
	var lit: int = int(round(n * float(_leds.size())))
	for i in _leds.size():
		var on: bool = i < lit
		var c: Color = Color(0.15, 0.85, 0.30)
		if i >= int(_leds.size() * 0.72):
			c = Color(0.95, 0.10, 0.10)
		elif i >= int(_leds.size() * 0.45):
			c = Color(0.95, 0.75, 0.10)
		_light_led(_leds[i], c if on else Color(0.05, 0.05, 0.06), on)
		if i < _dash_leds.size():
			_light_led(_dash_leds[i], c if on else Color(0.05, 0.05, 0.06), on)


func _light_led(led: MeshInstance3D, c: Color, on: bool) -> void:
	var mat: StandardMaterial3D = led.material_override
	if mat == null:
		return
	mat.albedo_color = c
	mat.emission_enabled = on
	if on:
		mat.emission = c
		mat.emission_energy_multiplier = 2.8


func _set_cockpit_props_visible(v: bool) -> void:
	if cockpit:
		cockpit.visible = v
	if dash:
		dash.visible = v


## ---- materials and primitives ---------------------------------------------

func _mat(color: Color, rough: float, metal: float, emissive: Color = Color(0, 0, 0, 0), energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emissive.a > 0.0 or emissive != Color(0, 0, 0, 0):
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.002)
	cap.radial_segments = 12
	cap.rings = 4
	mi.mesh = cap
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A beam (halo leg, mirror stalk) running from `a` to `b`.
func _beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	var mi := MeshInstance3D.new()
	mi.name = label
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, maxf(length, 0.01))
	mi.mesh = box
	mi.material_override = mat
	if length > 0.001:
		mi.transform = Transform3D(_basis_along(dir, false), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A limb (finger, thumb, arm) running from `a` to `b`, as a capsule whose long
## axis follows the segment.
func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	var mi := MeshInstance3D.new()
	mi.name = label
	if length < radius * 2.05:
		# A CapsuleMesh cannot be shorter than its own diameter, so a short
		# segment (a cuff ring, a knuckle) would silently become a ball. Use a
		# cylinder for those.
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = maxf(length, 0.002)
		cyl.radial_segments = 14
		mi.mesh = cyl
	else:
		var cap := CapsuleMesh.new()
		cap.radius = radius
		cap.height = length
		cap.radial_segments = 14
		cap.rings = 5
		mi.mesh = cap
	mi.material_override = mat
	if length > 0.001:
		mi.transform = Transform3D(_basis_along(dir, true), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _basis_along(dir: Vector3, along_y: bool) -> Basis:
	## Orthonormal basis whose +Y (capsule) or +Z (box) points along `dir`.
	var d: Vector3 = dir.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.985:
		up = Vector3.FORWARD
	var right: Vector3 = up.cross(d).normalized()
	if along_y:
		return Basis(right, d, right.cross(d).normalized())
	return Basis(right, d.cross(right).normalized(), d)


## Bounding box of a whole subtree in the coordinate system of `node`, so a GLB
## whose root carries an offset (this steering wheel sits 12 m off centre in its
## own file) can still be placed exactly where we want it.
func _local_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [{"node": node, "xf": Transform3D.IDENTITY}]
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var n: Node3D = item["node"]
		var xf: Transform3D = item["xf"]
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			var box: AABB = xf * mi.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
		for c in n.get_children():
			var c3 := c as Node3D
			if c3:
				stack.append({"node": c3, "xf": xf * c3.transform})
	return out


## ---- cockpit ---------------------------------------------------------------

func _build_cockpit() -> void:
	cockpit = Node3D.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	# The tub sits in the body's shadow, so without a little local light the
	# whole cockpit renders as black blobs. A soft lamp at the driver's head -
	# the trick real cockpit shots use - makes the wheel readable.
	var lamp := OmniLight3D.new()
	lamp.name = "CockpitLight"
	lamp.position = Vector3(0.0, 0.26, 0.12)
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.light_energy = 0.46
	lamp.omni_range = 2.6
	lamp.omni_attenuation = 0.9
	lamp.shadow_enabled = false
	cockpit.add_child(lamp)
	var fill := OmniLight3D.new()
	fill.name = "CockpitFill"
	fill.position = Vector3(0.0, -0.42, 0.10)
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.light_energy = 0.34
	fill.omni_range = 2.2
	fill.shadow_enabled = false
	cockpit.add_child(fill)
	var rim := OmniLight3D.new()
	rim.name = "CockpitRim"
	rim.position = Vector3(0.0, 0.02, 0.30)
	rim.light_color = Color(1.0, 0.93, 0.86)
	rim.light_energy = 0.30
	rim.omni_range = 1.1
	rim.shadow_enabled = false
	cockpit.add_child(rim)

	_build_wheel(cockpit)
	_build_dash(cockpit)
	_build_halo(cockpit)
	_build_tub(cockpit)
	_build_mirrors(cockpit)


func _build_wheel(parent: Node3D) -> void:
	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = Poses.WHEEL_LOCAL
	pivot.rotation = Vector3(Poses.WHEEL_TILT, 0.0, 0.0)
	parent.add_child(pivot)
	wheel_visual = pivot

	var packed: PackedScene = load(WHEEL_MODEL)
	if packed:
		var inst: Node3D = packed.instantiate()
		inst.name = "WheelModel"
		pivot.add_child(inst)
		var bounds: AABB = _local_bounds(inst)
		var scale: float = Poses.WHEEL_WIDTH / maxf(bounds.size.x, 0.001)
		inst.scale = Vector3(scale, scale, scale)
		inst.position = -bounds.get_center() * scale
		wheel_model = inst
		var half_h: float = bounds.size.y * 0.5 * scale
		_build_wheel_leds(pivot, half_h)
	else:
		push_warning("Cockpit: steering wheel model missing, using a placeholder")
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.105
		torus.outer_radius = 0.148
		rim.mesh = torus
		rim.material_override = _mat(Color(0.07, 0.07, 0.08), 0.6, 0.05)
		pivot.add_child(rim)
	_build_hands(pivot)


func _build_wheel_leds(pivot: Node3D, half_h: float) -> void:
	## The model's LED strip is baked into its texture and cannot light up, so a
	## row of real lamps sits right on top of it and follows the engine.
	var span: float = Poses.WHEEL_WIDTH * 0.34
	for i in LED_COUNT:
		var t: float = 0.0 if LED_COUNT <= 1 else float(i) / float(LED_COUNT - 1)
		var led := _box(pivot, Vector3(0.0125, 0.0105, 0.005),
			Vector3(lerpf(-span, span, t), half_h * 0.90, 0.030),
			Vector3(0, 0, 0), _mat(Color(0.05, 0.05, 0.06), 0.35, 0.0), "Led%d" % i)
		_leds.append(led)


func _build_hands(pivot: Node3D) -> void:
	## Gloved hands gripping the rim at 9 and 3 o'clock. They are children of the
	## wheel pivot, so they turn with the wheel exactly like a real driver's.
	var glove := _mat(Color(0.042, 0.043, 0.049), 0.70, 0.03)
	var glove_top := _mat(Color(0.072, 0.074, 0.082), 0.62, 0.04)
	var glove_dark := _mat(Color(0.030, 0.031, 0.035), 0.76, 0.02)
	var logo := _mat(Color(0.80, 0.81, 0.83), 0.55, 0.03)
	var accent := _mat(Color(0.70, 0.09, 0.10), 0.62, 0.03)
	var suit := _mat(Color(0.070, 0.073, 0.081), 0.74, 0.02)
	# The rim tube of the wheel model sits at roughly 41 % of the wheel width.
	var rim_x: float = Poses.WHEEL_WIDTH * 0.41
	for side in [-1.0, 1.0]:
		# The grip sits a little above the horizontal axis, the way a driver
		# actually holds a wheel - 9:30 and 2:30 rather than 9 and 3.
		var cx: float = side * rim_x
		var cy: float = Poses.WHEEL_WIDTH * 0.10
		var hand := Node3D.new()
		hand.name = "Hand_R" if side < 0.0 else "Hand_L"
		pivot.add_child(hand)
		hand.position = Vector3(cx, cy, 0.0)

		# The closed fist is one smooth mass sitting on the rim - a hand seen
		# from behind is a single shape, not a bundle of sausages.
		var palm := MeshInstance3D.new()
		palm.name = "Fist"
		var ball := SphereMesh.new()
		ball.radius = 0.030
		ball.height = 0.060
		ball.radial_segments = 20
		ball.rings = 10
		palm.mesh = ball
		palm.material_override = glove
		palm.position = Vector3(side * 0.004, 0.002, 0.012)
		palm.scale = Vector3(0.86, 1.48, 0.82)
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(palm)
		# back of the hand: a second, lighter shell so the glove separates from
		# the black carbon wheel instead of vanishing into it
		var back := MeshInstance3D.new()
		back.name = "BackOfHand"
		var shell := SphereMesh.new()
		shell.radius = 0.023
		shell.height = 0.046
		shell.radial_segments = 16
		shell.rings = 8
		back.mesh = shell
		back.material_override = glove_top
		back.position = Vector3(side * 0.008, 0.002, 0.028)
		back.scale = Vector3(0.84, 1.42, 0.46)
		back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(back)
		_box(hand, Vector3(0.014, 0.0075, 0.003), Vector3(side * 0.006, 0.024, 0.043),
			Vector3(0, 0, side * 6.0), logo, "Logo")
		for f in 4:
			var y: float = 0.034 - float(f) * 0.022
			# fingers only just stand proud of the fist, the way a glove looks
			# from the driver's side
			_limb(hand, Vector3(side * -0.006, y, 0.020), Vector3(side * -0.030, y, 0.008),
				0.0076, glove, "Finger%d" % f)
			_limb(hand, Vector3(side * -0.030, y, 0.008), Vector3(side * -0.042, y - 0.004, -0.002),
				0.0068, glove_dark, "FingerTip%d" % f)
		# thumb along the inside of the rim
		_limb(hand, Vector3(side * 0.000, 0.046, 0.020), Vector3(side * -0.024, 0.060, 0.010),
			0.0105, glove, "Thumb")
		# cuff and forearm, dropping out of the bottom of the frame
		_limb(hand, Vector3(side * 0.008, -0.046, 0.022), Vector3(side * 0.012, -0.078, 0.020),
			0.0300, suit, "Cuff")
		_limb(hand, Vector3(side * 0.011, -0.074, 0.020), Vector3(side * 0.014, -0.090, 0.019),
			0.0312, accent, "CuffBand")
		_limb(hand, Vector3(side * 0.014, -0.088, 0.019), Vector3(side * 0.240, -0.420, 0.020),
			0.0288, suit, "Arm")


func _build_dash(parent: Node3D) -> void:
	var carbon := _mat(Color(0.030, 0.030, 0.034), 0.62, 0.06)
	var screen_mat := _mat(Color(0.012, 0.020, 0.032), 0.86, 0.0, Color(0.05, 0.17, 0.32), 1.0)
	var bezel := _mat(Color(0.018, 0.019, 0.022), 0.60, 0.10)
	dash = Node3D.new()
	dash.name = "Dash"
	dash.position = Poses.DASH_LOCAL
	dash.rotation = Vector3(Poses.DASH_TILT, 0.0, 0.0)
	parent.add_child(dash)
	var w: float = Poses.DASH_SIZE.x
	var h: float = Poses.DASH_SIZE.y
	_box(dash, Vector3(w, h, 0.020), Vector3.ZERO, Vector3.ZERO, carbon, "DashPlate")
	_box(dash, Vector3(w * 0.92, h * 0.62, 0.006), Vector3(0.0, -0.004, 0.012), Vector3.ZERO,
		screen_mat, "DashScreen")
	_box(dash, Vector3(w * 0.96, h * 0.70, 0.004), Vector3(0.0, -0.004, 0.014), Vector3.ZERO,
		bezel, "DashBezel")
	# The bezel must frame the screen, not cover it - rebuild it as four thin
	# strips instead of a plate.
	dash.get_node("DashBezel").queue_free()
	var hw: float = w * 0.46
	var hh: float = h * 0.33
	var t: float = 0.007
	_box(dash, Vector3(hw * 2.0, t, 0.004), Vector3(0.0, hh, 0.014), Vector3.ZERO, bezel, "BezelTop")
	_box(dash, Vector3(hw * 2.0, t, 0.004), Vector3(0.0, -hh, 0.014), Vector3.ZERO, bezel, "BezelBottom")
	_box(dash, Vector3(t, hh * 2.0, 0.004), Vector3(-hw, 0.0, 0.014), Vector3.ZERO, bezel, "BezelLeft")
	_box(dash, Vector3(t, hh * 2.0, 0.004), Vector3(hw, 0.0, 0.014), Vector3.ZERO, bezel, "BezelRight")
	# side wings of the dashboard, so the panel is not a floating brick
	_box(dash, Vector3(0.055, h * 0.9, 0.10), Vector3(-w * 0.62, -0.006, -0.045), Vector3(0, 22, 0), carbon, "DashWingL")
	_box(dash, Vector3(0.055, h * 0.9, 0.10), Vector3(w * 0.62, -0.006, -0.045), Vector3(0, -22, 0), carbon, "DashWingR")

	_gear_label = Label3D.new()
	_gear_label.name = "GearReadout"
	_gear_label.text = "1"
	_gear_label.font_size = 84
	_gear_label.pixel_size = 0.00062
	_gear_label.outline_size = 12
	_gear_label.modulate = Color(0.95, 0.97, 1.0)
	_gear_label.outline_modulate = Color(0.01, 0.02, 0.04)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gear_label.position = Vector3(w * 0.20, -0.002, 0.020)
	_gear_label.no_depth_test = false
	dash.add_child(_gear_label)

	_speed_label = Label3D.new()
	_speed_label.name = "SpeedReadout"
	_speed_label.text = "0\nKM/H"
	_speed_label.font_size = 44
	_speed_label.pixel_size = 0.00055
	_speed_label.outline_size = 10
	_speed_label.modulate = Color(0.90, 0.94, 1.0)
	_speed_label.outline_modulate = Color(0.01, 0.02, 0.04)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.line_spacing = -0.15
	_speed_label.position = Vector3(-w * 0.24, -0.002, 0.020)
	dash.add_child(_speed_label)

	# Shift lights along the top edge of the dash panel.
	var span: float = w * 0.33
	for i in DASH_LED_COUNT:
		var t01: float = 0.0 if DASH_LED_COUNT <= 1 else float(i) / float(DASH_LED_COUNT - 1)
		var led := _box(dash, Vector3(0.0105, 0.0085, 0.004),
			Vector3(lerpf(-span, span, t01), h * 0.44, 0.014),
			Vector3.ZERO, _mat(Color(0.05, 0.05, 0.06), 0.35, 0.0), "DashLed%d" % i)
		_dash_leds.append(led)


func _build_halo(parent: Node3D) -> void:
	var carbon := _mat(Color(0.032, 0.032, 0.036), 0.60, 0.08)
	var bar_y: float = Poses.HALO_LOCAL.y
	var bar_z: float = Poses.HALO_LOCAL.z
	var half: float = Poses.HALO_WIDTH * 0.5
	_box(parent, Vector3(Poses.HALO_WIDTH, Poses.HALO_THICK, 0.055),
		Vector3(0.0, bar_y, bar_z), Vector3.ZERO, carbon, "HaloBar")
	# The centre pod hanging under the bar (in the reference this is the onboard
	# camera mount) - the detail that makes the hoop read as a hoop.
	_box(parent, Vector3(0.055, 0.062, 0.050),
		Vector3(0.0, bar_y - Poses.HALO_THICK * 0.5 - 0.029, bar_z + 0.002),
		Vector3.ZERO, carbon, "HaloPod")
	_box(parent, Vector3(0.026, 0.012, 0.004),
		Vector3(0.0, bar_y - Poses.HALO_THICK * 0.5 - 0.040, bar_z + 0.028),
		Vector3.ZERO, _mat(Color(0.01, 0.012, 0.02), 0.25, 0.0, Color(0.03, 0.06, 0.12), 1.0), "HaloPodLens")
	# Legs sweeping from the ends of the bar down past the driver's shoulders.
	for side in [-1.0, 1.0]:
		_beam(parent,
			Vector3(side * half, bar_y, bar_z),
			Vector3(side * 0.62, -0.30, 0.02),
			0.036, carbon, "HaloLeg_%s" % ("L" if side < 0.0 else "R"))


func _build_tub(parent: Node3D) -> void:
	var carbon := _mat(Color(0.075, 0.075, 0.082), 0.66, 0.05)
	var tub := Node3D.new()
	tub.name = "Tub"
	parent.add_child(tub)
	# Side walls: they only enter the frame at the bottom corners, exactly the
	# way the reference shot frames the cockpit.
	for side in [-1.0, 1.0]:
		_box(tub, Vector3(0.06, 0.55, 0.62), Vector3(side * 0.355, -0.33, -0.44),
			Vector3(-4.0, side * -13.0, 0.0), carbon, "TubWall_%s" % ("L" if side < 0.0 else "R"))
		_box(tub, Vector3(0.16, 0.05, 0.26), Vector3(side * 0.325, -0.245, -0.60),
			Vector3(-18.0, side * -12.0, 0.0), carbon, "TubShoulder_%s" % ("L" if side < 0.0 else "R"))
	_box(tub, Vector3(0.72, 0.06, 0.55), Vector3(0.0, -0.56, -0.42), Vector3(-6, 0, 0), carbon, "TubFloor")


func _build_mirrors(parent: Node3D) -> void:
	## Two mirrors that really show the road behind: a small SubViewport camera at
	## the tail of the car, mapped onto the glass.
	var carbon := _mat(Color(0.045, 0.045, 0.050), 0.62, 0.08)
	for side in [-1.0, 1.0]:
		var mirror: Node3D = CockpitMirror.new()
		mirror.name = "Mirror_%s" % ("L" if side < 0.0 else "R")
		parent.add_child(mirror)
		mirror.position = Vector3(Poses.MIRROR_LOCAL.x * side, Poses.MIRROR_LOCAL.y, Poses.MIRROR_LOCAL.z)
		mirror.rotation_degrees = Vector3(0.0, -side * 34.0, 0.0)
		mirror.setup(target, Poses.MIRROR_SIZE,
			Vector3(side * 0.42, 1.32, -2.85),
			-side * 13.0, -3.0, 46.0,
			Color(0.72, 0.76, 0.80))
		mirrors.append(mirror)
		# stalk from the mirror pod back into the cockpit side
		_beam(parent,
			Vector3(side * Poses.MIRROR_LOCAL.x * 0.92, Poses.MIRROR_LOCAL.y - 0.004, Poses.MIRROR_LOCAL.z - 0.012),
			Vector3(side * 0.30, -0.16, 0.02),
			0.026, carbon, "MirrorStalk_%s" % ("L" if side < 0.0 else "R"))
