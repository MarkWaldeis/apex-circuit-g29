extends SceneTree
## Rendert das Schul-HUD bei eingelegtem Rueckwaertsgang: Rueckfahrkamera
## und Abstandsanzeige sollen sichtbar sein (Zaun hinter dem Auto).

var world
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	world = load("res://scenes/school.tscn").instantiate()
	root.add_child(world)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var player = world.get("player") if world else null
	if player == null:
		return
	if frames == 5:
		var menu = world.get_node_or_null("Menu")
		if menu and menu.has_method("resume_game"):
			menu.resume_game()
		player.assists["auto_gearbox"] = true
		# Heck 3 m vor den Platz-Zaun, Rueckwaertsgang eingelegt.
		player.global_transform = Transform3D(
			Basis.looking_at(Vector3(0, 0, 1), Vector3.UP),
			Vector3(0.0, 0.4, 110.0))
		player.set_meta("script_gear", -1)
	if frames == 60:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/school_reverse.png")
		print("SHOT saved /tmp/school_reverse.png")
		quit(0)
