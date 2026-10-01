extends Node3D
## Bahnübergang auf der Ring-Ost-Straße (x = 240, Gleise bei z = -150 in
## x-Richtung). Zyklus: Ruhe -> Warnblinken + Schranken senken -> Zug
## durch -> Schranken heben. is_closed() sagt, wann der Schueler nicht
## mehr drauffahren darf.

const SPEED := 24.0            ## Zugtempo m/s
const WARN_TIME := 7.0         ## so viele Sekunden vorher geht's los
const BARRIER_T := 3.0         ## Senk-/Hebezeit der Schranken
const TRAIN_BACK := 46.0       ## x hinter dem Kreuzpunkt: Zug ist durch
const IDLE_MIN := 16.0
const IDLE_MAX := 42.0
const RAIL_X0 := -130.0        ## lokale x-Grenzen der Gleisanlage
const RAIL_X1 := 130.0

var center := Vector2(240.0, -150.0)
var _phase := "idle"           ## idle | warn | open
var _t := 10.0                 ## idle: Sekunden bis zum naechsten Zug
var _tx: float = -1e4          ## lokale x des Zugs (0 = Kreuzung)
var _barrier_a := 0.0          ## 0 = offen, 1 = unten
var _blink_t := 0.0
var _arms: Array = []          ## {pivot, dir} — Schrankenarme
var _lamps: Array = []         ## Blinklichter
var _train: AnimatableBody3D


func _ready() -> void:
	position = Vector3(center.x, 0.0, center.y)
	_build()


func is_closed() -> bool:
	return _barrier_a > 0.5 or (_phase == "warn" and _tx > -SPEED * 3.0) or absf(_tx) < 26.0


func is_warning() -> bool:
	return _phase != "idle"


func _physics_process(delta: float) -> void:
	match _phase:
		"idle":
			_t -= delta
			if _t <= 0.0:
				_phase = "warn"
				_tx = -SPEED * WARN_TIME   ## Zug taucht auf den Gleisen auf
				_blink_t = 0.0
		"warn":
			_blink_t += delta
			_tx += SPEED * delta
			_barrier_a = minf(1.0, _barrier_a + delta / BARRIER_T)
			if _tx > TRAIN_BACK:
				_phase = "open"
		"open":
			_blink_t += delta
			_barrier_a = maxf(0.0, _barrier_a - delta / BARRIER_T)
			if _barrier_a <= 0.0:
				_phase = "idle"
				_t = IDLE_MIN + randf() * (IDLE_MAX - IDLE_MIN)
				_tx = -1e4
	_update_visuals()


func _update_visuals() -> void:
	for a in _arms:
		a["pivot"].rotation_degrees.z = a["dir"] * 68.0 * _barrier_a
	if _train:
		_train.global_transform.origin = Vector3(center.x + _tx, 0.0, center.y)
	var lamp_on: bool = is_warning() and fmod(_blink_t, 1.0) < 0.5
	for lamp in _lamps:
		lamp.material_override.emission_energy_multiplier = 3.2 if lamp_on else 0.04


func _m(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	var steel := _m(Color(0.32, 0.33, 0.35), 0.4, 0.7)
	var dark := _m(Color(0.16, 0.15, 0.14))
	var white := _m(Color(0.95, 0.95, 0.93))
	var red := _m(Color(0.80, 0.08, 0.08))

	# Schotterbett + Schwellen + zwei Schienen in x-Richtung.
	_box(Vector3(RAIL_X1 - RAIL_X0, 0.06, 4.6), Vector3((RAIL_X0 + RAIL_X1) * 0.5, 0.04, 0), dark)
	for x in range(int(RAIL_X0), int(RAIL_X1), 3):
		_box(Vector3(0.34, 0.05, 2.1), Vector3(float(x), 0.08, 0), _m(Color(0.20, 0.16, 0.12)))
	for rz in [-0.78, 0.78]:
		_box(Vector3(RAIL_X1 - RAIL_X0, 0.07, 0.08), Vector3((RAIL_X0 + RAIL_X1) * 0.5, 0.13, rz), steel)

	# Andreaskreuze: Suedanfahrt auf der Ostseite, Nordanfahrt auf der
	# Westseite — jeweils vor der Querung, knapp neben dem Fahrbahnrand.
	_andreaskreuz(Vector3(3.6, 0, 9.0), red, white)
	_andreaskreuz(Vector3(-3.6, 0, -9.0), red, white)

	# Schranken: Suedseite-Arm von Osten nach Westen (-x), Nordseite
	# von Westen nach Osten (+x) — jede sperrt nur die Einfahrspur.
	_barrier(Vector3(3.7, 0, 6.0), -1.0, red, white)
	_barrier(Vector3(-3.7, 0, -6.0), 1.0, red, white)

	# Zug: Triebwagen + zwei Wagen, AnimatableBody3D damit er den
	# Schueler auf den Gleisen wirklich wegschiebt.
	_train = AnimatableBody3D.new()
	_train.name = "Train"
	add_child(_train)
	var tcol := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(52.0, 3.6, 3.0)
	tcol.shape = tbox
	tcol.position = Vector3(14.0, 1.9, 0.0)
	_train.add_child(tcol)
	var paint := _m(Color(0.62, 0.10, 0.09), 0.6)
	var roof := _m(Color(0.10, 0.10, 0.12))
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.95, 0.9, 0.6)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.95, 0.75)
	lamp_mat.emission_energy_multiplier = 2.5
	var offs := [12.0, -2.0, -16.0]
	for i in range(3):
		_box(Vector3(11.5, 2.9, 2.9), Vector3(offs[i], 1.85, 0), paint, _train)
		_box(Vector3(11.9, 0.25, 3.0), Vector3(offs[i], 3.45, 0), roof, _train)
	# Stirnlicht vorn (+x ist die Fahrtrichtung).
	_box(Vector3(0.1, 0.4, 1.4), Vector3(18.0, 1.2, 0), lamp_mat, _train)
	_update_visuals()


func _andreaskreuz(pos: Vector3, red: Material, white: Material) -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.045
	pm.height = 1.7
	post.mesh = pm
	post.material_override = _m(Color(0.4, 0.4, 0.42))
	post.position = pos + Vector3(0, 0.85, 0)
	add_child(post)
	var cross := Node3D.new()
	cross.position = pos + Vector3(0, 1.55, 0)
	add_child(cross)
	for ang in [45.0, -45.0]:
		var arm := Node3D.new()
		arm.rotation_degrees.z = ang
		cross.add_child(arm)
		_box(Vector3(0.86, 0.17, 0.025), Vector3.ZERO, white, arm)
		# Rote Endstreifen am Kreuzbalken.
		_box(Vector3(0.86, 0.035, 0.028), Vector3(0, 0.085, 0.004), red, arm)
		_box(Vector3(0.86, 0.035, 0.028), Vector3(0, -0.085, 0.004), red, arm)


func _barrier(pos: Vector3, dir: float, red: Material, white: Material) -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 1.0
	post.mesh = pm
	post.material_override = _m(Color(0.35, 0.35, 0.37))
	post.position = pos + Vector3(0, 0.5, 0)
	add_child(post)

	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, 0.92, 0)
	add_child(pivot)
	var arm := Node3D.new()
	pivot.add_child(arm)
	# Gestreifter Balken (rot/weiss), 3,4 m ueber die Einfahrspur.
	for i in range(6):
		var c := red if i % 2 == 0 else white
		_box(Vector3(0.57, 0.10, 0.05), Vector3(dir * (0.35 + i * 0.58), 0, 0), c, arm)
	_arms.append({"pivot": pivot, "dir": dir})

	# Blinklicht oben auf dem Schrankenpfosten.
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.09
	lm.height = 0.18
	lamp.mesh = lm
	var lm_mat := StandardMaterial3D.new()
	lm_mat.albedo_color = Color(0.5, 0.04, 0.04)
	lm_mat.emission_enabled = true
	lm_mat.emission = Color(1.0, 0.06, 0.04)
	lm_mat.emission_energy_multiplier = 0.04
	lamp.material_override = lm_mat
	lamp.position = pos + Vector3(0, 1.12, 0)
	add_child(lamp)
	_lamps.append(lamp)
