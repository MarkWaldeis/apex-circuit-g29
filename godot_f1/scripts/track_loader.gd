extends Node3D

const TRACK_PATH := "res://assets/track/apex_circuit.glb"


func _ready() -> void:
	var packed: PackedScene = load(TRACK_PATH)
	var root: Node3D = packed.instantiate()
	root.name = "ApexCircuit"
	add_child(root)
	_add_collision(root)
	print("Track loaded")


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
