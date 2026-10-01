extends RefCounted
## Sichtmodell des Fahrschulautos: ein kompakter 5-Türer aus Primitiven —
## kein Formel-Auto, sondern das Auto aus der Fahrschule. +Z = Fahrtrichtung
## (gleiche Konvention wie der F1-Wagen in car_controller.gd).
##
## `build()` liefert den Visual-Node; die Rad-Meshes heißen Wheel_FL/FR/RL/RR
## und sitzen an den Naben, die school_car.gd auch für die Physik nutzt.

const PAINT := Color(0.16, 0.42, 0.68)      ## Fahrschul-Blau
const GLASS := Color(0.10, 0.14, 0.18, 1.0)
const TYRE := Color(0.05, 0.05, 0.055)
const RIM := Color(0.62, 0.63, 0.66)

## Naben (x rechts +, z vorne +, y = Radmitte). Schule-Auto: Spur 1.56,
## Radstand 2.6, Radius 0.32.
const HUBS := {
	"FL": Vector3(0.78, 0.32, 1.30), "FR": Vector3(-0.78, 0.32, 1.30),
	"RL": Vector3(0.78, 0.32, -1.30), "RR": Vector3(-0.78, 0.32, -1.30),
}
const WHEEL_RADIUS := 0.32
const WHEEL_WIDTH := 0.24


static func _mat(color: Color, rough := 0.55, metal := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = GLASS
	m.roughness = 0.12
	m.metallic = 0.7
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Baut das Sichtmodell. Liefert {"root": Node3D, "wheels": {FL..RR: Node3D},
## "brake_l": Material, "blinker_l"/"blinker_r": Array[Material]} — die Lampen-
## Materialien schaltet das Auto selbst (Bremslicht, Blinker, Warnblinker).
static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "SchoolCarMesh"
	var paint := _mat(PAINT, 0.35, 0.4)
	var dark := _mat(Color(0.08, 0.08, 0.10), 0.8, 0.0)
	var glass := _glass_mat()

	# Unterboden und Schweller.
	_box(root, Vector3(1.62, 0.18, 4.10), Vector3(0, 0.30, 0), dark)
	# Karosserie: Bodengruppe, dann Motorhaube/Heckflanken.
	_box(root, Vector3(1.74, 0.42, 3.40), Vector3(0, 0.58, -0.30), paint)
	# Motorhaube (vorne, leicht abfallend angedeutet über zwei Boxen).
	_box(root, Vector3(1.74, 0.34, 0.78), Vector3(0, 0.56, 1.42), paint)
	_box(root, Vector3(1.70, 0.10, 0.78), Vector3(0, 0.72, 1.42), paint)
	# Kühlergrill.
	_box(root, Vector3(1.20, 0.16, 0.06), Vector3(0, 0.44, 1.83), dark)
	# Stoßfänger vorne/hinten.
	_box(root, Vector3(1.76, 0.22, 0.20), Vector3(0, 0.32, 1.86), paint)
	_box(root, Vector3(1.76, 0.22, 0.20), Vector3(0, 0.32, -1.86), paint)
	# Fahrgastzelle: Glasband zwischen den Säulen.
	_box(root, Vector3(1.52, 0.50, 2.10), Vector3(0, 1.03, -0.24), glass)
	# Dach.
	_box(root, Vector3(1.58, 0.07, 2.20), Vector3(0, 1.31, -0.24), paint)
	# A/B/C-Säulen als schmale Kästen am Glasband.
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.09, 0.52, 0.12), Vector3(0.74 * sx, 1.02, 0.78), paint)
		_box(root, Vector3(0.09, 0.52, 0.12), Vector3(0.74 * sx, 1.02, -1.22), paint)
	# Heckscheibe hinten geneigt.
	var rear := _box(root, Vector3(1.44, 0.52, 0.07), Vector3(0, 1.02, -1.30), glass)
	rear.rotation_degrees.x = -14.0

	# Scheinwerfer (weiße Linsen) + Rücklichter + Blinker vorn/hinten.
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.95, 0.95, 0.9)
	head.emission_enabled = true
	head.emission = Color(0.95, 0.95, 0.85)
	head.emission_energy_multiplier = 0.6
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.55, 0.06, 0.06)
	tail.emission_enabled = true
	tail.emission = Color(0.8, 0.05, 0.05)
	tail.emission_energy_multiplier = 0.4
	var blink := StandardMaterial3D.new()
	blink.albedo_color = Color(0.85, 0.45, 0.05)
	blink.emission_enabled = true
	blink.emission = Color(0.95, 0.55, 0.05)
	blink.emission_energy_multiplier = 0.2
	var blink_l: Array = []
	var blink_r: Array = []
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.34, 0.14, 0.06), Vector3(0.55 * sx, 0.62, 1.90), head)
		_box(root, Vector3(0.34, 0.14, 0.06), Vector3(0.55 * sx, 0.66, -1.93), tail)
		var bi := _box(root, Vector3(0.16, 0.10, 0.06), Vector3(0.80 * sx, 0.62, 1.90), blink.duplicate())
		var bj := _box(root, Vector3(0.16, 0.10, 0.06), Vector3(0.80 * sx, 0.66, -1.93), blink.duplicate())
		if sx > 0:
			blink_l.append(bi.material_override)
			blink_l.append(bj.material_override)
		else:
			blink_r.append(bi.material_override)
			blink_r.append(bj.material_override)
	# Bremslicht (leuchtet beim Bremsen auf — Fahrlehrer sieht es).
	var brake := StandardMaterial3D.new()
	brake.albedo_color = Color(0.45, 0.05, 0.05)
	brake.emission_enabled = true
	brake.emission = Color(0.9, 0.05, 0.05)
	brake.emission_energy_multiplier = 0.3
	_box(root, Vector3(0.9, 0.07, 0.05), Vector3(0, 1.26, -1.36), brake)

	# Fahrschul-Schild auf dem Dach (weißes Schild + rote Aufschrift).
	var sign_mat := _mat(Color(0.96, 0.96, 0.94), 0.7, 0.0)
	var sign := _box(root, Vector3(0.62, 0.34, 0.06), Vector3(0, 1.52, -0.2), sign_mat)
	sign.rotation_degrees.x = -6.0
	var signtext := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = "L"
	tm.font_size = 40
	signtext.mesh = tm
	var signtext_mat := StandardMaterial3D.new()
	signtext_mat.albedo_color = Color(0.85, 0.08, 0.08)
	signtext.material_override = signtext_mat
	signtext.rotation_degrees = Vector3(-90, 0, 0)
	signtext.position = Vector3(0, 1.53, -0.2)
	root.add_child(signtext)

	# Räder: Reifen-Torus + Felge.
	var wheels := {}
	for key in HUBS.keys():
		var w := Node3D.new()
		w.name = "Wheel_%s" % key
		w.position = HUBS[key]
		var tyre := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = WHEEL_RADIUS - WHEEL_WIDTH * 0.5
		torus.outer_radius = WHEEL_RADIUS
		torus.rings = 18
		torus.ring_segments = 24
		tyre.mesh = torus
		tyre.material_override = _mat(TYRE, 0.95, 0.0)
		tyre.rotation_degrees = Vector3(0, 90, 0)
		w.add_child(tyre)
		var rim := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = WHEEL_RADIUS - WHEEL_WIDTH * 0.55
		cyl.bottom_radius = WHEEL_RADIUS - WHEEL_WIDTH * 0.55
		cyl.height = WHEEL_WIDTH * 0.9
		cyl.radial_segments = 18
		rim.mesh = cyl
		rim.material_override = _mat(RIM, 0.35, 0.8)
		rim.rotation_degrees = Vector3(0, 0, 90)
		w.add_child(rim)
		root.add_child(w)
		wheels[key] = w

	return {
		"root": root,
		"wheels": wheels,
		"brake_l": brake,
		"blinker_l": blink_l,
		"blinker_r": blink_r,
	}
