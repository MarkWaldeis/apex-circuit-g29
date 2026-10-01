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
		{"pos": Vector2(14, -58.2), "text": "Gleich rechts in die Zufahrt zum Übungsplatz."},
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
		{"pos": Vector2(-94, -120.0), "text": "Am Ende rechts in die Weststraße — rechts vor links beachten."},
		{"pos": Vector2(-98.2, -150.0), "text": "Der Weststraße nach Norden folgen."},
		{"pos": Vector2(-98.2, -172.0), "text": "Gleich rechts in die Schulstraße — rechts vor links."},
		{"pos": Vector2(60, -178.2), "text": "Der Schulstraße folgen — Tempo 30."},
		{"pos": Vector2(98.2, -140.0), "text": "Rechts in die Oststraße — der Vorfahrtstraße folgen, rechts blinken."},
		{"pos": Vector2(98.2, -80.0), "text": "Weiter zur Hauptstraße."},
		{"pos": Vector2(40, -61.8), "text": "Rechts in die Hauptstraße abbiegen."},
		{"pos": Vector2(-10, -61.8), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


## Route D: die grosse Ring-Runde — Yield-Einfahrt auf die 100er-Strasse,
## Wildwechsel am West-Ring, Engstelle an der Kreis-Nordstrasse,
## Kreisverkehr von Norden herein und wieder nach Hause. Wegpunkte
## liegen auf der rechten Fahrspur.
static func route_d() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie links in die Hauptstraße ab."},
		{"pos": Vector2(-90, -61.8), "text": "Geradeaus über die Ampelkreuzung."},
		{"pos": Vector2(-200, -61.8), "text": "Weiter Richtung Westen — gleich Ringstraße."},
		{"pos": Vector2(-241.5, -56.0), "text": "Links auf die Ringstraße — Vorfahrt gewähren."},
		{"pos": Vector2(-241.5, -45.0), "text": "Achtung Wildwechsel — vom Gas, bremsbereit."},
		{"pos": Vector2(-241.5, 60.0), "text": "Der Ringstraße folgen — Tempo 100."},
		{"pos": Vector2(-190.0, 141.5), "text": "Links auf die Ringstraße Süd."},
		{"pos": Vector2(150.0, 141.5), "text": "Der Ringstraße folgen — gern den Lkw überholen."},
		{"pos": Vector2(241.5, 90.0), "text": "Links auf die Ringstraße Ost."},
		{"pos": Vector2(241.5, -140.0), "text": "Der Ringstraße nach Norden folgen."},
		{"pos": Vector2(200.0, -241.5), "text": "Links auf die Ringstraße Nord."},
		{"pos": Vector2(198.2, -225.0), "text": "Gleich links in die Kreisverkehr-Nordstraße — Vorfahrt gewähren."},
		{"pos": Vector2(198.2, -150.0), "text": "Der Nordstraße folgen — Engstelle beachten."},
		{"pos": Vector2(198.2, -92.0), "text": "Kreisverkehr — Vorfahrt dem Kreis."},
		{"pos": Vector2(178.0, -61.8), "text": "Erste Ausfahrt nach Westen — beim Rausfahren blinken."},
		{"pos": Vector2(80.0, -61.8), "text": "Der Hauptstraße zurück Richtung Zentrum."},
		{"pos": Vector2(6.0, -61.8), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


## Route E: grosse Runde gegen den Uhrzeigersinn — Ring West mit
## Wildwechsel, Ring Sued mit Lkw, dann ueber die Kreis-Suedstrasse in
## den Kreisverkehr und nach Hause.
static func route_e() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie links in die Hauptstraße ab."},
		{"pos": Vector2(-90, -61.8), "text": "Geradeaus über die Ampelkreuzung."},
		{"pos": Vector2(-200, -61.8), "text": "Weiter Richtung Westen — gleich Ringstraße."},
		{"pos": Vector2(-241.5, -56.0), "text": "Links auf die Ringstraße — Vorfahrt gewähren."},
		{"pos": Vector2(-241.5, -45.0), "text": "Achtung Wildwechsel — vom Gas, bremsbereit."},
		{"pos": Vector2(-241.5, 80.0), "text": "Der Ringstraße folgen — Tempo 100."},
		{"pos": Vector2(-190.0, 141.5), "text": "Links auf die Ringstraße Süd."},
		{"pos": Vector2(150.0, 141.5), "text": "Der Ringstraße folgen — gern den Lkw überholen."},
		{"pos": Vector2(241.5, 90.0), "text": "Links auf die Ringstraße Ost."},
		{"pos": Vector2(241.5, -40.0), "text": "Der Ringstraße nach Norden — gleich zum Kreisverkehr."},
		{"pos": Vector2(230.0, -44.0), "text": "Dem Abzweig zur Kreisverkehr-Südstraße folgen."},
		{"pos": Vector2(208.0, -30.0), "text": "Kreisverkehr — Vorfahrt dem Kreis, erste Ausfahrt."},
		{"pos": Vector2(178.0, -61.8), "text": "Erste Ausfahrt nach Westen — beim Rausfahren blinken."},
		{"pos": Vector2(80.0, -61.8), "text": "Der Hauptstraße zurück Richtung Zentrum."},
		{"pos": Vector2(6.0, -61.8), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
		{"pos": Vector2(0, 20.0), "text": "Zurück am Übungsplatz — stellen Sie das Auto ab."},
	]


## Route F: Ampel, Weststraße, rechts-vor-links in die Schulstraße,
## verkehrsberuhigter Bereich (Schritttempo), Biegung der Vorfahrtstraße
## mit Blinker in die Oststraße und Stoppschild am Heimweg.
static func route_f() -> Array:
	return [
		{"pos": Vector2(0, -55.0), "text": "Biegen Sie links in die Hauptstraße ab."},
		{"pos": Vector2(-90, -61.8), "text": "Geradeaus über die Ampelkreuzung."},
		{"pos": Vector2(-98.2, -110.0), "text": "Rechts in die Weststraße abbiegen."},
		{"pos": Vector2(-98.2, -172.0), "text": "Rechts in die Schulstraße — rechts vor links."},
		{"pos": Vector2(-60, -178.2), "text": "Verkehrsberuhigter Bereich — Schritttempo!"},
		{"pos": Vector2(60, -178.2), "text": "Der Biegung der Vorfahrtstraße folgen — rechts in die Oststraße, rechts blinken."},
		{"pos": Vector2(98.2, -160.0), "text": "Der Oststraße nach Süden folgen."},
		{"pos": Vector2(98.2, -70.0), "text": "Stoppschild an der Hauptstraße — Stillstand, dann rechts abbiegen."},
		{"pos": Vector2(40.0, -61.8), "text": "Der Hauptstraße Richtung Zentrum."},
		{"pos": Vector2(-10.0, -61.8), "text": "Gleich links in die Zufahrt zum Übungsplatz."},
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


func begin(force_route: int = -1) -> void:
	## Zufalls-Prüfer: Route wird pro Fahrt gewürfelt — der Prüfling weiss
	## nicht vorher, welche Strecke drankommt (wie in der echten Prüfung).
	## force_route >= 0 waehlt eine bestimmte Route (Tests).
	var routes := [default_route(), route_b(), route_c(), route_d(),
		route_e(), route_f()]
	var i := randi() % routes.size() if force_route < 0 \
		else force_route % routes.size()
	wps = routes[i]
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
