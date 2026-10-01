extends RefCounted
## Steuerung einer Ampelkreuzung nach deutscher Schaltfolge:
## grün → gelb → rot → rot+gelb → grün. Achse A (Hauptstraße) und Achse B
## (Weststraße) wechseln sich ab; zwischen den Phasen liegt immer kurz Rot für
## alle (Freigabezeit).

const PHASES := [
	{"a": "green", "b": "red", "t": 18.0},
	{"a": "amber", "b": "red", "t": 3.0},
	{"a": "red", "b": "red", "t": 1.5},
	{"a": "red", "b": "red_amber", "t": 1.0},
	{"a": "red", "b": "green", "t": 18.0},
	{"a": "red", "b": "amber", "t": 3.0},
	{"a": "red", "b": "red", "t": 1.5},
	{"a": "red_amber", "b": "red", "t": 1.0},
]

var phase_index: int = 0
var _t: float = 0.0
var state := {"a": "green", "b": "red"}


func update(delta: float) -> void:
	_t += delta
	var total := 0.0
	var acc := 0.0
	for p in PHASES:
		total += float(p["t"])
	var tm := fmod(_t, total)
	for p in PHASES:
		acc += float(p["t"])
		if tm <= acc:
			state["a"] = p["a"]
			state["b"] = p["b"]
			return


## Phase einer Haltelinie: `arm` ist "a" oder "b".
func phase_of(arm: String) -> String:
	return String(state.get(arm, "red"))
