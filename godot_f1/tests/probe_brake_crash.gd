extends SceneTree
## Diagnose: schlägt die Crash-Erkennung beim Bremsen an?
##
## Der Wagen wird in der Hauptszene auf Tempo gebracht und dann voll gebremst.
## Eine Bremsung ist keine Kollision, `crash.unexplained_ms` muss also unter
## `crash.IMPACT_MIN_MS` bleiben und `crash_count` auf 0.
##
##   godot --headless --path godot_f1 --script tests/probe_brake_crash.gd

var main: Node3D
var player
var frames: int = 0
var phase: int = 0
var worst: float = -INF
var worst_speed: float = 0.0
var brake_from: float = 0.0
var min_speed: float = INF


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	player.auto_drive = false
	player.apply_throttle(1.0)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var crash = player.get("crash")
	var u: float = float(crash.unexplained_ms)
	if player.speed_kmh > 190.0 and phase == 0:
		phase = 1
		brake_from = player.speed_kmh
		player.apply_throttle(0.0)
		player.apply_brake(1.0)
		print("BRAKE from %.0f km/h at frame %d" % [brake_from, frames])
	if phase == 1:
		min_speed = minf(min_speed, player.speed_kmh)
		if u > worst:
			worst = u
			worst_speed = player.speed_kmh
		if frames % 20 == 0:
			print("BRAKE f=%d kmh=%.0f unexplained=%.2f m/s expected=%.2f crashes=%d"
				% [frames, player.speed_kmh, u, float(crash.expected_loss_ms),
					int(crash.crash_count)])
		if player.speed_kmh < 20.0:
			print("BRAKE summary: %.0f -> %.0f km/h, worst unexplained %.2f m/s at %.0f km/h (threshold %.0f), crashes=%d"
				% [brake_from, player.speed_kmh, worst, worst_speed,
					float(crash.IMPACT_MIN_MS), int(crash.crash_count)])
			quit(0)
	if frames > 3000:
		print("BRAKE timeout at %.0f km/h, worst unexplained %.2f m/s, crashes=%d"
			% [player.speed_kmh, worst, int(crash.crash_count)])
		quit(1)
