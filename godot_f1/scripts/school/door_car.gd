class_name DoorCar
extends Node3D

## Parkendes Auto an der Weststrasse: alle ~42 s schwingt die
## Fahrertuer Richtung Fahrbahn auf — die klassische Dooring-Gefahr.
## Der Fahrlehrer liest `open_frac` aus und mahnt Abstand.

const CYCLE := 42.0          ## Sekunden pro Oeffnungszyklus
const OPEN_T := 3.6          ## wie lange die Tuer offen steht

var open_frac := 0.0         ## 0 = zu, 1 = weit offen
var _t := 14.0               ## erste Oeffnung frueh, aber nicht sofort
var _pivot: Node3D


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_t += delta
	var ph := fmod(_t, CYCLE)
	var want := 1.0 if ph < OPEN_T else 0.0
	open_frac = move_toward(open_frac, want, delta * 2.6)
	_pivot.rotation.y = -open_frac * 1.15


func is_open() -> bool:
	return open_frac > 0.4


func _build() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.76, 1.35, 4.1)
	col.shape = box
	col.position = Vector3(0, 0.7, 0)
	body.add_child(col)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.2, 0.16)
	mat.metallic = 0.4
	var vis := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(1.74, 0.5, 4.0)
	vis.mesh = vb
	vis.material_override = mat
	vis.position = Vector3(0, 0.55, 0)
	body.add_child(vis)
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color(0.1, 0.13, 0.17)
	var cab := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.5, 0.5, 2.1)
	cab.mesh = cb
	cab.material_override = cab_mat
	cab.position = Vector3(0, 1.0, -0.2)
	body.add_child(cab)

	# Fahrertuer auf der Fahrbahnseite (+x): am Vorderkanten-Scharnier
	# aufschwingend — der Schueler sieht das Aufklappen fruehzeitig.
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.88, 0.85, 0.55)
	body.add_child(_pivot)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.06, 0.7, 1.15)
	door.mesh = dm
	door.material_override = mat
	door.position = Vector3(0.0, 0.0, -0.57)
	_pivot.add_child(door)
	add_child(body)
