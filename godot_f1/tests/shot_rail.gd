extends SceneTree
## Bahnübergang Ring Ost: Schranken senken sich, Zug fährt durch.

var _world
var _frames := 0


func _initialize() -> void:
	var scene := load("res://scenes/school.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	var cam := Camera3D.new()
	cam.position = Vector3(240.0, 10.0, -120.0)
	cam.look_at_from_position(cam.position, Vector3(240.0, 0.5, -150.0), Vector3.UP)
	cam.fov = 50.0
	_world.add_child(cam)
	cam.make_current()
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	_frames += 1
	if _frames == 5:
		var menu = _world.get_node_or_null("Menu")
		if menu and menu.has_method("resume_game"):
			menu.resume_game()
		# Zug kommt sofort — Schranken und Blinklichter fuer den Shot.
		var rail = null
		for c in _world.get_children():
			if c.name.begins_with("Rail") or c.has_method("is_closed"):
				rail = c
		if rail:
			rail._t = 0.0
	if _frames == 200:
		var img: Image = root.get_texture().get_image()
		img.save_png("/tmp/rail.png")
		print("SHOT saved")
		quit(0)
