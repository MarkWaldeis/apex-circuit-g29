extends RefCounted
## Reines Datenmodell der Fahrschul-Stadt: Straßen, Kreuzungen, Schilder,
## Übungsplatz. city_builder.gd baut daraus die Welt, school_surfaces.gd
## sampelt daraus den Untergrund und school_instructor.gd liest daraus
## Tempolimits, Haltelinien und Rechts-vor-Links.
##
## Koordinaten: Godot 3D (x, z), y liegt auf Straßenhöhe 0. Straßen laufen
## entlang ihrer Polygonzüge; `dir` = Fahrtrichtung für Einbahnstraßen und
## Haltelinien (der Eintrag in points ist die Fahrbahn-Mitte).

const EYE := 0.0   ## Straßenhöhe

## Straßennetz. Jedes Segment: from/to (Vector2), limit (km/h),
## width (Fahrbahn), oneway (1 = nur in from→to-Richtung, 0 = beidseitig),
## name (für den Fahrlehrer), lanes (Mittellinie ja/nein).
static func roads() -> Array:
	return [
		{"name": "Hauptstraße", "from": Vector2(-196, -60), "to": Vector2(172, -60), "limit": 50, "width": 7.0, "oneway": 0, "line": true},
		{"name": "Hauptstraße Ost", "from": Vector2(212, -60), "to": Vector2(196, -60), "limit": 50, "width": 7.0, "oneway": 0, "line": true},
		{"name": "Schulstraße", "from": Vector2(-140, -180), "to": Vector2(140, -180), "limit": 30, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Einbahnstraße", "from": Vector2(100, -120), "to": Vector2(-100, -120), "limit": 30, "width": 5.5, "oneway": 1, "line": false},
		{"name": "Weststraße", "from": Vector2(-100, -240), "to": Vector2(-100, 128), "limit": 50, "width": 6.5, "oneway": 0, "line": true},
		{"name": "Oststraße", "from": Vector2(100, -240), "to": Vector2(100, 140), "limit": 50, "width": 6.5, "oneway": 0, "line": true},
		# Ring um den Stadtkern: sauberes Rechteck, Tempo 100 außerorts.
		{"name": "Ring Nord", "from": Vector2(-100, -240), "to": Vector2(-240, -240), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring West", "from": Vector2(-240, -240), "to": Vector2(-240, 140), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Süd", "from": Vector2(-240, 140), "to": Vector2(240, 140), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Ost", "from": Vector2(240, 140), "to": Vector2(240, -40), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Ost", "from": Vector2(240, -40), "to": Vector2(216, -20), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		# Zufahrt zum Übungsplatz von der Hauptstraße.
		{"name": "Übungsplatz-Zufahrt", "from": Vector2(0, -60), "to": Vector2(0, 40), "limit": 30, "width": 6.0, "oneway": 0, "line": false},
		# Kreisverkehr-Arme (Einfahrt in den Kreis bei (200,-60)).
		{"name": "Kreisverkehr Westarm", "from": Vector2(186, -60), "to": Vector2(212, -60), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Nordarm", "from": Vector2(200, -86), "to": Vector2(200, -74), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Südarm", "from": Vector2(200, -46), "to": Vector2(200, -34), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Nordstraße", "from": Vector2(200, -140), "to": Vector2(200, -86), "limit": 50, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Kreisverkehr Südstraße", "from": Vector2(200, -34), "to": Vector2(216, -20), "limit": 50, "width": 6.0, "oneway": 0, "line": true},
	]


## Kreuzungen: Haltelinien, Schilder, Ampel-Steuerung.
## `kind`: "light" (Ampel), "stop", "yield", "rbl" (rechts vor links),
##        "priority" (Vorfahrtstraße), "roundabout".
## `arm`/`to`: Weltkoordinaten des Haltelinie-Mittelpunkts bzw. Blickrichtung.
static func junctions() -> Dictionary:
	return {
		"ampel": {
			"kind": "light",
			"center": Vector2(-100, -60),
			# Vier Haltelinien: Achse "a" = Hauptstraße (Ost/West),
			# Achse "b" = Weststraße (Nord/Süd).
			"arms": [
				{"arm": "a", "pos": Vector2(-92.6, -60), "enter": Vector2(1, 0), "name": "Hauptstraße Ost"},
				{"arm": "a", "pos": Vector2(-107.4, -60), "enter": Vector2(-1, 0), "name": "Hauptstraße West"},
				{"arm": "b", "pos": Vector2(-100, -52.6), "enter": Vector2(0, -1), "name": "Weststraße Nord"},
				{"arm": "b", "pos": Vector2(-100, -67.4), "enter": Vector2(0, 1), "name": "Weststraße Süd"},
			],
		},
		"stop_kreuzung": {
			"kind": "stop",
			"center": Vector2(100, -60),
			"arms": [
				{"pos": Vector2(92.4, -60), "enter": Vector2(1, 0)},
				{"pos": Vector2(107.6, -60), "enter": Vector2(-1, 0)},
			],
		},
		"rbl_west": {
			"kind": "rbl",
			"center": Vector2(-100, -180),
			"arms": [
				{"pos": Vector2(-95, -176), "enter": Vector2(-0.7, 0.7)},
				{"pos": Vector2(-104, -184), "enter": Vector2(0.7, -0.7)},
			],
		},
		"yield_ost": {
			"kind": "yield",
			"center": Vector2(100, -180),
			"arms": [
				{"pos": Vector2(95, -176), "enter": Vector2(-0.7, 0.7)},
				{"pos": Vector2(104, -184), "enter": Vector2(0.7, -0.7)},
			],
		},
		"kreis": {
			"kind": "roundabout",
			"center": Vector2(200, -60),
			"island_r": 7.0,
			"arms": [
				{"pos": Vector2(184.5, -60), "enter": Vector2(1, 0)},
				{"pos": Vector2(200, -88.5), "enter": Vector2(0, 1)},
				{"pos": Vector2(200, -31.5), "enter": Vector2(0, -1)},
			],
		},
	}


## Verkehrszeichen: kind kommt aus traffic_signs.make_sign(),
## pos = Mast-Fußpunkt, rot_y = Grad um Y (0 = Schildfläche zeigt +Z,
## also zu Verkehr aus -Z-Richtung), arg = Zahl oder Text.
static func signs() -> Array:
	return [
		# Ampelkreuzung Hauptstraße × Weststraße — Ampeln baut junction_lights,
		# hier nur die Schilder der Nebenarme (keine, Vorfahrt über Ampel).
		# Stopschild-Kreuzung Oststraße × Hauptstraße (StoVo: Schild vor der Linie).
		{"kind": "stop", "pos": Vector3(93.0, 0, -56.6), "rot_y": 180.0},
		{"kind": "stop", "pos": Vector3(107.0, 0, -63.4), "rot_y": 0.0},
		# Rechts vor links: Schild 102 am Knoten Schulstraße/Weststraße.
		{"kind": "rbl", "pos": Vector3(-95.6, 0, -173.0), "rot_y": 225.0},
		{"kind": "rbl", "pos": Vector3(-104.4, 0, -187.0), "rot_y": 45.0},
		# Vorfahrt gewähren Schulstraße/Oststraße.
		{"kind": "yield", "pos": Vector3(95.6, 0, -173.0), "rot_y": 225.0},
		{"kind": "yield", "pos": Vector3(104.4, 0, -187.0), "rot_y": 45.0},
		# Einbahnstraße: blaues Pfeilschild am Anfang, Durchfahrt verboten am Ende.
		{"kind": "one_way", "pos": Vector3(96.0, 0, -116.0), "rot_y": 90.0},
		{"kind": "one_way", "pos": Vector3(96.0, 0, -124.0), "rot_y": 90.0},
		{"kind": "no_entry", "pos": Vector3(-96.0, 0, -116.0), "rot_y": -90.0},
		{"kind": "no_entry", "pos": Vector3(-96.0, 0, -124.0), "rot_y": -90.0},
		# Tempolimits: 30 auf der Schulstraße, 50 auf den Nebenstraßen,
		# 100 auf dem Ring (und Ende-Schilder beim Wiedereinfahren).
		{"kind": "limit", "arg": "30", "pos": Vector3(-134, 0, -176.0), "rot_y": 90.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(134, 0, -184.0), "rot_y": -90.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(96.5, 0, -116.5), "rot_y": 90.0},
		{"kind": "limit_end", "pos": Vector3(-96.5, 0, -127.5), "rot_y": -90.0},
		{"kind": "limit", "arg": "50", "pos": Vector3(-96.5, 0, -70.0), "rot_y": -90.0},
		{"kind": "limit", "arg": "50", "pos": Vector3(103.5, 0, -50.0), "rot_y": 90.0},
		{"kind": "limit", "arg": "100", "pos": Vector3(-104.5, 0, -234.0), "rot_y": 135.0},
		{"kind": "limit", "arg": "100", "pos": Vector3(-104.5, 0, 132.0), "rot_y": 45.0},
		{"kind": "limit_end", "pos": Vector3(-196.5, 0, -56.0), "rot_y": 90.0},
		# Kreisverkehr-Schilder vor den drei Einfahrten.
		{"kind": "roundabout", "pos": Vector3(184.0, 0, -56.0), "rot_y": 90.0},
		{"kind": "roundabout", "pos": Vector3(196.0, 0, -88.0), "rot_y": 0.0},
		{"kind": "roundabout", "pos": Vector3(196.0, 0, -32.0), "rot_y": 180.0},
		# Zebrastreifen Hauptstraße bei x = -40.
		{"kind": "zebra", "pos": Vector3(-40.0, 0, -52.5), "rot_y": 180.0},
		{"kind": "zebra", "pos": Vector3(-40.0, 0, -67.5), "rot_y": 0.0},
		# Parkplatz-Schild am Übungsplatz-Eingang.
		{"kind": "parking", "pos": Vector3(4.0, 0, 36.0), "rot_y": 0.0},
		{"kind": "board", "arg": "Fahrschul-Übungsplatz", "pos": Vector3(-4.0, 0, 36.0), "rot_y": 0.0},
		# Hinweisschilder auf dem Platz.
		{"kind": "board", "arg": "Slalom", "pos": Vector3(-46, 0, 58), "rot_y": 180.0},
		{"kind": "board", "arg": "Bremsen", "pos": Vector3(-46, 0, 50), "rot_y": 180.0},
		{"kind": "board", "arg": "Berganfahren", "pos": Vector3(-78, 0, 82), "rot_y": 135.0},
	]


## Haltelinien/Bodenmarkierungen (weiße Querbalken auf der Fahrbahn).
static func stop_lines() -> Array:
	var out: Array = []
	# Ampelkreuzung: vier Haltelinien.
	out.append({"pos": Vector2(-92.6, -60), "rot": 0.0, "w": 3.4})
	out.append({"pos": Vector2(-107.4, -60), "rot": 0.0, "w": 3.4})
	out.append({"pos": Vector2(-100, -52.6), "rot": 90.0, "w": 3.2})
	out.append({"pos": Vector2(-100, -67.4), "rot": 90.0, "w": 3.2})
	# Stop-Kreuzung.
	out.append({"pos": Vector2(92.4, -60), "rot": 0.0, "w": 3.2})
	out.append({"pos": Vector2(107.6, -60), "rot": 0.0, "w": 3.2})
	# Kreisverkehr: Haifischzähne-Ersatz als schmale Linie.
	out.append({"pos": Vector2(184.5, -60), "rot": 0.0, "w": 2.6})
	out.append({"pos": Vector2(200, -88.5), "rot": 90.0, "w": 2.6})
	out.append({"pos": Vector2(200, -31.5), "rot": 90.0, "w": 2.6})
	return out


## Zebrastreifen (Querstreifen über die Fahrbahn).
static func zebras() -> Array:
	return [{"pos": Vector2(-40, -60), "rot": 0.0, "w": 6.8}]


## Übungsplatz: Grundstück, Zaun, Elemente.
static func lot() -> Dictionary:
	return {
		# Platzfläche (Asphalt) — z Klapp in z-Richtung.
		"rect": {"x0": -80.0, "x1": 80.0, "z0": 42.0, "z1": 115.0},
		# Zaun läuft um den Platz, Tor bei (0,42) von der Zufahrt.
		"gate": {"pos": Vector2(0, 42), "w": 8.0},
		# Längsparken: zwei Buchten an der Ostkante, eine mit Übungs-Pkw belegt.
		"parallel_bays": [
			{"pos": Vector2(72, 62), "rot": 0.0, "len": 6.2, "occupied": false},
			{"pos": Vector2(72, 70), "rot": 0.0, "len": 6.2, "occupied": true},
			{"pos": Vector2(72, 78), "rot": 0.0, "len": 6.2, "occupied": false},
		],
		# Querparken: vier Buchten an der Südkante.
		"perp_bays": [
			{"pos": Vector2(-30, 110), "rot": 0.0, "occupied": false},
			{"pos": Vector2(-25, 110), "rot": 0.0, "occupied": false},
			{"pos": Vector2(-20, 110), "rot": 0.0, "occupied": true},
			{"pos": Vector2(-15, 110), "rot": 0.0, "occupied": false},
		],
		# Slalom: Pylone im Zickzack.
		"slalom": [
			Vector2(-45, 62), Vector2(-30, 66), Vector2(-15, 62), Vector2(0, 66),
			Vector2(15, 62), Vector2(30, 66),
		],
		# Bremsbahn: Anfahrt aus dem Westen, Marker alle 10 m.
		"brake_lane": {"from": Vector2(-45, 46), "to": Vector2(60, 46), "marks": [30, 40, 50]},
		# Hügel für Berganfahren: Rampe im Nordwesten.
		"hill": {"pos": Vector2(-66, 66), "rot": 90.0, "run": 14.0, "rise": 2.2, "w": 7.0},
		# Kreis zum Üben von Wendefahrten (markierter Kreis).
		"circle": {"pos": Vector2(30, 88), "r": 11.0},
	}


## Fußgängerzonen usw.: wo der Fahrlehrer "Neben der Fahrbahn" meldet.
## bounds des Spielfelds (über die Karte hinaus = aus der Welt fallen).
static func bounds() -> Rect2:
	return Rect2(-260, -260, 520, 420)


## Spawn des Fahrschulautos: am Eingang des Übungsplatzes, Blick nach Norden
## (auf die Zufahrt Richtung Hauptstraße).
static func spawn() -> Transform3D:
	var basis := Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	return Transform3D(basis, Vector3(0, 0.4, 60.0))


## Wo ein "Fahrzeug zurücksetzen" landet.
static func reset_spots() -> Array:
	return [
		{"pos": Vector2(0, 60), "rot": 180.0},
		{"pos": Vector2(-40, -60), "rot": 90.0},
	]
