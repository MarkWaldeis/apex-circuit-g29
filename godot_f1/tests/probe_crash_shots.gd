extends SceneTree
## Beweisbilder fuer Crashen und Ausritte: einmal neben der Strecke (Kies/Gras
## mit Grip-Anzeige), einmal nach dem Einschlag in die Barriere (Warnung,
## Schaden, Speed weg). Fenster-Modus, NICHT --headless.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var player
var line
var frames: int = 0
var stage: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	line = main.get("line")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	player.auto_drive = false
	_place_off_track()
	process_frame.connect(_on_frame)


## 12 m neben der Linie: das ist der Runoff (Kies).
func _place_off_track() -> void:
	var i := 300
	var tangent: Vector3 = line.flat_tangent(i)
	var left: Vector3 = line.left_at(i)
	var pos: Vector3 = line.points[i] + left * 12.0 + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-tangent, Vector3.UP), pos)
	player.linear_velocity = tangent * 25.0
	player.set_meta("script_throttle", 0.5)


## Auf die Barriere zuhalten: 16 m Offset, 1,15 m hoch.
func _place_into_wall() -> void:
	var i := 300
	var tangent: Vector3 = line.flat_tangent(i)
	var left: Vector3 = line.left_at(i)
	var outward: Vector3 = left
	var pos: Vector3 = line.points[i] + left * 4.0 + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-outward, Vector3.UP), pos)
	player.linear_velocity = outward * 45.0
	player.set_meta("script_throttle", 1.0)


func _shot(name: String) -> void:
	var img: Image = get_root().get_viewport().get_texture().get_image()
	var crash = player.get("crash")
	print("SHOT %s err=%d damage=%.2f crashes=%d surface=%s kmh=%.1f" % [
		name, img.save_png(OUT_DIR + "/" + name),
		float(crash.damage) if crash else -1.0,
		int(crash.crash_count) if crash else -1,
		String(player.surface_name), player.speed_kmh])


func _on_frame() -> void:
	frames += 1
	if frames == 20:
		_shot("crash_offtrack.png")
		stage = 1
		_place_into_wall()
	elif frames == 45:
		_shot("crash_impact.png")
	elif frames >= 55:
		quit(0)
