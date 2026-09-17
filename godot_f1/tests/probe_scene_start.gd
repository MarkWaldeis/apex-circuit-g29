extends SceneTree
## Diagnostic: what is the player standing on, and which barrier boxes are near
## the grid? Used while wiring the new surface/barrier modules.

var main: Node3D
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var player = main.get("player")
	if player == null:
		return
	if frames == 40:
		var barriers = main.get_node_or_null("Barriers")
		print("PROBE barriers=", barriers.get_child_count() if barriers else -1)
		if barriers:
			var near := []
			for c in barriers.get_children():
				var d: float = c.global_position.distance_to(player.global_position)
				if d < 25.0:
					near.append([snappedf(d, 0.01), c.global_position])
			near.sort_custom(func(a, b): return a[0] < b[0])
			print("PROBE near_boxes=", near.slice(0, 6))
		print("PROBE player pos=", player.global_position, " y_basis=", player.global_transform.basis.y)
	if frames == 200:
		var fl = player.get_node_or_null("Wheel_FL")
		print("PROBE f200 pos=", player.global_position, " kmh=", snappedf(player.speed_kmh, 0.1),
			" contact=", fl.is_in_contact() if fl else "?", " surface=", player.surface_name)
		quit(0)
