extends RefCounted
## Baut die Fahrschul-Welt aus dem Datenmodell in city_layout.gd:
## Straßen (Fahrbahn + Mittellinie + Bordsteine), Kreuzungen, Ampel,
## Verkehrszeichen, Zebrastreifen, Kreisverkehr, Übungsplatz mit allen
## Übungselementen, Häuserzeilen und Bäumen.
##
## `build(world) -> Dictionary` liefert die Knoten und Daten, die die
## Spielleitung braucht: {"roads_body", "junctions", "light_controller",
## "lot", "cones", "parked_cars"}.

const CityLayout = preload("res://scripts/school/city_layout.gd")
const TrafficSigns = preload("res://scripts/school/traffic_signs.gd")
const TrafficLight = preload("res://scripts/school/traffic_light.gd")

const ASPHALT_C := Color(0.24, 0.25, 0.27)
const ASPHALT_LOT := Color(0.30, 0.31, 0.33)
const KERB_C := Color(0.55, 0.55, 0.58)
const GRASS_C := Color(0.20, 0.36, 0.17)
const LINE_C := Color(0.92, 0.92, 0.90)
const KERB_H := 0.075

var _mat_cache := {}


func _mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


func build(world: Node3D) -> Dictionary:
	_mat_cache = {}
	var out := {"cones": [], "parked_cars": []}
	_ground(world)
	var roads_body := _roads(world)
	out["roads_body"] = roads_body
	_junction_patches(world)
	_markings(world)
	_signs(world)
	_roundabout(world)
	out["lights"] = _traffic_lights(world)
	_lot(world, out)
	_buildings(world)
	_trees(world)
	return out


# ---------------------------------------------------------------- Flächen

func _ground(world: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(560, 0.4, 460)
	col.shape = box
	col.position = Vector3(0, -0.28, -40)
	body.add_child(col)
	world.add_child(body)
	var vis := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(560, 460)
	vis.mesh = plane
	vis.material_override = _mat(GRASS_C, 1.0)
	vis.position = Vector3(0, -0.09, -40)
	world.add_child(vis)


## Ein längliches Kollisionsstück + eine Fahrbahnplatte entlang from→to.
func _road_segment(body: StaticBody3D, world: Node3D, a: Vector2, b: Vector2, width: float, line: bool) -> void:
	var dir := (b - a)
	var length := dir.length()
	if length < 0.5:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(dir.x, dir.y)
	# Kollision: eine Box pro Segment — genau wie die RoadBoxes im F1-Teil.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.3, length + 1.5)
	col.shape = box
	col.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, -0.11, mid.y))
	body.add_child(col)
	# Sichtbarer Belag.
	var vis := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.02, length + 1.5)
	vis.mesh = bm
	vis.material_override = _mat(ASPHALT_C)
	vis.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.001, mid.y))
	world.add_child(vis)
	# Bordsteine an beiden Rändern (erhöht, hell — Kerb-Zone in den Surfaces).
	for side in [-1.0, 1.0]:
		var off := Vector2(dir.y, -dir.x).normalized() * (width * 0.5 + 0.55)
		var k := MeshInstance3D.new()
		var kb := BoxMesh.new()
		kb.size = Vector3(1.1, KERB_H * 2.0, length + 1.5)
		k.mesh = kb
		k.material_override = _mat(KERB_C, 0.95)
		k.transform = Transform3D(Basis(Vector3.UP, yaw),
				Vector3(mid.x + off.x, KERB_H * 0.5, mid.y + off.y))
		world.add_child(k)
		var kcol := CollisionShape3D.new()
		var kbox := BoxShape3D.new()
		kbox.size = Vector3(1.1, KERB_H * 2.0, length + 1.5)
		kcol.shape = kbox
		kcol.transform = k.transform
		body.add_child(kcol)
	# Mittellinie: gestrichelt, nur wo markiert.
	if line:
		var dash := 3.0
		var gap := 6.0
		var n := int(length / (dash + gap))
		for i in range(n):
			var d := (i + 0.5) * (dash + gap)
			var p := a + dir.normalized() * d
			var lm := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.15, 0.012, dash)
			lm.mesh = lb
			lm.material_override = _mat(LINE_C)
			lm.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.02, p.y))
			world.add_child(lm)


func _roads(world: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Roads"
	world.add_child(body)
	for road in CityLayout.roads():
		_road_segment(body, world, road["from"], road["to"], float(road["width"]), bool(road["line"]))
	return body


## Auf den Kreuzungen liegt ein glattes Asphaltfeld ohne Markierungen.
func _junction_patches(world: Node3D) -> void:
	for j in CityLayout.junctions().values():
		var c: Vector2 = j["center"]
		var size := 15.0
		if j["kind"] == "roundabout":
			continue
		var vis := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size, 0.02, size)
		vis.mesh = bm
		vis.material_override = _mat(ASPHALT_C)
		vis.position = Vector3(c.x, 0.012, c.y)
		world.add_child(vis)


func _markings(world: Node3D) -> void:
	# Haltelinien.
	for s in CityLayout.stop_lines():
		var p: Vector2 = s["pos"]
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(s["w"]), 0.014, 0.5)
		m.mesh = bm
		m.material_override = _mat(LINE_C)
		m.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["rot"]))),
				Vector3(p.x, 0.025, p.y))
		world.add_child(m)
	# Zebrastreifen: weiße Querbalken.
	for z in CityLayout.zebras():
		var p: Vector2 = z["pos"]
		var w: float = float(z["w"])
		for i in range(6):
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.014, w)
			m.mesh = bm
			m.material_override = _mat(LINE_C)
			m.position = Vector3(p.x - 1.5 + i * 0.6, 0.026, p.y)
			m.rotation_degrees.y = float(z["rot"])
			world.add_child(m)


func _signs(world: Node3D) -> void:
	for s in CityLayout.signs():
		var sign := TrafficSigns.make_sign(String(s["kind"]), s.get("arg", ""))
		if sign == null:
			continue
		sign.position = s["pos"]
		sign.rotation_degrees.y = float(s.get("rot_y", 0.0))
		world.add_child(sign)


func _roundabout(world: Node3D) -> void:
	var j: Dictionary = CityLayout.junctions()["kreis"]
	var c: Vector2 = j["center"]
	var body := StaticBody3D.new()
	body.name = "Roundabout"
	world.add_child(body)
	# Insel: erhöhter Zylinder mit Bordsteinring.
	var isl := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(j["island_r"])
	cyl.bottom_radius = float(j["island_r"])
	cyl.height = 0.16
	cyl.radial_segments = 40
	isl.mesh = cyl
	isl.material_override = _mat(KERB_C, 0.95)
	isl.position = Vector3(c.x, 0.08, c.y)
	world.add_child(isl)
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = float(j["island_r"])
	cs.height = 0.16
	col.shape = cs
	col.position = Vector3(c.x, 0.08, c.y)
	body.add_child(col)
	# Gras in der Mitte.
	var g := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = float(j["island_r"]) - 0.5
	gc.bottom_radius = gc.top_radius
	gc.height = 0.05
	gc.radial_segments = 40
	g.mesh = gc
	g.material_override = _mat(GRASS_C, 1.0)
	g.position = Vector3(c.x, 0.19, c.y)
	world.add_child(g)
	# Fahrbahnring um die Insel.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = float(j["island_r"])
	torus.outer_radius = 16.0
	torus.rings = 4
	torus.ring_segments = 48
	ring.mesh = torus
	ring.material_override = _mat(ASPHALT_C)
	ring.position = Vector3(c.x, 0.005, c.y)
	ring.rotation_degrees.x = 90.0
	world.add_child(ring)
	var rcol := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(20.0, 0.3, 20.0)
	rcol.shape = rbox
	rcol.position = Vector3(c.x, -0.11, c.y)
	body.add_child(rcol)
	# Pfeil-Markierung + Begrenzungslinie des Rings (äußerer Rand).
	var edge := MeshInstance3D.new()
	var et := TorusMesh.new()
	et.inner_radius = 15.85
	et.outer_radius = 16.0
	et.rings = 3
	et.ring_segments = 48
	edge.mesh = et
	edge.material_override = _mat(LINE_C)
	edge.position = Vector3(c.x, 0.03, c.y)
	edge.rotation_degrees.x = 90.0
	world.add_child(edge)


func _traffic_lights(world: Node3D) -> Dictionary:
	var j: Dictionary = CityLayout.junctions()["ampel"]
	var lights := []
	for arm in j["arms"]:
		var enter: Vector2 = arm["enter"]
		var stop: Vector2 = arm["pos"]
		# Ampel steht rechts hinter der Haltelinie in Fahrtrichtung.
		var right := Vector2(-enter.y, enter.x)
		var pos := stop + enter * 4.6 + right * 3.4
		var light := TrafficLight.new()
		light.position = Vector3(pos.x, 0.0, pos.y)
		# Das Kopfstück zeigt dem entgegenkommenden Fahrer entgegen.
		light.rotation_degrees.y = rad_to_deg(atan2(-enter.x, -enter.y))
		world.add_child(light)
		lights.append({"light": light, "arm": String(arm["arm"])})
	return {"junction": j, "lights": lights}


# ---------------------------------------------------------------- Übungsplatz

func _lot(world: Node3D, out: Dictionary) -> void:
	var lot: Dictionary = CityLayout.lot()
	var r: Dictionary = lot["rect"]
	var w := float(r["x1"] - r["x0"])
	var h := float(r["z1"] - r["z0"])
	var cx := (float(r["x0"]) + float(r["x1"])) * 0.5
	var cz := (float(r["z0"]) + float(r["z1"])) * 0.5
	# Platte + Kollision.
	var vis := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.02, h)
	vis.mesh = bm
	vis.material_override = _mat(ASPHALT_LOT)
	vis.position = Vector3(cx, 0.005, cz)
	world.add_child(vis)
	var body := StaticBody3D.new()
	body.name = "Lot"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 0.3, h)
	col.shape = box
	col.position = Vector3(cx, -0.11, cz)
	body.add_child(col)
	world.add_child(body)

	# Zaun um den Platz (Tor offen).
	var fence := _mat(Color(0.35, 0.36, 0.38), 0.8)
	var gate: Dictionary = lot["gate"]
	var edges := [
		[Vector2(r["x0"], r["z0"]), Vector2(r["x1"], r["z0"])],
		[Vector2(r["x0"], r["z1"]), Vector2(r["x1"], r["z1"])],
		[Vector2(r["x0"], r["z0"]), Vector2(r["x0"], r["z1"])],
		[Vector2(r["x1"], r["z0"]), Vector2(r["x1"], r["z1"])],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		# Torlücke an der Südseite (z0-Kante um das Tor).
		var segs := [e]
		if absf(a.y - float(r["z0"])) < 0.1 and absf(b.y - float(r["z0"])) < 0.1:
			var gx: float = gate["pos"].x
			var gw: float = float(gate["w"]) * 0.5
			segs = [[a, Vector2(gx - gw, a.y)], [Vector2(gx + gw, b.y), b]]
		for seg in segs:
			var sa: Vector2 = seg[0]
			var sb: Vector2 = seg[1]
			if sa.distance_to(sb) < 0.5:
				continue
			_fence_span(world, body, sa, sb, fence)
	# Torpfosten.
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.18, 1.4, 0.18)
		post.mesh = pb
		post.material_override = _mat(Color(0.8, 0.2, 0.1), 0.6)
		post.position = Vector3(gate["pos"].x + sx * float(gate["w"]) * 0.5, 0.7, gate["pos"].y)
		world.add_child(post)

	# Längspark-Buchten: weiße Linien + ein stehendes Auto als Referenz.
	for bay in lot["parallel_bays"]:
		var bp: Vector2 = bay["pos"]
		var len: float = float(bay["len"])
		for off in [-len * 0.5, len * 0.5]:
			var m := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(2.2, 0.012, 0.12)
			m.mesh = mb
			m.material_override = _mat(LINE_C)
			m.position = Vector3(bp.x - 1.1, 0.02, bp.y + off)
			world.add_child(m)
		var side := MeshInstance3D.new()
		var sb2 := BoxMesh.new()
		sb2.size = Vector3(0.12, 0.012, len)
		side.mesh = sb2
		side.material_override = _mat(LINE_C)
		side.position = Vector3(bp.x - 2.2, 0.02, bp.y)
		world.add_child(side)
		if bool(bay["occupied"]):
			out["parked_cars"].append(_parked_car(world, Vector3(bp.x, 0.0, bp.y), 0.0, Color(0.7, 0.18, 0.14)))
	# Querpark-Buchten.
	for bay in lot["perp_bays"]:
		var bp: Vector2 = bay["pos"]
		for off in [-1.25, 1.25]:
			var m := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(0.12, 0.012, 4.8)
			m.mesh = mb
			m.material_override = _mat(LINE_C)
			m.position = Vector3(bp.x + off, 0.02, bp.y - 2.4)
			world.add_child(m)
		if bool(bay["occupied"]):
			out["parked_cars"].append(_parked_car(world, Vector3(bp.x, 0.0, bp.y - 2.4), 0.0, Color(0.9, 0.85, 0.6)))
	# Slalom-Pylone.
	for p in lot["slalom"]:
		out["cones"].append(_cone(world, Vector3(p.x, 0.0, p.y)))
	# Bremsbahn-Marker (Abstandsschilder am Rand).
	var bl: Dictionary = lot["brake_lane"]
	var bla: Vector2 = bl["from"]
	var blb: Vector2 = bl["to"]
	var dir := (blb - bla).normalized()
	var total := bla.distance_to(blb)
	for mark in bl["marks"]:
		var d := total - float(mark)
		var p := blb - dir * d
		var s := TrafficSigns.make_sign("marker", str(mark))
		if s:
			s.position = Vector3(p.x, 0.0, p.y + 3.6)
			s.rotation_degrees.y = 180.0
			world.add_child(s)
	# Hügel: schräge Rampe als rotiertes Box-Stück (Kollision wie die Straßen).
	var hill: Dictionary = lot["hill"]
	var hp: Vector2 = hill["pos"]
	var run: float = float(hill["run"])
	var rise: float = float(hill["rise"])
	var hw: float = float(hill["w"])
	var slope := atan2(rise, run)
	var hill_body := StaticBody3D.new()
	hill_body.name = "Hill"
	var hcol := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	var hlen := sqrt(run * run + rise * rise)
	hbox.size = Vector3(hw, 0.3, hlen)
	hcol.shape = hbox
	hcol.transform = Transform3D(Basis(Vector3.RIGHT, -slope), Vector3(hp.x, rise * 0.5 - 0.15, hp.y))
	hill_body.add_child(hcol)
	world.add_child(hill_body)
	var hvis := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(hw, 0.06, hlen)
	hvis.mesh = hbm
	hvis.material_override = _mat(ASPHALT_LOT)
	hvis.transform = Transform3D(Basis(Vector3.RIGHT, -slope), Vector3(hp.x, rise * 0.5 + 0.03, hp.y))
	world.add_child(hvis)
	# Plateau hinter der Rampe (damit man oben anhalten kann).
	var pcol := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(hw, 0.3, 6.0)
	pcol.shape = pbox
	pcol.position = Vector3(hp.x, rise - 0.15, hp.y - run * 0.5 - 3.0)
	hill_body.add_child(pcol)
	var pvis := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(hw, 0.06, 6.0)
	pvis.mesh = pbm
	pvis.material_override = _mat(ASPHALT_LOT)
	pvis.position = Vector3(hp.x, rise + 0.03, hp.y - run * 0.5 - 3.0)
	world.add_child(pvis)
	# Wendekreis: gemalter Ring.
	var circle: Dictionary = lot["circle"]
	var cp: Vector2 = circle["pos"]
	var ringm := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = float(circle["r"]) - 0.12
	torus.outer_radius = float(circle["r"])
	torus.rings = 3
	torus.ring_segments = 40
	ringm.mesh = torus
	ringm.material_override = _mat(LINE_C)
	ringm.position = Vector3(cp.x, 0.02, cp.y)
	ringm.rotation_degrees.x = 90.0
	world.add_child(ringm)


func _fence_span(world: Node3D, body: StaticBody3D, a: Vector2, b: Vector2, mat: Material) -> void:
	var dir := b - a
	var length := dir.length()
	var mid := (a + b) * 0.5
	var yaw := atan2(dir.x, dir.y)
	var f := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.06, 1.0, length)
	f.mesh = fb
	f.material_override = mat
	f.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.5, mid.y))
	world.add_child(f)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.15, 1.0, length)
	col.shape = box
	col.transform = f.transform
	body.add_child(col)


func _cone(world: Node3D, pos: Vector3) -> Node3D:
	var c := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.16
	cone.height = 0.5
	cone.radial_segments = 12
	c.mesh = cone
	c.material_override = _mat(Color(0.95, 0.30, 0.05), 0.8)
	c.position = pos + Vector3(0, 0.25, 0)
	world.add_child(c)
	var band := MeshInstance3D.new()
	var bb := CylinderMesh.new()
	bb.top_radius = 0.09
	bb.bottom_radius = 0.12
	bb.height = 0.1
	bb.radial_segments = 12
	band.mesh = bb
	band.material_override = _mat(Color(1, 1, 1), 0.8)
	band.position = pos + Vector3(0, 0.28, 0)
	world.add_child(band)
	return c


func _parked_car(world: Node3D, pos: Vector3, rot: float, color: Color) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.76, 1.35, 4.1)
	col.shape = box
	col.position = Vector3(0, 0.7, 0)
	body.add_child(col)
	var vis := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(1.74, 0.5, 4.0)
	vis.mesh = vb
	vis.material_override = _mat(color, 0.4, 0.3)
	vis.position = Vector3(0, 0.55, 0)
	body.add_child(vis)
	var cab := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.5, 0.5, 2.1)
	cab.mesh = cb
	cab.material_override = _mat(Color(0.1, 0.13, 0.17), 0.2, 0.6)
	cab.position = Vector3(0, 1.0, -0.2)
	body.add_child(cab)
	world.add_child(body)
	return body


# ---------------------------------------------------------------- Umgebung

func _buildings(world: Node3D) -> void:
	# Häuserzeilen an Haupt- und Schulstraße — Kulisse, kein Fahrzeugkontakt.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var fronts := [
		{"from": Vector2(-170, -47), "to": Vector2(-15, -47), "dir": 1},
		{"from": Vector2(15, -47), "to": Vector2(85, -47), "dir": 1},
		{"from": Vector2(118, -47), "to": Vector2(160, -47), "dir": 1},
		{"from": Vector2(-130, -73), "to": Vector2(-15, -73), "dir": -1},
		{"from": Vector2(-120, -167), "to": Vector2(-20, -167), "dir": 1},
		{"from": Vector2(20, -167), "to": Vector2(85, -167), "dir": 1},
		{"from": Vector2(-120, -193), "to": Vector2(-20, -193), "dir": -1},
		{"from": Vector2(20, -193), "to": Vector2(85, -193), "dir": -1},
		{"from": Vector2(-86, -230), "to": Vector2(-86, -150), "dir": 1},
		{"from": Vector2(114, -230), "to": Vector2(114, -150), "dir": -1},
	]
	var palette := [Color(0.82, 0.78, 0.68), Color(0.75, 0.62, 0.50), Color(0.68, 0.72, 0.75), Color(0.80, 0.72, 0.62)]
	for front in fronts:
		var a: Vector2 = front["from"]
		var b: Vector2 = front["to"]
		var dir := (b - a)
		var length := dir.length()
		dir = dir.normalized()
		var cursor := 0.0
		while cursor < length - 8.0:
			var w := rng.randf_range(8.0, 14.0)
			var d := rng.randf_range(9.0, 13.0)
			var hgt := rng.randf_range(6.0, 16.0)
			var p := a + dir * (cursor + w * 0.5)
			var col_mat: Color = palette[rng.randi_range(0, palette.size() - 1)]
			var house := MeshInstance3D.new()
			var hb := BoxMesh.new()
			hb.size = Vector3(w - 1.2, hgt, d)
			house.mesh = hb
			house.material_override = _mat(col_mat, 0.9)
			var yaw := atan2(dir.x, dir.y)
			house.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, hgt * 0.5, p.y))
			world.add_child(house)
			# Kollision: das Haus ist ein Hindernis, wenn einer vom Gehweg abkommt.
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(w - 1.2, hgt, d)
			col.shape = box
			body.transform = house.transform
			body.add_child(col)
			world.add_child(body)
			# Fensterband: ein einfacher heller Streifen je Etage.
			for fl in range(1, int(hgt / 3.0)):
				var win := MeshInstance3D.new()
				var wb := BoxMesh.new()
				wb.size = Vector3(w - 2.4, 0.9, 0.04)
				win.mesh = wb
				win.material_override = _mat(Color(0.20, 0.26, 0.33), 0.25, 0.5)
				var out_dir := Vector2(dir.y, -dir.x) * float(front["dir"])
				win.transform = Transform3D(Basis(Vector3.UP, yaw),
						Vector3(p.x + out_dir.x * (d * 0.5 + 0.03), fl * 3.0 + 0.8, p.y + out_dir.y * (d * 0.5 + 0.03)))
				world.add_child(win)
			cursor += w + rng.randf_range(2.0, 5.0)


func _trees(world: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Allee entlang des Rings + ein paar Bäume am Platz.
	var spots := []
	for i in range(10):
		spots.append(Vector2(-235 + i * 0.0, -215 + i * 24))
	for i in range(6):
		spots.append(Vector2(-40 + i * 30, 128))
	for i in range(5):
		spots.append(Vector2(120 + i * 22, 40))
	var trunk_m := _mat(Color(0.35, 0.24, 0.14), 1.0)
	var leaf_m := _mat(Color(0.16, 0.40, 0.16), 1.0)
	for p in spots:
		var trunk := MeshInstance3D.new()
		var tb := CylinderMesh.new()
		tb.top_radius = 0.14
		tb.bottom_radius = 0.2
		tb.height = 2.6
		trunk.mesh = tb
		trunk.material_override = trunk_m
		trunk.position = Vector3(p.x, 1.3, p.y)
		world.add_child(trunk)
		var crown := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = rng.randf_range(1.6, 2.4)
		sph.height = sph.radius * 2.0
		crown.mesh = sph
		crown.material_override = leaf_m
		crown.position = Vector3(p.x, 3.4, p.y)
		world.add_child(crown)
