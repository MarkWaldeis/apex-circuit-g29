extends SceneTree
## Diagnose: welche Parameter der Ideallinie sind wirklich schneller?
## Baut die Linie mit mehreren Saetzen und vergleicht Rundenzeit,
## Kruemmungsenergie und Breite. Kein Abnahmetest, nur ein Messwerkzeug.

const RacingLine = preload("res://scripts/racing_line.gd")
const IdealLine = preload("res://scripts/ideal_line.gd")


func _initialize() -> void:
	var line = RacingLine.new()
	if not line.load_json("res://assets/track/racing_line.json"):
		quit(1)
		return
	var centre = IdealLine.new()
	centre.build(line, {"corridor": 0.0})
	print("Mitte: t=%.2f s J=%.4f len=%.1f" % [
		_lap_time(centre), _energy(centre), centre.length])
	var sets := [
		{"corridor": 5.2, "control_step": 12, "passes": 9, "search_start": 0.8, "curvature_penalty": 0.0},
		{"corridor": 5.2, "control_step": 12, "passes": 9, "search_start": 0.8, "curvature_penalty": 20.0},
		{"corridor": 5.2, "control_step": 12, "passes": 9, "search_start": 0.8, "curvature_penalty": 60.0},
		{"corridor": 5.2, "control_step": 12, "passes": 12, "search_start": 1.0, "curvature_penalty": 120.0},
		{"corridor": 5.2, "control_step": 8, "passes": 12, "search_start": 1.0, "curvature_penalty": 120.0},
		{"corridor": 5.2, "control_step": 8, "passes": 12, "search_start": 1.0, "curvature_penalty": 400.0},
	]
	for s in sets:
		var ideal = IdealLine.new()
		ideal.build(line, s)
		var dt: float = _lap_time(centre) - _lap_time(ideal)
		print("SET %s -> t=%.2f s (%+.2f s) J=%.4f maxoff=%.2f len=%.1f" % [
			JSON.stringify(s), _lap_time(ideal), dt, _energy(ideal),
			_max_offset(ideal), ideal.length])
	quit(0)


func _lap_time(model) -> float:
	var t := 0.0
	for i in model.points.size():
		t += model.segments[i] / maxf(model.target_speed[i], 1.0)
	return t


func _energy(model) -> float:
	var j := 0.0
	for i in model.points.size():
		var k: float = model.curvature[i]
		j += k * k * model.segments[i]
	return j


func _max_offset(model) -> float:
	var m := 0.0
	for v in model.offsets:
		m = maxf(m, absf(v))
	return m
