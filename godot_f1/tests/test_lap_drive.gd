extends SceneTree
## End-to-end gate on the real main scene: the cars have to drive the intended
## way round the circuit. Checks that
##   * the player accelerates away from the grid (positive forward speed),
##   * the AI car follows the racing line and makes progress along it,
##   * nobody leaves the track or loses wheel contact.

const RacingLine = preload("res://scripts/racing_line.gd")

var main: Node3D
var line = RacingLine.new()
var frames: int = 0
var player_start_z: float = 0.0
var player_start_ok: bool = false
var ai_start_index: int = -1
var ai_max_dev: float = 0.0
var worst_lateral: float = 0.0
var lowest_y: float = INF
var lowest_label: String = ""
var no_contact: int = 0
var samples: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _boot() -> void:
	if not line.load_json("res://assets/track/racing_line.json"):
		_check(false, "racing_line_loads")
		_finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	# Gemessen am 21.09.2026 (18:56): lief dieser Test gleichzeitig mit einer
	# zweiten Godot-Instanz, scheiterte schon das Laden von main.gd ("Could not
	# preload resource script res://scripts/ffb_link.gd"), das Auto wurde nie
	# gebaut - und der Test meldete trotzdem "LAP_DRIVE PASS". Jede Pruefung war
	# mit leerem Feld vakuum-gruen, sichtbar nur an "lowest y=inf". Ein Test,
	# der bei kaputter Szene gruen ist, beweist nichts: deshalb fragen die
	# Pruefungen unten ausdruecklich nach den Autos.
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	if frames == 5:
		var player = main.get("player")
		var ai = main.get("ai_car")
		_check(player != null, "the_player_car_exists",
			"player=%s" % ("da" if player else "FEHLT - main.gd hat kein Auto gebaut"))
		_check(ai != null, "the_ai_car_exists",
			"ai_car=%s" % ("da" if ai else "FEHLT - main.gd hat kein Auto gebaut"))
		if player:
			player_start_z = player.global_position.z
			player_start_ok = true
			# The player spawns nose-first down the main straight: its forward
			# axis (+Z) has to point away from the start line, i.e. towards -Z.
			_check(player.global_transform.basis.z.dot(Vector3(0, 0, -1)) > 0.95,
				"player_nose_points_down_the_straight",
				"dot=%.3f" % player.global_transform.basis.z.dot(Vector3(0, 0, -1)))
		if ai:
			ai_start_index = line.closest_index(ai.global_position)
	if frames < 6:
		return

	var player2 = main.get("player")
	var ai2 = main.get("ai_car")
	# The player car spawns with the auto-pilot off and waits for the driver, so
	# this run has to press the throttle itself. Leaving that out made the three
	# "player ..." checks below fail no matter what the car did - they were
	# reading a stationary car and blaming the physics for it.
	if player2 and player2.has_method("apply_throttle"):
		player2.apply_throttle(1.0)
	if player2 and frames == 400:
		var moved: float = player_start_z - player2.global_position.z
		var fwd: float = player2.global_transform.basis.z.dot(player2.linear_velocity)
		_check(moved > 25.0, "player_accelerates_forward", "moved %.1f m" % moved)
		_check(fwd > 5.0, "player_forward_speed_positive", "fwd=%.2f" % fwd)
		_check(player2.global_position.z < player_start_z, "player_leaves_the_grid_forward")
	# The track surface sits above y = 0 everywhere, so anything below -4 m has
	# fallen out of the world. Nobody may get that far down: the runoff apron
	# has to catch wide excursions, and car_controller.rejoin_to_line() the rest.
	for car in [player2, ai2]:
		if car == null:
			continue
		samples += 1
		var y: float = car.global_position.y
		if y < lowest_y:
			lowest_y = y
			lowest_label = "%s at frame %d, z=%.1f" % [car.name, frames, car.global_position.z]
	if ai2:
		var idx: int = line.closest_index(ai2.global_position)
		var dev: float = ai2.global_position.distance_to(line.points[idx])
		worst_lateral = maxf(worst_lateral, dev)
		var fwd_ai: float = ai2.global_transform.basis.z.dot(ai2.linear_velocity)
		if ai2.speed_kmh > 20.0 and fwd_ai < 0.0:
			no_contact += 1  # reuse counter: driving backwards while fast
	if frames >= 2400:
		_finish()


func _finish() -> void:
	var ai = main.get("ai_car") if main else null
	if ai and ai_start_index >= 0:
		var idx_now: int = line.closest_index(ai.global_position)
		var progressed: int = posmod(idx_now - ai_start_index, line.points.size())
		_check(progressed > 200, "ai_follows_the_racing_line",
			"progressed %d of %d points" % [progressed, line.points.size()])
		_check(worst_lateral < 10.0, "ai_stays_on_the_track",
			"worst distance to line %.2f m" % worst_lateral)
		var fwd: float = ai.global_transform.basis.z.dot(ai.linear_velocity)
		_check(fwd >= -0.5, "ai_never_drives_backwards", "fwd=%.2f" % fwd)
	else:
		# Ohne KI-Auto lief die Runde gar nicht - dann darf hier kein stilles
		# "keine Verstoesse" stehen, sondern es muss auffallen. Vorher wurden
		# diese drei Pruefungen bei fehlendem Auto einfach uebersprungen.
		_check(false, "ai_was_simulated_at_all",
			"kein KI-Auto (ai=%s, start_index=%d)" % [str(ai != null), ai_start_index])
	_check(no_contact == 0, "ai_forward_axis_matches_motion", "violations=%d" % no_contact)
	_check(samples > 0, "the_cars_were_really_there",
		"gelesene Positionen=%d" % samples)
	_check(samples > 0 and lowest_y > -4.0, "nobody_falls_out_of_the_world",
		"lowest y=%.2f m (%s), Positionen=%d" % [lowest_y, lowest_label, samples])
	if failed > 0:
		print("LAP_DRIVE FAIL count=", failed)
		quit(1)
	else:
		print("LAP_DRIVE PASS")
		quit(0)
