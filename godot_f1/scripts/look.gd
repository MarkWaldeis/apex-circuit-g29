extends Node3D
## Visual dressing for the circuit: better track materials plus trackside props
## taken from the imported prop GLBs. Everything is positioned from the racing
## line, and nothing is allowed inside the driving surface.

const PROPS := {
	"tire_stack": {"path": "res://assets/props/tire_stack.glb", "height": 1.25},
	"tire_rack": {"path": "res://assets/props/tire_rack.glb", "height": 1.9},
	"cone": {"path": "res://assets/props/traffic_cone.glb", "height": 0.75},
	"signboard": {"path": "res://assets/props/signboard.glb", "height": 3.0},
	"guard_tower": {"path": "res://assets/props/guard_tower.glb", "height": 9.0},
	"seating": {"path": "res://assets/props/stadium_seating.glb", "height": 6.0},
	"gantry": {"path": "res://assets/props/traffic_light_gantry.glb", "height": 7.0},
	"bar": {"path": "res://assets/props/bar_counter.glb", "height": 1.1},
}

const ROAD_HALF_WIDTH := 9.5
const MIN_CLEARANCE := 10.5

var _cache: Dictionary = {}
var placed: int = 0


func build(line, track_root: Node3D) -> int:
	if line == null or line.points.size() < 32:
		push_warning("Look: racing line missing, skipping props")
		return 0
	_tune_track_materials(track_root)
	_place_corner_props(line)
	_place_trackside_props(line)
	print("PROPS placed=", placed)
	print("PROPS nodes=", _count_nodes(self))
	return placed


func _count_nodes(node: Node) -> int:
	var n: int = node.get_child_count()
	for c in node.get_children():
		n += _count_nodes(c)
	return n


## ---- materials ------------------------------------------------------------

func _tune_track_materials(root: Node) -> void:
	## The GLB materials are flat: asphalt is too bright, kerbs and runoff have
	## no depth. Nudge rough/metal and tint slightly so the surface reads as
	## tarmac instead of grey plastic.
	var tuned: int = 0
	for node in _walk(root):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			var sm := mat as StandardMaterial3D
			if sm == null:
				continue
			var name := sm.resource_name.to_lower()
			var copy: StandardMaterial3D = sm.duplicate()
			if "asphalt" in name or "road" in name:
				copy.albedo_color = copy.albedo_color.darkened(0.22)
				copy.roughness = 0.88
				copy.metallic = 0.0
			elif "kerb" in name:
				copy.roughness = 0.55
				copy.albedo_color = copy.albedo_color.lightened(0.08)
			elif "runoff" in name or "gravel" in name:
				copy.roughness = 0.95
			elif "grass" in name:
				copy.roughness = 1.0
				copy.albedo_color = copy.albedo_color.darkened(0.12)
			elif "barrier" in name:
				copy.metallic = 0.35
				copy.roughness = 0.45
			else:
				continue
			mi.set_surface_override_material(i, copy)
			tuned += 1
	print("LOOK materials_tuned=", tuned)


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out


## ---- props ----------------------------------------------------------------

func _place_corner_props(line) -> void:
	var n: int = line.points.size()
	var i: int = 8
	while i < n:
		var curve: float = line.curvature_ahead(line.points[i], 1.0)
		if curve < 0.09:
			i += 6
			continue
		var t: Vector3 = line.tangents[i]
		t.y = 0.0
		t = t.normalized()
		var left: Vector3 = t.cross(Vector3.UP).normalized()
		var turn: float = t.signed_angle_to(line.tangents[(i + 14) % n], Vector3.UP)
		# Outside of the corner gets the tyre wall, inside the cones.
		var outside: Vector3 = left * (-1.0 if turn > 0.0 else 1.0)
		var inside: Vector3 = -outside
		var p: Vector3 = line.points[i]
		_spawn("tire_stack", p + outside * 11.5, outside, 1.0, 2.0)
		_spawn("tire_stack", p + outside * 12.6 + t * 2.2, outside, 0.9, 2.4)
		_spawn("tire_rack", p + outside * 13.4 + t * 4.4, outside, 1.0, 2.6)
		# Cones mark the inside of the corner, but they stay beyond the kerb so
		# the car never drives through them.
		_spawn("cone", p + inside * 10.1 - t * 3.0, inside, 1.0, 3.2)
		_spawn("cone", p + inside * 10.3 + t * 3.0, inside, 1.0, 3.2)
		i += 26


func _place_trackside_props(line) -> void:
	var n: int = line.points.size()
	# Advertising boards and marshal towers along the straights.
	var i: int = 20
	var side := 1.0
	while i < n:
		var t: Vector3 = line.tangents[i]
		t.y = 0.0
		t = t.normalized()
		var left: Vector3 = t.cross(Vector3.UP).normalized()
		var p: Vector3 = line.points[i]
		var dir: Vector3 = left * side
		_spawn("signboard", p + dir * 12.5, dir, 1.0, 0.9)
		if (i / 55) % 3 == 0:
			_spawn("guard_tower", p + dir * 19.0, dir, 1.0, 1.6)
		if (i / 55) % 4 == 1:
			_spawn("seating", p + dir * 24.0, dir, 1.0, 1.6)
		side = -side
		i += 55
	# Start/finish furniture and a little pit-lane life near the S/F line.
	var sf_t: Vector3 = line.tangents[2]
	sf_t.y = 0.0
	sf_t = sf_t.normalized()
	var sf_left: Vector3 = sf_t.cross(Vector3.UP).normalized()
	var sf: Vector3 = line.points[2]
	_spawn("gantry", sf - sf_left * 12.0, sf_left, 1.0, 1.0)
	_spawn("gantry", sf + sf_left * 12.0, -sf_left, 1.0, 1.0)
	_spawn("seating", sf - sf_left * 20.5, sf_left, 1.0, 1.0)
	_spawn("seating", sf + sf_left * 20.5, -sf_left, 1.0, 1.0)
	_spawn("bar", sf - sf_left * 16.0 + sf_t * 12.0, sf_left, 1.0, 1.0)
	_spawn("tire_rack", sf + sf_left * 15.0 + sf_t * 26.0, sf_left, 1.0, 1.0)
	_spawn("tire_stack", sf + sf_left * 14.0 + sf_t * 32.0, sf_left, 1.0, 1.0)


func _spawn(kind: String, pos: Vector3, face_dir: Vector3, scale_mul: float = 1.0, sink: float = 0.0) -> void:
	var spec: Dictionary = PROPS[kind]
	var packed: PackedScene = _load(spec["path"])
	if packed == null:
		return
	var inst: Node3D = packed.instantiate()
	inst.name = "Prop_%s_%d" % [kind, placed]
	add_child(inst)
	# Scale the model so its height matches the real-world size we want.
	var aabb: AABB = _aabb(inst)
	var target: float = float(spec["height"]) * scale_mul
	var h: float = maxf(aabb.size.y, 0.01)
	var s: float = target / h
	inst.scale = Vector3(s, s, s)
	inst.position = pos + Vector3(0.0, target * 0.5 - sink, 0.0)
	# Face the track.
	var flat := Vector3(face_dir.x, 0.0, face_dir.z)
	if flat.length() > 0.01:
		inst.rotation.y = atan2(-flat.x, -flat.z)
	placed += 1


func _load(path: String) -> PackedScene:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in _walk(node):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
