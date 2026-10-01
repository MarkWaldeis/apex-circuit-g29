extends SceneTree
## Screenshot: Nachtfahrt mit Abblendlicht an der Ampelkreuzung.

var frames: int = 0
var _world: Node3D


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var WorldEnv = load("res://scripts/world_env.gd")
	var packed: PackedScene = load("res://scenes/school.tscn")
	_world = packed.instantiate()
	root.add_child(_world)
	WorldEnv.set_night(_world, true)
	var player = _world.get("player")
	if player:
		# Vor die Ampelkreuzung stellen, Licht an.
		player.global_transform = Transform3D(
			Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(-80.0, 0.4, -58.2))
		player._toggle_lights()
	var cam := Camera3D.new()
	# Blick die Hauptstrasse entlang: Autolicht + Laternen-Pools.
	cam.position = Vector3(-16.0, 7.0, -60.0)
	cam.look_at_from_position(cam.position, Vector3(-90.0, 0.5, -60.0), Vector3.UP)
	cam.fov = 55.0
	_world.add_child(cam)
	cam.make_current()
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames == 5:
		var menu = _world.get("menu")
		if menu:
			menu.resume_game()
	if frames == 60:
		root.get_texture().get_image().save_png("/tmp/school_night.png")
		print("SHOT saved /tmp/school_night.png")
		quit(0)
