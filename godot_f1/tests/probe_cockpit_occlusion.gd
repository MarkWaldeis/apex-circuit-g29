extends SceneTree
## Occlusion probe for the cockpit view.
##
## The framing solver (tests/probe_framing.gd) places the halo, the wheel and the
## dash on the rows the reference picture has. It cannot know that the car's own
## bodywork is in the way - and at low eye heights it is: the nose ridge rises
## above the wheel and hides the driver's hands, which is the one thing the
## cockpit has to show.
##
## This probe measures the missing constraint: for a range of eye heights it
## projects (a) the silhouette top of the car's own body *beyond* the wheel and
## (b) the screen box of the wheel and of both hands, and reports whether the
## bodywork stays below the wheel.
##
##   PASS  bodywork top row > hand bottom row   -> wheel and hands fully visible
##   FAIL  bodywork top row <= hand bottom row  -> the car hides its own driver

const F1Car = preload("res://scripts/car_controller.gd")
const CockpitCamera = preload("res://scripts/cockpit_camera.gd")
const Poses = preload("res://scripts/camera_poses.gd")

const VIEW := Vector2(1920.0, 1080.0)
const FOV := 54.0
## The reference cockpit picture puts the horizon at 30 % of the frame height,
## so the camera pitch follows from the field of view.
const HORIZON_FRAC := 0.30
## Anything of the car ahead of the lens (car space, metres) can hide the wheel.
## The wheel itself hangs 0.40 m in front of the eye, so bodywork nearer than
## that sits *in front of* the wheel and paints over it - which is exactly what
## happens when the eye drops below the hull line.
const AHEAD_OF_LENS_Z := 0.18

var car
var cam
var body: MeshInstance3D
var wheel_model: Node3D
var hands: Array = []
var failed: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	root.size = Vector2i(int(VIEW.x), int(VIEW.y))
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment = e
	world.add_child(env)

	car = F1Car.new()
	car.name = "Player"
	car.livery = "crimson"
	world.add_child(car)
	car.setup(null, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))

	cam = CockpitCamera.new()
	cam.name = "Cam"
	world.add_child(cam)
	cam.setup(car, null)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT

	_collect_body(car)
	_collect_cockpit(cam)
	print("OCclusion probe: body=", body.name if body else "<none>",
		" wheel=", wheel_model.name if wheel_model else "<none>",
		" hands=", hands.size(),
		" viewport=", cam.get_viewport().get_visible_rect().size)
	for eye_y in [1.12, 1.20, 1.26, 1.29, 1.34, 1.40, 1.46]:
		_measure(eye_y)
	if failed > 0:
		print("COCKPIT_OCCLUSION FAIL count=", failed)
		quit(1)
	else:
		print("COCKPIT_OCCLUSION PASS")
		quit(0)


func _collect_body(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh and String(node.name).ends_with("_Body"):
		body = mi
	for c in node.get_children():
		_collect_body(c)


func _collect_cockpit(node: Node) -> void:
	var n := String(node.name)
	var n3 := node as Node3D
	if n == "WheelModel" and n3:
		wheel_model = n3
	if n.begins_with("Hand"):
		hands.append(node)
	for c in node.get_children():
		_collect_cockpit(c)


func _measure(eye_y: float) -> void:
	var look_z: float = 16.0
	var pitch: float = deg_to_rad((HORIZON_FRAC - 0.5) * -FOV)
	var eye := Vector3(0.0, eye_y, 0.05)
	var look := Vector3(0.0, eye_y - look_z * tan(pitch), eye.z + look_z)
	cam.global_position = car.global_transform * eye
	cam.look_at(car.global_transform * look, Vector3.UP)
	cam.fov = FOV

	var horizon: float = _row(car.global_transform * Vector3(0.0, eye_y, eye.z + 200.0))
	var wheel_rects: Array = []
	_collect_rects(wheel_model, wheel_rects)
	var wheel := _merge_rects(wheel_rects)
	var hand := _box_of(hands)
	var body_top := _body_silhouette_top()

	var visible: bool = body_top > hand.position.y
	if not visible:
		failed += 1
	print("eye_y=%.2f  horizon=%.1f%%  wheel y=%.1f..%.1f%%  hands y=%.1f..%.1f%%  body_top=%.1f%%  %s" % [
		eye_y, horizon,
		wheel.position.y, wheel.end.y,
		hand.position.y, hand.end.y,
		body_top,
		"OK" if visible else "HIDDEN"])


func _row(world: Vector3) -> float:
	return cam.unproject_position(world).y / VIEW.y * 100.0


func _node_box(mi: MeshInstance3D) -> Rect2:
	if mi == null:
		return Rect2()
	var aabb: AABB = mi.get_aabb()
	var xf: Transform3D = mi.global_transform
	var out := Rect2()
	var first := true
	for i in 8:
		var corner: Vector3 = aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		var p: Vector2 = cam.unproject_position(xf * corner)
		p.x = p.x / VIEW.x * 100.0
		p.y = p.y / VIEW.y * 100.0
		if first:
			out = Rect2(p, Vector2.ZERO)
			first = false
		else:
			out = out.expand(p)
	return out


func _box_of(nodes: Array) -> Rect2:
	var rects: Array = []
	for node in nodes:
		_collect_rects(node, rects)
	return _merge_rects(rects)


func _collect_rects(node: Node, into: Array) -> void:
	if node == null:
		return
	# The forearm and cuff are supposed to leave the frame; only the grip has to
	# stay visible, so they are excluded from the hand box.
	var n := String(node.name)
	if n == "Arm" or n == "Cuff":
		return
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		into.append(_node_box(mi))
	for c in node.get_children():
		_collect_rects(c, into)


func _merge_rects(rects: Array) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var out: Rect2 = rects[0]
	for i in range(1, rects.size()):
		out = out.merge(rects[i])
	return out


func _body_silhouette_top() -> float:
	## Upper envelope of the car's own bodywork in the centre column, measured on
	## the real vertices, so it describes what actually blocks the view.
	if body == null:
		return 100.0
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(body.mesh, 0) != OK:
		return 100.0
	var top_row: float = 100.0
	var top_z: float = 0.0
	var top_y: float = 0.0
	for i in mdt.get_vertex_count():
		var v: Vector3 = mdt.get_vertex(i)
		if absf(v.x) > 0.40 or v.z < AHEAD_OF_LENS_Z:
			continue
		var row: float = _row(body.global_transform * v)
		if row < top_row:
			top_row = row
			top_z = v.z
			top_y = v.y
	print("        bodywork nearest the centre line at z=%.2f y=%.2f" % [top_z, top_y])
	return top_row
