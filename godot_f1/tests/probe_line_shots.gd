extends SceneTree
## Beweisbilder fuer die Ideallinie: einmal auf der Geraden (gruen), einmal in
## der Anfahrt auf eine rote Bremszone, einmal mitten in der Kurve.
## Fenster-Modus (NICHT --headless), sonst gibt es kein Bild.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var player
var frames: int = 0
var shots: Array = []


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	var ideal = main.get("ideal")
	var n: int = ideal.points.size()
	# 1. Gerade: 200 m nach dem Start (dort ist alles gruen).
	# 2. 70 m vor einer roten Zone.
	# 3. Mitten in der engsten Kurve.
	var brake_at := -1
	for i in n:
		if ideal.phase[i] == 2:
			brake_at = i
			break
	var tight := 0
	var tight_k := 0.0
	for i in n:
		if absf(ideal._centre_k[i]) > tight_k:
			tight_k = absf(ideal._centre_k[i])
			tight = i
	shots = [
		{"name": "line_straight.png", "index": 170, "speed": 70.0},
		{"name": "line_braking.png", "index": maxi(brake_at - 20, 0), "speed": 75.0},
		{"name": "line_corner.png", "index": tight, "speed": 30.0},
	]
	process_frame.connect(_on_frame)
	_place(0)


func _place(which: int) -> void:
	var ideal = main.get("ideal")
	var spec: Dictionary = shots[which]
	var i: int = int(spec["index"])
	var tangent: Vector3 = ideal.tangent_at(i)
	var basis := Basis.looking_at(-tangent, Vector3.UP)
	player.global_transform = Transform3D(basis, ideal.points[i] + Vector3(0, 0.25, 0))
	player.linear_velocity = tangent * float(spec["speed"])
	player.engine_force = 0.0
	player.set_meta("script_throttle", 0.35)


func _on_frame() -> void:
	frames += 1
	# Genug Zeit, damit Kamera und HUD sich setzen, aber zu wenig, um aus der
	# Kurve zu fliegen.
	if frames in [25, 65, 105]:
		var which: int = [25, 65, 105].find(frames)
		var img: Image = get_root().get_viewport().get_texture().get_image()
		var name: String = String(shots[which]["name"])
		print("SHOT ", name, " err=", img.save_png(OUT_DIR + "/" + name))
		if which + 1 < shots.size():
			_place(which + 1)
	if frames >= 115:
		quit(0)
