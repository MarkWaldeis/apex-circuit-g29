extends RefCounted
## Deutsche Verkehrszeichen, komplett aus Godot-Primitiven gebaut (kein Bildmaterial
## nötig — die Gesichter sind Scheiben/Platten aus CylinderMesh, BoxMesh und
## TextMesh, damit sie auch headless erzeugt werden können).
##
## make_sign(kind, arg) -> Node3D: fertige Schild-Einheit (Mast + Schild) an
## Position 0, Schildgesicht zeigt +Z — der Aufrufer rotiert um Y.

const POLE_H := 2.4
const SIGN_Y := 2.1
const DISC_R := 0.30
const DISC_T := 0.02

static var _mats := {}


static func _mat(name: String, color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[name] = m
	return m


static func _disc(radius: float, sides: int, mat: Material, thickness: float = DISC_T) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.radial_segments = sides
	c.height = thickness
	mi.mesh = c
	mi.material_override = mat
	mi.rotation_degrees = Vector3(90, 0, 0)
	return mi


static func _text(txt: String, size: float, color: Color) -> MeshInstance3D:
	var t := TextMesh.new()
	t.text = txt
	t.font_size = 64
	t.depth = 0.005
	t.pixel_size = size
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _mat("txt_" + color.to_html(), color)
	mi.rotation_degrees = Vector3(0, 0, 0)
	return mi


static func _bar(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	return mi


static func _ring(outer: float, inner: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 8
	t.ring_segments = 32
	mi.mesh = t
	mi.material_override = mat
	return mi


static func _tri(radius: float, mat: Material, flip_down: bool) -> MeshInstance3D:
	## Dreiecksscheibe (3-seitiges Prisma); flip_down = Spitze nach unten.
	var mi := _disc(radius, 3, mat)
	mi.rotation_degrees = Vector3(90, 0, 180.0 if flip_down else 0.0)
	return mi


static func _arrow(down: bool, thick: bool, mat: Material) -> Node3D:
	## Hoch-/Runterpfeil aus Schaft + Spitze fuer die Engstellen-Schilder.
	var a := Node3D.new()
	var shaft := _bar(Vector3(0.095 if thick else 0.042, 0.20, 0.02), mat)
	shaft.position.y = -0.05
	a.add_child(shaft)
	var head := _tri(0.078 if thick else 0.055, mat, false)
	head.position.y = 0.10
	a.add_child(head)
	if down:
		a.rotation_degrees.z = 180.0
	return a


## Baut das komplette Schild. `kind`/`arg` siehe Aufrufer in city_builder.
static func make_sign(kind: String, arg := "") -> Node3D:
	var root := Node3D.new()
	root.name = "Sign_" + kind
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.05
	pm.height = POLE_H
	pole.mesh = pm
	pole.material_override = _mat("pole", Color(0.45, 0.46, 0.48))
	pole.position = Vector3(0, POLE_H * 0.5, -0.06)
	root.add_child(pole)

	var face := Node3D.new()
	face.name = "Face"
	face.position = Vector3(0, SIGN_Y, 0)
	root.add_child(face)

	var red := _mat("red", Color(0.78, 0.10, 0.10))
	var white := _mat("white", Color(0.96, 0.96, 0.94))
	var blue := _mat("blue", Color(0.07, 0.25, 0.72))
	var yellow := _mat("yellow", Color(0.95, 0.75, 0.12))
	var black := _mat("black", Color(0.05, 0.05, 0.06))
	var grey := _mat("grey", Color(0.55, 0.56, 0.58))

	match kind:
		"stop":
			var back := _disc(0.42, 8, red, 0.03)
			back.rotation_degrees.z = 22.5
			face.add_child(back)
			var inner := _disc(0.33, 8, white, 0.031)
			inner.rotation_degrees.z = 22.5
			inner.position.z = 0.002
			face.add_child(inner)
			var core := _disc(0.30, 8, red, 0.032)
			core.rotation_degrees.z = 22.5
			core.position.z = 0.004
			face.add_child(core)
			var txt := _text("STOP", 0.0030, Color(0.96, 0.96, 0.94))
			txt.position.z = 0.03
			face.add_child(txt)
		"yield":
			var back := _tri(0.48, red, true)
			face.add_child(back)
			var inner := _tri(0.38, white, true)
			inner.position.z = 0.004
			face.add_child(inner)
		"priority":
			var back := _disc(0.34, 4, white, 0.03)
			face.add_child(back)
			var inner := _disc(0.26, 4, yellow, 0.032)
			inner.position.z = 0.004
			face.add_child(inner)
		"rbl":
			## Zeichen 102: Kreuzung/Einmündung mit Vorfahrt von rechts.
			var back := _tri(0.48, red, false)
			face.add_child(back)
			var inner := _tri(0.38, white, false)
			inner.position.z = 0.004
			face.add_child(inner)
			var cross := _bar(Vector3(0.05, 0.26, 0.02), black)
			cross.position.z = 0.02
			face.add_child(cross)
			var cross2 := _bar(Vector3(0.26, 0.05, 0.02), black)
			cross2.position.z = 0.02
			face.add_child(cross2)
		"limit":
			var back := _disc(DISC_R + 0.045, 40, red)
			face.add_child(back)
			var inner := _disc(DISC_R - 0.03, 40, white)
			inner.position.z = 0.004
			face.add_child(inner)
			var txt := _text(arg, 0.0040, Color(0.05, 0.05, 0.06))
			txt.position.z = 0.03
			face.add_child(txt)
		"limit_end":
			var back := _disc(DISC_R + 0.045, 40, grey)
			face.add_child(back)
			var inner := _disc(DISC_R - 0.03, 40, white)
			inner.position.z = 0.004
			face.add_child(inner)
			for i in range(5):
				var stripe := _bar(Vector3(0.035, 0.62, 0.01), black)
				stripe.rotation_degrees.z = 45
				stripe.position = Vector3(-0.18 + i * 0.09, 0.0, 0.02)
				face.add_child(stripe)
		"roundabout":
			var back := _disc(0.40, 40, blue)
			face.add_child(back)
			var ringm := _ring(0.22, 0.16, _mat("white", Color(0.96, 0.96, 0.94)))
			ringm.position.z = 0.02
			face.add_child(ringm)
			for i in range(3):
				var a := TAU * float(i) / 3.0
				var head := _tri(0.09, white, false)
				head.position = Vector3(cos(a) * 0.19, sin(a) * 0.19, 0.025)
				head.rotation_degrees.z = -rad_to_deg(a) - 90
				face.add_child(head)
		"one_way":
			var back := _bar(Vector3(0.62, 0.42, 0.03), blue)
			face.add_child(back)
			var arrow := _bar(Vector3(0.40, 0.10, 0.02), white)
			arrow.position.z = 0.025
			face.add_child(arrow)
			var head := _tri(0.13, white, true)
			head.rotation_degrees = Vector3(90, 0, -90)
			head.position = Vector3(0.24, 0.0, 0.025)
			face.add_child(head)
		"no_entry":
			var back := _disc(0.40, 40, red)
			face.add_child(back)
			var bar := _bar(Vector3(0.52, 0.10, 0.02), white)
			bar.position.z = 0.02
			face.add_child(bar)
		"zebra":
			var back := _bar(Vector3(0.62, 0.62, 0.03), blue)
			face.add_child(back)
			var tri := _tri(0.24, white, false)
			tri.position.z = 0.025
			face.add_child(tri)
			for i in range(3):
				var dot := _disc(0.045, 12, black, 0.015)
				dot.position = Vector3(-0.10 + i * 0.10, -0.055, 0.04)
				face.add_child(dot)
		"engst_wait":
			## Zeichen 208: Dem Gegenverkehr Vorrang gewaehren — eigenes
			## (dickes, schwarzes) Hoch muss auf den duennen roten
			## Gegenpfeil warten.
			var rim := _bar(Vector3(0.60, 0.60, 0.015), black)
			rim.position.z = -0.012
			face.add_child(rim)
			var back := _bar(Vector3(0.56, 0.56, 0.02), white)
			face.add_child(back)
			var up := _arrow(false, true, black)
			up.position = Vector3(-0.10, 0.0, 0.03)
			face.add_child(up)
			var dn := _arrow(true, false, red)
			dn.position = Vector3(0.12, 0.0, 0.03)
			face.add_child(dn)
		"engst_prio":
			## Zeichen 308: Vorrang vor dem Gegenverkehr — dicker weisser
			## Hochpfeil darf zuerst durch die Engstelle.
			var back := _bar(Vector3(0.56, 0.56, 0.02), blue)
			face.add_child(back)
			var up := _arrow(false, true, white)
			up.position = Vector3(-0.10, 0.0, 0.03)
			face.add_child(up)
			var dn := _arrow(true, false, red)
			dn.position = Vector3(0.12, 0.0, 0.03)
			face.add_child(dn)
		"parking":
			var back := _bar(Vector3(0.55, 0.55, 0.03), blue)
			face.add_child(back)
			var txt := _text("P", 0.011, Color(0.96, 0.96, 0.94))
			txt.position.z = 0.03
			face.add_child(txt)
		"board":
			## Große weiße Hinweistafel mit beliebigem Text (arg), z. B. ÜBUNGSPLATZ.
			var back := _bar(Vector3(1.5, 0.55, 0.03), white)
			face.add_child(back)
			var rim := _bar(Vector3(1.56, 0.61, 0.015), black)
			rim.position.z = -0.012
			face.add_child(rim)
			var txt := _text(arg, 0.0020, Color(0.05, 0.05, 0.06))
			txt.position.z = 0.03
			face.add_child(txt)
		"marker":
			var back := _bar(Vector3(0.42, 0.55, 0.03), white)
			face.add_child(back)
			var txt := _text(arg, 0.0038, Color(0.05, 0.05, 0.06))
			txt.position.z = 0.03
			face.add_child(txt)
		_:
			var back := _disc(0.3, 32, grey)
			face.add_child(back)
	return root
