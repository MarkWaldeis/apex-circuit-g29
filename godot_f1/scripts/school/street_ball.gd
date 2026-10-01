extends AnimatableBody3D
## Situationsgefahr: ein Ball rollt zwischen zwei parkenden Autos auf
## die Fahrbahn. Fahrschul-Klassiker — wo ein Ball rollt, folgt oft
## ein Kind. on_road() sagt, ob der Ball auf der Fahrbahn ist.

const ROLL_V := 3.8            ## m/s quer über die Straße
const WAIT_MIN := 14.0
const WAIT_MAX := 30.0
const EDGE := 3.4              ## halbe Fahrbahnbreite

var from := Vector2(206.5, -110.0)
var to := Vector2(193.5, -110.0)
var _road := Vector2(200.0, -110.0)   ## Fahrbahn-Mitte
var _half := EDGE
var _dir_i := 1
var _wait := 6.0               ## bis zum ersten Losrollen
var _rolling := false
var _mesh: MeshInstance3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	col.shape = sph
	col.position.y = 0.17
	add_child(col)
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.08)
	_mesh.material_override = mat
	_mesh.position.y = 0.17
	add_child(_mesh)
	global_position = Vector3(from.x, 0.0, from.y)


## Auf der Fahrbahn (zwischen den Fahrbahnkanten der Straße, die er
## kreuzt) — nur dann muss der Schueler wirklich reagieren.
func on_road() -> bool:
	var p := Vector2(global_position.x, global_position.z)
	return p.distance_to(_road) < _half + 2.0


func is_rolling() -> bool:
	return _rolling


func _physics_process(delta: float) -> void:
	if _rolling:
		var p := Vector2(global_position.x, global_position.z)
		var target: Vector2 = to if _dir_i == 1 else from
		var d := target - p
		if d.length() < 0.2:
			_rolling = false
			_dir_i = -_dir_i
			_wait = WAIT_MIN + randf() * (WAIT_MAX - WAIT_MIN)
			return
		var step := d.normalized() * ROLL_V * delta
		p += step
		# Purzeln: Kugel dreht sich um die Querachse zur Rollrichtung
		# (Vector2(x, z) -> Weltachse (z, 0, -x)).
		var axis := Vector3(step.normalized().y, 0.0, -step.normalized().x)
		_mesh.rotate(axis, (step.length() / 0.16))
		global_transform.origin = Vector3(p.x, 0.0, p.y)
	else:
		_wait -= delta
		if _wait <= 0.0:
			_rolling = true
