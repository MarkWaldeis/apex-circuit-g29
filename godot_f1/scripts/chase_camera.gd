extends Camera3D

var target: Node3D
var mode: int = 0
var _offset := Vector3(0, 2.4, 7.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_cycle"):
		mode = (mode + 1) % 3


func _process(delta: float) -> void:
	if target == null:
		return
	var follow := target.global_transform
	var desired: Transform3D
	match mode:
		1:
			desired = follow
			desired.origin += follow.basis.y * 0.72 + follow.basis.z * 0.4
		2:
			desired = Transform3D(Basis.looking_at(Vector3(0, -0.35, -1), Vector3.UP), follow.origin + Vector3(0, 42, 18))
		_:
			# +Z is vehicle forward; sit behind the car.
			desired = follow
			desired.origin += follow.basis.y * _offset.y - follow.basis.z * _offset.z
	global_transform = global_transform.interpolate_with(desired, clampf(delta * 6.0, 0.0, 1.0))
	if mode != 1:
		look_at(target.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	fov = 62.0 if mode != 1 else 70.0
