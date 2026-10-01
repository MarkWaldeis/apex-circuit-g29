extends Node3D
## Schulbus an der Schulstraße: hält periodisch mit Warnblinker —
## §20 StVO: an einem haltenden Bus mit Warnblinklicht nur
## Schrittgeschwindigkeit vorbei. Der Fahrlehrer liest `hazards_on`.

var hazards_on := false

var _t := 8.0                ## Restsekunden bis zum nächsten Halt
var _phase := 0.0            ## Blinkphase
var _lamps: Array = []       ## gelbe Warnlampen (MeshInstance3D)
var _peds: Array = []        ## ein-/aussteigende Fahrgaeste {node, a, b, t}


func setup(spec: Dictionary) -> void:
	var p: Vector2 = spec["pos"]
	global_position = Vector3(p.x, 0.0, p.y)
	rotation_degrees.y = float(spec.get("rot", 0.0))


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "Schulbus"
	add_child(body)
	# Kastenaufbau im typischen Schulgelb.
	var shell := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 2.8, 9.0)
	shell.mesh = box
	shell.material_override = _mat(Color(0.95, 0.72, 0.05))
	shell.position.y = 1.6
	body.add_child(shell)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.5, 2.8, 9.0)
	col.shape = shape
	col.position.y = 1.6
	body.add_child(col)
	# Fensterband + Schriftzug "SCHULBUS" als schwarze Streifen.
	var win := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(2.54, 0.7, 7.6)
	win.mesh = wbox
	win.material_override = _mat(Color(0.08, 0.09, 0.11))
	win.position.y = 2.3
	body.add_child(win)
	# Vier gelbe Warnlampen: vorn und hinten je zwei.
	for z in [-4.35, 4.35]:
		for x in [-0.9, 0.9]:
			var lamp := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.35, 0.22, 0.12)
			lamp.mesh = lb
			lamp.material_override = _mat(Color(0.9, 0.6, 0.0), true)
			lamp.position = Vector3(x, 2.55, z)
			body.add_child(lamp)
			_lamps.append(lamp)
	# Räder.
	for z in [-3.0, 3.0]:
		for x in [-1.15, 1.15]:
			var tyre := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.18
			torus.outer_radius = 0.42
			tyre.mesh = torus
			tyre.material_override = _mat(Color(0.06, 0.06, 0.07))
			tyre.rotation_degrees = Vector3(0, 0, 90)
			tyre.position = Vector3(x, 0.42, z)
			body.add_child(tyre)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.emission_enabled = true
		m.emission = c
	return m


func _physics_process(delta: float) -> void:
	# Halt-Wechsel: ~22 s mit Warnblinker, ~18 s Pause — wie ein Bus,
	# der Schüler ein- und aussteigen lässt und dann weiterfährt.
	_t -= delta
	if _t <= 0.0:
		hazards_on = not hazards_on
		_t = 22.0 if hazards_on else 18.0
		if hazards_on:
			_board_passengers()
	_phase += delta
	var glow := hazards_on and fmod(_phase, 0.7) < 0.35
	for lamp in _lamps:
		var m: StandardMaterial3D = lamp.material_override
		m.emission_energy_multiplier = 4.0 if glow else 0.0
	# Fahrgaeste laufen zwischen Bordstein und Bustuer hin und her.
	var gone: Array = []
	for p in _peds:
		var nd: Node3D = p["node"]
		if not is_instance_valid(nd):
			gone.append(p)
			continue
		p["t"] = float(p["t"]) + delta / 4.5
		nd.global_position = p["a"].lerp(p["b"], minf(float(p["t"]), 1.0))
		if float(p["t"]) >= 1.25:
			nd.queue_free()
			gone.append(p)
	for p in gone:
		_peds.erase(p)


## Bei jedem Halt: zwei Schueler steigen aus (Bus -> Bordstein) und
## einer steigt ein (Bordstein -> Bustuer). Die Tuer zeigt zum
## suedlichen Gehweg der Schulstrasse.
func _board_passengers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base := global_position
	for i in 2:
		var a := base + Vector3(rng.randf_range(-2.5, 2.5), 0.0, 1.9)
		var b := Vector3(a.x + rng.randf_range(-4.0, 4.0), 0.0, -172.8)
		_add_figure(a, b)
	var a_in := base + Vector3(rng.randf_range(-5.0, 5.0), 0.0, 4.8)
	_add_figure(Vector3(a_in.x, 0.0, -172.8),
		base + Vector3(0.0, 0.0, 1.9))


func _add_figure(a: Vector3, b: Vector3) -> void:
	var f := Node3D.new()
	var body := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = 0.16
	c.height = 0.75
	body.mesh = c
	body.position.y = 0.55
	body.material_override = _mat(Color(randf_range(0.25, 0.85),
		randf_range(0.2, 0.6), randf_range(0.5, 0.9)))
	f.add_child(body)
	add_child(f)
	f.global_position = a
	_peds.append({"node": f, "a": a, "b": b, "t": 0.0})
