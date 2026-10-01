extends SceneTree
## Zufahrt-Mündung zur Hauptstraße: Bordsteine offen, Vorfahrt-Schild sichtbar.

var _world
var _frames := 0


func _initialize() -> void:
	var scene := load("res://scenes/school.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 14.0, -28.0)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.0, -60.0), Vector3.UP)
	cam.fov = 55.0
	_world.add_child(cam)
	cam.make_current()
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	_frames += 1
	if _frames == 5:
		var menu = _world.get_node_or_null("Menu")
		if menu and menu.has_method("resume_game"):
			menu.resume_game()
	if _frames == 50:
		var img: Image = root.get_texture().get_image()
		img.save_png("/tmp/zufahrt.png")
		print("SHOT saved")
		quit(0)
