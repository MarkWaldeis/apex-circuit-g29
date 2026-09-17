extends SceneTree
## Diagnose: was passiert dem Wagen bei Hoechstgeschwindigkeit auf der Geraden?
## Protokolliert Speed, Hoehe, Aufrecht-Vektor, Kontakt und jeden Reset.

var main: Node3D
var car
var frames: int = 0
var last_rejoin: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	car = main.get("player")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	car.auto_drive = false
	car.set_meta("script_throttle", 1.0)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames % 30 == 0:
		var up: float = car.global_transform.basis.y.dot(Vector3.UP)
		print("f=%4d kmh=%6.1f gear=%d y=%7.3f up=%.3f contacts=%d rejoin=%d pitch=%+.3f roll=%+.3f vy=%+.2f" % [
			frames, car.speed_kmh, car.gear, car.global_position.y, up,
			car.get_contact_count(), int(car.get("rejoin_count")),
			car.rotation.x, car.rotation.z,
			car.linear_velocity.y])
	if frames >= 1500:
		print("TOP_SPEED done at %.1f km/h, reinjoins=%d" % [car.speed_kmh, int(car.get("rejoin_count"))])
		quit(0)
