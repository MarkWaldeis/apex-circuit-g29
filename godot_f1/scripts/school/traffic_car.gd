extends AnimatableBody3D
## KI-Verkehr: ein Stadtauto auf fester Blockrunde durch die Fahrschul-
## Stadt (Schulstraße -> Weststraße -> Hauptstraße -> Oststraße, links
## herum um den Block, auf der rechten Fahrspur). Haelt an der Ampel,
## macht am Stoppschild eine Vollbremsung, laesst dem Schueler die
## Vorfahrt (rechts vor links / Vorfahrt gewaehren) und bremst vor dem
## Schuelerauto. Kinematischer Koerper: der Schueler kann dagegen
## fahren und merkt es.

const CityLayout = preload("res://scripts/school/city_layout.gd")

## Wegpunkte (x, z) — Spur ~1.8 m rechts der Fahrbahnmitte.
const PATH := [
	Vector2(96.0, -181.8),    # 0 Schulstraße, Richtung West
	Vector2(-94.0, -181.8),   # 1
	Vector2(-101.8, -174.0),  # 2 Kurve Weststraße Nord
	Vector2(-101.8, -64.0),   # 3 Weststraße, Richtung Süd
	Vector2(-94.0, -58.2),    # 4 Kurve Hauptstraße West
	Vector2(90.0, -58.2),     # 5 Hauptstraße, Richtung Ost
	Vector2(101.8, -66.0),    # 6 Kurve Oststraße Süd
	Vector2(101.8, -174.0),   # 7 Oststraße, Richtung Nord -> Kurve zu 0
]
const CORNER_TARGETS := [2, 4, 6, 0]   ## Ziel-Indizes, vor denen abgebremst wird
const CRUISE := 8.3                    ## ~30 km/h
const CORNER_V := 3.5
const ACCEL := 6.0

## Stoppschild Ostseite der Kreuzung (100,-60) fuer Ost-Richtung.
const STOP_POS := Vector2(92.0, -58.2)
const STOP_WAIT := 1.2

## Ampel-Haltelinie fuer Ost-Richtung (Hauptstrasse Ost, Achse "a").
const LIGHT_X := -92.6

var lights
var player
var speed_ms: float = 0.0

var _i: int = 0                  ## Index des aktuellen Ziel-Wegpunkts
var _stop_left: float = 0.0      ## verbleibende Haltezeit am Stoppschild
var _stop_done: bool = false     ## Stoppschild diese Runde schon bedient


func setup(p_lights, p_player, start_i: int = 0) -> void:
	lights = p_lights
	player = p_player
	_i = start_i % PATH.size()
	var from: Vector2 = PATH[(_i - 1 + PATH.size()) % PATH.size()]
	var to: Vector2 = PATH[_i]
	var dir := (to - from).normalized()
	global_transform = Transform3D(_basis_to(dir), Vector3(from.x, 0.0, from.y))
	_build_mesh()


func _basis_to(dir: Vector2) -> Basis:
	# Wagen-Nase zeigt +Z: looking_at(-d) dreht +Z auf d.
	return Basis.looking_at(Vector3(-dir.x, 0.0, -dir.y), Vector3.UP)


func _physics_process(delta: float) -> void:
	_stop_left = maxf(_stop_left - delta, 0.0)
	var pos := Vector2(global_position.x, global_position.z)
	var target: Vector2 = PATH[_i]
	var to := target - pos
	var dist := to.length()
	if dist < 1.4:
		_i = (_i + 1) % PATH.size()
		return
	var dir := to.normalized()

	var v := CRUISE
	if dist < 16.0 and _i in CORNER_TARGETS:
		v = CORNER_V
	v = _apply_rules(pos, dir, v)

	var accel := ACCEL if v > speed_ms else ACCEL * 2.2
	speed_ms = move_toward(speed_ms, v, accel * delta)
	pos += dir * speed_ms * delta
	# Eine einzige Transform-Zuweisung: global_position lesen liefert im
	# selben Physik-Tick noch den alten Wert und wuerde den Schritt ruecksetzen.
	global_transform = Transform3D(_basis_to(dir), Vector3(pos.x, 0.0, pos.y))


func _apply_rules(pos: Vector2, dir: Vector2, v: float) -> float:
	# Ampel: auf der Ost-Spur der Hauptstrasse, wenn Achse a nicht gruen.
	if lights and dir.x > 0.9 and pos.x > LIGHT_X - 7.0 and pos.x < LIGHT_X + 2.0:
		if String(lights.phase_of("a")) != "green":
			v = 0.0
	# Stoppschild: einmal voller Halt, dann weiter.
	if dir.x > 0.9:
		var d_stop := pos.distance_to(STOP_POS)
		if d_stop < 4.0 and not _stop_done:
			_stop_left = STOP_WAIT
			_stop_done = true
		if _stop_left > 0.0:
			v = 0.0
		if d_stop > 20.0:
			_stop_done = false
	# Nicht auffahren: Schuelerauto dicht voraus -> anhalten.
	if player:
		var rel := Vector2(player.global_position.x, player.global_position.z) - pos
		var ahead := rel.dot(dir)
		var side := absf(rel.dot(Vector2(-dir.y, dir.x)))
		if ahead > 0.0 and ahead < 10.0 and side < 3.2:
			v = minf(v, 0.0)
	v = _yield_check(pos, dir, v)
	return v


# Vorfahrt: kommt das Auto auf eine Kreuzung zu, auf der der Schueler
# wartet oder gerade quert, entscheidet die Regel wer faehrt — sonst
# lernt niemand, dass Gegenverkehr auch mal warten muss.
func _yield_check(pos: Vector2, dir: Vector2, v: float) -> float:
	if player == null:
		return v
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var p_spd := Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
	for j in CityLayout.junctions().values():
		var kind := String(j["kind"])
		if kind != "rbl" and kind != "yield":
			continue
		var c: Vector2 = j["center"]
		var d_ai := pos.distance_to(c)
		if d_ai > 24.0 or d_ai < 1.5:
			continue
		if (c - pos).normalized().dot(dir) < 0.6:
			continue
		var d_p := p2.distance_to(c)
		if d_p > 16.0:
			continue
		if not _student_has_priority(j, p2, p_spd, dir):
			continue
		# Vorfahrt des Schuelers: langsam ran, dicht dran anhalten.
		v = 0.0 if d_ai < 9.0 else minf(v, 3.0)
	return v


func _student_has_priority(j: Dictionary, p2: Vector2, p_spd: float, dir: Vector2) -> bool:
	var c: Vector2 = j["center"]
	# Steht der Schueler still und weit draussen, faehrt die KI einfach —
	# sonst wartet sie ewig auf zoegerliche Anfaenger.
	if p_spd < 1.0 and p2.distance_to(c) > 9.0:
		return false
	# Arm des Schuelers und eigener Arm bestimmen.
	var p_arm: Dictionary = {}
	var ai_arm: Dictionary = {}
	var p_best := 999.0
	var ai_best := 999.0
	var me := Vector2(global_position.x, global_position.z)
	for arm in j.get("arms", []):
		var ap: Vector2 = arm["pos"]
		var dp := ap.distance_to(p2)
		if dp < p_best:
			p_best = dp
			p_arm = arm
		var da := ap.distance_to(me)
		if da < ai_best:
			ai_best = da
			ai_arm = arm
	if p_arm.is_empty():
		return false
	if p_arm == ai_arm:
		return false   # gleiche Einfahrt — dafuer bremst schon die Kolonne
	if String(j["kind"]) == "yield":
		# Yield-Arme sind die Wartepflichtigen. Stehen wir gar nicht auf
		# einem, fahren wir auf der Vorfahrtstrasse — der Schueler wartet.
		var e: Vector2 = ai_arm["enter"]
		var on_yield_arm: bool = ai_best < 7.0 and dir.normalized().dot(e.normalized()) > 0.6
		return on_yield_arm
	# rbl: der Schueler faehrt uns von rechts rein.
	var right := Vector2(dir.y, dir.x)
	var e: Vector2 = p_arm["enter"]
	return e.normalized().dot(-right) > 0.45


func _build_mesh() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.25, 4.3)
	col.shape = box
	col.position = Vector3(0.0, 0.75, 0.0)
	add_child(col)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.75, 0.12, 0.10)
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.06, 0.07, 0.09)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 4.2)
	body.mesh = bm
	body.material_override = body_mat
	body.position = Vector3(0.0, 0.62, 0.0)
	add_child(body)

	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.6, 0.55, 2.1)
	cabin.mesh = cm
	cabin.material_override = dark_mat
	cabin.position = Vector3(0.0, 1.18, -0.25)
	add_child(cabin)

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.05)
	for hub in [Vector3(-0.82, 0.33, 1.35), Vector3(0.82, 0.33, 1.35),
			Vector3(-0.82, 0.33, -1.35), Vector3(0.82, 0.33, -1.35)]:
		var w := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.33
		wm.bottom_radius = 0.33
		wm.height = 0.25
		w.mesh = wm
		w.material_override = wheel_mat
		w.rotation.z = PI / 2.0
		w.position = hub
		add_child(w)
