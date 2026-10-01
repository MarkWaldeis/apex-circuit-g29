extends SceneTree
## Screenshot der Weltwahl (boot.tscn).

var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn")
	root.add_child(packed.instantiate())
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames == 60:
		root.get_texture().get_image().save_png("/tmp/boot_menu.png")
		print("SHOT saved /tmp/boot_menu.png")
		quit(0)
