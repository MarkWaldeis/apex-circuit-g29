extends VehicleBody3D
## Das Fahrschulauto: Kompaktklasse mit Vorderradantrieb, H-Schaltung und
## echter Kupplung (h_gearbox.gd). Spiegelt die Schnittstelle von
## car_controller.gd, damit Menü (`player.has_method("_reset")`,
## `toggle_assists()`, `assists_label()`), HUD und Lenkrad-Feedback
## unverändert weiterlaufen.
##
## Eingaben: G29-Lenkrad/Pedale/Schalthebel über g29_input.gd, Tastatur wie
## im F1-Modus plus: 1–6 Gänge, N/0 Leerlauf, V Rückwärtsgang, Q/E Blinker,
## H Warnblinker, Leertaste Handbremse.

const CarMesh = preload("res://scripts/school/school_car_mesh.gd")
const HGearbox = preload("res://scripts/school/h_gearbox.gd")
const CityLayout = preload("res://scripts/school/city_layout.gd")
const WheelFeedback = preload("res://scripts/wheel_feedback.gd")
const FfbLink = preload("res://scripts/ffb_link.gd")

@export var max_steer: float = 0.62       ## Radwinkel am Lenkanschlag
@export var auto_drive: bool = false

const REST := 0.16
const BRAKE_MAX := 900.0                  ## Rad-Drehmoment gesamt
const HANDBRAKE_MAX := 1400.0             ## auf die Hinterachse
const VOID_Y := -6.0

## Zusatzbelegung der Lenkrad-Knöpfe (Treiber variieren — `last_button` in
## den Einstellungen zeigt, welcher physische Knopf gerade gedrückt wird).
var button_map := {"ind_left": 4, "ind_right": 5, "teleport": 6, "exam": 7,
	"hazard": 8, "handbrake": 9, "lights": 10, "reset": 11}

## Rueckverweis auf die Welt (fuer Pruefungs-Taste am Lenkrad); wird
## von school_world beim Aufbau gesetzt, bleibt in Tests null.
var world

var g29
var surfaces
var gearbox := HGearbox.new()
var feedback
var ffb
var ffb_settings

var speed_kmh: float = 0.0
var gear: int = 0
var rpm: float = 800.0
var last_steer: float = 0.0
var stalled: bool = false
var motor_on: bool = true
var handbrake_on: bool = false
var indicator_left: bool = false
var indicator_right: bool = false
var hazard: bool = false
var damage: float = 0.0
var surface_name: String = "Asphalt"
var assists := {"auto_gearbox": false, "traction_control": true, "clutch_assist": true}

var spawn_transform: Transform3D
var reset_count: int = 0
var stall_events: int = 0
var last_spot: String = ""             ## zuletzt angesteuerte Uebungsstation
var _spot_i: int = -1
var clutch_heat: float = 0.0              ## Lern-Feedback: zu lange schleifen
var brake_strength: float = 0.0           ## aktueller Fußbremse-Input 0..1

var _wheels: Array = []                   ## {vis, wheel, front, rear}
var _wheel_roll: float = 0.0
var _prev_vel := Vector3.ZERO
var _prev_vel_y: float = 0.0
var _prev_speed: float = 0.0
var _vert_ready: bool = false
var _vertical_g: float = 1.0
var _lateral_g: float = 0.0
var _auto_clutch_t: float = 0.0           ## Tastatur-Hilfskupplung beim Schalten
var _stall_note_t: float = 0.0
var _blink_t: float = 0.0
var _lamps: Dictionary = {}
var headlights_on := false
var _headlights: Array = []
var _last_impact_v: float = 0.0
var _last_impact_name: String = ""
var _prev_yaw: float = 0.0
var _ind_yaw: float = 0.0            ## seit Blinker-An akkumulierte Drehung
var _engine_player: AudioStreamPlayer3D
var _engine_gen: AudioStreamGeneratorPlayback
var _engine_phase: float = 0.0
var _click_gap: float = 0.0    ## Samples bis zum naechsten Blinker-Klack
var _click_left: float = 0.0   ## Samples im aktuellen Klack-Burst
var _horn_left: float = 0.0    ## verbleibende Horn-Samples (Taste B)
var _horn_phase: float = 0.0
var _pdc_gap: float = 0.0      ## Samples bis zum naechsten Parkpiep
var _pdc_left: float = 0.0     ## Samples im Piep-Burst
var _pdc_phase: float = 0.0
var _skid: float = 0.0         ## Schlupfpegel fuer Reifenquietschen


func setup(wheel_input, surface_model, start: Transform3D) -> void:
	g29 = wheel_input
	surfaces = surface_model
	spawn_transform = start
	mass = 1280.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.06, 0.12)   ## Motor vorne: leicht kopflastig
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_hit)
	_build_chassis()
	var mesh: Dictionary = CarMesh.build()
	add_child(mesh["root"])
	_lamps = {"brake": mesh["brake_l"], "bl": mesh["blinker_l"], "br": mesh["blinker_r"]}
	# Abblendlicht: zwei Strahler vorne (Taste L). Von vorn etwas
	# nach unten gerichtet, wie an einer echten Licht-Einstellplatte.
	for sx in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.spot_range = 26.0
		spot.spot_angle = 28.0
		spot.light_energy = 9.0
		spot.spot_attenuation = 0.9
		spot.position = Vector3(0.55 * sx, 0.62, 1.95)
		spot.basis = Basis.from_euler(Vector3(-0.38, PI, 0.0))
		spot.visible = false
		add_child(spot)
		_headlights.append(spot)
	_build_wheels(mesh["wheels"])
	# Motorsound: synthetisiert aus Drehzahl — 2-Takt-Grundton plus
	# Oberton, Lautstaerke folgt Gasstellung. Schueler lernen das
	# Schalten zum grossen Teil ubers Gehoer.
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.25
	_engine_player = AudioStreamPlayer3D.new()
	_engine_player.stream = stream
	_engine_player.unit_size = 6.0
	_engine_player.max_distance = 60.0
	add_child(_engine_player)
	_engine_player.play()
	_engine_gen = _engine_player.get_stream_playback()
	gearbox.setup()
	ffb = FfbLink.new()
	ffb.setup(ffb_settings, wheel_input)
	feedback = WheelFeedback.new()
	feedback.setup(self, wheel_input, ffb.model if ffb else null)
	global_transform = start
	if g29:
		if g29.has_signal("gear_changed") and not g29.gear_changed.is_connected(_on_wheel_gear):
			g29.gear_changed.connect(_on_wheel_gear)
		if g29.has_signal("button_pressed") and not g29.button_pressed.is_connected(_on_wheel_button):
			g29.button_pressed.connect(_on_wheel_button)


func _on_body_hit(_body: Node) -> void:
	# Blechschaden zählt erst bei echtem Tempo — ein leichtes Antippen
	# des Bordsteins bleibt rumble, wird aber nicht bewertet.
	var kmh := maxf(linear_velocity.length(), _prev_speed) * 3.6
	if kmh > 12.0:
		_last_impact_v = kmh
		_last_impact_name = _body.name
		if feedback:
			feedback.poke("bump", 0.8)


func _build_chassis() -> void:
	var col := CollisionShape3D.new()
	col.name = "Chassis"
	var box := BoxShape3D.new()
	box.size = Vector3(1.76, 1.15, 4.15)
	col.shape = box
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)


func _build_wheels(wheel_meshes: Dictionary) -> void:
	for key in CarMesh.HUBS.keys():
		var hub: Vector3 = CarMesh.HUBS[key]
		var is_front: bool = key.begins_with("F")
		var wheel := VehicleWheel3D.new()
		wheel.name = "Wheel_%s" % key
		wheel.position = hub + Vector3(0.0, REST, 0.0)
		wheel.use_as_steering = is_front
		wheel.use_as_traction = is_front        ## Vorderradantrieb
		wheel.wheel_radius = CarMesh.WHEEL_RADIUS
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.22
		wheel.suspension_stiffness = 34.0
		wheel.suspension_max_force = 26000.0
		wheel.damping_compression = 1.6
		wheel.damping_relaxation = 2.0
		wheel.wheel_friction_slip = 10.0
		wheel.wheel_roll_influence = 0.12
		add_child(wheel)
		var mesh: Node3D = wheel_meshes.get(key)
		var vis := Node3D.new()
		vis.name = "Vis_%s" % key
		vis.position = hub
		add_child(vis)
		if mesh != null:
			mesh.get_parent().remove_child(mesh)
			vis.add_child(mesh)
			mesh.position = Vector3.ZERO
		_wheels.append({"vis": vis, "wheel": wheel, "front": is_front, "key": key})


func _on_wheel_gear(g: int) -> void:
	# Der H-Schalthebel liefert direkt den Gang — Einlegen geht nur mit
	# genügend getretener Kupplung, sonst knirscht es (zählt der Fahrlehrer).
	var clutch_pedal: float = g29.clutch if g29 else 0.0
	if bool(assists.get("clutch_assist", true)) and (g29 == null or not g29.connected):
		clutch_pedal = 1.0
	var speed: float = linear_velocity.dot(global_transform.basis.z)
	if gearbox.request_gear(g, clutch_pedal, speed) and feedback:
		feedback.poke("shift", 0.3)


func _on_wheel_button(index: int) -> void:
	if index == int(button_map["ind_left"]):
		_toggle_indicator("l")
	elif index == int(button_map["ind_right"]):
		_toggle_indicator("r")
	elif index == int(button_map["teleport"]):
		_teleport_next()
	elif index == int(button_map["reset"]):
		_reset()
	elif index == int(button_map["exam"]):
		if world != null and world.get("instructor") != null:
			world.instructor.toggle_exam()
	elif index == int(button_map["hazard"]):
		hazard = not hazard
		if hazard:
			indicator_left = false
			indicator_right = false
	elif index == int(button_map["lights"]):
		_toggle_lights()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1: _kb_gear(1)
		KEY_2: _kb_gear(2)
		KEY_3: _kb_gear(3)
		KEY_4: _kb_gear(4)
		KEY_5: _kb_gear(5)
		KEY_6: _kb_gear(6)
		KEY_0, KEY_N: _kb_gear(0)
		KEY_V: _kb_gear(-1)
		KEY_Q: _toggle_indicator("l")
		KEY_E: _toggle_indicator("r")
		KEY_T: _teleport_next()
		KEY_L: _toggle_lights()
		KEY_F: _toggle_high_beam()
		KEY_H:
			hazard = not hazard
			if hazard:
				indicator_left = false
				indicator_right = false


## Abblendlicht an/aus (Taste L oder Lenkrad-Knopf).
func _toggle_lights() -> void:
	headlights_on = not headlights_on
	for s in _headlights:
		s.visible = headlights_on
	if not headlights_on and high_beam:
		_set_high_beam(false)


## Fernlicht (Taste F): weit und steiler gestellt — blendet den
## Gegenverkehr, deshalb nur auf dunkler, freier Strecke erlaubt.
var high_beam := false
func _toggle_high_beam() -> void:
	if not headlights_on:
		return
	_set_high_beam(not high_beam)


func _set_high_beam(on: bool) -> void:
	high_beam = on
	for s in _headlights:
		s.spot_range = 60.0 if on else 26.0
		s.spot_angle = 20.0 if on else 28.0
		s.light_energy = 16.0 if on else 9.0
		s.basis = Basis.from_euler(
			Vector3(-0.16 if on else -0.38, PI, 0.0))


## Taste T: direkt an die naechste Uebungsstation springen - das Auto
## steht sofort auf Fahrposition, alle Uebungen bleiben ein Klick entfernt.
func _teleport_next() -> void:
	var spots: Array = CityLayout.exercise_spots()
	_spot_i = (_spot_i + 1) % spots.size()
	var spot: Dictionary = spots[_spot_i]
	var dir: Vector2 = spot["dir"]
	var pos: Vector2 = spot["pos"]
	# +Z-Basis zeigt die Fahrtrichtung: looking_at(-d) macht +Z -> d.
	var basis := Basis.looking_at(Vector3(-dir.x, 0.0, -dir.y).normalized(), Vector3.UP)
	global_transform = Transform3D(basis, Vector3(pos.x, 0.4, pos.y))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	brake = BRAKE_MAX * 0.2
	steering = 0.0
	gearbox.reset()
	gear = 0
	stalled = false
	motor_on = true
	clutch_heat = 0.0
	indicator_left = false
	indicator_right = false
	hazard = false
	last_spot = String(spot["name"])
	if feedback:
		feedback.poke("reset", 0.0)


func _kb_gear(g: int) -> void:
	# Tastatur hat keine Kupplungspedal: kurzes Einrückfenster simulieren,
	# damit 1..6/V ohne Pedal schalten (so will es auch der Fahrschüler, der
	# gerade kein drittes Pedal hat — Assistent, kein Ersatz für den Hebel).
	_auto_clutch_t = 0.35
	var speed: float = linear_velocity.dot(global_transform.basis.z)
	var clutch_pedal := maxf(_clutch_pedal(), 1.0)
	if gearbox.request_gear(g, clutch_pedal, speed) and feedback:
		feedback.poke("shift", 0.3)


func _clutch_pedal() -> float:
	var pedal := 0.0
	if g29 and g29.connected:
		pedal = maxf(pedal, g29.clutch)
	if has_meta("script_clutch"):
		pedal = maxf(pedal, float(get_meta("script_clutch")))
	if _auto_clutch_t > 0.0:
		pedal = 1.0
	return pedal


func _toggle_indicator(side: String) -> void:
	if side == "l":
		indicator_left = not indicator_left
		indicator_right = false
	else:
		indicator_right = not indicator_right
		indicator_left = false
	hazard = false
	_ind_yaw = 0.0


func _wheel_steer() -> float:
	# Das Schulauto nutzt den vollen 900°-Bereich des G29 — im Gegensatz zum
	# F1-Wagen (steer_soft, auf den eingestellten Bereich begrenzt).
	if g29 == null:
		return 0.0
	return clampf(float(g29.steer), -1.0, 1.0)


func _physics_process(delta: float) -> void:
	var forward_vel: float = global_transform.basis.z.dot(linear_velocity)
	speed_kmh = linear_velocity.length() * 3.6
	var steer_in := 0.0
	var throttle_in := 0.0
	var brake_in := 0.0
	var clutch_pedal := 0.0
	handbrake_on = Input.is_key_pressed(KEY_SPACE)

	_auto_clutch_t = maxf(_auto_clutch_t - delta, 0.0)

	if g29 and g29.connected:
		var ws: float = _wheel_steer()
		if absf(ws) > 0.03:
			steer_in = ws
		throttle_in = maxf(throttle_in, g29.throttle)
		brake_in = maxf(brake_in, g29.brake)
		clutch_pedal = _clutch_pedal()
		handbrake_on = handbrake_on or g29.joy_button(int(button_map["handbrake"]))
	# Tastatur läuft parallel — wer kein Lenkrad hat, fährt trotzdem.
	var kb_steer: float = Input.get_axis("steer_left", "steer_right")
	if absf(kb_steer) > 0.05:
		steer_in = kb_steer
	throttle_in = maxf(throttle_in, Input.get_action_strength("throttle"))
	brake_in = maxf(brake_in, Input.get_action_strength("brake"))
	if has_meta("script_steer"):
		steer_in = float(get_meta("script_steer"))
	if has_meta("script_throttle"):
		throttle_in = float(get_meta("script_throttle"))
	if has_meta("script_brake"):
		brake_in = float(get_meta("script_brake"))
	if has_meta("headless_gas"):
		throttle_in = 0.65
	if has_meta("script_gear"):
		var g := int(get_meta("script_gear"))
		if g != gearbox.gear:
			gearbox.request_gear(g, 1.0, forward_vel)

	if Input.is_action_just_pressed("reset_car"):
		_reset()
	if Input.is_action_just_pressed("toggle_assists"):
		toggle_assists()

	# Untergrund abtasten (Grip/Widerstand/Ruetteln + Name fürs HUD).
	var surface: Dictionary = surfaces.sample(global_position) if surfaces else {}
	var grip: float = float(surface.get("grip", 1.0))
	var drag: float = float(surface.get("drag", 0.0))
	var rumble: float = float(surface.get("rumble", 0.0))
	surface_name = String(surface.get("name", "Asphalt"))

	# Lenken: Stadtauto, voller Lenkeinschlag nur im Schritttempo.
	var spd: float = absf(forward_vel)
	var steer_limit: float = max_steer * lerpf(1.0, 0.30, clampf(spd / 22.0, 0.0, 1.0))
	var steer_cmd: float = clampf(steer_in, -1.0, 1.0)
	steering = lerpf(steering, -steer_cmd * steer_limit, clampf(delta * 9.0, 0.0, 1.0))
	last_steer = steer_cmd
	_animate_wheels(delta, forward_vel)

	# Blinker-Selbstausloesung: linke Kurve dreht den Kurs um +Y.
	# Ausloesen, sobald rund 45 Grad abgebogen wurde und das Lenkrad
	# wieder fast gerade steht - wie die Rueckstellnocke im echten Auto.
	var yaw: float = global_transform.basis.get_euler().y
	if indicator_left or indicator_right:
		_ind_yaw += wrapf(yaw - _prev_yaw, -PI, PI)
		var turned: float = _ind_yaw if indicator_left else -_ind_yaw
		if turned > 0.8 and absf(steer_in) < 0.12:
			indicator_left = false
			indicator_right = false
			_ind_yaw = 0.0
		elif turned < -0.5:
			_ind_yaw = 0.0
	else:
		_ind_yaw = 0.0
	_prev_yaw = yaw

	# Beschleunigungen fürs Feedback.
	var accel_vec: Vector3 = (linear_velocity - _prev_vel) / maxf(delta, 0.0001)
	_lateral_g = accel_vec.dot(global_transform.basis.x.normalized()) / 9.81
	var raw_vert_g := 1.0
	if _vert_ready:
		raw_vert_g = (linear_velocity.y - _prev_vel_y) / maxf(delta, 0.0001) / 9.81 + 1.0
	_vert_ready = true
	_prev_vel_y = linear_velocity.y
	_vertical_g += (clampf(raw_vert_g, -1.0, 4.0) - _vertical_g) * clampf(delta / 0.09, 0.0, 1.0)
	_prev_vel = linear_velocity
	_prev_speed = linear_velocity.length()

	# Antrieb: H-Getriebe mit Kupplung.
	var gb: Dictionary = gearbox.update(delta, {
		"speed": forward_vel,
		"throttle": throttle_in,
		"brake": brake_in,
		"clutch": clutch_pedal,
		"auto": bool(assists.get("auto_gearbox", false)),
	})
	gear = int(gb["gear"])
	rpm = float(gb["rpm"])
	engine_force = float(gb["engine_force"]) * grip
	# Blechschaden: ab ~halber Ladung geht dem Motor die Leistung aus —
	# das merkt man beim Fahren, erst Recht in der Pruefung.
	if damage > 0.5:
		engine_force *= lerpf(1.0, 0.4, clampf((damage - 0.5) / 0.5, 0.0, 1.0))
	# Traktionskontrolle: durchdrehende Antriebsraeder -> Gas weg.
	if bool(assists.get("traction_control", true)) and engine_force > 0.0:
		var worst_skid := 1.0
		for item in _wheels:
			var tw: VehicleWheel3D = item["wheel"]
			if tw.use_as_traction:
				worst_skid = minf(worst_skid, tw.get_skidinfo())
		if worst_skid < 0.75:
			engine_force *= 0.5 * clampf(worst_skid / 0.75, 0.0, 1.0)
	var now_stalled: bool = bool(gb["stalled"])
	if now_stalled and not stalled:
		stall_events += 1
		if feedback:
			feedback.poke("bump", 0.5)
		_stall_note_t = 3.0
	stalled = now_stalled
	motor_on = bool(gb["motor_on"])
	if stalled:
		# Tastatur hat kein Kupplungspedal: Anlasser dreht von allein.
		var crank_clutch: float = clutch_pedal
		if g29 == null or not g29.connected:
			crank_clutch = 1.0
		gearbox.start_motor(crank_clutch)
	if absf(float(gb.get("judder", 0.0))) > 0.1:
		# Kurzer Ruck ~1 m/s (nicht Startbeschleunigung): 0,35 s * judder *
		# mass * Faktor. Mit 0,00006 landet der Delta-v bei ~1,1 m/s.
		apply_central_impulse(global_transform.basis.z * float(gb["judder"]) * mass * 0.00006 * 60.0 * delta)
	# Kupplung schleifen lassen = Hitze (Fahrlehrerhinweis, kein Schaden).
	# Hitzefenster endet am BITE_OUT (0.72): darueber ist die Kupplung
	# sauber getrennt und schleift nichts mehr.
	if clutch_pedal > 0.25 and clutch_pedal < 0.72 and absf(forward_vel) < 4.0 and throttle_in > 0.2:
		clutch_heat = minf(clutch_heat + delta * 0.25, 3.0)
	else:
		clutch_heat = maxf(clutch_heat - delta, 0.0)

	# Bremsen: Fußbremse auf alle Räder, Handbremse auf die Hinterachse.
	brake_strength = brake_in
	var brake_force: float = brake_in * BRAKE_MAX
	if brake_in > 0.06:
		engine_force = minf(engine_force, 0.0)
	brake = brake_force
	for item in _wheels:
		var w: VehicleWheel3D = item["wheel"]
		if not item["front"]:
			w.brake = HANDBRAKE_MAX if handbrake_on else 0.0
	# Grip/Untergrund wirken auf die Reifen.
	for item in _wheels:
		var w: VehicleWheel3D = item["wheel"]
		w.wheel_friction_slip = 10.0 * grip
	# Rollwiderstand des Untergrunds.
	if drag > 0.0 and spd > 0.2:
		var fwd: Vector3 = global_transform.basis.z.normalized()
		apply_central_force(-fwd * signf(forward_vel) * mass * drag * 9.81 * 0.5)

	# Slip-Schätzung fürs Lenkradgefühl (untersteuern ~ Sättigung Querlast).
	var understeer: float = clampf((absf(_lateral_g) - 0.55) / 0.35, 0.0, 1.0)
	var oversteer: float = clampf((absf(angular_velocity.y) * maxf(spd, 0.0) - absf(_lateral_g) * 9.81 * 0.6) / 8.0, 0.0, 1.0)
	_skid = maxf(understeer, oversteer) if spd > 3.0 else 0.0
	var slip_front: float = clampf(steer_cmd * absf(_lateral_g) * 0.09, -1.0, 1.0)

	# Aufprall: harter Geschwindigkeitsabfall ohne Bremsen = Wand/Hindernis.
	var dv: float = (_prev_vel - linear_velocity).length()
	if dv > 2.4 and _vert_ready:
		var sev: float = clampf(dv / 8.0, 0.15, 1.0)
		damage = clampf(damage + sev * 0.12, 0.0, 1.0)
		if feedback:
			feedback.poke("crash", sev)
		if ffb:
			ffb.poke("crash", sev)

	# Lampen: Bremslicht + Blinker (Warnblinker blinkt beide Seiten).
	_update_lamps(delta, brake_in)

	# Lenkrad-Feedback: dieselbe ctx-Form wie der F1-Wagen.
	var feel := {
		"steer": last_steer,
		"steer_angle": steering,
		"speed": spd,
		"lateral_g": _lateral_g,
		"vertical_g": _vertical_g,
		"yaw_rate": angular_velocity.y,
		"surface": surface,
		"slip": maxf(understeer, oversteer),
		"slip_front": slip_front,
		"slip_rear": oversteer * signf(steer_cmd),
		"front_grip": grip,
		"rear_grip": grip,
		"downforce": 1.0,
		"understeer": understeer,
		"oversteer": oversteer,
		"throttle": throttle_in,
		"brake": brake_in,
		"lock_pressure": 0.0,
		"traction_control": bool(assists.get("traction_control", true)),
		"crash": dv if dv > 1.5 else 0.0,
		"damage": damage,
		"stall": stalled,
	}
	if rumble > 0.0 and spd > 0.5:
		feel["surface_rumble"] = rumble
	if feedback:
		feedback.update(delta, feel)
	if ffb:
		ffb.update(delta, feel)
	_engine_sound(throttle_in)

	if global_position.y < VOID_Y:
		_reset()
	# Wer ueber die Stadtkarte hinausfaehrt, wird auf den naechsten
	# Reset-Punkt zurueckgesetzt (sonst rollt man ins Leere).
	var bb := CityLayout.bounds()
	if not bb.has_point(Vector2(global_position.x, global_position.z)):
		_reset()


## Synthetischer Motorsound: Grundton ~ Halbe Kurbelwellenfrequenz
## (rpm/60*2 ≈ 2-Zylinder-Ton) plus Oberton — Drehzahl und Gas hoert
## man wie an einem echten Motor. Faellt der Motor ab, wirds still.
func _engine_sound(throttle_in: float) -> void:
	if _engine_gen == null:
		return
	var frames: int = _engine_gen.get_frames_available()
	if frames <= 0:
		return
	var mix := 22050.0
	var freq: float = (rpm * 0.033) if motor_on else 0.0
	var vol: float = (0.10 + throttle_in * 0.16) if motor_on else 0.0
	# Abgewuergt: kurzes Abrasseln statt sofortiger Stille.
	if stalled and _engine_phase > 0.0:
		vol = 0.05
	var blinker_an: bool = indicator_left or indicator_right or hazard
	var horn_f1 := 420.0 / mix
	var horn_f2 := 530.0 / mix
	# Einparkpiepser: nur im Rueckwaertsgang, Abstandsfrequenz.
	var pdc_gap_frames := -1.0
	if gear == -1:
		var d: float = rear_distance()
		if d < 4.0:
			# 0.35 m -> Dauerton, 4 m -> ~1.1 s Pausen.
			pdc_gap_frames = maxf(0.0, (d - 0.35) / 3.65) * 24000.0
	for i in frames:
		_engine_phase += freq / mix
		if _engine_phase >= 1.0:
			_engine_phase -= 1.0
		var s: float = sin(TAU * _engine_phase) * 0.55 \
			+ sin(TAU * _engine_phase * 2.0) * 0.28 \
			+ sin(TAU * _engine_phase * 3.0) * 0.12
		s = tanh(s * 1.6) * vol
		# Blinkerrelais: kurzes Klack alle ~0.45 s, solange geblinkt wird.
		if blinker_an:
			_click_gap -= 1.0
			if _click_left > 0.0:
				_click_left -= 1.0
				s += (0.22 if _click_left > 40.0 else -0.22) * (_click_left / 60.0)
			elif _click_gap <= 0.0:
				_click_left = 60.0      ## ~3 ms Klack bei 22050 Hz
				_click_gap = 9920.0     ## ~0.45 s wie ein echtes Relais
		# Hupe: zwei schrille Toene uebereinander, mit Ein-/Ausklingen.
		if _horn_left > 0.0:
			_horn_left -= 1.0
			_horn_phase += 1.0
			var h: float = sin(TAU * _horn_phase * horn_f1) \
				+ sin(TAU * _horn_phase * horn_f2)
			s += tanh(h) * 0.30 * clampf(_horn_left / 3000.0, 0.0, 1.0)
		# Reifenquietschen: Rauschen, Pegel folgt dem Schlupf.
		if _skid > 0.05:
			s += (randf() * 2.0 - 1.0) * _skid * 0.13
		# Einparkpiepser: kurzer 1400-Hz-Piep, immer kuerzer werdend.
		if pdc_gap_frames >= 0.0:
			_pdc_gap -= 1.0
			if _pdc_left > 0.0 or pdc_gap_frames < 1.0:
				_pdc_left = maxf(_pdc_left - 1.0, 0.0)
				_pdc_phase += 1400.0 / mix
				s += sin(TAU * _pdc_phase) * 0.22
				if pdc_gap_frames < 1.0:
					_pdc_left = 99999.0
			elif _pdc_gap <= 0.0:
				_pdc_left = 1400.0      ## ~64 ms Piep
				_pdc_gap = pdc_gap_frames
		_engine_gen.push_frame(Vector2(s, s))


## Hupe: kurzes Zweiklang-Horn (~0.4 s), wie in der Stadt ueblich.
func honk() -> void:
	if _horn_left <= 0.0:
		_horn_left = 8800.0        ## ~0.4 s bei 22050 Hz


func _update_lamps(delta: float, brake_in: float) -> void:
	var brake_mat: StandardMaterial3D = _lamps.get("brake")
	if brake_mat:
		brake_mat.emission_energy_multiplier = 2.8 if brake_in > 0.08 else 0.3
	_blink_t += delta
	var on: bool = fmod(_blink_t, 0.9) < 0.45
	for i in _lamps.get("bl", []).size():
		var m: StandardMaterial3D = _lamps["bl"][i]
		m.emission_energy_multiplier = 3.2 if (on and (indicator_left or hazard)) else 0.2
	for i in _lamps.get("br", []).size():
		var m: StandardMaterial3D = _lamps["br"][i]
		m.emission_energy_multiplier = 3.2 if (on and (indicator_right or hazard)) else 0.2


func _animate_wheels(delta: float, forward_speed: float) -> void:
	var roll_rate: float = forward_speed / maxf(CarMesh.WHEEL_RADIUS, 0.1)
	_wheel_roll = fposmod(_wheel_roll + roll_rate * delta, TAU)
	for item in _wheels:
		var vis: Node3D = item["vis"]
		var wheel: VehicleWheel3D = item["wheel"]
		if vis == null or wheel == null:
			continue
		# Lenkeinschlag: VehicleWheel3D dreht sein Node nicht mit — wir
		# nehmen die aktuelle Lenkung nur fuer Vorderraecher.
		var yaw: float = steering if wheel.use_as_steering else 0.0
		vis.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _wheel_roll)


func toggle_assists() -> Dictionary:
	# F-Taste: Automatik an/aus. Die Kupplungshilfe für Tastatur bleibt immer
	# an — ohne Pedal geht sonst gar nichts.
	var on: bool = not bool(assists.get("auto_gearbox", false))
	assists["auto_gearbox"] = on
	return assists


func assists_label() -> String:
	if bool(assists.get("auto_gearbox", false)):
		return "AUTOMATIK"
	return "SCHALTER"


## Abstand zum naechsten Hindernis hinter dem Auto (Einparkhilfe).
## INF, wenn in 4 m nichts liegt. Drei Strahlen an der Heckkante:
## links/Mitte/rechts, jeweils von knapp ausserhalb des Stossfaengers aus.
func rear_distance() -> float:
	if not is_inside_tree():
		return INF
	var space := get_world_3d().direct_space_state
	var best := INF
	for x in [-0.7, 0.0, 0.7]:
		var from := global_transform * Vector3(x, 0.35, -2.12)
		var to := global_transform * Vector3(x, 0.35, -6.1)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.distance_to(hit["position"]))
	return best


## Wo der Fahrlehrer "aktueller Gang" als Text liest.
func gear_label() -> String:
	match gear:
		-1: return "R"
		0: return "N"
		_: return str(gear)


func _reset() -> void:
	reset_count += 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Naechster festgelegter Reset-Punkt statt immer zum Start — nach
	# einem Malheur auf dem Ring steht man nicht wieder am Platz.
	var spot := spawn_transform
	var bd := 1e9
	for s in CityLayout.reset_spots():
		var d := Vector2(global_position.x, global_position.z).distance_to(s["pos"])
		if d < bd:
			bd = d
			var p: Vector2 = s["pos"]
			spot = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["rot"]))),
				Vector3(p.x, 0.4, p.y))
	global_transform = spot
	engine_force = 0.0
	brake = BRAKE_MAX * 0.2
	steering = 0.0
	gearbox.reset()
	gear = 0
	stalled = false
	motor_on = true
	clutch_heat = 0.0
	indicator_left = false
	indicator_right = false
	hazard = false
	damage = 0.0
	if feedback:
		feedback.poke("reset", 0.0)


func _exit_tree() -> void:
	pass
