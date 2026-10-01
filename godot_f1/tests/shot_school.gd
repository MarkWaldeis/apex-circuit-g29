extends SceneTree
## Screenshots für den PR — läuft MIT Rendering (ohne --headless).
## Fährt das Schulauto automatisch und speichert Bilder nach /tmp.

var world: Node3D
var frames: int = 0
var shots := {"300": "/tmp/school_drive1.png", "600": "/tmp/school_drive2.png"}


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/school.tscn")
	world = packed.instantiate()
	root.add_child(world)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var player = world.get("player") if world else null
	if frames == 5 and player:
		player.assists["auto_gearbox"] = true
		player.set_meta("script_throttle", 0.55)
		var menu = world.get("menu")
		if menu:
			menu.resume_game()
	var key := str(frames)
	if shots.has(key):
		var img := root.get_texture().get_image()
		img.save_png(shots[key])
		print("SHOT saved ", shots[key])
	if frames >= 640:
		quit(0)
