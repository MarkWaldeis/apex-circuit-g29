extends Node3D
## The ribbon that shows the ideal line on the road.
##
## OWNER: agent LINE. Green = throttle, yellow = lift, red = brake, drawn a
## little above the asphalt so it never z-fights with it.

const IdealLine = preload("res://scripts/ideal_line.gd")

## Höhe über dem Asphalt: aus dem Cockpit schaut man flach über die Nase, und
## bei 7 cm verschwand die Linie in der Anfahrt auf die Kurve hinter dem
## Dashboard. 12 cm heben sie ins Blickfeld, ohne zu schweben.
const HEIGHT := 0.12
## Breit genug, dass die Linie aus dem Cockpit (Kamera 1,1 m hoch, FOV ~70)
## schon 30 m vor dem Auto klar zu lesen ist - eine 0,55 m schmale Linie ging
## dort im Asphalt unter.
## Breite des Bandes. 1,1 m liest sich aus 200 m Entfernung noch als Linie und
## ist aus dem Cockpit nicht mehr nur ein Strich.
const WIDTH := 1.1
const COLOR_THROTTLE := Color(0.22, 1.0, 0.32, 0.92)
const COLOR_LIFT := Color(1.0, 0.86, 0.16, 0.94)
const COLOR_BRAKE := Color(1.0, 0.15, 0.12, 0.96)

var visible_segments: int = 0
var _mesh: MeshInstance3D
var _enabled: bool = true


func build(line, ideal) -> void:
	if ideal == null or ideal.points.size() < 8:
		push_warning("RacingLineDisplay: no ideal line")
		return
	var n: int = ideal.points.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made := 0
	for i in n:
		var i2: int = (i + 1) % n
		var a: Vector3 = ideal.points[i]
		var b: Vector3 = ideal.points[i2]
		var la: Vector3 = Vector3.UP.cross(ideal.tangent_at(i)).normalized()
		var lb: Vector3 = Vector3.UP.cross(ideal.tangent_at(i2)).normalized()
		var ca: Color = _color(ideal.phase[i])
		var cb: Color = _color(ideal.phase[i2])
		var up := Vector3(0, HEIGHT, 0)
		var a0: Vector3 = a + la * (WIDTH * 0.5) + up
		var a1: Vector3 = a - la * (WIDTH * 0.5) + up
		var b0: Vector3 = b + lb * (WIDTH * 0.5) + up
		var b1: Vector3 = b - lb * (WIDTH * 0.5) + up
		_quad(st, a0, a1, b0, b1, ca, cb)
		made += 1
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	if _mesh:
		_mesh.queue_free()
	_mesh = MeshInstance3D.new()
	_mesh.name = "LineMesh"
	_mesh.mesh = mesh
	_mesh.material_override = _material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible_segments = made
	set_enabled(_enabled)


func _quad(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3,
		ca: Color, cb: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a0)
	st.set_color(ca)
	st.add_vertex(a1)
	st.set_color(cb)
	st.add_vertex(b0)
	st.set_color(ca)
	st.add_vertex(a1)
	st.set_color(cb)
	st.add_vertex(b1)
	st.set_color(cb)
	st.add_vertex(b0)


func _color(phase_value: int) -> Color:
	match phase_value:
		IdealLine.BRAKE:
			return COLOR_BRAKE
		IdealLine.LIFT:
			return COLOR_LIFT
		_:
			return COLOR_THROTTLE


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


func set_enabled(on: bool) -> void:
	_enabled = on
	if _mesh:
		_mesh.visible = on


func is_enabled() -> bool:
	return _enabled
