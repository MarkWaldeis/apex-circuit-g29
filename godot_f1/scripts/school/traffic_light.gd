extends Node3D
## Deutsche Kfz-Ampel: Mast + Signalkasten mit rot/gelb/grün.
## `set_phase(phase)` schaltet das Lichtbild, die Phase kommt aus
## `junction_lights.gd` (die Kreuzungssteuerung).

const RED := Color(0.90, 0.08, 0.06)
const AMBER := Color(0.95, 0.65, 0.05)
const GREEN := Color(0.10, 0.75, 0.25)
const OFF := Color(0.10, 0.10, 0.10)

var _lamps: Array = []        ## [red, amber, green] StandardMaterial3D


static func lamp_mat(color: Color, on: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color if on else OFF
	if on:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.2
	return m


func _ready() -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.09
	pm.height = 3.4
	pole.mesh = pm
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.30, 0.31, 0.33)
	pole.material_override = pole_mat
	pole.position = Vector3(0, 1.7, 0)
	add_child(pole)

	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.36, 1.0, 0.22)
	head.mesh = hb
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.12, 0.12, 0.13)
	head.material_override = head_mat
	head.position = Vector3(0, 3.4, 0)
	add_child(head)

	for i in range(3):
		var col: Color = [RED, AMBER, GREEN][i]
		var mat := lamp_mat(col, i == 0)
		var lamp := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.105
		lm.bottom_radius = 0.105
		lm.radial_segments = 16
		lm.height = 0.05
		lamp.mesh = lm
		lamp.material_override = mat
		lamp.rotation_degrees = Vector3(90, 0, 0)
		lamp.position = Vector3(0, 3.72 - i * 0.32, 0.13)
		add_child(lamp)
		_lamps.append({"mat": mat, "color": col})
	set_phase("red")


func set_phase(phase: String) -> void:
	var on := {"r": phase in ["red", "red_amber"], "y": phase in ["amber", "red_amber"], "g": phase == "green"}
	for i in range(3):
		var want: bool = [on["r"], on["y"], on["g"]][i]
		var l: Dictionary = _lamps[i]
		var mat: StandardMaterial3D = l["mat"]
		var col: Color = l["color"]
		mat.albedo_color = col if want else OFF
		mat.emission_enabled = want
		mat.emission = col
