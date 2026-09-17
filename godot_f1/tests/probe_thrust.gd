extends SceneTree
## Calibration: what does `VehicleBody3D.engine_force` actually do to this
## chassis?
##
## The car's engine force comes out of the gearbox module in "Newton", but the
## number the engine turns into motion is not a plain F = m * a: the wheel
## friction ceiling and the wheel radius are in that path too. So instead of
## trusting the number, this probe bolts the real chassis on a flat plane with
## the subsystems switched off, sets a known engine_force and measures the
## acceleration it really produces.
##
##   godot --headless --path godot_f1 --script tests/probe_thrust.gd

const F1Car = preload("res://scripts/car_controller.gd")
const RacingLine = preload("res://scripts/racing_line.gd")

const MASS := 740.0
## force (N) and the friction ceiling forced onto every wheel
## (-1 = leave whatever the car/tyre model set).
const CASES := [
	[1305.0, -1.0],
	[1305.0, 8.4],
	[1305.0, 5.29],
	[1305.0, 3.0],
	[1305.0, 1.5],
	[2610.0, 5.29],
]
const SETTLE := 60
const MEASURE := 90

var plane: StaticBody3D
var car
var frames: int = 0
var index: int = 0
var phase: int = 0
var v0: float = 0.0
var f0: float = 0.0
var _friction: float = -1.0
var results: Array = []


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 4000.0)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(col)
	root.add_child(ground)
	_spawn(float(CASES[0][0]), float(CASES[0][1]))
	physics_frame.connect(_on_phys)


func _spawn(force: float, friction: float = -1.0) -> void:
	if car:
		car.queue_free()
	car = F1Car.new()
	car.livery = "crimson"
	root.add_child(car)
	var line := RacingLine.new()
	car.setup(line, null, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
	# Switch the game logic off: nothing may overwrite `engine_force` now.
	car.gearbox = null
	car.engine_force = force
	# Optional: clamp the friction ceiling the tyre model would set, so the
	# "is the engine force friction limited?" question can be answered.
	if friction > 0.0:
		for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			var w = car.get_node_or_null(name)
			if w:
				w.wheel_friction_slip = friction
	f0 = force
	_friction = friction
	frames = 0
	phase = SETTLE
	v0 = 0.0


func _on_phys() -> void:
	frames += 1
	if phase == SETTLE:
		car.engine_force = f0
		if frames >= SETTLE:
			phase = MEASURE
			frames = 0
			v0 = car.global_transform.basis.z.dot(car.linear_velocity)
		return
	if frames >= MEASURE:
		var v1: float = car.global_transform.basis.z.dot(car.linear_velocity)
		var dt: float = float(MEASURE) / float(Engine.physics_ticks_per_second)
		var a: float = (v1 - v0) / dt
		results.append({"force": f0, "a": a, "kn_per_g": 0.0})
		var equivalent: float = a * MASS
		print("THRUST force=%.0f friction=%.2f -> a=%.2f m/s^2  (%.0f N, %.2f x)" % [
			f0, _friction, a, equivalent, equivalent / maxf(f0, 1.0)])
		index += 1
		if index >= CASES.size():
			print("THRUST done")
			quit(0)
			return
		_spawn(float(CASES[index][0]), float(CASES[index][1]))
