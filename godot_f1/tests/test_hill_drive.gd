extends SceneTree
## Berganfahren-Gate: Schulauto wird vor die Rampe gestellt und faehrt
## mit Automatik geradeaus nach Sueden. Erfolgreich, wenn es die
## Rampenhoehe erreicht und auf dem Plateau weiterfaehrt — dann ist der
## Hügel geometrisch befahrbar (Rampe -> Plateau -> Gegenrampe).

var world: Node3D
var frames: int = 0
var max_y: float = 0.0
var max_z: float = 0.0
var failed: int = 0
var _done: bool = false


func _initialize() -> void:
	call_deferred("_boot")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/school.tscn")
	world = packed.instantiate()
	root.add_child(world)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	if _done:
		return
	frames += 1
	var player = world.get("player") if world else null
	if player == null:
		if frames >= 300:
			_finish()
		return
	if frames == 5:
		# Vor dem Rampenfuss (Rampe steigt von z=59 bis 73 nach Sueden),
		# +Z-Basisrichtung zeigt +z — Blick auf den Berg.
		player.global_transform = Transform3D(
			Basis.looking_at(Vector3(0, 0, -1), Vector3.UP),
			Vector3(-66.0, 0.5, 52.0))
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.assists["auto_gearbox"] = true
		player.set_meta("script_throttle", 0.55)
		return
	if frames < 6:
		return
	max_y = maxf(max_y, player.global_position.y)
	max_z = maxf(max_z, player.global_position.z)
	if frames >= 700:
		_finish()


func _finish() -> void:
	_done = true
	_check(max_y > 1.6, "hill_reached_plateau", "max_y=%.2f" % max_y)
	_check(max_z > 78.0, "hill_crossed_mesa", "max_z=%.2f" % max_z)
	print("HILL_DRIVE %s" % ("PASS" if failed == 0 else "FAIL count=%d" % failed))
	quit(failed)
