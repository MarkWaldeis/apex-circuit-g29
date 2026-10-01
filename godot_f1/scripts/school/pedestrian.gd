extends Node3D
## Fussgaenger am Zebrastreifen: wartet am Bordstein, geht rueber,
## wartet dort, geht zurueck. Der Fahrlehrer liest die Position und
## prueft, ob der Schueler Vorrang gewaehrt. Ein kinematicscher
## Kollisionskoerper wandert als Kind mit, damit das Schulauto
## einen Zusammenstoß physisch spürt.

const CROSS_X := -40.0       ## Zebrastreifen aus city_layout.zebras()[0]
const Z_SIDE_A := -53.5      ## Bordstein suedlich der Hauptstrasse
const Z_SIDE_B := -66.5      ## Bordstein noerdlich
const ROAD_Z := -60.0        ## Fahrbahnmitte
const ROAD_HALF := 4.4
const WALK_V := 1.5          ## Gehtempo in m/s
const WAIT_MIN := 4.0
const WAIT_MAX := 13.0

var _target_z: float = Z_SIDE_B
var _wait: float = 3.0
var _walking := false


func _ready() -> void:
	global_position = Vector3(CROSS_X, 0.0, Z_SIDE_A)
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


## Auf der Fahrbahn (zwischen den Bordsteinen) — Vorrang-Zone.
func on_road() -> bool:
	return absf(global_position.z - ROAD_Z) < ROAD_HALF \
		and absf(global_position.x - CROSS_X) < 5.0


func _physics_process(delta: float) -> void:
	if _walking:
		var z := global_position.z
		var step: float = signf(_target_z - z) * WALK_V * delta
		if absf(_target_z - z) <= absf(step):
			global_position.z = _target_z
			_walking = false
			_wait = randf_range(WAIT_MIN, WAIT_MAX)
		else:
			global_position.z += step
	else:
		_wait -= delta
		if _wait <= 0.0:
			_target_z = Z_SIDE_A if _target_z < ROAD_Z else Z_SIDE_B
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
