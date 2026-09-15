extends Camera3D
## Default view: above the hull, looking down the nose. Wheel on camera -Z.

const Poses = preload("res://scripts/camera_poses.gd")

var target: Node3D
var g29
var mode: int = 0 ## 0 cockpit, 1 chase, 2 heli
var wheel_visual: Node3D
var dash: Node3D


func setup(car: Node3D, wheel_input) -> void:
	target = car
	g29 = wheel_input
	current = true
	far = 2200.0
	near = 0.08
	fov = 72.0
	doppler_tracking = Camera3D.DOPPLER_TRACKING_DISABLED
	_build_wheel()
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_cycle"):
		mode = (mode + 1) % 3
		_set_cockpit_props_visible(mode == 0)


func _process(_delta: float) -> void:
	if target == null:
		return
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
	if wheel_visual:
		wheel_visual.rotation = Vector3(0.0, 0.0, -steer_amt * 2.4)


func _set_cockpit_props_visible(v: bool) -> void:
	if wheel_visual:
		wheel_visual.visible = v
	if dash:
		dash.visible = v


func _build_wheel() -> void:
	var holder := Node3D.new()
	holder.name = "CockpitWheel"
	add_child(holder)
	holder.position = Poses.WHEEL_LOCAL
	wheel_visual = holder
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.155
	torus.rings = 24
	torus.ring_segments = 16
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.07, 0.08)
	mat.roughness = 0.4
	mat.metallic = 0.15
	ring.material_override = mat
	ring.rotation_degrees = Vector3(78, 0, 0)
	holder.add_child(ring)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 0.04
	hub.mesh = cyl
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.75, 0.12, 0.12)
	hub.material_override = hmat
	hub.rotation_degrees = Vector3(78, 0, 0)
	holder.add_child(hub)
	dash = MeshInstance3D.new()
	dash.name = "CockpitDash"
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.045, 0.16)
	dash.mesh = box
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.05, 0.05, 0.055)
	dmat.roughness = 0.55
	dash.material_override = dmat
	dash.position = Poses.DASH_LOCAL
	add_child(dash)
