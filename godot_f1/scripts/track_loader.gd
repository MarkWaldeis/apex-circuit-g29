extends Node3D

const TRACK_PATH := "res://assets/track/apex_circuit.glb"
const LINE_PATH := "res://assets/track/racing_line.json"
const RacingLine = preload("res://scripts/racing_line.gd")
const Look = preload("res://scripts/look.gd")


func _ready() -> void:
	var packed: PackedScene = load(TRACK_PATH)
	var root: Node3D = packed.instantiate()
	root.name = "ApexCircuit"
	add_child(root)
	_add_collision(root)
	print("Track loaded")
	_dress(root)


func _dress(root: Node3D) -> void:
	## Trackside decoration + material polish (see scripts/look.gd).
	var line = RacingLine.new()
	if not line.load_json(LINE_PATH):
		push_warning("Track: racing line missing, skipping props")
		return
	var look := Look.new()
	look.name = "Look"
	add_child(look)
	look.build(line, root)


func _add_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var n := mi.name
		if n.begins_with("PitBuilding") or n.begins_with("PitRoof"):
			if mi.mesh:
				var body := StaticBody3D.new()
				body.name = "Static_" + n
				var col := CollisionShape3D.new()
				var shape := mi.mesh.create_trimesh_shape()
				if shape:
					shape.margin = 0.05
					col.shape = shape
					body.add_child(col)
					mi.add_child(body)
				if n.begins_with("COL_"):
					mi.visible = false
	for c in node.get_children():
		_add_collision(c)
