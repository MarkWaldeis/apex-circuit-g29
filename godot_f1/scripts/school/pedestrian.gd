extends Node3D
## Fussgaenger an einem Zebrastreifen: wartet am Bordstein, geht rueber,
## wartet dort, geht zurueck. Der Fahrlehrer liest die Position und
## prueft, ob der Schueler Vorrang gewaehrt. Ein kinematischer
## Kollisionskoerper wandert als Kind mit, damit das Schulauto
## einen Zusammenstoss physisch spuert.
##
## Querung und Tempo werden per setup_crossing() konfiguriert
## (Standard: Zebrastreifen auf der Hauptstrasse bei x=-40).

const WALK_V := 1.5          ## Gehtempo in m/s
const WAIT_MIN := 4.0
const WAIT_MAX := 13.0

var _from := Vector2(-40.0, -53.5)   ## Bordstein suedliche Hauptstrasse
var _to := Vector2(-40.0, -66.5)     ## Bordstein noerdlich
var _road := Vector2(-40.0, -60.0)   ## Fahrbahnmitte der Querung
var _road_half := 4.4                ## halbe Fahrbahnbreite (Vorrang-Zone)

var _dir_i: int = 1          ## 1 = von _from nach _to, -1 = zurueck
var _wait: float = 3.0
var _walking := false
var watchers: Array = []     ## Fahrzeuge, vor denen gewartet wird


func setup_crossing(from: Vector2, to: Vector2, road: Vector2, half: float) -> void:
	_from = from
	_to = to
	_road = road
	_road_half = half
	global_position = Vector3(_from.x, 0.0, _from.y)


func _ready() -> void:
	global_position = Vector3(_from.x, 0.0, _from.y)
	var body := AnimatableBody3D.new()
	body.name = "Fussgaenger"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	body.add_child(col)
	add_child(body)
	_build_mesh()


## Auf der Fahrbahn (rund um die Querungs-Mitte) — Vorrang-Zone.
func on_road() -> bool:
	var p := Vector2(global_position.x, global_position.z)
	return p.distance_to(_road) < _road_half + 0.4


func _physics_process(delta: float) -> void:
	if _walking:
		var target: Vector2 = _to if _dir_i == 1 else _from
		var p := Vector2(global_position.x, global_position.z)
		var d := target - p
		var step := WALK_V * delta
		if d.length() <= step:
			global_position = Vector3(target.x, 0.0, target.y)
			_walking = false
			_dir_i *= -1
			_wait = randf_range(WAIT_MIN, WAIT_MAX)
		else:
			p += d.normalized() * step
			global_position = Vector3(p.x, 0.0, p.y)
	else:
		_wait -= delta
		if _wait <= 0.0:
			# Erst gehen, wenn die Querung frei ist: ein Fahrzeug, das sich
			# der Querung noch nähert, blockiert den Start. Ein stehendes
			# Auto (der Schueler laesst passieren) blockiert nicht.
			var blocked := false
			for w in watchers:
				if not is_instance_valid(w):
					continue
				var wp := Vector2(w.global_position.x, w.global_position.z)
				if wp.distance_to(_road) > 13.0:
					continue
				# Starre Karosserie: RigidBody -> linear_velocity,
				# KI-AnimatableBody -> speed_ms; ohne Wert gilt "steht".
				var wspd := 0.0
				var wv = w.get("linear_velocity")
				if wv != null:
					wspd = Vector2(wv.x, wv.z).length()
				elif w.get("speed_ms") != null:
					wspd = float(w.get("speed_ms"))
				if wspd > 0.6:
					blocked = true
			if blocked:
				_wait = 0.7
			else:
				_walking = true


func _build_mesh() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.24
	capsule.height = 1.55
	body.mesh = capsule
	body.position.y = 0.78
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.28, 0.15)   ## auffaellige Jacke
	body.material_override = bm
	add_child(body)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	head.mesh = sphere
	head.position.y = 1.7
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.85, 0.7, 0.55)
	head.material_override = hm
	add_child(head)
