extends RefCounted
## Which surface is under the car, and what that does to grip and drag.
##
## The circuit is a 12 m asphalt ribbon with 0.85 m kerbs, a 10 m runoff and a
## barrier 16 m from the centre (see blender/scripts/05_build_track.py). The
## physics geometry under the cars is a flat apron, so the surface has to be
## derived from the car's lateral offset to the racing line - there is no
## material to query.
##
## OWNER: agent CRASH. Values in `TUNING` are the place to work; the API must
## stay as documented in docs/DRIVE_FEEL_PLAN.md.

const ASPHALT := 0
const KERB := 1
const RUNOFF := 2
const GRASS := 3

## From the Blender build. Constants, not guesses.
const ROAD_HALF := 6.0
const KERB_WIDTH := 0.85
const RUNOFF_WIDTH := 10.0
const BARRIER_OFFSET := 16.0

## grip = multiplier on the tyre friction the physics uses on asphalt.
## drag = additional longitudinal deceleration in m/s^2, faded in with speed.
const TUNING := {
	ASPHALT: {"name": "Asphalt", "grip": 1.00, "drag": 0.0, "rumble": 0.0, "rough": 0.0},
	KERB: {"name": "Kerb", "grip": 0.94, "drag": 1.2, "rumble": 0.75, "rough": 0.55},
	RUNOFF: {"name": "Kies", "grip": 0.46, "drag": 7.5, "rumble": 0.45, "rough": 0.70},
	GRASS: {"name": "Gras", "grip": 0.30, "drag": 10.0, "rumble": 0.30, "rough": 0.50},
}

var line
var _last: Dictionary = {}


func setup(racing_line) -> void:
	line = racing_line


## Classify the surface at `pos`. Pass the previous `index` back as `hint` so
## the search stays inside a window instead of walking all 1440 points.
func sample(pos: Vector3, hint: int = -1) -> Dictionary:
	if line == null or line.points.size() < 8:
		return _make(ASPHALT, 0.0, 0)
	var index: int = line.closest_index_near(pos, hint) if hint >= 0 else line.closest_index(pos)
	var offset: float = line.offset_at(pos, index)
	var kind := _classify(absf(offset))
	var out := _make(kind, offset, index)
	_last = out
	return out


func _classify(distance: float) -> int:
	if distance <= ROAD_HALF:
		return ASPHALT
	if distance <= ROAD_HALF + KERB_WIDTH:
		return KERB
	if distance <= ROAD_HALF + KERB_WIDTH + RUNOFF_WIDTH:
		return RUNOFF
	return GRASS


func _make(kind: int, offset: float, index: int) -> Dictionary:
	var t: Dictionary = TUNING[kind]
	return {
		"surface": kind,
		"name": t["name"],
		"offset": offset,
		"index": index,
		"grip": float(t["grip"]),
		"drag": float(t["drag"]),
		"rumble": float(t["rumble"]),
		"rough": float(t["rough"]),
	}


func name_of(kind: int) -> String:
	var t: Dictionary = TUNING.get(kind, TUNING[ASPHALT])
	return String(t["name"])


func is_outside_corridor(offset: float) -> bool:
	return absf(offset) >= BARRIER_OFFSET
