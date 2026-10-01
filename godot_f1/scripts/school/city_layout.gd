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
		{"name": "Hauptstraße", "from": Vector2(-240, -60), "to": Vector2(172, -60), "limit": 50, "width": 7.0, "oneway": 0, "line": true},

		{"name": "Schulstraße", "from": Vector2(-240, -180), "to": Vector2(240, -180), "limit": 30, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Einbahnstraße", "from": Vector2(100, -120), "to": Vector2(-100, -120), "limit": 30, "width": 5.5, "oneway": 1, "line": false},
		{"name": "Weststraße", "from": Vector2(-100, -240), "to": Vector2(-100, 140), "limit": 50, "width": 6.5, "oneway": 0, "line": true},
		{"name": "Oststraße", "from": Vector2(100, -240), "to": Vector2(100, 140), "limit": 50, "width": 6.5, "oneway": 0, "line": true},
		# Ring um den Stadtkern: sauberes Rechteck, Tempo 100 außerorts.
		{"name": "Ring Nord", "from": Vector2(-100, -240), "to": Vector2(-240, -240), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Nord", "from": Vector2(240, -240), "to": Vector2(-100, -240), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring West", "from": Vector2(-240, -240), "to": Vector2(-240, 140), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Süd", "from": Vector2(-240, 140), "to": Vector2(240, 140), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Ost", "from": Vector2(240, 140), "to": Vector2(240, -60), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Ost", "from": Vector2(240, -60), "to": Vector2(216, -20), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		{"name": "Ring Ost", "from": Vector2(240, -60), "to": Vector2(240, -240), "limit": 100, "width": 6.0, "oneway": 0, "line": true},
		# Zufahrt zum Übungsplatz von der Hauptstraße.
		{"name": "Übungsplatz-Zufahrt", "from": Vector2(0, -60), "to": Vector2(0, 40), "limit": 30, "width": 6.0, "oneway": 0, "line": false},
		# Kreisverkehr-Arme (Einfahrt in den Kreis bei (200,-60)).
		{"name": "Kreisverkehr Westarm", "from": Vector2(172, -60), "to": Vector2(184, -60), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Ostarm", "from": Vector2(216, -60), "to": Vector2(240, -60), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Nordarm", "from": Vector2(200, -86), "to": Vector2(200, -74), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Südarm", "from": Vector2(200, -46), "to": Vector2(200, -34), "limit": 30, "width": 5.5, "oneway": 0, "line": false},
		{"name": "Kreisverkehr Nordstraße", "from": Vector2(200, -240), "to": Vector2(200, -86), "limit": 50, "width": 6.0, "oneway": 0, "line": true},
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
				{"arm": "a", "pos": Vector2(-92.6, -60), "enter": Vector2(-1, 0), "name": "Hauptstraße Ost"},
				{"arm": "a", "pos": Vector2(-107.4, -60), "enter": Vector2(1, 0), "name": "Hauptstraße West"},
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
				{"pos": Vector2(-100, -174), "enter": Vector2(0, -1)},
				{"pos": Vector2(-100, -186), "enter": Vector2(0, 1)},
				{"pos": Vector2(-94, -180), "enter": Vector2(-1, 0)},
				{"pos": Vector2(-106, -180), "enter": Vector2(1, 0)},
			],
		},
		"zufahrt": {
			"kind": "yield",
			"center": Vector2(0, -60),
			# Einfahrt auf die Hauptstraße: Vorfahrt gewähren. Die beiden
			# Hauptstraßen-Arme sind freie Fahrbahn (kein Halt, aber fuer die
			# Vorfahrt-Auswertung des Querverkehrs noetig).
			"arms": [
				{"pos": Vector2(0, -57), "enter": Vector2(0, -1), "yield": true},
				{"pos": Vector2(-11, -58.2), "enter": Vector2(1, 0)},
				{"pos": Vector2(11, -61.8), "enter": Vector2(-1, 0)},
			],
		},
		"yield_ost": {
			"kind": "yield",
			"center": Vector2(100, -180),
			# Schulstraße gibt Vorfahrt, Oststraße (50) ist die Vorfahrtstraße.
			"arms": [
				{"pos": Vector2(94, -180), "enter": Vector2(1, 0), "yield": true},
				{"pos": Vector2(106, -180), "enter": Vector2(-1, 0), "yield": true},
				{"pos": Vector2(100, -174), "enter": Vector2(0, -1)},
				{"pos": Vector2(100, -186), "enter": Vector2(0, 1)},
			],
		},
		# Vier T-Einfahrten auf den 100er-Ring: die mündende Straße
		# gewährt Vorfahrt, der Ring fließt durch.
		"ring_west_haupt": {
			"kind": "yield",
			"center": Vector2(-240, -60),
			"arms": [
				{"pos": Vector2(-232, -61.8), "enter": Vector2(-1, 0), "yield": true},
				{"pos": Vector2(-240, -66), "enter": Vector2(0, 1)},
				{"pos": Vector2(-240, -54), "enter": Vector2(0, -1)},
			],
		},
		"ring_west_schul": {
			"kind": "yield",
			"center": Vector2(-240, -180),
			"arms": [
				{"pos": Vector2(-232, -181.8), "enter": Vector2(-1, 0), "yield": true},
				{"pos": Vector2(-240, -186), "enter": Vector2(0, 1)},
				{"pos": Vector2(-240, -174), "enter": Vector2(0, -1)},
			],
		},
		"ring_ost_schul": {
			"kind": "yield",
			"center": Vector2(240, -180),
			"arms": [
				{"pos": Vector2(232, -178.2), "enter": Vector2(1, 0), "yield": true},
				{"pos": Vector2(240, -186), "enter": Vector2(0, 1)},
				{"pos": Vector2(240, -174), "enter": Vector2(0, -1)},
			],
		},
		"ring_nord_kreis": {
			"kind": "yield",
			"center": Vector2(200, -240),
			"arms": [
				{"pos": Vector2(201.8, -232), "enter": Vector2(0, -1), "yield": true},
				{"pos": Vector2(194, -240), "enter": Vector2(1, 0)},
				{"pos": Vector2(206, -240), "enter": Vector2(-1, 0)},
			],
		},
		# T-Knoten ohne Licht/Schild: Rechts vor links gilt. Sie werden
		# als junction gefuehrt, damit Haltelinie und Abbiege-Blinker
		# ausgewertet werden koennen.
		"einbahn_ost": {
			"kind": "rbl",
			"center": Vector2(100, -120),
			"arms": [
				{"pos": Vector2(100, -114), "enter": Vector2(0, -1)},
				{"pos": Vector2(100, -126), "enter": Vector2(0, 1)},
			],
		},
		"einbahn_west": {
			"kind": "rbl",
			"center": Vector2(-100, -120),
			"arms": [
				{"pos": Vector2(-100, -114), "enter": Vector2(0, -1)},
				{"pos": Vector2(-100, -126), "enter": Vector2(0, 1)},
				{"pos": Vector2(-94, -120), "enter": Vector2(-1, 0)},
			],
		},
		"ring_west_nord": {
			"kind": "rbl",
			"center": Vector2(-100, -240),
			"arms": [
				{"pos": Vector2(-100, -234), "enter": Vector2(0, -1)},
				{"pos": Vector2(-106, -240), "enter": Vector2(1, 0)},
				{"pos": Vector2(-94, -240), "enter": Vector2(-1, 0)},
			],
		},
		"ring_ost_nord": {
			"kind": "rbl",
			"center": Vector2(100, -240),
			"arms": [
				{"pos": Vector2(100, -234), "enter": Vector2(0, -1)},
				{"pos": Vector2(94, -240), "enter": Vector2(1, 0)},
				{"pos": Vector2(106, -240), "enter": Vector2(-1, 0)},
			],
		},
		"ring_west_sued": {
			"kind": "rbl",
			"center": Vector2(-100, 140),
			"arms": [
				{"pos": Vector2(-100, 134), "enter": Vector2(0, 1)},
				{"pos": Vector2(-106, 140), "enter": Vector2(1, 0)},
				{"pos": Vector2(-94, 140), "enter": Vector2(-1, 0)},
			],
		},
		"ring_ost_sued": {
			"kind": "rbl",
			"center": Vector2(100, 140),
			"arms": [
				{"pos": Vector2(100, 134), "enter": Vector2(0, 1)},
				{"pos": Vector2(94, 140), "enter": Vector2(1, 0)},
				{"pos": Vector2(106, 140), "enter": Vector2(-1, 0)},
			],
		},
		"kreis": {
			"kind": "roundabout",
			"center": Vector2(200, -60),
			"island_r": 7.0,
			"arms": [
				{"pos": Vector2(184.5, -60), "enter": Vector2(1, 0)},
				{"pos": Vector2(215.5, -60), "enter": Vector2(-1, 0)},
				{"pos": Vector2(200, -76.5), "enter": Vector2(0, 1)},
				{"pos": Vector2(200, -44.3), "enter": Vector2(0, -1)},
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
		{"kind": "stop", "pos": Vector3(93.0, 0, -56.6), "rot_y": 270.0},
		{"kind": "stop", "pos": Vector3(107.0, 0, -63.4), "rot_y": 90.0},
		# Rechts vor links: Schild 102 an allen vier Zufahrten des Knotens
		# Schulstraße/Weststraße (jeweils rechter Fahrbahnrand, Sichtseite
		# zum ankommenden Verkehr).
		{"kind": "rbl", "pos": Vector3(-103.5, 0, -183.8), "rot_y": 180.0},
		{"kind": "rbl", "pos": Vector3(-96.5, 0, -171.5), "rot_y": 0.0},
		{"kind": "rbl", "pos": Vector3(-94.0, 0, -183.8), "rot_y": 90.0},
		{"kind": "rbl", "pos": Vector3(-108.0, 0, -176.2), "rot_y": 270.0},
		# Vorfahrt gewähren Schulstraße/Oststraße.
		{"kind": "yield", "pos": Vector3(94.0, 0, -176.2), "rot_y": 270.0},
		{"kind": "yield", "pos": Vector3(106.0, 0, -183.8), "rot_y": 90.0},
		# Einbahnstraße: blaues Pfeilschild am Anfang, Durchfahrt verboten am Ende.
		{"kind": "one_way", "pos": Vector3(96.0, 0, -116.0), "rot_y": 90.0},
		{"kind": "one_way", "pos": Vector3(96.0, 0, -124.0), "rot_y": 90.0},
		{"kind": "no_entry", "pos": Vector3(-96.0, 0, -116.0), "rot_y": -90.0},
		{"kind": "no_entry", "pos": Vector3(-96.0, 0, -124.0), "rot_y": -90.0},
		# Tempolimits: 30 auf der Schulstraße, 50 auf den Nebenstraßen,
		# 100 auf dem Ring (und Ende-Schilder beim Wiedereinfahren).
		{"kind": "limit", "arg": "30", "pos": Vector3(-134, 0, -176.0), "rot_y": 270.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(134, 0, -184.0), "rot_y": 90.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(96.5, 0, -116.5), "rot_y": 90.0},
		{"kind": "limit_end", "pos": Vector3(-96.5, 0, -127.5), "rot_y": 270.0},
		{"kind": "limit", "arg": "50", "pos": Vector3(-96.5, 0, -70.0), "rot_y": 0.0},
		{"kind": "limit", "arg": "50", "pos": Vector3(96.5, 0, -50.0), "rot_y": 180.0},
		{"kind": "limit", "arg": "100", "pos": Vector3(-96.0, 0, -233.0), "rot_y": 0.0},
		{"kind": "limit", "arg": "100", "pos": Vector3(-104.5, 0, 132.0), "rot_y": 180.0},
		{"kind": "limit_end", "pos": Vector3(-226.0, 0, -56.0), "rot_y": 270.0},
		# Vorfahrt gewähren an den vier neuen Ring-Einfahrten.
		{"kind": "yield", "pos": Vector3(-230.0, 0, -64.0), "rot_y": 90.0},
		{"kind": "yield", "pos": Vector3(-230.0, 0, -184.5), "rot_y": 90.0},
		{"kind": "yield", "pos": Vector3(230.0, 0, -175.5), "rot_y": 270.0},
		{"kind": "yield", "pos": Vector3(204.5, 0, -230.0), "rot_y": 0.0},
		# Kreisverkehr-Schilder vor den drei Einfahrten.
		{"kind": "roundabout", "pos": Vector3(184.0, 0, -56.0), "rot_y": 270.0},
		{"kind": "roundabout", "pos": Vector3(196.0, 0, -88.0), "rot_y": 180.0},
		{"kind": "roundabout", "pos": Vector3(203.5, 0, -32.0), "rot_y": 0.0},
		{"kind": "roundabout", "pos": Vector3(216.0, 0, -63.5), "rot_y": 90.0},
		# Baustelle Ring Sued: Warnschilder + 30er + Ende-Schilder.
		{"kind": "baustelle", "pos": Vector3(-58.0, 0, 143.4), "rot_y": 270.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(-42.0, 0, 143.4), "rot_y": 270.0},
		{"kind": "limit_end", "pos": Vector3(26.0, 0, 143.4), "rot_y": 270.0},
		{"kind": "baustelle", "pos": Vector3(32.0, 0, 136.6), "rot_y": 90.0},
		{"kind": "limit", "arg": "30", "pos": Vector3(24.0, 0, 136.6), "rot_y": 90.0},
		{"kind": "limit_end", "pos": Vector3(-46.0, 0, 136.6), "rot_y": 90.0},
		# Auffahrt-Hinweis auf der Oststrasse Richtung Ring Nord.
		{"kind": "board", "arg": "Auffahrt — Gas geben", "pos": Vector3(103.5, 0, -212.0), "rot_y": 0.0},
		# Vorfahrt achten bei der Einfahrt vom Übungsplatz auf die Hauptstraße.
		{"kind": "yield", "pos": Vector3(4.4, 0, -57.0), "rot_y": 0.0},
		# Zeichen 306 Vorfahrtstraße: die Hauptstraße hat vor der Zufahrt
		# Vorfahrt, die Oststraße vor der Schulstraße.
		{"kind": "priority", "pos": Vector3(-10.0, 0, -56.5), "rot_y": 270.0},
		{"kind": "priority", "pos": Vector3(10.0, 0, -63.5), "rot_y": 90.0},
		{"kind": "priority", "pos": Vector3(96.5, 0, -174.0), "rot_y": 180.0},
		{"kind": "priority", "pos": Vector3(103.5, 0, -186.0), "rot_y": 0.0},
		# Zebrastreifen Hauptstraße bei x = -40.
		{"kind": "zebra", "pos": Vector3(-40.0, 0, -52.5), "rot_y": 270.0},
		{"kind": "zebra", "pos": Vector3(-40.0, 0, -67.5), "rot_y": 90.0},
		# Zebrastreifen Weststraße bei z = -150.
		{"kind": "zebra", "pos": Vector3(-96.3, 0, -143.0), "rot_y": 0.0},
		{"kind": "zebra", "pos": Vector3(-103.7, 0, -157.0), "rot_y": 180.0},
		# Parkplatz-Schild am Übungsplatz-Eingang.
		{"kind": "parking", "pos": Vector3(4.0, 0, 36.0), "rot_y": 180.0},
		{"kind": "board", "arg": "Fahrschul-Übungsplatz", "pos": Vector3(-4.0, 0, 36.0), "rot_y": 180.0},
		# Hinweisschilder auf dem Platz.
		{"kind": "board", "arg": "Slalom", "pos": Vector3(-46, 0, 58), "rot_y": 180.0},
		{"kind": "board", "arg": "Bremsen", "pos": Vector3(-46, 0, 50), "rot_y": 180.0},
		{"kind": "board", "arg": "Berganfahren", "pos": Vector3(-78, 0, 82), "rot_y": 135.0},
		# Engstelle auf der Kreisverkehr-Nordstraße: wer die parkenden
		# Autos auf seiner Seite hat (Nordfahrtrichtung), wartet auf den
		# Gegenverkehr (208); die freie Seite darf zuerst (308).
		{"kind": "engst_wait", "pos": Vector3(203.6, 0, -100.0), "rot_y": 0.0},
		{"kind": "engst_prio", "pos": Vector3(196.4, 0, -119.0), "rot_y": 180.0},
	]


## Haltelinien/Bodenmarkierungen (weiße Querbalken auf der Fahrbahn).
static func stop_lines() -> Array:
	var out: Array = []
	# Ampelkreuzung: vier Haltelinien. `w` laeuft in lokalem X, `rot`
	# dreht es: Straße entlang x -> rot 90 (Linie quer zur Fahrtrichtung),
	# Straße entlang z -> rot 0.
	out.append({"pos": Vector2(-92.6, -60), "rot": 90.0, "w": 3.4})
	out.append({"pos": Vector2(-107.4, -60), "rot": 90.0, "w": 3.4})
	out.append({"pos": Vector2(-100, -52.6), "rot": 0.0, "w": 3.2})
	out.append({"pos": Vector2(-100, -67.4), "rot": 0.0, "w": 3.2})
	# Stop-Kreuzung.
	out.append({"pos": Vector2(92.4, -60), "rot": 90.0, "w": 3.2})
	out.append({"pos": Vector2(107.6, -60), "rot": 90.0, "w": 3.2})
	# Kreisverkehr: Haifischzähne-Ersatz als schmale Linie (an den
	# Einfahrtsarmen, knapp vor der Ringkante).
	out.append({"pos": Vector2(184.5, -60), "rot": 90.0, "w": 2.6})
	out.append({"pos": Vector2(215.5, -60), "rot": 90.0, "w": 2.6})
	out.append({"pos": Vector2(200, -76.5), "rot": 0.0, "w": 2.6})
	out.append({"pos": Vector2(200, -44.3), "rot": 0.0, "w": 2.6})
	# Ring-Einfahrten (yield): Haltelinien auf den mündenden Armen.
	out.append({"pos": Vector2(-232, -61.8), "rot": 90.0, "w": 3.4})
	out.append({"pos": Vector2(-232, -181.8), "rot": 90.0, "w": 3.0})
	out.append({"pos": Vector2(232, -178.2), "rot": 90.0, "w": 3.0})
	out.append({"pos": Vector2(201.8, -232), "rot": 0.0, "w": 3.0})
	return out


## Zebrastreifen (Querstreifen über die Fahrbahn).
static func zebras() -> Array:
	return [
		{"pos": Vector2(-40, -60), "rot": 90.0, "w": 6.8},
		{"pos": Vector2(-100, -150), "rot": 0.0, "w": 6.0},
	]


## Strassenlaternen: Standorte am Gehwegrand mit Richtung zur Fahrbahn.
## {pos} auf dem Gehweg, {arm} Richtungsvektor des Leuchtenarms.
static func lamps() -> Array:
	var out: Array = []
	# Hauptstrasse (z=-60): abwechselnd sued-/nordseitig alle ~80 m.
	var hx := [-140.0, -60.0, 20.0, 100.0, 180.0]
	for i in hx.size():
		var side: float = 1.0 if i % 2 == 0 else -1.0
		out.append({"pos": Vector2(hx[i], -60 + side * 7.5), "arm": Vector2(0, -side)})
	# Schulstrasse (z=-180): suedseitig, Arm nach Norden.
	for x in [-120.0, -40.0, 40.0, 120.0]:
		out.append({"pos": Vector2(x, -187.5), "arm": Vector2(0, 1)})
	# Weststrasse (x=-100) und Oststrasse (x=100): je zwei.
	out.append({"pos": Vector2(-107.5, -90.0), "arm": Vector2(1, 0)})
	out.append({"pos": Vector2(-92.5, -140.0), "arm": Vector2(-1, 0)})
	out.append({"pos": Vector2(107.5, -140.0), "arm": Vector2(-1, 0)})
	out.append({"pos": Vector2(92.5, -90.0), "arm": Vector2(1, 0)})
	return out


## Blitzer-Standorte: {pos} Kameramast am Fahrbahnrand, {watch} ueberwachte
## Stelle auf der Fahrbahn, {limit} km/h.
static func speed_cams() -> Array:
	return [{"pos": Vector2(55.0, -52.6), "watch": Vector2(55.0, -60.0), "limit": 50}]


## Übungsplatz: Grundstück, Zaun, Elemente.
static func lot() -> Dictionary:
	return {
		# Platzfläche (Asphalt) — z Klapp in z-Richtung.
		"rect": {"x0": -80.0, "x1": 80.0, "z0": 42.0, "z1": 115.0},
		# Zaun läuft um den Platz, Tor bei (0,42) von der Zufahrt.
		"gate": {"pos": Vector2(0, 42), "w": 8.0},
		# Längsparken: zwei Buchten an der Ostkante, eine mit Übungs-Pkw belegt.
		"parallel_bays": [
			{"pos": Vector2(72, 62), "rot": 0.0, "len": 6.2, "occupied": true},
			{"pos": Vector2(72, 70), "rot": 0.0, "len": 6.2, "occupied": false},
			{"pos": Vector2(72, 78), "rot": 0.0, "len": 6.2, "occupied": true},
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
		# Hügel für Berganfahren: Rampe steigt im Westen nach Süden.
		"hill": {"pos": Vector2(-66, 66), "rot": 90.0, "run": 14.0, "rise": 2.2, "w": 7.0, "down": 8.0},
		# Kreis zum Üben von Wendefahrten (markierter Kreis).
		"circle": {"pos": Vector2(30, 88), "r": 11.0},
	}


## Bahnübergang auf der Ring-Ost-Straße: Gleise laufen in x-Richtung
## und kreuzen die Straße bei center.
static func rail_crossing() -> Dictionary:
	return {"center": Vector2(240.0, -150.0)}


## Baustelle auf der Ring-Sued-Strasse (z=140): suedliche Spur ist
## x von -40 bis +20 verengt/abgesperrt — Tempo 30, Kegelfuehrung.
static func baustelle() -> Dictionary:
	return {
		"zone": Rect2(Vector2(-40.0, 137.0), Vector2(60.0, 6.0)),
		"limit": 30,
		# Kegel stehen auf der Suedspur (z ~ 141.5), Autos muessen auf die
		# Nordspur — einseitig verengte Fahrbahn.
		"cones": true,
	}


## Pannen-Übung: ruhiges Teilstueck am westlichen Fahrbahnrand der
## Schulstraße — hier simuliert der Schueler eine Panne (Warnblinker an).
static func pannen_zone() -> Rect2:
	return Rect2(Vector2(-80.0, -123.0), Vector2(60.0, 5.5))


## Situationsgefahr Ball: auf der Kreisverkehr-Nordstraße rollt ein
## Ball zwischen zwei parkenden Autos auf die Fahrbahn (Klassiker:
## ein Kind koennte folgen). `cars` sind die abgestellten Fahrzeuge.
static func street_ball() -> Dictionary:
	return {
		"from": Vector2(206.5, -110.0),
		"to": Vector2(193.5, -110.0),
		"road": Vector2(200.0, -110.0),
		"cars": [Vector2(202.2, -105.5), Vector2(202.2, -114.5)],
	}


## Schulbus an der Schulstraße: haelt am Bordstein und blinkt —
## §20 StVO: an einem haltenden Bus nur Schrittgeschwindigkeit.
static func school_bus() -> Dictionary:
	return {"pos": Vector2(40.0, -177.6), "rot": 0.0}


## Radfahrer-Rundkurs: rechte Fahrbahnseite der Hauptstraße (ostwärts
## z=-57,2 — rechter Rand seiner Spur — westwärts z=-62,8), Wenden über
## die Fahrbahn an den Enden.
static func cyclist() -> Array:
	return [
		Vector2(-160, -57.2), Vector2(160, -57.2), Vector2(166, -60.0),
		Vector2(160, -62.8), Vector2(-160, -62.8), Vector2(-166, -60.0),
	]


## Fußgängerzonen usw.: wo der Fahrlehrer "Neben der Fahrbahn" meldet.
## Anschlusspunkte ohne Vorfahrtsregelung: Enden, die ineinander
## uebergehen (Kurve/Einmuendung). Nur fuer Bordstein-Luecken und
## Asphaltpatches — keine Haltelinie, kein Fahrlehrer-Check.
static func corners() -> Array:
	return [
		{"center": Vector2(240, -60), "r": 12.0},
		{"center": Vector2(216, -20), "r": 12.0},
	]


## bounds des Spielfelds (über die Karte hinaus = aus der Welt fallen).
static func bounds() -> Rect2:
	return Rect2(-260, -260, 520, 420)


## Spawn des Fahrschulautos: am Eingang des Übungsplatzes, Blick nach Norden
## (auf die Zufahrt Richtung Hauptstraße).
static func spawn() -> Transform3D:
	# +Z des Autos zeigt -z (Norden): Blick auf die Zufahrt zur Hauptstraße.
	var basis := Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)
	return Transform3D(basis, Vector3(0, 0.4, 60.0))


## Wo ein "Fahrzeug zurücksetzen" landet.
static func reset_spots() -> Array:
	return [
		{"pos": Vector2(0, 60), "rot": 180.0},
		{"pos": Vector2(-40, -61.8), "rot": 90.0},
		{"pos": Vector2(172, -61.8), "rot": 270.0},
	]


## Übungs-Startpunkte: die Taste T stellt das Auto abwechselnd an jede
## Station. `dir` ist die Blickrichtung des Autos (+Z-Basis), damit man
## sofort auf Fahrposition steht, ohne erst wenden zu muessen.
static func exercise_spots() -> Array:
	return [
		{"name": "Übungsplatz", "pos": Vector2(0, 60), "dir": Vector2(0, -1)},
		{"name": "Längsparken", "pos": Vector2(52, 70), "dir": Vector2(1, 0)},
		{"name": "Querparken", "pos": Vector2(-22, 96), "dir": Vector2(0, 1)},
		{"name": "Slalom", "pos": Vector2(-62, 64), "dir": Vector2(1, 0)},
		{"name": "Bremsbahn", "pos": Vector2(-62, 46), "dir": Vector2(1, 0)},
		{"name": "Berganfahren", "pos": Vector2(-66, 52), "dir": Vector2(0, 1)},
		{"name": "Wendekreis", "pos": Vector2(30, 104), "dir": Vector2(0, -1)},
		{"name": "Ampelkreuzung", "pos": Vector2(-78, -60), "dir": Vector2(-1, 0)},
		{"name": "Stopp-Kreuzung", "pos": Vector2(78, -60), "dir": Vector2(1, 0)},
		{"name": "Kreisverkehr", "pos": Vector2(172, -60), "dir": Vector2(1, 0)},
		{"name": "Einbahnstraße", "pos": Vector2(101.8, -95), "dir": Vector2(0, -1)},
		{"name": "Bahnübergang", "pos": Vector2(240, -168), "dir": Vector2(0, 1)},
	]
