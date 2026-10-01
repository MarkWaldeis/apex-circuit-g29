extends Node3D
## Radfahrer, der am rechten Fahrbahnrand der Hauptstraße entlangfährt.
## Der Fahrlehrer prüft den Seitenabstand beim Überholen (StVO: >= 1,5 m).
## Ein kinematischer Kollisionskoerper wandert als Kind mit, damit das
## Schulauto einen Zusammenstoß physisch spürt.

const SPEED := 5.5          ## Radtempo in m/s

var waypoints: Array = []   ## Vector2-Rundkurs (rechte Fahrbahnseite)
var lights                  ## junction_lights.gd-Instanz (Ampelachtung)
var player                  ## Schulauto — vor Fahrzeugen wird gebremst
var oneshot := false        ## true: nach dem letzten Wegpunkt freigeben
## KI-Bremsschnittstelle (wie Fussgaenger): immer "unterwegs" auf der
## Fahrbahn — ein Radler im Kreuzungsbereich darf nicht uebersehen werden.
var watchers: Array = []
var _walking := false
var _wp: int = 0
var _wheel_a: Node3D
var _wheel_b: Node3D


func setup(path: Array, p_lights = null) -> void:
	waypoints = path
	lights = p_lights
	if waypoints.size() > 0:
		var p: Vector2 = waypoints[0]
		global_position = Vector3(p.x, 0.0, p.y)


## aktuelle Position als Vector2 (für den Fahrlehrer).
func pos2() -> Vector2:
	var p: Vector3 = global_position
	return Vector2(p.x, p.z)


## KI bremst für alles, was auf der Fahrbahn ist — Radler sind es immer.
func on_road() -> bool:
	return true


func _ready() -> void:
	var body := AnimatableBody3D.new()
	body.name = "Radfahrer"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.9
	body.add_child(col)
	add_child(body)
	_build_mesh()


func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return
	var target: Vector2 = waypoints[_wp]
	var here: Vector2 = pos2()
	var to := target - here
	var dist := to.length()
	if dist < 0.4:
		if oneshot and _wp == waypoints.size() - 1:
			queue_free()
			return
		_wp = (_wp + 1) % waypoints.size()
		return
	var spd := SPEED
	# Ampelkreuzung (-100,-60) auf der Hauptstrasse respektieren: vor
	# der Haltelinie ~7,6 m vor dem Zentrum bei Rot/Amber anhalten.
	if lights != null and lights.phase_of("a") != "green":
		var dirx := to.normalized().x
		if absf(dirx) > 0.5:
			var stopx := -100.0 - 7.6 * dirx
			var s := (stopx - global_position.x) * dirx
			if s > -1.0 and s < 12.0:
				spd = SPEED * clampf(s / 6.0, 0.0, 1.0) if s > 0.0 else 0.0
	# Nicht auffahren: hält das Schulauto davor, wartet der Radler
	# hinter dem Fahrzeug statt aufzufahren.
	if player != null and is_instance_valid(player):
		var dir2 := to.normalized()
		var rel := Vector2(player.global_position.x,
			player.global_position.z) - here
		var ahead := rel.dot(dir2)
		var side := absf(rel.dot(Vector2(-dir2.y, dir2.x)))
		if ahead > 0.0 and ahead < 9.0 and side < 2.4:
			spd = 0.0
	var step := to.normalized() * spd * delta
	global_position += Vector3(step.x, 0.0, step.y)
	# Blickrichtung entlang der Fahrt: +Z-Modellachse zeigt vorn.
	rotation.y = atan2(step.x, step.y)
	if _wheel_a:
		_wheel_a.rotate_object_local(Vector3.UP, SPEED * delta / 0.34)
	if _wheel_b:
		_wheel_b.rotate_object_local(Vector3.UP, SPEED * delta / 0.34)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _build_mesh() -> void:
	var frame_c := Color(0.12, 0.12, 0.14)
	var skin_c := Color(0.55, 0.42, 0.32)
	var shirt_c := Color(0.85, 0.3, 0.1)   ## Signalfarbe: gut sichtbar
	# Zwei Laufräder (dünne Zylinder, Achse quer zur Fahrt = X).
	for x_pos in [-0.55, 0.55]:
		var w := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.34
		cyl.bottom_radius = 0.34
		cyl.height = 0.05
		cyl.radial_segments = 16
		w.mesh = cyl
		w.material_override = _mat(frame_c)
		w.rotation_degrees.z = 90.0
		w.position = Vector3(0.0, 0.34, x_pos)
		add_child(w)
		if x_pos < 0.0:
			_wheel_a = w
		else:
			_wheel_b = w
	# Rahmenrohre: Steuerrohr zum Lenker, Sattelstütze, Hauptrahmen.
	var bar := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.03
	bcyl.bottom_radius = 0.03
	bcyl.height = 1.05
	bar.mesh = bcyl
	bar.material_override = _mat(frame_c)
	bar.position = Vector3(0.0, 0.62, 0.1)
	bar.rotation_degrees.x = 24.0
	add_child(bar)
	var seat := MeshInstance3D.new()
	var scyl := CylinderMesh.new()
	scyl.top_radius = 0.03
	scyl.bottom_radius = 0.03
	scyl.height = 0.9
	seat.mesh = scyl
	seat.material_override = _mat(frame_c)
	seat.position = Vector3(0.0, 0.6, -0.32)
	seat.rotation_degrees.x = -18.0
	add_child(seat)
	var hbar := MeshInstance3D.new()
	var hcyl := CylinderMesh.new()
	hcyl.top_radius = 0.025
	hcyl.bottom_radius = 0.025
	hcyl.height = 0.44
	hbar.mesh = hcyl
	hbar.material_override = _mat(frame_c)
	hbar.position = Vector3(0.0, 1.0, 0.42)
	hbar.rotation_degrees.z = 90.0
	add_child(hbar)
	# Fahrer: Oberkörper (Kapsel) + Kopf.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.16
	cap.height = 0.62
	body.mesh = cap
	body.material_override = _mat(shirt_c)
	body.position = Vector3(0.0, 1.02, -0.12)
	body.rotation_degrees.x = 30.0
	add_child(body)
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.11
	ball.height = 0.2
	head.mesh = ball
	head.material_override = _mat(skin_c)
	head.position = Vector3(0.0, 1.34, 0.06)
	add_child(head)
