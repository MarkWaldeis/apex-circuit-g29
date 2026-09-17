extends Camera3D
## Default view: helmet cam above the cockpit, looking down the nose (+Z).
##
## Everything here is built in CAMERA space: the lens looks along its own -Z, so
## a prop that has to be visible in the frame needs a negative local z.
##
## The wheel itself is the 3D model the driver picked (a Formula wheel with
## carbon face, coloured buttons and an LED strip), mounted on a raked column.
## Two gloved hands grip the rim and turn with it, exactly like the reference
## cockpit view. The shift lights follow the engine rpm.

const Poses = preload("res://scripts/camera_poses.gd")

const WHEEL_MODEL := "res://assets/props/steering_wheel.glb"
const WHEEL_WIDTH := 0.315          ## real Formula wheel is ~0.30-0.32 m wide
const TILT := deg_to_rad(-24.0)     ## column rake, top leaning away
const LED_COUNT := 12

var target: Node3D
var g29
var mode: int = 0 ## 0 cockpit, 1 chase, 2 heli
var wheel_visual: Node3D
var dash: Node3D
var cockpit: Node3D
var wheel_model: Node3D
var _dash_label: Label3D
var _leds: Array = []
var _wheel_rot: float = 0.0
var _props_shown: int = -1


func setup(car: Node3D, wheel_input) -> void:
	target = car
	g29 = wheel_input
	current = true
	far = 2200.0
	near = 0.04
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
	if _dash_label:
		var gear = target.get("gear")
		var kmh = target.get("speed_kmh")
		if gear != null and kmh != null:
			_dash_label.text = "%d   %d" % [int(gear), int(round(float(kmh)))]


func _snap() -> void:
	var xf: Transform3D = target.global_transform
	var steer_amt: float = 0.0
	if g29:
		steer_amt = g29.steer
	elif target.get("last_steer") != null:
		steer_amt = float(target.last_steer)
	var look: Vector3 = Poses.LOOK
	# The driver's head follows the wheel a little, which makes the cockpit feel
	# alive instead of glued to the hull.
	look.x += steer_amt * 1.2
	global_position = xf * Poses.HELMET
	look_at(xf * look, Vector3.UP)
	fov = 72.0
	# Turn the wheel inside its own plane: Godot applies Euler rotations as
	# Y * X * Z, so the z rotation happens before the column tilt.
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
			mat.emission_energy_multiplier = 2.6
		else:
			mat.albedo_color = Color(0.05, 0.05, 0.06)
			mat.emission_enabled = false


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


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: StandardMaterial3D, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.01)
	mi.mesh = cap
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


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
	# The tub sits in the body's shadow, so the whole cockpit would render as
	# black blobs. A soft lamp at the driver's head makes the wheel, the hands
	# and the dash readable - the same trick real cockpit shots use.
	var lamp := OmniLight3D.new()
	lamp.name = "CockpitLight"
	lamp.position = Vector3(0.0, 0.16, 0.12)
	lamp.light_color = Color(1.0, 0.97, 0.93)
	lamp.light_energy = 0.85
	lamp.omni_range = 2.4
	lamp.omni_attenuation = 1.1
	lamp.shadow_enabled = false
	cockpit.add_child(lamp)
	_build_wheel(cockpit)
	_build_hands()
	_build_dash(cockpit)
	_build_halo_and_mirrors(cockpit)


func _build_wheel(parent: Node3D) -> void:
	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = Poses.WHEEL_LOCAL
	pivot.rotation = Vector3(TILT, 0.0, 0.0)
	parent.add_child(pivot)
	wheel_visual = pivot

	var packed: PackedScene = load(WHEEL_MODEL)
	if packed:
		var inst: Node3D = packed.instantiate()
		inst.name = "WheelModel"
		pivot.add_child(inst)
		var bounds: AABB = _local_bounds(inst)
		var scale: float = WHEEL_WIDTH / maxf(bounds.size.x, 0.001)
		inst.scale = Vector3(scale, scale, scale)
		# Centre the artwork on the pivot: the model's own origin is off centre.
		inst.position = -bounds.get_center() * scale
		wheel_model = inst
		# The model's own LED strip is part of the texture, but it cannot light
		# up - so a thin row of real lamps sits right in front of it.
		var top: float = (bounds.end.y - bounds.get_center().y) * scale
		var half_width: float = bounds.size.x * 0.5 * scale * 0.62
		for i in LED_COUNT:
			var t: float = float(i) / float(LED_COUNT - 1)
			var led := _box(pivot, Vector3(0.008, 0.008, 0.004),
				Vector3(lerpf(-half_width, half_width, t), top * 0.96, 0.030),
				Vector3.ZERO, _mat(Color(0.05, 0.05, 0.06), 0.35, 0.0), "Led%d" % i)
			_leds.append(led)
	else:
		push_warning("Cockpit: steering wheel model missing, using a placeholder")
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.105
		torus.outer_radius = 0.148
		rim.mesh = torus
		rim.material_override = _mat(Color(0.07, 0.07, 0.08), 0.6, 0.05)
		pivot.add_child(rim)


func _build_hands() -> void:
	## Gloved hands gripping the rim at 9 and 3 o'clock. They are children of the
	## wheel pivot, so they turn with the wheel exactly like a real driver's.
	var glove := _mat(Color(0.15, 0.15, 0.17), 0.55, 0.05)
	var glove_dark := _mat(Color(0.06, 0.06, 0.07), 0.68, 0.03)
	var glove_accent := _mat(Color(0.86, 0.13, 0.15), 0.48, 0.07)
	var patch := _mat(Color(0.62, 0.63, 0.65), 0.50, 0.06)
	var seam := _mat(Color(0.42, 0.43, 0.45), 0.50, 0.12)
	var suit := _mat(Color(0.05, 0.055, 0.065), 0.62, 0.05)
	for side in [-1.0, 1.0]:
		# Grip at roughly 8 o'clock (left) and 4 o'clock (right) like in the
		# reference picture, not on the horizontal spokes.
		# Slightly in front of the wheel plane, so the gloved fingers are the
		# thing the driver sees and not a silhouette behind the rim.
		var grip := Vector3(side * WHEEL_WIDTH * 0.335, -WHEEL_WIDTH * 0.150, 0.004)
		var hand := Node3D.new()
		hand.name = "Hand_R" if side < 0.0 else "Hand_L"
		wheel_visual.add_child(hand)
		hand.position = grip
		hand.rotation_degrees = Vector3(0.0, 0.0, side * 34.0)
		# Fingers come over the front of the rim, the palm sits behind it.
		_box(hand, Vector3(0.064, 0.070, 0.042), Vector3.ZERO, Vector3.ZERO,
			glove, "Palm")
		# bright patch on the back of the hand: the cue that makes a dark glove
		# readable in front of a black carbon wheel
		_box(hand, Vector3(0.024, 0.015, 0.004), Vector3(side * 0.004, 0.010, 0.023), Vector3.ZERO,
			patch, "Patch")
		_box(hand, Vector3(0.056, 0.009, 0.030), Vector3(0.0, 0.036, -0.002), Vector3.ZERO,
			glove_accent, "Knuckle")
		for f in 4:
			var y: float = 0.030 - float(f) * 0.020
			# fingers curl from the palm over the front of the rim
			_capsule(hand, 0.0115, 0.050, Vector3(side * -0.016, y, 0.010), Vector3(78.0, 0.0, side * 24.0),
				glove, "Finger%d" % f)
			_capsule(hand, 0.0105, 0.034, Vector3(side * -0.024, y, -0.016), Vector3(116.0, 0.0, side * 24.0),
				glove_dark, "FingerTip%d" % f)
			# a light seam between the fingers so they read as fingers
			_box(hand, Vector3(0.034, 0.0024, 0.032), Vector3(side * -0.018, y - 0.010, 0.008),
				Vector3(70.0, 0.0, side * 24.0), seam, "Seam%d" % f)
		# thumb along the inside of the rim
		_capsule(hand, 0.012, 0.044, Vector3(side * -0.030, 0.040, 0.010), Vector3(80.0, side * 32.0, 0.0),
			glove, "Thumb")
		# Forearm drops away towards the driver and leaves the frame at the
		# bottom corner - pointing it straight at the lens would cover the wheel.
		_capsule(hand, 0.017, 0.36, Vector3(side * 0.060, -0.085, 0.16), Vector3(64.0, 0.0, side * 40.0),
			suit, "Arm")
		_box(hand, Vector3(0.044, 0.016, 0.040), Vector3(side * 0.028, -0.036, 0.058), Vector3(0.0, 0.0, side * 28.0),
			glove_accent, "Cuff")


func _build_dash(parent: Node3D) -> void:
	var carbon := _mat(Color(0.030, 0.030, 0.034), 0.42, 0.18)
	var screen_mat := _mat(Color(0.015, 0.020, 0.030), 0.22, 0.0, Color(0.06, 0.20, 0.42), 1.2)
	dash = Node3D.new()
	dash.name = "Dash"
	parent.add_child(dash)
	# The dash sits behind the wheel and shows only its upper edge above the rim,
	# exactly where a real driver sees it (and where the reference shows it).
	_box(dash, Vector3(0.34, 0.045, 0.16), Vector3(0.0, -0.045, -1.00), Vector3(16, 0, 0), carbon, "DashPlate")
	_box(dash, Vector3(0.19, 0.014, 0.07), Vector3(0.0, -0.024, -0.985), Vector3(16, 0, 0), screen_mat, "DashScreen")
	# A readable gear / speed readout on the dash, like the reference cockpit.
	_dash_label = Label3D.new()
	_dash_label.name = "DashReadout"
	_dash_label.text = "1   0"
	_dash_label.font_size = 120
	_dash_label.pixel_size = 0.0011
	_dash_label.outline_size = 24
	_dash_label.modulate = Color(0.92, 0.96, 1.0)
	_dash_label.outline_modulate = Color(0.02, 0.04, 0.08)
	_dash_label.position = Vector3(0.0, -0.030, -0.962)
	_dash_label.rotation_degrees = Vector3(16, 0, 0)
	_dash_label.no_depth_test = true
	dash.add_child(_dash_label)
	_box(dash, Vector3(0.045, 0.08, 0.14), Vector3(-0.20, -0.06, -0.96), Vector3(12, 8, 0), carbon, "DashWingL")
	_box(dash, Vector3(0.045, 0.08, 0.14), Vector3(0.20, -0.06, -0.96), Vector3(12, -8, 0), carbon, "DashWingR")
	# Cockpit tub: the carbon walls that frame the view like in the reference.
	_box(dash, Vector3(0.05, 0.30, 0.48), Vector3(-0.52, -0.29, -0.26), Vector3(-3, 16, 0), carbon, "TubL")
	_box(dash, Vector3(0.05, 0.30, 0.48), Vector3(0.52, -0.29, -0.26), Vector3(-3, -16, 0), carbon, "TubR")
	_box(dash, Vector3(0.52, 0.05, 0.30), Vector3(0.0, -0.44, -0.34), Vector3(8, 0, 0), carbon, "TubFloor")


func _build_halo_and_mirrors(parent: Node3D) -> void:
	var carbon := _mat(Color(0.030, 0.030, 0.034), 0.42, 0.18)
	var metal := _mat(Color(0.35, 0.37, 0.40), 0.30, 0.85)
	_box(parent, Vector3(0.036, 0.34, 0.042), Vector3(0.0, -0.15, -1.05), Vector3(-14, 0, 0), carbon, "HaloPillar")
	_box(parent, Vector3(1.05, 0.030, 0.05), Vector3(0.0, 0.33, -1.35), Vector3(-6, 0, 0), carbon, "HaloBar")
	# Mirrors: a carbon stalk with a slightly blue, semi-reflective glass.
	var glass := _mat(Color(0.30, 0.36, 0.44), 0.10, 0.60)
	for side in [-1.0, 1.0]:
		var stalk := _box(parent, Vector3(0.03, 0.028, 0.16), Vector3(side * 0.30, -0.10, -0.90),
			Vector3(0, side * 26.0, 0), carbon, "MirrorStalk")
		stalk.position.z = -0.90
		_box(parent, Vector3(0.105, 0.070, 0.016), Vector3(side * 0.355, -0.086, -0.965),
			Vector3(0, side * 30.0, 0), glass, "MirrorGlass")
		_box(parent, Vector3(0.115, 0.078, 0.010), Vector3(side * 0.352, -0.086, -0.972),
			Vector3(0, side * 30.0, 0), metal, "MirrorFrame")
