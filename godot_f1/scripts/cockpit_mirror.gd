extends Node3D
## A rear-view mirror that really shows the road behind.
##
## The glass is a small SubViewport rendered by its own camera. That camera is
## glued to the car's tail - a little above and beside the rear wing, looking
## back down the straight - because that is the only place from which a rear
## view is not blocked by the car's own body. The image is flipped horizontally
## so it reads like a mirror and not like a second windscreen.
##
## Note the camera yaw convention: a Camera3D looks along its own -Z, and the
## car's nose is +Z, so yaw 0 already looks straight back over the tail.
##
## The module is deliberately small: 320x180 pixels, only updated when the
## cockpit is on screen, and never more often than `interval` frames.

const RESOLUTION := Vector2i(320, 180)
## Cockpit props live on layer 2 so a mirror can never film itself.
const PROP_LAYER := 2

var car: Node3D
var viewport: SubViewport
var view_cam: Camera3D

var cam_pos := Vector3(0.0, 1.35, -2.95)
var cam_basis := Basis.IDENTITY
var interval: int = 1
var _tick: int = 0
var _glass: MeshInstance3D
var _was_visible: bool = false


func setup(p_car: Node3D, size: Vector2, p_cam_pos: Vector3, cam_yaw_deg: float,
		cam_pitch_deg: float, fov: float, tint: Color) -> void:
	car = p_car
	cam_pos = p_cam_pos
	cam_basis = Basis.from_euler(Vector3(
		deg_to_rad(cam_pitch_deg), deg_to_rad(cam_yaw_deg), 0.0))

	viewport = SubViewport.new()
	viewport.name = "MirrorView"
	viewport.size = RESOLUTION
	viewport.own_world_3d = false
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	view_cam = Camera3D.new()
	view_cam.name = "MirrorCam"
	view_cam.fov = fov
	view_cam.near = 0.10
	view_cam.far = 900.0
	view_cam.cull_mask = ~(1 << (PROP_LAYER - 1)) & 0xFFFFF
	viewport.add_child(view_cam)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	# Mirrors flip front-to-back, not left-to-right: the texture has to be
	# mirrored in u so the glass reads the same way a real one does.
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = size
	_glass.mesh = quad
	_glass.material_override = mat
	_glass.layers = 1 << (PROP_LAYER - 1)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)

	var carbon := StandardMaterial3D.new()
	carbon.albedo_color = Color(0.055, 0.056, 0.062)
	carbon.roughness = 0.62
	carbon.metallic = 0.08
	# A frame made of four thin strips, not a plate: a solid housing in front of
	# the glass would simply cover the reflection.
	var edge: float = 0.011
	var strips := [
		{"size": Vector3(size.x + edge * 2.0, edge, 0.010), "pos": Vector3(0.0, size.y * 0.5 + edge * 0.5, 0.005)},
		{"size": Vector3(size.x + edge * 2.0, edge, 0.010), "pos": Vector3(0.0, -size.y * 0.5 - edge * 0.5, 0.005)},
		{"size": Vector3(edge, size.y + edge * 2.0, 0.010), "pos": Vector3(-size.x * 0.5 - edge * 0.5, 0.0, 0.005)},
		{"size": Vector3(edge, size.y + edge * 2.0, 0.010), "pos": Vector3(size.x * 0.5 + edge * 0.5, 0.0, 0.005)},
	]
	for i in strips.size():
		var strip := MeshInstance3D.new()
		strip.name = "Frame%d" % i
		var sb := BoxMesh.new()
		sb.size = strips[i]["size"]
		strip.mesh = sb
		strip.material_override = carbon
		strip.position = strips[i]["pos"]
		strip.layers = 1 << (PROP_LAYER - 1)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)

	var back := MeshInstance3D.new()
	back.name = "Back"
	var back_box := BoxMesh.new()
	back_box.size = Vector3(size.x + 0.028, size.y + 0.028, 0.03)
	back.mesh = back_box
	var pod := StandardMaterial3D.new()
	pod.albedo_color = Color(0.05, 0.55, 0.52)
	pod.roughness = 0.35
	pod.metallic = 0.30
	back.material_override = pod
	back.position = Vector3(0.0, 0.0, -0.016)
	back.layers = 1 << (PROP_LAYER - 1)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)


func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car) or view_cam == null:
		return
	var shown: bool = is_visible_in_tree()
	_tick += 1
	if not shown:
		if _was_visible:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_was_visible = false
		return
	var refresh: bool = _tick % maxi(interval, 1) == 0
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if refresh else SubViewport.UPDATE_DISABLED)
	_was_visible = true
	view_cam.global_transform = car.global_transform * Transform3D(cam_basis, cam_pos)
