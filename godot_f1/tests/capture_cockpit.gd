extends SceneTree
## Cockpit view capture harness: drives the real scene for a while and writes
## a set of screenshots (straight, full left, full right, braking, chase) plus
## wheel telemetry, so the cockpit can be judged against the reference picture.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var frames: int = 0
var _steer_script: float = 0.0
var _gas: bool = true


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
			_report_wheels(player)
			print("FPS ", Engine.get_frames_per_second())
			quit(0)


func _steer(player, amount: float) -> void:
	player.set_meta("script_steer", amount)


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
			" rpm=", snapped(w.get_rpm(), 1.0),
			" contact_y=", snapped(contact.y, 4),
			" hub_y=", snapped(hub.y, 4),
			" gap=", snapped(hub.y - contact.y, 4),
			" node_y=", snapped(w.position.y, 4))
