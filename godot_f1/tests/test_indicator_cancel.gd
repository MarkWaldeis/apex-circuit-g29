extends SceneTree
## Blinker-Selbstausloesung: rechts blinken, laengere Rechtskurve fahren,
## Lenkrad gerade stellen -> der Blinker muss von allein ausgehen.
## (script_steer > 0 lenkt in diesem Auto nach rechts.)

var world
var frames: int = 0
var _done: bool = false


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		_done = true
		print("INDICATOR_CANCEL FAIL ", label)
		quit(1)


func _boot() -> void:
	world = load("res://scenes/school.tscn").instantiate()
	root.add_child(world)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	if _done:
		return
	frames += 1
	var player = world.get("player") if world else null
	if player == null:
		if frames > 300:
			_check(false, "car_missing")
		return
	if frames == 5:
		player.assists["auto_gearbox"] = true
		player.indicator_right = true
	if frames >= 30 and frames < 300:
		# 5 s lang links lenken (~45 Grad+) bei Schritttempo-Gas.
		player.set_meta("script_steer", 0.45)
		player.set_meta("script_throttle", 0.3)
	elif frames == 300:
		player.set_meta("script_steer", 0.0)
	elif frames == 420:
		_check(not player.indicator_right, "indicator_self_cancels",
			"right=%s" % str(player.indicator_right))
		_done = true
		print("INDICATOR_CANCEL PASS")
		quit(0)
