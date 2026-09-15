extends Camera3D
## Helmet-cam: default view. Looks along vehicle +Z (forward).

var target: Node3D
var g29
var mode: int = 0 ## 0 cockpit, 1 chase, 2 heli
var wheel_visual: Node3D

# Just above the halo, looking down the nose. Godot cameras look along local -Z,
# so props in front of the lens must sit on -Z.
const HELMET := Vector3(0.0, 1.14, 0.22)
const LOOK := Vector3(0.0, 0.48, 14.0)
const WHEEL_LOCAL := Vector3(0.0, -0.26, -0.48)


func setup(car: Node3D, wheel_input) -> void:
	target = car
	g29 = wheel_input
	current = true
	far = 2200.0
	near = 0.04
	fov = 68.0
	doppler_tracking = Camera3D.DOPPLER_TRACKING_DISABLED
	_build_wheel()
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_cycle"):
		mode = (mode + 1) % 3
		if wheel_visual:
			wheel_visual.visible = mode == 0


func _process(_delta: float) -> void:
	if target == null:
		return
	match mode:
		0:
			_snap()
		1:
			var follow := target.global_transform
			var origin: Vector3 = follow.origin + follow.basis.y * 2.4 - follow.basis.z * 7.4
			global_position = origin
			look_at(follow.origin + follow.basis.z * 10.0 + follow.basis.y * 0.4, Vector3.UP)
			fov = 62.0
		2:
			var o: Vector3 = target.global_position + Vector3(0, 46, 20)
			global_position = o
			look_at(target.global_position, Vector3.UP)
			fov = 55.0


func _snap() -> void:
	var xf: Transform3D = target.global_transform
	var steer_amt: float = 0.0
	if g29:
		steer_amt = g29.steer
	elif target.get("last_steer") != null:
		steer_amt = float(target.last_steer)
	var yaw := steer_amt * 0.10
	var helmet: Vector3 = HELMET
	var look: Vector3 = LOOK
	look.x += tan(yaw) * LOOK.z
	global_position = xf * helmet
	look_at(xf * look, xf.basis.y)
	fov = 70.0
	if wheel_visual:
		wheel_visual.rotation = Vector3(deg_to_rad(-18.0), 0.0, -steer_amt * 2.6)


func _build_wheel() -> void:
	var holder := Node3D.new()
	holder.name = "CockpitWheel"
	add_child(holder)
	holder.position = WHEEL_LOCAL
	wheel_visual = holder
	var packed: PackedScene = load("res://assets/props/steering_wheel.glb")
	if packed:
		var inst: Node3D = packed.instantiate()
		inst.name = "WheelMesh"
		holder.add_child(inst)
		inst.scale = Vector3(0.22, 0.22, 0.22)
		inst.rotation_degrees = Vector3(-22, 180, 0)
		inst.position = Vector3(0, 0, 0)
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.09
		torus.outer_radius = 0.14
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.06, 0.06, 0.07)
		mat.roughness = 0.35
		mat.metallic = 0.2
		ring.material_override = mat
		holder.add_child(ring)
	# Carbon dash under the wheel so the view is framed, not empty mesh guts.
	var dash := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.06, 0.22)
	dash.mesh = box
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.04, 0.04, 0.045)
	dmat.roughness = 0.5
	dash.material_override = dmat
	dash.position = Vector3(0.0, -0.36, -0.38)
	dash.rotation_degrees = Vector3(18, 0, 0)
	add_child(dash)
	var left := _side_panel(-0.38)
	var right := _side_panel(0.38)
	add_child(left)
	add_child(right)


func _side_panel(x: float) -> MeshInstance3D:
	var p := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.42, 0.7)
	p.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.035)
	mat.roughness = 0.55
	p.material_override = mat
	p.position = Vector3(x, -0.22, -0.18)
	p.rotation_degrees = Vector3(-8, 0, 0)
	return p
