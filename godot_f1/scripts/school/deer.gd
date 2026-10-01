extends Node3D
## Reh am Wildwechsel (VZ 142) am West-Ring: steht am Waldrand und
## sprintet unvermittelt ueber die Fahrbahn — ob gerade ein Auto
## kommt, ist dem Tier egal. Genau darauf trainiert das Schild:
## die Querung gilt als Gefahrenstelle, nicht als Zebrastreifen.
##
## Schnittstelle wie pedestrian.gd (on_road(), _walking), damit die
## KI-Autos vor ihm bremsen. Ein kinematischer Koerper wandert mit,
## damit das Schulauto den Zusammenstoss physisch spuert.

const RUN_V := 7.5           ## Fluchttempo in m/s
const WAIT_MIN := 45.0
const WAIT_MAX := 110.0
const TRIGGER_D := 62.0      ## Abstand, ab dem der Schueler es ausloest

var _from := Vector2(-256.0, -40.0)  ## Waldrand westlich des Rings
var _to := Vector2(-224.0, -40.0)    ## offene Flaeche oestlich
var _road := Vector2(-240.0, -40.0)  ## Fahrbahnmitte der Querung
var _road_half := 4.4

var _dir_i: int = 1          ## 1 = von _from nach _to, -1 = zurueck
var _wait: float = 25.0
var _running := false
var _walking := false        ## fuer KI-Bremslogik: "bewegt sich auf Bahn"
var _dart_cd: float = 15.0   ## Sperrzeit zwischen zwei Ausloesungen
var player: Node3D           ## Schulauto — loest den Sprint aus


func _ready() -> void:
	global_position = Vector3(_from.x, 0.0, _from.y)
	var body := AnimatableBody3D.new()
	body.name = "Reh"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.1
	col.shape = cap
	col.position.y = 0.75
	body.add_child(col)
	add_child(body)
	_build_mesh()


func on_road() -> bool:
	var p := Vector2(global_position.x, global_position.z)
	return p.distance_to(_road) < _road_half + 0.4


func _physics_process(delta: float) -> void:
	_dart_cd = maxf(_dart_cd - delta, 0.0)
	if _running:
		var target: Vector2 = _to if _dir_i == 1 else _from
		var p := Vector2(global_position.x, global_position.z)
		var d := target - p
		var step := RUN_V * delta
		if d.length() <= step:
			global_position = Vector3(target.x, 0.0, target.y)
			_running = false
			_walking = false
			_dir_i *= -1
			_wait = randf_range(WAIT_MIN, WAIT_MAX)
		else:
			p += d.normalized() * step
			global_position = Vector3(p.x, 0.0, p.y)
		return
	_wait -= delta
	var triggered := false
	if _dart_cd <= 0.0 and player != null and is_instance_valid(player):
		var pp := Vector2(player.global_position.x, player.global_position.z)
		triggered = pp.distance_to(_road) < TRIGGER_D
	if _wait <= 0.0 or triggered:
		_running = true
		_walking = true
		_dart_cd = 80.0
		# Nase in Laufrichtung drehen.
		var tgt: Vector2 = _to if _dir_i == 1 else _from
		var dir2 := (tgt - Vector2(global_position.x, global_position.z))\
			.normalized()
		if dir2 != Vector2.ZERO:
			rotation.y = Basis.looking_at(
				Vector3(-dir2.x, 0.0, -dir2.y), Vector3.UP)\
				.get_euler().y


func _build_mesh() -> void:
	var brown := StandardMaterial3D.new()
	brown.albedo_color = Color(0.42, 0.28, 0.15)
	# Rumpf.
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.38, 0.55, 1.05)
	body.mesh = bb
	body.material_override = brown
	body.position.y = 0.85
	add_child(body)
	# Kopf mit Hals vorn (+z).
	var neck := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.16, 0.45, 0.18)
	neck.mesh = nb
	neck.material_override = brown
	neck.position = Vector3(0.0, 1.25, 0.5)
	add_child(neck)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.20, 0.22, 0.34)
	head.mesh = hb
	head.material_override = brown
	head.position = Vector3(0.0, 1.5, 0.6)
	add_child(head)
	# Vier Beine.
	for lx in [-0.13, 0.13]:
		for lz in [0.38, -0.38]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.09, 0.62, 0.09)
			leg.mesh = lb
			leg.material_override = brown
			leg.position = Vector3(lx, 0.31, lz)
			add_child(leg)
