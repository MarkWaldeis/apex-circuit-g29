extends SceneTree
## Screenshot der Stadt-Kreuzung mit Ampeln (freie Kamera).

var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/school.tscn")
	var world: Node3D = packed.instantiate()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(-72.0, 26.0, -32.0)
	cam.look_at_from_position(cam.position, Vector3(-100.0, 0.0, -60.0), Vector3.UP)
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	_world = world
	physics_frame.connect(_on_phys)


var _world: Node3D


func _on_phys() -> void:
	frames += 1
	if frames == 5:
		var menu = _world.get("menu")
		if menu:
			menu.resume_game()
	if frames == 140:
		root.get_texture().get_image().save_png("/tmp/city_junction.png")
		print("SHOT saved /tmp/city_junction.png")
		quit(0)
