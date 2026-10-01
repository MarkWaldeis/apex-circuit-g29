extends Node3D
## Fussgaengerampel (kleiner Signalgeber mitten auf der Hauptstrasse
## bei x=40). Ein Fussgaenger wartet am Bordstein; wenn seine Ampel
## gruen wird, zeigt die Fahrbahn-Ampel gelb, dann rot — der
## Fussgaenger quert, der Verkehr haelt.
##
## Die Ampel laeuft eigenstaendig: Wartezeit (Fussgaenger steht da) ->
## gelb -> rot (Fussgaenger geht) -> frei. Der Fahrlehrer fragt
## car_phase() ab und wertet Rotlicht sowie das rechtzeitige Anhalten.

const CrossingPed = preload("res://scripts/school/crossing_ped.gd")

const P_X := 40.0          ## Querungspunkt auf der Hauptstrasse
const Z_ROAD := -60.0      ## Fahrbahnmitte Hauptstrasse
const Z_S := -53.0         ## Bordstein Suedseite
const Z_N := -67.0         ## Bordstein Nordseite

var _phase := "green"      ## Fahrbahn-Signal: green/amber/red
var _t := 0.0
var _ped_side := 1.0       ## 1 = wartet suedlich, -1 = wartet noerdlich
var _ped_wait := 7.0       ## bis zur naechsten Querungs-Anforderung
var _ped_walk := false
var _ped_t := 0.0
var _lamp_car: Array = []  ## [ [rot, gelb, gruen] je Richtung ]
var _lamp_ped: Array = []  ## [ rot, gruen ] Fußgaengersignal
var _ped: Node3D
var watchers: Array = []   ## Kompatibilitaet mit pedestrian.gd (KI-Liste)

## Die KI-Liste bekommt diese Figur (eigene Position + on_road()).
func ped_node() -> Node3D:
	return _ped


func _ready() -> void:
	_build_markings()
	_build_mast(Vector2(P_X + 4.5, Z_S), 270.0)   # Ost-Richtung
	_build_mast(Vector2(P_X - 4.5, Z_N), 90.0)    # West-Richtung
	_build_ped_lamp(Vector2(P_X + 4.5, Z_S + 1.0), 180.0)
	_build_ped_lamp(Vector2(P_X - 4.5, Z_N - 1.0), 0.0)
	_ped = CrossingPed.new()
	_ped.name = "PedXFigur"
	_build_figure(_ped)
	_ped.global_position = Vector3(P_X + 1.6, 0.0, Z_S)
	add_child(_ped)


func car_phase() -> String:
	return _phase


func cross_pos() -> Vector2:
	return Vector2(P_X, Z_ROAD)


## Wie bei pedestrian.gd: KI-Autos fragen ab, ob die Figur gerade
## auf der Fahrbahn ist — dann bremsen sie davor.
func on_road() -> bool:
	return _ped_walk and absf(_ped.global_position.z - Z_ROAD) < 4.0


func _physics_process(delta: float) -> void:
	_t += delta
	match _phase:
		"green":
			if _t >= _ped_wait:
				_phase = "amber"
				_t = 0.0
		"amber":
			if _t > 2.2:
				_phase = "red"
				_t = 0.0
				_ped_walk = true
				_ped_t = 0.0
		"red":
			if _t > 12.5:
				_phase = "green"
				_t = 0.0
				_ped_wait = randf_range(16.0, 30.0)
	_update_lamps()
	if _ped_walk:
		_ped_t += delta
		var u: float = clampf(_ped_t / 9.5, 0.0, 1.0)
		var z: float = lerpf(Z_S * _ped_side, -Z_S * _ped_side, u)
		_ped.global_position = Vector3(P_X + 1.6, 0.0, z)
		if u >= 1.0:
			_ped_walk = false
			_ped_side *= -1.0
	_ped.walking = _ped_walk


func _update_lamps() -> void:
	# Ein-/Ausschalten ueber Sichtbarkeit der Lampen-Meshes.
	for pair in _lamp_car:
		pair[0].visible = _phase == "red"
		pair[1].visible = _phase == "amber"
		pair[2].visible = _phase == "green"
	_lamp_ped[0].visible = _phase != "red" or _ped_t > 10.5
	_lamp_ped[1].visible = _phase == "red" and _ped_t <= 10.5


func _build_figure(n: Node3D) -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.55
	body.mesh = cap
	body.position.y = 0.78
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.45, 0.85)
	body.material_override = bm
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.15
	sp.height = 0.3
	head.mesh = sp
	head.position.y = 1.7
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.85, 0.7, 0.55)
	head.material_override = hm
	n.add_child(head)
	var col_body := AnimatableBody3D.new()
	col_body.name = "Fussgaenger"
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.26
	cs.height = 1.6
	col.shape = cs
	col.position.y = 0.8
	col_body.add_child(col)
	n.add_child(col_body)


func _build_markings() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	# Querbalken der Querung (wie Zebrastreifen).
	for i in range(5):
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.014, 7.0)
		m.mesh = bm
		m.material_override = white
		m.position = Vector3(P_X - 1.8 + i * 0.9, 0.026, Z_ROAD)
		add_child(m)
	# Haltelinie je Richtung (nur auf der eigenen Fahrbahnhaelfte).
	for off in [[-3.4, 1.8], [3.4, -1.8]]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.014, 3.4)
		m.mesh = bm
		m.material_override = white
		m.position = Vector3(P_X + float(off[0]), 0.026, Z_ROAD + float(off[1]))
		add_child(m)


func _signal_head(rot_y: float, ped: bool) -> Node3D:
	var head := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.9 if not ped else 0.62, 0.18)
	box.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	box.material_override = dark
	head.add_child(box)
	var colors: Array = []
	if ped:
		colors = [Color(1.0, 0.15, 0.15), Color(0.15, 0.9, 0.25)]
	else:
		colors = [Color(1.0, 0.15, 0.15), Color(1.0, 0.7, 0.1),
			Color(0.15, 0.9, 0.25)]
	var lamps: Array = []
	for i in colors.size():
		var l := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.085
		sm.height = 0.17
		l.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 2.5
		l.material_override = mat
		var y := (0.26 - i * 0.26) if not ped else (0.14 - i * 0.28)
		l.position = Vector3(0.0, y, -0.12)
		lamps.append(l)
		head.add_child(l)
	head.rotation_degrees.y = rot_y
	if ped:
		_lamp_ped.append_array(lamps)
	else:
		_lamp_car.append(lamps)
	return head


func _build_mast(pos: Vector2, rot_y: float) -> void:
	var mast := Node3D.new()
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 3.0
	pole.mesh = pm
	pole.position.y = 1.5
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.38)
	pole.material_override = gm
	mast.add_child(pole)
	var head := _signal_head(rot_y, false)
	head.position.y = 2.6
	mast.add_child(head)
	mast.position = Vector3(pos.x, 0.0, pos.y)
	add_child(mast)


func _build_ped_lamp(pos: Vector2, rot_y: float) -> void:
	var mast := Node3D.new()
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.05
	pm.height = 2.4
	pole.mesh = pm
	pole.position.y = 1.2
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.38)
	pole.material_override = gm
	mast.add_child(pole)
	var head := _signal_head(rot_y, true)
	head.position.y = 2.15
	mast.add_child(head)
	mast.position = Vector3(pos.x, 0.0, pos.y)
	add_child(mast)
