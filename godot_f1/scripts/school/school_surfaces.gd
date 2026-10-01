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


func setup() -> void:
	_roads = CityLayout.roads()
	_lot_rect = CityLayout.lot()["rect"]
	_island = CityLayout.junctions().get("kreis", {})


## Position -> Untergrund. `offset`/`index` füllt das Auto selbst aus seinem
## Spurmodell; hier sind sie fest 0/-1 (keine Rennstrecke).
func sample(pos: Vector3, _line_hint: int = -1) -> Dictionary:
	# Kreisverkehr-Insel zuerst: erhaben und absichtlich schlecht zu befahren.
	if not _island.is_empty():
		var c: Vector2 = _island["center"]
		var r: float = float(_island["island_r"]) - 0.4
		var d2: Vector2 = Vector2(pos.x, pos.z) - c
		if d2.length() < r:
			return ISLAND.duplicate()
	# Übungsplatz-Fläche.
	var lr: Dictionary = _lot_rect
	if pos.x >= lr.get("x0", 0.0) and pos.x <= lr.get("x1", 0.0) \
			and pos.z >= lr.get("z0", 0.0) and pos.z <= lr.get("z1", 0.0):
		return ASPHALT.duplicate()
	# Fahrbahnen und ihre Gehwege.
	for road in _roads:
		var a: Vector2 = road["from"]
		var b: Vector2 = road["to"]
		var w: float = float(road["width"])
		var d: float = _seg_dist(Vector2(pos.x, pos.z), a, b)
		if d <= w * 0.5:
			var out := ASPHALT.duplicate()
			out["name"] = String(road["name"])
			return out
		if d <= w * 0.5 + 1.1:
			return KERB.duplicate()
	return GRASS.duplicate()


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
	var best := 999.0
	var limit := -1
	for road in _roads:
		var d: float = _seg_dist(Vector2(pos.x, pos.z), road["from"], road["to"])
		var w: float = float(road["width"]) * 0.5 + 1.5
		if d <= w and d < best:
			best = d
			limit = int(road["limit"])
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
