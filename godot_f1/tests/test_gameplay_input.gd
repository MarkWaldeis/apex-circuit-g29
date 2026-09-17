extends SceneTree
## Integration gate on the REAL scene: a stub wheel drives the game and the
## whole chain has to behave - gas accelerates forward, the brake slows the car
## down, a right turn really turns right, and the rim in the cockpit follows the
## real wheel. Catches wiring mistakes between input, car and camera.

var main: Node3D
var car
var cam
var wheel
var frames: int = 0
var speed_at_brake: float = 0.0
var speed_after_brake: float = 0.0
var heading_before_turn: Vector3
var failed: int = 0


class StubWheel:
	signal shift_up
	signal shift_down
	var steer: float = 0.0
	var throttle: float = 0.0
	var brake: float = 0.0
	var clutch: float = 0.0
	var connected: bool = true
	var device_name: String = "STUB G29"
	var cal_phase: int = 5
	var cal_hint: String = ""
	var axes_live: bool = true
	var hardware_hint: String = ""
	var throttle_axis: int = 2
	var brake_axis: int = 3
	var clutch_axis: int = 1
	var steer_axis: int = 0
	var invert_throttle: bool = true
	var invert_brake: bool = true
	var invert_clutch: bool = true
	var steer_invert: bool = false
	var steer_deadzone: float = 0.03

	func has_driver_input() -> bool:
		return true

	func axis_snapshot() -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(8)
		return out


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	wheel = StubWheel.new()
	car = main.get("player")
	cam = main.get("cam")
	var hud = main.get("hud")
	main.set("g29", wheel)
	if car:
		car.g29 = wheel
	if cam:
		cam.g29 = wheel
	if hud:
		hud.g29 = wheel
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	# gas
	wheel.throttle = 0.9
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var fwd: float = car.global_transform.basis.z.dot(car.linear_velocity)
	if frames == 200:
		_check(car.speed_kmh > 40.0, "gas_accelerates", "%.1f km/h" % car.speed_kmh)
		_check(fwd > 5.0, "car_moves_forwards", "fwd=%.2f" % fwd)
		speed_at_brake = car.speed_kmh
		wheel.throttle = 0.0
		wheel.brake = 1.0
		return
	if frames == 320:
		speed_after_brake = car.speed_kmh
		_check(speed_after_brake < speed_at_brake * 0.5, "brake_slows_the_car",
			"%.1f -> %.1f km/h" % [speed_at_brake, speed_after_brake])
		wheel.brake = 0.0
		wheel.throttle = 0.5
		return
	if frames == 360:
		wheel.steer = 1.0
		heading_before_turn = car.global_transform.basis.z
		return
	if frames == 480:
		var swing: float = car.global_transform.basis.z.x - heading_before_turn.x
		_check(swing > 0.05, "steering_right_turns_the_car_right",
			"nose.x swing=%+.3f" % swing)
		var rim: float = cam.wheel_visual.rotation.z if cam and cam.wheel_visual else 0.0
		_check(rim < -0.1, "cockpit_rim_turns_with_the_wheel", "rot.z=%+.2f" % rim)
		if failed > 0:
			print("GAMEPLAY FAIL count=", failed)
			quit(1)
		else:
			print("GAMEPLAY PASS")
			quit(0)
