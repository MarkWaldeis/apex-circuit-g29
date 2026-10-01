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
## Route A: Blockrunde Schul-/West-/Haupt-/Oststraße.
const ROUTE_A := [
	Vector2(96.0, -181.8),    # 0 Schulstraße, Richtung West
	Vector2(-94.0, -181.8),   # 1
	Vector2(-101.8, -174.0),  # 2 Kurve Weststraße Nord
	Vector2(-101.8, -64.0),   # 3 Weststraße, Richtung Süd
	Vector2(-94.0, -58.2),    # 4 Kurve Hauptstraße West
	Vector2(90.0, -58.2),     # 5 Hauptstraße, Richtung Ost
	Vector2(101.8, -66.0),    # 6 Kurve Oststraße Süd
	Vector2(101.8, -174.0),   # 7 Oststraße, Richtung Nord -> Kurve zu 0
]
const CORNERS_A := [2, 4, 6, 0]   ## Ziel-Indizes, vor denen abgebremst wird
## Blinken nicht an Index 0: dort biegt die Vorfahrtstrasse ab (Ost-
## Sued -> Schul-West, VZ 306) — dem Knick folgt man OHNE Blinker.
const BLINK_A := [2, 4, 6]

## Route B: Kreisverkehr-Schleife — Südarm rein, Ostarm raus, ueber die
## Ring-Ost-Diagonale zurueck in die Suedstrasse. Lerneffekt: wer in den
## Kreis einfaehrt, muss dem Fahrzeug IM Ring Vorfahrt gewaehren.
const ROUTE_B := [
	Vector2(206.0, -30.0),    # 0 Suedstrasse Richtung Kreis
	Vector2(200.0, -40.0),    # 1 Suedarm-Einfahrt
	Vector2(199.0, -50.0),    # 2 Ring-Einfahrt Sued (Vorfahrt wartet)
	Vector2(204.5, -51.0),    # 3 Ring Suedviertel Richtung Ost
	Vector2(211.0, -58.0),    # 4 Ring Ost
	Vector2(217.0, -60.0),    # 5 Ausfahrt Ostarm
	Vector2(230.0, -58.4),    # 6 Ostarm Ausfahrt
	Vector2(240.0, -60.0),    # 7 Ecke Ostarm -> Ring Ost Diagonale
	Vector2(224.0, -32.0),    # 8 Diagonale Ring Ost -> Suedstrasse
	Vector2(213.0, -26.0),    # 9 Suedstrasse zurueck
]
const CORNERS_B := [2, 5, 7]
## Blink-Lite ohne Ring-EINFahrt (Index 2): ins Rondell wird per
## Regel NICHT geblinkt — erst die Ausfahrt (5) blinkt rechts.
const BLINK_B := [5, 7]

## Route C: ueber den Kreis zur Kreis-Nordstrasse, dort durch die
## Engstelle zwischen den parkenden Autos, wenden und zurueck.
## Lerneffekt: wer auf der blockierten Seite ankommt (Nordwaerts),
## muss dem Gegenverkehr in der Luecke Vorrang lassen (VZ 208).
const ROUTE_C := [
	Vector2(207.0, -28.0),    # 0  Suedstrasse Richtung Kreis
	Vector2(200.0, -40.0),    # 1  Suedarm-Einfahrt
	Vector2(199.0, -50.0),    # 2  Ring-Einfahrt Sued (Vorfahrt wartet)
	Vector2(204.5, -51.0),    # 3  Ring Suedviertel
	Vector2(211.0, -58.0),    # 4  Ring Ostviertel
	Vector2(215.5, -64.0),    # 5
	Vector2(212.0, -70.0),    # 6  Ring Nordostviertel
	Vector2(205.0, -74.5),    # 7
	Vector2(200.0, -80.0),    # 8  Nordarm Ausfahrt
	Vector2(201.6, -95.0),    # 9  eigene Nordspur vor der Engstelle
	Vector2(198.4, -106.0),   # 10 in die Luecke einscheren
	Vector2(198.5, -134.0),   # 11 Nordende
	Vector2(201.0, -139.0),   # 12 Wende am Ende
	Vector2(199.0, -134.5),   # 13
	Vector2(198.2, -100.0),   # 14 zurueck suedwaerts (freie Spur)
	Vector2(200.0, -79.0),    # 15 Nordarm Einfahrt (Vorfahrt wartet)
	Vector2(196.5, -73.0),    # 16 Ring Nordwestviertel
	Vector2(189.0, -66.0),    # 17
	Vector2(184.5, -60.0),    # 18 Ring West
	Vector2(189.0, -54.0),    # 19
	Vector2(196.0, -50.5),    # 20 Ring Suedwest
	Vector2(200.0, -45.5),    # 21 Suedarm Ausfahrt
	Vector2(207.0, -30.0),    # 22 Suedstrasse -> Schleife
]
const CORNERS_C := [2, 8, 12, 15, 21]
## Blinken nur bei den Kreis-AUSfahrten (8, 21) und der Wende (12) —
## die Einfahrten (2, 15) sind blinkfrei.
const BLINK_C := [8, 12, 21]

## Route D: grosse Ring-Runde im Uhrzeigersinn (Ost -> Nord -> West
## -> Sued). Auf dem 100er-Ring zieht der Lkw mit ~40 km/h seine
## Runde — der Schueler bekommt einen echten Ueberhol-Anlass.
const ROUTE_D := [
	Vector2(241.5, -40.0),    # 0  Ring Ost nordwaerts
	Vector2(241.5, -228.0),   # 1
	Vector2(234.0, -241.0),   # 2  Kurve Nord-Ost
	Vector2(120.0, -241.5),   # 3  Ring Nord westwaerts
	Vector2(-230.0, -241.5),  # 4
	Vector2(-241.0, -234.0),  # 5  Kurve Nord-West
	Vector2(-241.5, -120.0),  # 6  Ring West suedwaerts
	Vector2(-241.5, 130.0),   # 7
	Vector2(-234.0, 141.0),   # 8  Kurve West-Sued
	Vector2(-120.0, 141.5),   # 9  Ring Sued ostwaerts
	Vector2(230.0, 141.5),    # 10
	Vector2(241.0, 134.0),    # 11 Kurve Sued-Ost
	Vector2(241.5, 0.0),      # 12 Ost zurueck -> Schleife
]
const CORNERS_D := [2, 5, 8, 11]
const CRUISE := 8.3                    ## ~30 km/h
const CORNER_V := 3.5
const ACCEL := 6.0

## Stoppschild Ostseite der Kreuzung (100,-60) fuer Ost-Richtung.
const STOP_POS := Vector2(92.0, -58.2)
const STOP_WAIT := 1.2

## Ampel-Check achsneutral: Arm-Achse ueber die Fahrtrichtung gewaehlt,
## Abstand zur Kreuzungsmitte entscheidet ueber das Halten.

var lights
var player
var speed_ms: float = 0.0

var _i: int = 0                  ## Index des aktuellen Ziel-Wegpunkts
var _stop_left: float = 0.0      ## verbleibende Haltezeit am Stoppschild
var _stop_done: bool = false     ## Stoppschild diese Runde schon bedient
var pedestrians: Array = []    ## Fussgaenger, vor denen man anhaelt
var _brake_lamps: Array = []   ## Rueckleuchten-Meshs (gemeinsames Material)
var _ind_lamps := {"l": [], "r": []}  ## Blinker-Lampen links/rechts
var _ind_side := 0             ## -1 links, +1 rechts, 0 aus
var _ind_hold := 0.0           ## Nachlaufzeit des Blinkers
var _blink_t := 0.0
var _path: Array = ROUTE_A
var _corners: Array = CORNERS_A
var truck := false           ## Lkw-Mesh + langsames Reisetempo
var cruise := CRUISE
var _blink: Array = BLINK_A
var _oneshot := false         ## freier Kurs: am Ende verschwindet das Auto
var ttl := -1.0               ## Sekunden bis zum Despawn (<0 = unbegrenzt)
var night := false            ## Welt setzt es — Scheinwerfer gluehen
var _head_mat: StandardMaterial3D
var _horn_player: AudioStreamPlayer3D
var _horn_gen                ## AudioStreamGeneratorPlayback
var _horn_left: float = 0.0  ## restliche Horn-Samples
var _horn_phase: float = 0.0
var _horn_cd: float = 0.0


func setup(p_lights, p_player, start_i: int = 0, route: int = 0,
		path: Array = []) -> void:
	lights = p_lights
	player = p_player
	if route < 0:
		# Freier Kurs (z. B. RvL-Training): einmal abfahren, dann weg.
		_path = path
		_corners = []
		_blink = []
		_oneshot = true
	elif route == 1:
		_path = ROUTE_B
		_corners = CORNERS_B
		_blink = BLINK_B
	elif route == 2:
		_path = ROUTE_C
		_corners = CORNERS_C
		_blink = BLINK_C
	elif route == 3:
		_path = ROUTE_D
		_corners = CORNERS_D
		_blink = CORNERS_D
		truck = true
		cruise = 11.0           ## Lkw schleicht mit ~40 km/h
	_i = start_i % _path.size()
	var from: Vector2 = _path[(_i - 1 + _path.size()) % _path.size()]
	var to: Vector2 = _path[_i]
	var dir := (to - from).normalized()
	global_transform = Transform3D(_basis_to(dir), Vector3(from.x, 0.0, from.y))
	_build_mesh()
	_build_horn()


## Lkw-Aufbau: Zugmaschine + Kofferauflieger, damit der Schueler
## auf dem Ring von weitem sieht: hier lohnt ein Ueberholvorgang.
func _build_truck_mesh() -> void:
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.62, 0.64, 0.67)
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color(0.15, 0.35, 0.6)
	var cab := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(2.3, 1.9, 2.2)
	cab.mesh = cb
	cab.material_override = cab_mat
	cab.position = Vector3(0.0, 1.5, 3.0)
	add_child(cab)
	var box := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.5, 2.7, 6.0)
	box.mesh = bb
	box.material_override = grey
	box.position = Vector3(0.0, 1.75, -1.2)
	add_child(box)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.05)
	for wz in [2.9, -0.2, -3.4]:
		for wx in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.45
			wm.bottom_radius = 0.45
			wm.height = 0.3
			w.mesh = wm
			w.material_override = wheel_mat
			w.rotation.z = PI / 2.0
			w.position = Vector3(wx, 0.45, wz)
			add_child(w)

	# Leuchten am Lkw: Scheinwerfer an der Fahrerhaus-Front (z≈4.15),
	# Rueckleuchten am Koffer-Heck (z≈-4.25).
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.85, 0.85, 0.78)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.98, 0.82)
	_head_mat.emission_energy_multiplier = 0.15
	for hx in [-0.85, 0.85]:
		var hl := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.45, 0.20, 0.06)
		hl.mesh = hm
		hl.material_override = _head_mat
		hl.position = Vector3(hx, 0.75, 4.15)
		add_child(hl)
	var tlamp := StandardMaterial3D.new()
	tlamp.albedo_color = Color(0.30, 0.03, 0.03)
	tlamp.emission_enabled = true
	tlamp.emission = Color(1.0, 0.05, 0.03)
	tlamp.emission_energy_multiplier = 0.05
	for tx in [-0.95, 0.95]:
		var tl := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.30, 0.35, 0.06)
		tl.mesh = tm
		tl.material_override = tlamp
		tl.position = Vector3(tx, 0.85, -4.25)
		add_child(tl)
		_brake_lamps.append(tl)


## Hupe: zweigestrichener Zweiklang wie beim Schulauto — die KI
## warnt hoerbar, wenn der Schueler gefaehrlich dicht reinzieht.
func _build_horn() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.3
	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.stream = stream
	_horn_player.unit_size = 9.0
	_horn_player.max_distance = 90.0
	add_child(_horn_player)
	_horn_player.play()
	_horn_gen = _horn_player.get_stream_playback()


func _process(delta: float) -> void:
	_horn_cd = maxf(_horn_cd - delta, 0.0)
	if _horn_gen == null:
		return
	var frames := int(_horn_gen.get_frames_available())
	for i in range(frames):
		var s := 0.0
		if _horn_left > 0.0:
			_horn_left -= 1.0
			_horn_phase += 1.0
			s = (sin(TAU * _horn_phase * 0.0177) \
				+ sin(TAU * _horn_phase * 0.023)) * 0.22
		_horn_gen.push_frame(Vector2(s, s))


func _basis_to(dir: Vector2) -> Basis:
	# Wagen-Nase zeigt +Z: looking_at(-d) dreht +Z auf d.
	return Basis.looking_at(Vector3(-dir.x, 0.0, -dir.y), Vector3.UP)


func _physics_process(delta: float) -> void:
	_stop_left = maxf(_stop_left - delta, 0.0)
	if ttl > 0.0:
		ttl -= delta
		if ttl <= 0.0:
			# Timeout-Despawn: ein Trainer, der nicht durchkommt,
			# duerfte den Verkehr nicht ewig blockieren.
			queue_free()
			return
	var pos := Vector2(global_position.x, global_position.z)
	var target: Vector2 = _path[_i]
	var to := target - pos
	var dist := to.length()
	if dist < 1.4:
		if _oneshot and _i == _path.size() - 1:
			queue_free()
			return
		_i = (_i + 1) % _path.size()
		return
	var dir := to.normalized()

	var v := cruise
	if dist < 16.0 and _i in _corners:
		v = CORNER_V
	v = _apply_rules(pos, dir, v)

	# Blinker: vor Abbiege-Wegpunkten in die Abbiegerichtung blinken —
	# der Schueler sieht die Absicht des Gegenverkehrs wie im echten Leben.
	_blink_t += delta
	if dist < 22.0 and _i in _blink and _path.size() > 1:
		var dn: Vector2 = (_path[(_i + 1) % _path.size()] - _path[_i]).normalized()
		var turn: float = dir.x * dn.y - dir.y * dn.x   ## >0 rechts, <0 links
		_ind_side = 1 if turn > 0.05 else (-1 if turn < -0.05 else 0)
		_ind_hold = 2.6
	elif _ind_hold > 0.0:
		_ind_hold -= delta
	else:
		_ind_side = 0
	var blink_on: bool = fmod(_blink_t, 0.8) < 0.42
	for l in _ind_lamps["l"]:
		l.visible = blink_on and _ind_side < 0
	for l in _ind_lamps["r"]:
		l.visible = blink_on and _ind_side > 0

	var accel := ACCEL if v > speed_ms else ACCEL * 2.2
	speed_ms = move_toward(speed_ms, v, accel * delta)
	# Bremslichter: an, sobald die KI bremst oder (fuer Regeln) steht.
	if not _brake_lamps.is_empty():
		var on := v < speed_ms - 0.05 or speed_ms < 0.05
		_brake_lamps[0].material_override.emission_energy_multiplier = 3.0 if on else 0.05
	if _head_mat:
		_head_mat.emission_energy_multiplier = 2.6 if night else 0.15
	pos += dir * speed_ms * delta
	# Eine einzige Transform-Zuweisung: global_position lesen liefert im
	# selben Physik-Tick noch den alten Wert und wuerde den Schritt ruecksetzen.
	global_transform = Transform3D(_basis_to(dir), Vector3(pos.x, 0.0, pos.y))


func _apply_rules(pos: Vector2, dir: Vector2, v: float) -> float:
	# Ampel: gilt fuer beide Fahrbahnachsen — Ost/West (a) und
	# Nord/Sued (b) — in jeder Fahrtrichtung, solange die Kreuzung voraus liegt.
	if lights:
		var j: Dictionary = CityLayout.junctions()["ampel"]
		var c: Vector2 = j["center"]
		var d_j := pos.distance_to(c)
		if d_j < 9.0 and d_j > 1.5 and (c - pos).normalized().dot(dir) > 0.8:
			if absf(dir.x) > 0.9 and String(lights.phase_of("a")) != "green":
				v = 0.0
			elif absf(dir.y) > 0.9 and String(lights.phase_of("b")) != "green":
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
		# Gefaehrliches Reinziehen: der KI-Fahrer hupt und bremst.
		if ahead > 0.0 and ahead < 7.0 and side < 2.8 \
				and speed_ms > 4.5 and _horn_cd <= 0.0:
			_horn_left = 15000.0
			_horn_cd = 7.0
	# Fussgaenger auf der Querung: Vorrang, wie es die StVO verlangt.
	for pd in pedestrians:
		if not is_instance_valid(pd):
			continue
		var pp := Vector2(pd.global_position.x, pd.global_position.z)
		var rel2 := pp - pos
		var ahead2 := rel2.dot(dir)
		var side2 := absf(rel2.dot(Vector2(-dir.y, dir.x)))
		# Auf der Fahrbahn querend: bis 13 m voraus halten.
		if bool(pd.call("on_road")) and ahead2 > 0.0 and ahead2 < 13.0 and side2 < 3.4:
			v = 0.0
		# Am Bordstein wartend: rechtzeitig bremsen — er darf losgehen.
		elif not bool(pd.get("_walking")) and ahead2 > 0.0 and ahead2 < 16.0 and side2 < 5.5:
			v = 0.0
	v = _yield_check(pos, dir, v)
	v = _engstelle_check(pos, dir, v)
	return v


# Engstelle auf der Kreis-Nordstrasse: die parkenden Autos stehen auf
# der Ostspur — die Nordfahrt (blockierte Seite, VZ 208) laesst den
# Suedverkehr erst durch die Luecke.
func _engstelle_check(pos: Vector2, dir: Vector2, v: float) -> float:
	if player == null or dir.y > -0.5:
		return v
	# Nur nordwaerts auf der Engstellen-Zufahrt aktiv.
	if pos.x < 192.0 or pos.x > 208.0 or pos.y < -106.0 or pos.y > -95.0:
		return v
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var p_lv = player.get("linear_velocity")
	if p_lv == null:
		return v
	var pv := Vector2(p_lv.x, p_lv.z)
	# Spieler in der Luecke oder suedwaerts darauf zurollend.
	var in_gap := p2.x > 194.0 and p2.x < 206.0 \
		and p2.y > -120.0 and p2.y < -101.0
	var coming := p2.y > -145.0 and p2.y < -100.0 and pv.y > 0.8 \
		and p2.x > 192.0 and p2.x < 208.0
	if in_gap or coming:
		# Vor der Luecke (Suedkante z=-101) zum Stehen kommen.
		if pos.y > -101.0:
			v = minf(v, maxf(0.0, (-101.0 - pos.y) * 0.8))
		else:
			v = 0.0
	return v


# Vorfahrt: kommt das Auto auf eine Kreuzung zu, auf der der Schueler
# wartet oder gerade quert, entscheidet die Regel wer faehrt — sonst
# lernt niemand, dass Gegenverkehr auch mal warten muss.
func _yield_check(pos: Vector2, dir: Vector2, v: float) -> float:
	if player == null:
		return v
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var p_lv = player.get("linear_velocity")
	var p_spd := 0.0
	if p_lv != null:
		p_spd = Vector2(p_lv.x, p_lv.z).length()
	for j in CityLayout.junctions().values():
		var kind := String(j["kind"])
		if kind != "rbl" and kind != "yield" and kind != "stop" and kind != "roundabout":
			continue
		var c: Vector2 = j["center"]
		var d_ai := pos.distance_to(c)
		if d_ai > 24.0 or d_ai < 1.5:
			continue
		if (c - pos).normalized().dot(dir) < 0.6:
			continue
		var d_p := p2.distance_to(c)
		if d_p > 16.5:
			continue
		if not _student_has_priority(j, p2, p_spd, dir):
			continue
		# Vorfahrt des Schuelers: langsam ran, dicht dran anhalten.
		# Am Kreisverkehr muss die KI VOR der Ringkante (r=16) stehen —
		# bei 9 m waere sie schon auf der Kreisbahn.
		var stop_d := 16.5 if kind == "roundabout" else 9.0
		v = 0.0 if d_ai < stop_d else minf(v, 3.0)
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
		var on_yield_arm: bool = bool(ai_arm.get("yield", false)) and ai_best < 7.0 and dir.normalized().dot(e.normalized()) > 0.6
		return on_yield_arm
	if String(j["kind"]) == "stop":
		# Vorfahrt hat der Schueler erst, wenn er die Haltelinie
		# ueberfahren hat und im Knoten quert (Linien liegen 7,6 m
		# vor dem Zentrum) — ein korrekt wartender Schueler soll
		# den Vorfahrtsverkehr nicht aufhalten.
		return p2.distance_to(c) < 5.8
	if String(j["kind"]) == "roundabout":
		# Wer IM Ring faehrt, hat Vorfahrt vor der Einfahrt.
		return p2.distance_to(c) < 13.5
	# rbl: der Schueler faehrt uns von rechts rein.
	var right := Vector2(-dir.y, dir.x)
	var e: Vector2 = p_arm["enter"]
	return e.normalized().dot(-right) > 0.45


func _build_mesh() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if truck:
		box.size = Vector3(2.4, 2.9, 8.4)
		col.position = Vector3(0.0, 1.5, 0.0)
	else:
		box.size = Vector3(1.8, 1.25, 4.3)
		col.position = Vector3(0.0, 0.75, 0.0)
	col.shape = box
	add_child(col)

	if truck:
		_build_truck_mesh()
		return

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

	# Bremslichter: Front zeigt +z, also sitzen die Leuchten hinten (-z).
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.30, 0.03, 0.03)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.05, 0.03)
	lamp_mat.emission_energy_multiplier = 0.05
	for lx in [-0.62, 0.62]:
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.42, 0.16, 0.06)
		lamp.mesh = lm
		lamp.material_override = lamp_mat
		lamp.position = Vector3(lx, 0.68, -2.12)
		add_child(lamp)
		_brake_lamps.append(lamp)

	# Scheinwerfer vorn (+z): bei Nacht gluehen sie weiss — der Schueler
	# sieht den Gegenverkehr wie im echten Leben aufleuchten.
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.85, 0.85, 0.78)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.98, 0.82)
	_head_mat.emission_energy_multiplier = 0.15
	for hx in [-0.62, 0.62]:
		var hl := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.40, 0.16, 0.06)
		hl.mesh = hm
		hl.material_override = _head_mat
		hl.position = Vector3(hx, 0.68, 2.12)
		add_child(hl)

	# Blinker: gelbe Eckleuchten vorn/hinten je Seite. Fahrtrichtung +z,
	# Fahrer-Links = +x, Fahrer-Rechts = -x.
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.95, 0.58, 0.06)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.55, 0.05)
	amber.emission_energy_multiplier = 2.2
	for sxp in [[0.84, "l"], [-0.84, "r"]]:
		for lz in [2.12, -2.12]:
			var il := MeshInstance3D.new()
			var im := BoxMesh.new()
			im.size = Vector3(0.30, 0.13, 0.06)
			il.mesh = im
			il.material_override = amber
			il.position = Vector3(sxp[0], 0.70, lz)
			il.visible = false
			add_child(il)
			_ind_lamps[sxp[1]].append(il)
