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


func begin() -> void:
	wps = default_route()
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
	elif not _offtrack_warned and d > OFFTRACK_DIST and _said:
		_offtrack_warned = true
		out.append({"ev": "offtrack"})
	return out


func abort() -> void:
	active = false
