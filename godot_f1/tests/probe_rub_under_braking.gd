extends SceneTree
## Diagnose: zählt ein Streifer als Crash, wenn der Fahrer dabei bremst?
##
## `probe_scrape.gd` setzt den Wagen neben die Wand und lässt ihn hinein
## schieben - ohne Bremse, und das bleibt folgenlos. Offen war bisher, was
## passiert, wenn derselbe Streifer stattfindet, während der Fahrer bremst:
## `_expected_loss()` bekommt in `crash.gd` nicht die Bremse, sondern
## `_contact_seen` als "braking"-Argument, und der Rollterm fällt dadurch von
## 10,0 auf 4,5 m/s^2. Gemessen wird `crash.unexplained_ms` pro Fenster, also
## genau die Zahl, die über einen Crash entscheidet.
##
##   godot --headless --path godot_f1 --script tests/probe_rub_under_braking.gd
##   $env:RUB_BRAKE="1"; godot --headless --path godot_f1 --script tests/probe_rub_under_braking.gd

const RacingLine = preload("res://scripts/racing_line.gd")

var line = RacingLine.new()
var main: Node3D
var player
var frames: int = 0
var braking: bool = false
var contacts: int = 0
var contacts_after_brake: int = 0
var worst: float = -INF
var worst_speed: float = 0.0
var worst_expected: float = 0.0
var brake_frame: int = -1
var idx: int = 300


func _initialize() -> void:
	braking = OS.get_environment("RUB_BRAKE") == "1"
	call_deferred("_boot")


func _boot() -> void:
	line.load_json("res://assets/track/racing_line.json")
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	player.auto_drive = false
	# Dasselbe Absetzen wie in probe_scrape.gd: die Innenkante der Wand steht
	# bei 15,7 m, das Auto überlappt sie bei 15,35 m also knapp.
	var tangent: Vector3 = line.flat_tangent(idx)
	var left: Vector3 = line.left_at(idx)
	var pos: Vector3 = line.points[idx] + left * 15.35 + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-tangent, Vector3.UP), pos)
	player.linear_velocity = tangent * 25.0
	player.angular_velocity = Vector3.ZERO
	player.apply_throttle(0.0)
	player.set_meta("test_placed", true)
	print("RUB mode=%s, abgesetzt bei 15.35 m Querabstand, 25.0 m/s vorwärts"
		% ["bremsend" if braking else "rollend"])
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var crash = player.get("crash")
	var off: float = line.offset_at(
		player.global_position, line.closest_index(player.global_position))
	# Erst Kontakt aufbauen, dann bremsen: der Fahrer streift die Wand und
	# tritt danach voll auf die Bremse. Andersherum stünde der Wagen vor dem
	# ersten Kontakt schon.
	if braking and frames == 60:
		brake_frame = frames
		player.apply_brake(1.0)
		print("RUB Bremse getreten bei Frame %d, Querabstand %.2f m, %.0f km/h"
			% [frames, off, player.speed_kmh])
	if player.get_contact_count() > 0:
		contacts += 1
		var u: float = float(crash.unexplained_ms)
		var expected: float = float(crash.expected_loss_ms)
		if u > worst:
			worst = u
			worst_speed = player.speed_kmh
			worst_expected = expected
		if braking and brake_frame >= 0 and frames > brake_frame:
			contacts_after_brake += 1
		if frames % 5 == 0 or u >= float(crash.IMPACT_MIN_MS):
			print("RUB f=%d off=%.2f kmh=%.0f unexplained=%.2f expected=%.2f damage=%.2f crashes=%d"
				% [frames, off, player.speed_kmh, u, expected,
					float(crash.damage), int(crash.crash_count)])
	if frames >= 240:
		print("RUB summary mode=%s: %d Kontakt-Ticks (%d nach der Bremse), schlimmste unerklärte Abgabe %.2f m/s bei %.2f m/s erwartet, bei %.0f km/h, Crashs=%d, Schaden=%.2f"
			% ["bremsend" if braking else "rollend", contacts, contacts_after_brake,
				worst, worst_expected, worst_speed, int(crash.crash_count),
				float(crash.damage)])
		quit(0)
