extends SceneTree
## Abnahme für die Fahrgefühl-Module `scripts/surfaces.gd` und
## `scripts/crash.gd`: erst die Zuordnung als Einheitentest, dann zwei echte
## Messungen in der Hauptszene — ein Einschlag in die Barriere und ein
## Streifer an derselben Wand.
##
##   godot --headless --path godot_f1 --script tests/test_crash_surfaces.gd

const SurfaceModel = preload("res://scripts/surfaces.gd")
const RacingLine = preload("res://scripts/racing_line.gd")

var failed: int = 0
var main: Node3D
var line = RacingLine.new()
var player
var frames: int = 0
var stage: int = 0
var test_index: int = 300
var crash_before: int = 0
var speed_before: float = 0.0
var damage_before: float = 0.0
var impact_frames: int = 0
var worst_offset: float = 0.0
var scrape_normal_ms: float = 0.0
var scrape_touches: int = 0
var scrape_worst_ms: float = 0.0
var scrape_speed_loss: float = 0.0


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _initialize() -> void:
	_unit()
	call_deferred("_boot")


## Reine Rechnung, ohne Szene: welcher Untergrund liegt bei welchem Querabstand
## an, und ist die Grip-Reihenfolge die, die die Strecke verspricht?
func _unit() -> void:
	if not line.load_json("res://assets/track/racing_line.json"):
		_check(false, "racing_line_loads")
		return
	var s = SurfaceModel.new()
	s.setup(line)
	var here: Vector3 = line.points[600]
	var left: Vector3 = line.left_at(600)
	# Die Breiten aus dem Blender-Bau: 6,0 m Asphalt, 0,85 m Kerb, 10 m Runoff.
	var expect := [
		[0.0, SurfaceModel.ASPHALT, "Asphalt"],
		[5.9, SurfaceModel.ASPHALT, "Asphalt"],
		[6.2, SurfaceModel.KERB, "Kerb"],
		[6.8, SurfaceModel.KERB, "Kerb"],
		[7.2, SurfaceModel.RUNOFF, "Kies"],
		[12.0, SurfaceModel.RUNOFF, "Kies"],
		[16.9, SurfaceModel.GRASS, "Gras"],
		[19.0, SurfaceModel.GRASS, "Gras"],
	]
	for e in expect:
		var offset: float = e[0]
		var hit: Dictionary = s.sample(here + left * offset)
		_check(int(hit["surface"]) == int(e[1]), "surface_at_%.1f_m_is_%s" % [offset, e[2]],
			"got %s at %.2f m" % [String(hit["name"]), float(hit["offset"])])
	# Beide Seiten müssen sich gleich verhalten - die Strecke ist symmetrisch
	# gebaut, ein Vorzeichenfehler in `offset_at` bliebe sonst unbemerkt.
	var right_hit: Dictionary = s.sample(here - left * 12.0)
	_check(int(right_hit["surface"]) == SurfaceModel.RUNOFF,
		"the_surface_model_is_symmetric", "right side %s" % String(right_hit["name"]))
	# Grip: Asphalt > Kerb > Kies > Gras, und Kies/Gras ziehen messbar.
	var g := [
		float(SurfaceModel.TUNING[SurfaceModel.ASPHALT]["grip"]),
		float(SurfaceModel.TUNING[SurfaceModel.KERB]["grip"]),
		float(SurfaceModel.TUNING[SurfaceModel.RUNOFF]["grip"]),
		float(SurfaceModel.TUNING[SurfaceModel.GRASS]["grip"]),
	]
	_check(g[0] > g[1] and g[1] > g[2] and g[2] > g[3], "grip_falls_off_off_the_track",
		"%.2f / %.2f / %.2f / %.2f" % [g[0], g[1], g[2], g[3]])
	_check(float(SurfaceModel.TUNING[SurfaceModel.ASPHALT]["drag"]) == 0.0,
		"asphalt_does_not_slow_the_car")
	_check(float(SurfaceModel.TUNING[SurfaceModel.GRASS]["drag"])
		> float(SurfaceModel.TUNING[SurfaceModel.RUNOFF]["drag"]),
		"grass_costs_more_than_gravel")
	# Die Barriere steht bei 16 m; genau das ist die Grenze, die die Wand baut.
	_check(SurfaceModel.BARRIER_OFFSET == 16.0, "the_barrier_offset_matches_the_track_build",
		"%.1f m" % SurfaceModel.BARRIER_OFFSET)
	_check(not s.is_outside_corridor(15.9) and s.is_outside_corridor(16.0),
		"the_corridor_ends_at_the_barrier")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get("player")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	if player == null:
		_check(false, "the_main_scene_has_a_player")
		_finish()
		return
	# Von hier aus geht es zur Wand: der Wagen wird neben der Ideallinie
	# abgesetzt und quer zur Strecke auf die Barriere zu beschleunigt.
	player.auto_drive = false
	physics_frame.connect(_on_phys)


func _place(offset: float, outward_speed: float) -> void:
	var left: Vector3 = line.left_at(test_index)
	# Nase = Fahrtrichtung: das Auto schaut entlang -left, fährt also nach außen.
	var pos: Vector3 = line.points[test_index] + left * offset + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-left, Vector3.UP), pos)
	player.linear_velocity = left * outward_speed
	player.angular_velocity = Vector3.ZERO
	player.apply_throttle(0.0)
	player.set_meta("test_placed", true)


## Streifer: der Wagen liegt fast parallel zur Wand und schiebt sich nur mit
## einem kleinen Queranteil hinaus. Der normale Anteil der Geschwindigkeit
## muss unter `crash.IMPACT_MIN_MS` bleiben, sonst ist es kein Streifer mehr.
func _place_scrape(offset: float, along_speed: float, outward_speed: float) -> void:
	var tangent: Vector3 = line.flat_tangent(test_index)
	var left: Vector3 = line.left_at(test_index)
	var pos: Vector3 = line.points[test_index] + left * offset + Vector3(0, 0.35, 0)
	player.global_transform = Transform3D(Basis.looking_at(-tangent, Vector3.UP), pos)
	player.linear_velocity = tangent * along_speed + left * outward_speed
	player.angular_velocity = Vector3.ZERO
	player.apply_throttle(0.0)
	player.set_meta("test_placed", true)
	scrape_normal_ms = outward_speed
	print("SCRAPE placed %.1f m out, %.1f m/s along, %.1f m/s towards the wall"
		% [offset, along_speed, outward_speed])


func _on_phys() -> void:
	frames += 1
	var crash = player.get("crash")
	if crash == null:
		_finish()
		return
	if stage == 0:
		_place(4.0, 30.0)
		crash_before = int(crash.crash_count)
		stage = 1
	elif stage == 1 and frames >= 6:
		speed_before = player.speed_kmh
		damage_before = float(crash.damage)
		_check(player.surface_name == "Asphalt", "the_car_starts_on_asphalt",
			"surface=%s at %.2f m offset" % [player.surface_name, 4.0])
		stage = 2
	elif stage == 2:
		# Wie weit ist der Wagen von der Linie weg? Wenn die Barriere trägt,
		# kommt er nicht über die 16 m hinaus.
		var idx: int = line.closest_index(player.global_position)
		worst_offset = maxf(worst_offset, absf(line.offset_at(player.global_position, idx)))
		if int(crash.crash_count) > crash_before:
			impact_frames = frames
			stage = 3
		elif frames > 240:
			_check(false, "driving_into_the_barrier_is_a_crash",
				"no crash after 240 frames, worst offset %.1f m, %.1f km/h"
				% [worst_offset, player.speed_kmh])
			_finish()
	elif stage == 3 and frames >= impact_frames + 12:
		_check(int(crash.crash_count) > crash_before, "driving_into_the_barrier_is_a_crash",
			"crash #%d at frame %d" % [int(crash.crash_count), impact_frames])
		_check(float(crash.damage) > damage_before, "the_impact_bends_the_tub",
			"damage %.2f -> %.2f" % [damage_before, float(crash.damage)])
		_check(float(crash.last_impact_ms) >= 3.0, "the_impact_is_measured",
			"%.1f m/s in %.2f s" % [float(crash.last_impact_ms), 0.15])
		_check(player.speed_kmh < speed_before * 0.5, "the_wall_takes_the_speed_away",
			"%.0f -> %.0f km/h" % [speed_before, player.speed_kmh])
		_check(worst_offset < 17.5, "the_car_does_not_drive_through_the_wall",
			"furthest offset %.2f m, barrier at %.1f m"
			% [worst_offset, SurfaceModel.BARRIER_OFFSET])
		# --- Streifer: dieselbe Wand, aber flach angeflogen -----------------
		crash.reset()
		crash_before = 0
		# 15,0 m: die Innenkante der Wand steht bei 16,0 - 0,3 = 15,7 m, das
		# Auto hat also 0,7 m Luft. Zusätzlich dreht es sich um 20 m/s um die
		# eigene Hochachse, damit es die Wand wirklich entlangschrammt statt
		# sie einmal anzutippen und wieder wegzufliegen.
		_place_scrape(15.0, 20.0, 0.5, 20.0)
		stage = 4
	elif stage == 4:
		var idx2: int = line.closest_index(player.global_position)
		worst_offset = maxf(worst_offset, absf(line.offset_at(player.global_position, idx2)))
		if player.get_contact_count() > 0:
			scrape_touches += 1
			scrape_worst_ms = maxf(scrape_worst_ms, float(crash.unexplained_ms))
			if scrape_speed_loss == 0.0:
				scrape_speed_loss = player.speed_kmh
		if frames > 420:
			_check(scrape_touches > 0, "the_scrape_actually_touches_the_wall",
				"%d contact ticks" % scrape_touches)
			_check(scrape_worst_ms < 3.0, "rubbing_along_the_wall_is_not_a_crash",
				"worst unexplained loss %.2f m/s while touching (threshold %.0f)"
				% [scrape_worst_ms, 3.0])
			_check(int(crash.crash_count) == crash_before,
				"a_rub_never_counts_a_crash",
				"%d crashes, %.0f -> %.0f km/h along the wall"
				% [int(crash.crash_count), scrape_speed_loss, player.speed_kmh])
			_check(player.speed_kmh > 40.0, "the_scrape_keeps_most_of_the_speed",
				"%.0f km/h at the end, %d contact ticks" % [player.speed_kmh, scrape_touches])
			_finish()


func _finish() -> void:
	if failed > 0:
		print("CRASH_SURFACES FAIL count=", failed)
		quit(1)
	else:
		print("CRASH_SURFACES PASS impact frame %d, %.0f -> %.0f km/h"
			% [impact_frames, speed_before, player.speed_kmh if player else 0.0])
		quit(0)
