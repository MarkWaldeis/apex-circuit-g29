extends AnimatableBody3D
## Rettungswagen auf Alarmfahrt entlang der Hauptstrasse: ab und zu
## (alle ~2,5 Min) oder wenn der Fahrlehrer alert() ruft. Faehrt den
## Hauptstrassen-Korridor einmal ostwaerts und zurueck, mit
## Blaulichtblitz und Martinshorn. Naehert sich der Schueler ohne
## Platz zu machen, kriecht der Wagen hinterher — der Fahrlehrer
## bewertet das Reagieren als Aufgabe "rettung".

const DEPOT := Vector2(-186.0, -70.0)   ## Parkposition neben der Zufahrt
const RUN := [
	Vector2(-180.0, -62.0),   # aus dem Depot auf die Hauptstrasse West
	Vector2(-170.0, -58.4),   # Spur Richtung Ost
	Vector2(160.0, -58.4),
	Vector2(168.0, -61.8),    # Wende auf die Westspur
	Vector2(-170.0, -61.8),
	Vector2(-182.0, -64.0),   # zurueck ins Depot
]
const CRUISE := 17.0          ## ~61 km/h im Einsatz
const ACCEL := 5.0
const IDLE_TIME := 150.0      ## Ruhezeit zwischen zwei Alarmfahrten

var player
var alarm := false            ## Alarmfahrt aktiv (Blaulicht, Sirene)
var speed_ms := 0.0

var _i := 0
var _idle := 40.0             ## erste Alarmfahrt recht bald
var _lamp_red
var _lamp_blue
var _lamp_phase := 0.0
var _siren_player
var _siren_gen
var _siren_phase := 0.0
var _siren_hi := false
var _siren_t := 0.0


func setup(p_player) -> void:
	player = p_player
	global_position = Vector3(DEPOT.x, 0.0, DEPOT.y)
	_build_mesh()
	_siren_player = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_siren_player.stream = gen
	_siren_player.unit_size = 8.0
	_siren_player.max_distance = 140.0
	add_child(_siren_player)
	_siren_player.play()
	_siren_gen = _siren_player.get_stream_playback()


func _build_mesh() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.94, 0.95)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.9, 2.15, 5.1)
	body.mesh = box
	body.material_override = white
	body.position = Vector3(0, 1.25, 0)
	add_child(body)
	# Roter Laengsstreifen und weisses Kreuz vorn.
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.8, 0.05, 0.05)
	var stripe := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(1.95, 0.35, 5.12)
	stripe.mesh = sbox
	stripe.material_override = red
	stripe.position = Vector3(0, 1.7, 0)
	add_child(stripe)
	var cross_v := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(0.22, 1.0, 0.06)
	cross_v.mesh = cbox
	cross_v.material_override = red
	cross_v.position = Vector3(0, 1.25, 2.56)
	add_child(cross_v)
	var cross_h := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(1.0, 0.22, 0.06)
	cross_h.mesh = hbox
	cross_h.material_override = red
	cross_h.position = Vector3(0, 1.25, 2.56)
	add_child(cross_h)
	# Leuchtbalken: rote und blaue Kammer, blinken im Wechsel.
	var bar := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(1.5, 0.14, 0.5)
	bar.mesh = bbox
	bar.position = Vector3(0, 2.42, -0.6)
	add_child(bar)
	_lamp_red = _lamp(Vector3(-0.4, 2.55, -0.6), Color(1.0, 0.1, 0.1))
	_lamp_blue = _lamp(Vector3(0.4, 2.55, -0.6), Color(0.2, 0.4, 1.0))


func _lamp(off: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.5, 0.16, 0.4)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	mi.material_override = m
	mi.position = off
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if not alarm:
		_idle -= delta
		if _idle <= 0.0:
			alert()
		return
	# Alarmfahrt: dem Wegpunkten folgen, beim Schueler warten.
	var target: Vector2 = RUN[_i]
	var p2 := Vector2(global_position.x, global_position.z)
	var to: Vector2 = target - p2
	var dist := to.length()
	var wish := CRUISE
	if player:
		var dp := global_position.distance_to(player.global_position)
		var pv: float = player.linear_velocity.length()
		# Bleibt der Schueler auf der Spur stehen, wartet der Wagen auf 7 m.
		if dp < 11.0 and pv < 1.0:
			wish = 0.0
		elif dp < 16.0 and pv < wish:
			wish = maxf(pv, 2.5)
	speed_ms = move_toward(speed_ms, wish, ACCEL * delta)
	if dist < 4.0:
		_i += 1
		if _i >= RUN.size():
			_finish()
			return
		target = RUN[_i]
		to = target - p2
	if to.length() > 0.1:
		var dir: Vector2 = to.normalized()
		global_position += Vector3(dir.x, 0.0, dir.y) * speed_ms * delta
		var yaw := atan2(dir.x, dir.y)
		rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))
	_lamps(delta)
	_siren(delta)


func _lamps(delta: float) -> void:
	_lamp_phase += delta * 7.0
	var on := int(_lamp_phase) % 2 == 0
	for lamp in [_lamp_red, _lamp_blue]:
		var m: StandardMaterial3D = lamp.material_override
		m.emission_energy_multiplier = 3.5 if (lamp == _lamp_red) == on else 0.05


func _siren(delta: float) -> void:
	_siren_t += delta
	if _siren_t > 0.55:
		_siren_t = 0.0
		_siren_hi = not _siren_hi
	var freq := 720.0 if _siren_hi else 520.0
	var frames: int = _siren_gen.get_frames_available()
	for _n in range(frames):
		_siren_phase += freq / 22050.0
		var s := sin(_siren_phase * TAU) * 0.22
		_siren_gen.push_frame(Vector2(s, s))


func alert() -> void:
	if alarm:
		return
	alarm = true
	_i = 0
	_idle = IDLE_TIME


func _finish() -> void:
	alarm = false
	speed_ms = 0.0
	_i = 0
	global_position = Vector3(DEPOT.x, 0.0, DEPOT.y)
	rotation.y = 0.0
	for lamp in [_lamp_red, _lamp_blue]:
		var m: StandardMaterial3D = lamp.material_override
		m.emission_energy_multiplier = 0.05
