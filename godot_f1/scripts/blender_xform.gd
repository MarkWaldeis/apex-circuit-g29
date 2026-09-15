extends RefCounted
## Blender Z-up (X,Y,Z) -> glTF/Godot Y-up (X, Z, -Y) as used by Blender's export_yup.

static func vec(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func vecv(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
