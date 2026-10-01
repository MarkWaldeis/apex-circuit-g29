extends RefCounted
## Untergrund-Abtastung für die Fahrschul-Welt. Gleiche Dict-Form wie
## scripts/surfaces.gd ({name, grip, drag, rumble, index, offset}), damit
## Lenkrad-Feedback und Auto sie unverändert benutzen.
##
## Zonen: Straßenbelag, Gehweg (erhöht, Bordsteinkante), Rasenfläche,
## Kreisverkehr-Insel. Die Position wird gegen das Layout aus
## city_layout.gd geprüft — die Straßen dort sind die Wahrheit.

const CityLayout := preload("res://scripts/school/city_layout.gd")

const ASPHALT := {"name": "Asphalt", "grip": 1.0, "drag": 0.012, "rumble": 0.0, "surface": "asphalt"}
const KERB := {"name": "Gehweg", "grip": 0.72, "drag": 0.05, "rumble": 0.55, "surface": "kerb"}
const GRASS := {"name": "Wiese", "grip": 0.55, "drag": 0.16, "rumble": 0.35, "surface": "grass"}
const ISLAND := {"name": "Insel", "grip": 0.4, "drag": 0.2, "rumble": 0.6, "surface": "island"}

var _roads: Array = []
var _lot_rect: Dictionary = {}
var _island := {}
var _junction_centers: Array = []
var _baustelle := Rect2()      ## Kegel schieben auf die Gegenspur
var _engstelle := Rect2()      ## parkende Autos -> Ausweichkorridor
var _last_limit := -1         ## letztes Strassenlimit (Kreuzungsbereich)
var wet := false               ## Nässe: Grip lässt überall nach
var icy := false               ## Glätte: Grip bricht stark ein


func set_wet(on: bool) -> void:
	wet = on


func set_icy(on: bool) -> void:
	icy = on


func setup() -> void:
	_roads = CityLayout.roads()
	_lot_rect = CityLayout.lot()["rect"]
	_baustelle = CityLayout.baustelle()["zone"]
	# Engstelle Kreis-Nordstrasse: parkende Autos auf der Ostspur,
	# die Nordspur muss legal links ausweichen (VZ 208).
	_engstelle = Rect2(Vector2(192.0, -120.0), Vector2(16.0, 25.0))
	var junc: Dictionary = CityLayout.junctions()
	_island = junc.get("kreis", {})
	_junction_centers.clear()
	for key in junc.keys():
		var c = junc[key].get("center", null)
		if c is Vector2:
			_junction_centers.append(c)


## Position -> Untergrund. `offset`/`index` füllt das Auto selbst aus seinem
## Spurmodell; hier sind sie fest 0/-1 (keine Rennstrecke).
func sample(pos: Vector3, _line_hint: int = -1) -> Dictionary:
	# Kreisverkehr-Insel zuerst: erhaben und absichtlich schlecht zu befahren.
	if not _island.is_empty():
		var c: Vector2 = _island["center"]
		var r: float = float(_island["island_r"]) - 0.4
		var d2: Vector2 = Vector2(pos.x, pos.z) - c
		if d2.length() < r:
			return _wet_out(ISLAND.duplicate())
		# Fahrting um die Insel ist Asphalt (kein roads()-Segment).
		if d2.length() < 16.5:
			var ring := ASPHALT.duplicate()
			ring["name"] = "Kreisverkehr"
			return _wet_out(ring)
	# Übungsplatz-Fläche.
	var lr: Dictionary = _lot_rect
	if pos.x >= lr.get("x0", 0.0) and pos.x <= lr.get("x1", 0.0) \
			and pos.z >= lr.get("z0", 0.0) and pos.z <= lr.get("z1", 0.0):
		return _wet_out(ASPHALT.duplicate())
	# Fahrbahnen und ihre Gehwege.
	for road in _roads:
		var a: Vector2 = road["from"]
		var b: Vector2 = road["to"]
		var w: float = float(road["width"])
		var d: float = _seg_dist(Vector2(pos.x, pos.z), a, b)
		if d <= w * 0.5:
			var out := ASPHALT.duplicate()
			out["name"] = String(road["name"])
			return _wet_out(out)
		if d <= w * 0.5 + 1.1:
			return _wet_out(KERB.duplicate())
	return _wet_out(GRASS.duplicate())


## Bei Nässe: Grip ~35 % weniger, etwas mehr Wasserwiderstand.
## Glätte geht vor: ~60 % Grip-Verlust — Bremswege explodieren.
func _wet_out(out: Dictionary) -> Dictionary:
	if icy:
		out["grip"] = float(out["grip"]) * 0.38
		out["drag"] = float(out["drag"]) + 0.006
		out["name"] = String(out["name"]) + " vereist"
	elif wet:
		out["grip"] = float(out["grip"]) * 0.62
		out["drag"] = float(out["drag"]) + 0.004
		out["name"] = String(out["name"]) + " nass"
	return out


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Tempolimit an dieser Stelle: die nächste Straße liefert es. -1 = keins
## (Übungsplatz: Schritttempo wird vom Fahrlehrer selbst erwartet).
func limit_at(pos: Vector3) -> int:
	# Baustelle hat Vorrang vor dem Strassenlimit (Tempo-30-Zone).
	var ba: Dictionary = CityLayout.baustelle()
	if Rect2(ba["zone"]).has_point(Vector2(pos.x, pos.z)):
		return int(ba["limit"])
	# Verkehrsberuhigter Bereich: Schritttempo (ca. 7 km/h).
	var sp: Dictionary = CityLayout.spiel()
	if Rect2(sp["rect"]).has_point(Vector2(pos.x, pos.z)):
		return int(sp["limit"])
	# Mitten im Kreuzungsbereich gilt kein eigenes Limit — das Limit
	# der Strasse behalten, von der man kommt (sonst gewinnt eine
	# zufaellige Straße aus der Liste).
	var p2q := Vector2(pos.x, pos.z)
	for c in _junction_centers:
		if p2q.distance_to(c) < 14.0:
			return _last_limit
	var best := 999.0
	var limit := -1
	for road in _roads:
		var d: float = _seg_dist(Vector2(pos.x, pos.z), road["from"], road["to"])
		var w: float = float(road["width"]) * 0.5 + 1.5
		if d <= w and d < best:
			best = d
			limit = int(road["limit"])
	_last_limit = limit
	return limit


## Welche Straße (Name) liegt hier — für "du bist auf …" Meldungen.
func road_at(pos: Vector3) -> String:
	var best := 999.0
	var name := ""
	for road in _roads:
		var d: float = _seg_dist(Vector2(pos.x, pos.z), road["from"], road["to"])
		var w: float = float(road["width"]) * 0.5 + 1.5
		if d <= w and d < best:
			best = d
			name = String(road["name"])
	return name


## Einbahnstraßen-Verstoß: auf einer Einbahnstraße gegen die Fahrtrichtung.
## Gibt die Straße zurück, wenn falsch gefahren wird, sonst "".
func wrong_way(pos: Vector3, vel: Vector3) -> String:
	for road in _roads:
		if int(road["oneway"]) != 1:
			continue
		var a: Vector2 = road["from"]
		var b: Vector2 = road["to"]
		var d: float = _seg_dist(Vector2(pos.x, pos.z), a, b)
		if d > float(road["width"]) * 0.5 + 1.0:
			continue
		var dir := (b - a).normalized()
		var vd := Vector2(vel.x, vel.z).dot(dir)
		if vd < -1.5:
			return String(road["name"])
	return ""


## Vorzeichenbehafteter Seitenversatz zur Fahrbahnmitte: positiv auf
## der rechten Fahrspur (in Fahrtrichtung), negativ auf der linken.
## 9999.0 wenn nicht auswertbar (Kreuzung, Einbahnstraße, zu langsam).
func lane_offset(pos: Vector3, vel: Vector3) -> float:
	var v := Vector2(vel.x, vel.z)
	if v.length() < 2.0:
		return 9999.0
	v = v.normalized()
	var right := Vector2(-v.y, v.x)
	var p2 := Vector2(pos.x, pos.z)
	for c in _junction_centers:
		if p2.distance_to(c) < 14.0:
			return 9999.0
	# Baustelle und Engstelle: dort ist das Ausweichen auf die
	# Gegenspur vorgesehen — kein Links-fahren-Verstoss.
	if _baustelle.has_point(p2) or _engstelle.has_point(p2):
		return 9999.0
	for road in _roads:
		if int(road.get("oneway", 0)) != 0:
			continue
		var a: Vector2 = road["from"]
		var b: Vector2 = road["to"]
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 < 0.001:
			continue
		var t := clampf((p2 - a).dot(ab) / len2, 0.0, 1.0)
		var c := a + ab * t
		if p2.distance_to(c) > float(road["width"]) * 0.5 + 1.0:
			continue
		return (p2 - c).dot(right)
	return 9999.0


## Rechtsfahrgebot: auf zweispurigen Straßen (keine Einbahnstraße) mit >
## ~1 m links der Mittellinie fahren heißt Gegenverkehr. Rückgabe:
## Straßenname bei Verstoß, sonst "". Kreuzungsbereiche und Langsames
## (Einparken, Rangieren) zählen nicht.
func left_lane(pos: Vector3, vel: Vector3) -> String:
	var lat := lane_offset(pos, vel)
	if lat > 9000.0:
		return ""
	var p2 := Vector2(pos.x, pos.z)
	for road in _roads:
		var a: Vector2 = road["from"]
		var b: Vector2 = road["to"]
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 < 0.001:
			continue
		var t := clampf((p2 - a).dot(ab) / len2, 0.0, 1.0)
		var c := a + ab * t
		if p2.distance_to(c) > float(road["width"]) * 0.5 + 1.0:
			continue
		if lat < -1.1:
			return String(road["name"])
	return ""
