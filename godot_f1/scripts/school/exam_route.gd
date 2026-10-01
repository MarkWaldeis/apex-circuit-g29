extends RefCounted
## Prüfungsfahrt: eine feste Route durch die Stadt mit Prüfer-Anweisungen
## ("in X Metern links/rechts abbiegen"). school_instructor startet sie
## mit Taste P und ruft pro Physik-Tick `update()` auf; Rückgabe ist ein
## Array von Ereignissen {"ev", ...}, die der Instructor ansagt.
##
## Wegpunkte liegen auf der rechten Fahrspur. Anweisungen werden ~55 m vor
## dem Wegpunkt ausgegeben, der Wegpunkt gilt ab 9 m als erreicht.

var wps: Array = []      ## [{pos: Vector2, text: String}]
var idx := 0
var active := false
var _said := false
var _offtrack_warned := false

const WP_REACHED := 9.0
const SAY_DIST := 55.0
const OFFTRACK_DIST := 75.0


## Route B: Stopp-Kreuzung, Kreisverkehr (2. Ausfahrt), Ringstraße mit
## Tempo 100, dann zurueck ueber die Weststrasse. Wegpunkte liegen wieder
## auf der rechten Fahrspur.
static func route_b() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie rechts in die Hauptstraße ab."},
		{"pos": Vector2(60, -58.2), "text": "Gleich Stoppschild — zum Stillstand kommen, dann vorsichtig weiter."},
		{"pos": Vector2(150, -58.2), "text": "Weiter zum Kreisverkehr — Vorfahrt dem Kreis."},
		{"pos": Vector2(216, -58.2), "text": "Zweite Ausfahrt nehmen — beim Rausfahren blinken."},
		{"pos": Vector2(236, -58.2), "text": "Links auf den Ring Ost — Tempo 100."},
		{"pos": Vector2(241.8, -140.0), "text": "Der Ringstraße folgen."},
		{"pos": Vector2(180, -241.8), "text": "Links auf die Ringstraße Nord."},
		{"pos": Vector2(-60, -241.8), "text": "Geradeaus — freie Fahrt."},
		{"pos": Vector2(-101.8, -150.0), "text": "Links in die Weststraße abbiegen."},
		{"pos": Vector2(-101.8, -70.0), "text": "Links zurück in die Hauptstraße."},
		{"pos": Vector2(-40, -58.2), "text": "Zurück in Richtung Zentrum — Achtung Zebrastreifen."},
		{"pos": Vector2(14, -58.2), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


## Route C: Stoppschild, Oststrasse Sued, Einbahnstrasse (nur Westwaerts),
## rechts-vor-links am Einbahn-Ende und an der Schulstrasse, Tempo-30-Zone.
static func route_c() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie rechts in die Hauptstraße ab."},
		{"pos": Vector2(60, -58.2), "text": "Gleich Stoppschild — zum Stillstand kommen, dann vorsichtig weiter."},
		{"pos": Vector2(98.2, -95.0), "text": "Rechts in die Oststraße abbiegen."},
		{"pos": Vector2(98.2, -117.0), "text": "Gleich rechts in die Einbahnstraße."},
		{"pos": Vector2(60, -121.4), "text": "Einbahnstraße — nur in diese Richtung erlaubt."},
		{"pos": Vector2(-94, -120.0), "text": "Am Ende links in die Weststraße — rechts vor links beachten."},
		{"pos": Vector2(-101.8, -150.0), "text": "Der Weststraße nach Süden folgen."},
		{"pos": Vector2(-101.8, -172.0), "text": "Gleich links in die Schulstraße — rechts vor links."},
		{"pos": Vector2(60, -178.2), "text": "Der Schulstraße folgen — Tempo 30."},
		{"pos": Vector2(98.2, -140.0), "text": "Links in die Oststraße — rechts vor links."},
		{"pos": Vector2(98.2, -80.0), "text": "Weiter zur Hauptstraße."},
		{"pos": Vector2(40, -61.8), "text": "Links in die Hauptstraße abbiegen."},
		{"pos": Vector2(-10, -61.8), "text": "Gleich rechts in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


static func default_route() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie links in die Hauptstraße ab."},
		{"pos": Vector2(-85, -61.8), "text": "Geradeaus über die Ampelkreuzung — Achtung Zebrastreifen."},
		{"pos": Vector2(-98.2, -110.0), "text": "Rechts in die Weststraße abbiegen."},
		{"pos": Vector2(-98.2, -170.0), "text": "An der nächsten Kreuzung rechts — rechts vor links beachten."},
		{"pos": Vector2(80, -178.2), "text": "Der Schulstraße folgen (Tempo 30), dann rechts in die Oststraße."},
		{"pos": Vector2(98.2, -140.0), "text": "Geradeaus über die Kreuzungen weiter."},
		{"pos": Vector2(98.2, -80.0), "text": "Rechts in die Hauptstraße abbiegen."},
		{"pos": Vector2(30, -61.8), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


var _route_i := -1   ## Routen A/B wechseln sich bei jedem Start ab


func begin() -> void:
	_route_i = (_route_i + 1) % 3
	match _route_i:
		0:
			wps = default_route()
		1:
			wps = route_b()
		_:
			wps = route_c()
	idx = 0
	active = true
	_said = true   ## erste Anweisung wird beim Start gesprochen
	_offtrack_warned = false


func next_wp() -> Vector2:
	if not active or idx >= wps.size():
		return Vector2.ZERO
	return wps[idx]["pos"]


func update(p2: Vector2) -> Array:
	var out: Array = []
	if not active:
		return out
	var wp: Vector2 = wps[idx]["pos"]
	var d := p2.distance_to(wp)
	if d < WP_REACHED:
		idx += 1
		_said = false
		_offtrack_warned = false
		if idx >= wps.size():
			active = false
			out.append({"ev": "done"})
		else:
			out.append({"ev": "next", "wp": wps[idx]["pos"]})
	elif not _said and d < SAY_DIST:
		_said = true
		out.append({"ev": "say", "text": wps[idx]["text"]})
	elif not _offtrack_warned and ((d > OFFTRACK_DIST and _said) or d > OFFTRACK_DIST * 1.7):
		# 75 m ab Ansage -> Kurskorrektur; >~128 m ist das Abkommen so gross,
		# dass es auch ohne Ansage gemeldet wird (wer die Route voellig
		# verlaesst, darf nicht ohne Hinweis weiterfahren).
		_offtrack_warned = true
		out.append({"ev": "offtrack"})
	return out


func abort() -> void:
	active = false
