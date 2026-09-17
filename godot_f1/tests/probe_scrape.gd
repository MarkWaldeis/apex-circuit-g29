extends SceneTree
## Diagnose: was kostet ein Streifer an der Barriere wirklich? Der Wagen wird
## neben der Wand abgesetzt und schiebt sich mit einem kleinen Queranteil
## hinein; gemessen wird die unerklärte Geschwindigkeitsabgabe pro Fenster
## (`crash.unexplained_ms`), also genau das, was als Crash zählt.
##
##   godot --headless --path godot_f1 --script tests/probe_scrape.gd

const RacingLine = preload("res://scripts/racing_line.gd")

var line = RacingLine.new()
var main: Node3D
var player
var frames: int = 0
var contacts: int = 0
var worst: float = -INF
var worst_speed: float = 0.0
var start_speed: float = 0.0
var min_offset: float = INF
var max_offset: float = -INF
var idx: int = 300


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	line.load_json("res://assets/track/racing_line.json")
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	player.auto_drive = false
	var tangent: Vector3 = line.flat_tangent(idx)
	var left: Vector3 = line.left_at(idx)
	# 15,35 m: die Innenkante der Wand steht bei 15,7 m, das Auto überlappt sie
	# also knapp. Reine Vorwärtsgeschwindigkeit - kein künstlicher Drall.
	var pos: Vector3 = line.points[idx] + left * 15.35 + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-tangent, Vector3.UP), pos)
	player.linear_velocity = tangent * 25.0
	player.angular_velocity = Vector3.ZERO
	player.apply_throttle(0.0)
	# `car.speed_kmh` is refreshed by the car's own physics tick, so reading it
	# right after the transform still returns the stationary value and the
	# summary printed "0 -> 56 km/h" for a run that started at 90 km/h. Take the
	# entry speed from the velocity that was actually set.
	start_speed = player.linear_velocity.length() * 3.6
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var crash = player.get("crash")
	var off: float = line.offset_at(player.global_position, line.closest_index(player.global_position))
	min_offset = minf(min_offset, off)
	max_offset = maxf(max_offset, off)
	if player.get_contact_count() > 0:
		contacts += 1
		var u: float = float(crash.unexplained_ms)
		if u > worst:
			worst = u
			worst_speed = player.speed_kmh
		print("SCRAPE f=%d off=%.2f kmh=%.0f unexplained=%.2f m/s crashes=%d"
			% [frames, off, player.speed_kmh, u, int(crash.crash_count)])
	if frames >= 150:
		print("SCRAPE summary: %d contact ticks, offset %.2f..%.2f m, worst unexplained %.2f m/s at %.0f km/h, %.0f -> %.0f km/h, crashes=%d"
			% [contacts, min_offset, max_offset, worst, worst_speed,
				start_speed, player.speed_kmh, int(crash.crash_count)])
		quit(0)
