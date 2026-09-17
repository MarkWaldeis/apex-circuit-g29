extends SceneTree
## Visual check on the real game with the real device: start menu, settings,
## calibration screen, then the race from the cockpit and the chase camera.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var frames: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _menu():
	return main.get("menu")


func _on_frame() -> void:
	frames += 1
	match frames:
		40:
			_shot("game_menu.png")
			var m = _menu()
			if m and m.has_method("_open_settings"):
				m._open_settings(0)
		80:
			var m2 = _menu()
			if m2 and m2.has_method("_open_settings"):
				m2._open_settings(0)
		300:
			_shot("game_settings.png")
			var m3 = _menu()
			if m3 and m3.has_method("_start_calibration"):
				m3._start_calibration("throttle")
		360:
			_shot("game_calibrate.png")
			var m4 = _menu()
			if m4 and m4.has_method("_cancel_calibration"):
				m4._cancel_calibration()
			if m4 and m4.has_method("resume_game"):
				m4.resume_game()
			var player = main.get("player")
			if player:
				player.set_meta("headless_gas", true)
		760:
			_shot("game_cockpit.png")
			var cam = main.get("cam")
			if cam:
				cam.mode = 1
		800:
			_shot("game_chase.png")
			quit(0)


func _shot(file: String) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT failed ", file)
		return
	print("SHOT ", file, " err=", img.save_png(OUT_DIR + "/" + file), " size=", img.get_size())
