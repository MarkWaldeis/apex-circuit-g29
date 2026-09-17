extends SceneTree
## Cockpit view capture harness: drives the real scene for a while and writes
## a set of screenshots (straight, full left, full right, braking, chase) plus
## wheel telemetry, so the cockpit can be judged against the reference picture.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var frames: int = 0
var _steer_script: float = 0.0
var _gas: bool = true
var _saved_wheel_on: Image


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	var player = main.get("player")
	var cam = main.get("cam")
	if player == null or cam == null:
		return
	if frames == 30:
		# no menu: drive straight away
		var m = main.get("menu")
		if m and m.has_method("resume_game"):
			m.resume_game()
		if player.has_method("apply_throttle"):
			player.apply_throttle(1.0)
	match frames:
		240:
			player.apply_throttle(1.0)
			_snap("cp_01_straight.png", player, cam)
			_measure_wheel(player, cam)
		242:
			_measure_wheel_off(cam)
		400:
			player.apply_throttle(0.85)
			_steer(player, 1.0)
			_snap("cp_02_full_right.png", player, cam)
		560:
			player.apply_throttle(0.85)
			_steer(player, -1.0)
			_snap("cp_03_full_left.png", player, cam)
		720:
			_steer(player, 0.0)
			player.apply_throttle(0.0)
			player.apply_brake(1.0)
			_snap("cp_04_braking.png", player, cam)
		880:
			player.apply_brake(0.0)
			player.apply_throttle(1.0)
			cam.mode = 1
		940:
			_snap("cp_05_chase.png", player, cam)
			_report_mirrors(cam)
			_report_wheels(player)
			print("FPS ", Engine.get_frames_per_second())
			quit(0)


func _steer(player, amount: float) -> void:
	player.set_meta("script_steer", amount)


func _measure_wheel(player, cam) -> void:
	## Objective check on the framing: render the cockpit with and without the
	## steering wheel and diff the two images, which gives the wheel's exact
	## rectangle in the frame - no eyeballing.
	# The whole car has to stand still, otherwise the track itself changes
	# between the two frames and the diff is meaningless.
	player.freeze = true
	var ai = main.get("ai_car")
	if ai:
		ai.visible = false
	_saved_wheel_on = get_root().get_viewport().get_texture().get_image()
	_saved_wheel_on.save_png(OUT_DIR + "/cp_20_wheel_on.png")
	cam.wheel_visual.visible = false


func _measure_wheel_off(cam) -> void:
	var off: Image = get_root().get_viewport().get_texture().get_image()
	off.save_png(OUT_DIR + "/cp_21_wheel_off.png")
	cam.wheel_visual.visible = true
	var ai2 = main.get("ai_car")
	if ai2:
		ai2.visible = true
	var on: Image = _saved_wheel_on
	on.convert(Image.FORMAT_RGB8)
	off.convert(Image.FORMAT_RGB8)
	var w: int = on.get_width()
	var h: int = on.get_height()
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	var count := 0
	for y in h:
		for x in w:
			var a: Color = on.get_pixel(x, y)
			var b: Color = off.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.10:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				count += 1
	if max_x < 0:
		print("WHEELFRAME none")
		return
	print("WHEELFRAME x=", min_x, "..", max_x,
		" (", "%.1f" % (float(min_x) / float(w) * 100.0), "% .. ",
		"%.1f" % (float(max_x) / float(w) * 100.0), "% )",
		" y=", min_y, "..", max_y,
		" ( ", "%.1f" % (float(min_y) / float(h) * 100.0), "% .. ",
		"%.1f" % (float(max_y) / float(h) * 100.0), "% )",
		" pixels=", count)


func _snap(file: String, player, cam) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT failed ", file)
		return
	print("SHOT ", file, " err=", img.save_png(OUT_DIR + "/" + file),
		" kmh=", snapped(player.speed_kmh, 0.1), " gear=", player.gear,
		" steer=", snapped(player.last_steer, 0.01), " mode=", cam.mode)


func _report_wheels(player) -> void:
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: VehicleWheel3D = player.get_node_or_null(name)
		if w == null:
			continue
		var mesh: Node3D = null
		for c in w.get_children():
			if c is MeshInstance3D:
				mesh = c
				break
		var contact: Vector3 = w.get_contact_point()
		var hub: Vector3 = w.global_transform.origin if mesh == null else mesh.global_transform.origin
		print("WHEEL ", name, " contact=", w.is_in_contact(),
			" rpm=", "%.1f" % w.get_rpm(),
			" contact_y=", "%.4f" % contact.y,
			" hub_y=", "%.4f" % hub.y,
			" gap=", "%.4f" % (hub.y - contact.y),
			" node_y=", "%.4f" % w.position.y,
			" mesh_y=", "%.4f" % (mesh.position.y if mesh else 0.0))


func _report_mirrors(cam) -> void:
	## Is the mirror viewport really rendering the road behind, or just black?
	if cam == null or cam.get("mirrors") == null:
		return
	for m in cam.mirrors:
		if m == null or m.viewport == null:
			continue
		var img: Image = m.viewport.get_texture().get_image()
		if img == null:
			print("MIRROR ", m.name, " no image")
			continue
		img.convert(Image.FORMAT_RGB8)
		var sum := Vector3.ZERO
		var w: int = img.get_width()
		var h: int = img.get_height()
		var step: int = maxi(w / 32, 1)
		var n: int = 0
		for y in range(0, h, step):
			for x in range(0, w, step):
				var c: Color = img.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		var mean: Vector3 = sum / float(maxi(n, 1))
		print("MIRROR ", m.name, " size=", img.get_size(),
			" mean=(", "%.3f" % mean.x, ", ", "%.3f" % mean.y, ", ", "%.3f" % mean.z, ")",
			" cam_pos=", m.view_cam.global_position, " cam_fwd=", -m.view_cam.global_transform.basis.z)
