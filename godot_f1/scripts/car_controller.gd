extends VehicleBody3D

const SurfaceModel = preload("res://scripts/surfaces.gd")
const CrashModel = preload("res://scripts/crash.gd")
const WheelFeedback = preload("res://scripts/wheel_feedback.gd")
const Gearbox = preload("res://scripts/gearbox.gd")
const TyreModel = preload("res://scripts/tyre_model.gd")
const FfbLink = preload("res://scripts/ffb_link.gd")

@export var livery: String = "crimson"
@export var auto_drive: bool = false
@export var is_ai: bool = false
@export var max_steer: float = 0.48

var racing_line
## The ideal line, when the game has one: the AI drives it and takes its corner
## speeds from it. The player's own driving is never assisted by it.
var ideal_line
var g29
## Sub-systems. Each one owns one question: what is under the tyres (surfaces),
## what does the engine do (gearbox), how much grip is left (tyres), did we hit
## something (crash), and what does that feel like (feedback).
var surfaces
var gearbox
var tyres
var crash
var feedback
## Force-Feedback-Einstellungen (Staerke, Daempfung, Lenkbereich). `main.gd`
## legt sie an und reicht sie herein, damit Menue, G29, Auto und HUD an genau
## demselben Objekt drehen.
var ffb_settings
## The channel to the real wheel: `tools/g29_ffb.py` turns these numbers into
## DirectInput forces on the G29. Harmless when nothing is listening.
var ffb
## Driver assists. F1 games ship with these on; the driver can switch the
## automatic gearbox off and shift with the paddles himself.
var assists: Dictionary = {"auto_gearbox": true, "traction_control": true}
var spawn_transform: Transform3D
var speed_kmh: float = 0.0
var last_steer: float = 0.0
var gear: int = 1
var rpm: float = 4200.0
var clutch_assist: bool = true
var _shift_cd: float = 0.0
## Last racing line point, so finding "where am I" stays a window search
## instead of walking all 1440 points every tick.
var _line_hint: int = -1
## Last point index on the ideal line, so aiming at it stays a window search.
var _ideal_hint: int = -1
var surface_name: String = "Asphalt"
## Querabstand zur Mittellinie in Metern (aus `scripts/surfaces.gd`).
var surface_offset: float = 0.0
var surface_drag: float = 0.0
## 0..1 how much the ground rattles the car (kerb, gravel, grass). The camera
## and the wheel read this; it is 0 on clean asphalt.
var surface_rumble: float = 0.0
## Telemetry the HUD and the tests read: how hard the car is sliding, how much
## downforce it carries, and how bent the tub is after a hit.
var slip: float = 0.0
var lateral_g: float = 0.0
var downforce: float = 0.0
## 0..1, wie weit der Fahrer das Lenkrad ueber den Lenkanschlag hinaus dreht.
## Der Anschlag steckt im Modell (`ffb_model.gd`), sichtbar ist er hier.
var lock_pressure: float = 0.0
## Senkrechte Last in g, gefiltert: 1.0 = Auto steht auf den Raedern, darunter
## entlastet (Kuppe, Lenkrad wird leicht), darueber gestaucht (Bodenwelle,
## kurzer Stoss). Das Modell macht daraus die Kraft.
var vertical_g: float = 1.0
var _prev_vel_y: float = 0.0
var _vert_ready: bool = false
var _bump_cd: float = 0.0
## Aerodynamic drag this tick, in Newton, and the acceleration the car feels
## in its own frame (used by the camera and by the HUD).
var aero_drag_n: float = 0.0
var long_accel: float = 0.0
var lat_accel: float = 0.0
var _prev_vel: Vector3 = Vector3.ZERO
## Visual wheel meshes, kept so the rims can steer and roll with the car.
var _wheel_meshes: Array = []
var _wheel_roll: float = 0.0
var _wheel_radius_avg: float = 0.365
## Below this height there is no track, apron or terrain left - the car is in
## the void and has to be put back on the line.
const VOID_Y := -3.0
## Ab dieser senkrechten Last (g) gilt die Feder als gestaucht: das gibt einen
## kurzen Stoss ans Lenkrad (Bodenwelle, Randstein, harte Fuge). Alles darunter
## ist normales Fahren oder eine Entlastung (Kuppe) - die macht das Lenkrad
## leicht, statt zu stossen.
const COMPRESS_G := 1.35
var _rejoin_cd: float = 0.0
var rejoin_count: int = 0
## Weit draussen im Kies liegen bleiben: siehe `_watch_stuck()`.
var _stuck_time: float = 0.0
## Ab diesem Querabstand ist das Auto nicht mehr "weit gefahren", sondern
## neben der Strecke (Asphalt + Kerb enden bei 6,85 m, der Kiesapron bei
## 16,85 m; die Wand steht bei 16 m). Ein Meter Abstand zum Kerb, damit ein
## kurz stehengebliebenes Auto am Streckenrand nicht sofort umgesetzt wird.
const STUCK_OFFSET := 8.0
## Darunter gilt das Auto als stehend (Rad dreht nicht, es kommt nicht weg).
const STUCK_SPEED := 2.0
## So lange darf ein autonom fahrendes Auto neben der Strecke stehen, bevor es
## zurueck auf die Linie gesetzt wird.
const STUCK_AFTER := 2.5
## Und so lange, wenn es zwar faehrt, aber draussen bleibt (z. B. parallel zur
## Strecke im Kies).
const STUCK_AFTER_MOVING := 8.0
## How often the car had to be put back on its wheels. A non-zero value while
## driving normally is a physics bug, not a driving mistake.
var reset_count: int = 0

const LIVERY_PATH := "res://assets/cars/car_%s.glb"
const RIG_PATH := "res://assets/cars/car_rig.json"
const LIVERY_SHADER := "res://assets/shaders/livery.gdshader"
const WHEEL_KEYS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

## Paint / accent per livery (the GLB itself carries no colour at all).
const LIVERIES := {
	"crimson": {"paint": Color(0.74, 0.035, 0.05), "accent": Color(1.0, 0.95, 0.92)},
	"silver": {"paint": Color(0.62, 0.65, 0.68), "accent": Color(0.02, 0.12, 0.42)},
	"navy": {"paint": Color(0.02, 0.05, 0.16), "accent": Color(0.92, 0.78, 0.08)},
	"papaya": {"paint": Color(0.92, 0.38, 0.08), "accent": Color(0.05, 0.05, 0.06)},
	"green": {"paint": Color(0.02, 0.22, 0.14), "accent": Color(0.95, 0.82, 0.12)},
	"azure": {"paint": Color(0.05, 0.28, 0.72), "accent": Color(0.95, 0.35, 0.55)},
}
const REST := 0.18
const IDLE_RPM := 4200.0
const REDLINE := 12500.0
const MAX_GEAR := 8
## Approximate sequential ratios. Index 0 unused (gear is 1..8).
const RATIOS := [0.0, 3.4, 2.7, 2.2, 1.85, 1.58, 1.38, 1.22, 1.08]
const POWER := 3200.0
const BRAKE_MAX := 110.0


func setup(line, wheel_input, start: Transform3D) -> void:
	racing_line = line
	g29 = wheel_input
	spawn_transform = start
	mass = 740.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Weight slightly towards the rear axle (nose is +Z), like a real F1 car.
	center_of_mass = Vector3(0.0, -0.10, -0.42)
	continuous_cd = true
	can_sleep = false
	_build_wheels_and_mesh()
	_build_chassis_collider()
	gearbox = Gearbox.new()
	gearbox.setup(IDLE_RPM)
	surfaces = SurfaceModel.new()
	surfaces.setup(line)
	tyres = TyreModel.new()
	tyres.setup(self, line)
	crash = CrashModel.new()
	crash.setup(self, surfaces)
	# Only the player's car drives the wheel: two cars sending force at the same
	# time would fight over the same G29.
	ffb = null
	if not is_ai:
		ffb = FfbLink.new()
		# Das Lenkrad mitgeben: damit kann der Kanal die Kraftrichtung selbst
		# messen (DirectInput-Achse des Helfers gegen die SDL-Achse des Spiels)
		# und muss sie nicht aus einer Annahme ableiten.
		ffb.setup(ffb_settings, wheel_input)
	# HUD, Kamera und Gamepad-Vibration lesen dasselbe Modell wie das echte
	# Lenkrad. Ein KI-Auto hat keinen Lenkradkanal und rechnet selbst.
	feedback = WheelFeedback.new()
	feedback.setup(self, wheel_input, ffb.model if ffb else null)
	if crash and crash.has_signal("crashed") and not crash.crashed.is_connected(_on_crash):
		crash.crashed.connect(_on_crash)
	global_transform = start
	if g29 and not is_ai:
		if not g29.shift_up.is_connected(_on_shift_up):
			g29.shift_up.connect(_on_shift_up)
			g29.shift_down.connect(_on_shift_down)


func _build_chassis_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "Chassis"
	var box := BoxShape3D.new()
	# Hull box centred between the axles (front axle +1.43, rear axle -2.00).
	box.size = Vector3(1.8, 0.55, 3.9)
	col.shape = box
	col.position = Vector3(0.0, 0.60, -0.25)
	add_child(col)


func _build_wheels_and_mesh() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	var rig_radius: float = float(rig.get("wheel_radius", 0.365))
	var packed: PackedScene = load(LIVERY_PATH % livery)
	var visual: Node3D = packed.instantiate()
	visual.name = "Visual"
	add_child(visual)
	# The artwork is modelled nose-first along +Z, and VehicleBody3D pushes the
	# hull towards +Z for a positive engine_force, so the visual must stay
	# unrotated. Any yaw here makes the car drive tail-first (the "I drive
	# backwards" bug: nose pointing at the rear wing, cockpit over the engine).
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	_apply_livery(visual)

	# The wheel meshes are the only nodes with a translation in the GLB, so the
	# model itself tells us where the axles are. car_rig.json stays the fallback.
	var entries: Array = []
	for key in WHEEL_KEYS:
		var node := _find_token(visual, key)
		var pos := Vector3.ZERO
		var radius: float = rig_radius
		if node:
			pos = node.position
			radius = _mesh_radius(node, rig_radius)
		else:
			var loc: Array = rig["wheels"][key]["location"]
			# Blender (X right, Y forward, Z up) -> Godot (X, Z, -Y).
			pos = Vector3(float(loc[0]), float(loc[2]), -float(loc[1]))
		entries.append({"key": key, "pos": pos, "node": node, "radius": radius})

	# Front axle = nose side (+Z), left hand side = +X for a +Z/+Y body.
	entries.sort_custom(func(a, b): return a.pos.z > b.pos.z)
	# The imported model is not perfectly symmetric: the rear hubs sit 1 cm
	# off centre (|x| 0.882 vs 0.860). That is invisible in the cockpit, but the
	# drive force acts through those two points, so the car carried a constant
	# 0.001 rad/s yaw rate - at 300 km/h it wandered 37 m sideways in 20 s
	# (measured with tests/test_gearbox.gd). Only the PHYSICS hubs are
	# symmetrised; the artwork keeps the shape the modeller built.
	var half_track_front: float = (absf(entries[0].pos.x) + absf(entries[1].pos.x)) * 0.5
	var half_track_rear: float = (absf(entries[2].pos.x) + absf(entries[3].pos.x)) * 0.5
	_wheel_meshes.clear()
	var radius_sum: float = 0.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var is_front: bool = i < 2
		var is_left: bool = e.pos.x > 0.0
		var role: String = ("Wheel_F" if is_front else "Wheel_R") + ("L" if is_left else "R")
		var hub: Vector3 = e.pos
		var half_track: float = half_track_front if is_front else half_track_rear
		hub.x = half_track if is_left else -half_track
		var radius: float = e.radius
		radius_sum += radius
		var wheel := VehicleWheel3D.new()
		wheel.name = role
		wheel.position = hub + Vector3(0.0, REST, 0.0)
		# Formula 1: the front axle steers, the rear axle drives.
		wheel.use_as_steering = is_front
		wheel.use_as_traction = not is_front
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = REST
		wheel.suspension_travel = 0.18
		wheel.suspension_stiffness = 52.0
		wheel.suspension_max_force = 14000.0
		wheel.damping_compression = 0.82
		wheel.damping_relaxation = 0.92
		wheel.wheel_friction_slip = 7.8
		wheel.wheel_roll_influence = 0.08
		add_child(wheel)
		var mesh: Node3D = e.node
		if mesh:
			# The visual rim does NOT live under the VehicleWheel3D node.
			#
			# Godot turns that node itself - it carries the steering angle and a
			# rolling angle - and a mesh child that also rolls therefore cancels
			# it out. Measured on the real scene at 150 km/h: the tyre's world
			# orientation stayed put to within 0.1 deg over eight physics ticks 
			# while the node and the mesh rotated 73 deg per tick in opposite
			# directions. That is why the wheels looked like they never turned,
			# and the same cancellation swung the rim's centre around the
			# suspension mount by +/-0.15 m, a wobble no wheel ever makes.
			#
			# So the rim gets its own carrier, parented to the car: the position
			# comes from the modelled hub, the steering from the physics node
			# (its X axis carries the yaw and nothing else) and the rolling angle
			# from the speed. One owner per quantity, nothing to cancel.
			var old_parent := mesh.get_parent()
			if old_parent:
				old_parent.remove_child(mesh)
			var vis := Node3D.new()
			vis.name = "Vis_" + role
			vis.position = hub
			add_child(vis)
			vis.add_child(mesh)
			mesh.owner = vis
			var base_scale: Vector3 = mesh.transform.basis.get_scale()
			mesh.transform = Transform3D(Basis.from_scale(base_scale), Vector3.ZERO)
			var detail := _add_wheel_details(mesh, hub.x, radius)
			_wheel_meshes.append({
				"mesh": mesh, "vis": vis, "wheel": wheel, "front": is_front,
				"rim_mat": detail["rim"], "decal_mat": detail["decal"],
			})
	_wheel_radius_avg = radius_sum / maxf(float(entries.size()), 1.0)


func _paint_material() -> Material:
	var entry: Dictionary = LIVERIES.get(livery, LIVERIES["crimson"])
	var shader: Shader = load(LIVERY_SHADER)
	if shader:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("paint_color", entry["paint"])
		sm.set_shader_parameter("accent_color", entry["accent"])
		return sm
	# Fallback for a missing shader file: plain painted metal.
	var m := StandardMaterial3D.new()
	m.albedo_color = entry["paint"]
	m.metallic = 0.28
	m.roughness = 0.18
	m.clearcoat_enabled = true
	m.clearcoat = 0.85
	m.clearcoat_roughness = 0.06
	return m


func _apply_livery(node: Node) -> void:
	## The GLB exports a single "Paint_*" surface per body mesh without any base
	## colour, so the livery is applied on top of it here.
	var paint := _paint_material()
	_paint_walk(node, paint)


func _paint_walk(node: Node, paint: Material) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			var sname: String = src.resource_name if src else ""
			if "Paint" in sname or (src == null and mi.mesh.get_surface_count() == 1 and i == 0):
				mi.set_surface_override_material(i, paint)
	for c in node.get_children():
		_paint_walk(c, paint)


func _mesh_radius(node: Node3D, fallback: float) -> float:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return fallback
	var aabb: AABB = mi.mesh.get_aabb()
	# A wheel is a disc: two of the three extents describe its diameter.
	var sizes: Array = [aabb.size.x, aabb.size.y, aabb.size.z]
	sizes.sort()
	var r: float = float(sizes[2]) * 0.5
	if r < 0.15 or r > 0.7:
		return fallback
	return r


func _add_wheel_details(mesh: Node3D, _hub_x: float, radius: float) -> Dictionary:
	## F1 wheels are bare slicks, so a plain tyre looks like it does not turn.
	## A coloured sidewall band (the compound marking), a small decal and a star
	## of rim spokes make the rotation visible - and they are what a real wheel
	## looks like from the cockpit.
	##
	## The band is a closed ring, so spinning it changes nothing on screen. The
	## spokes and the sticker are not: at racing speed they pass the eye many
	## times per frame and strobe. Their materials are handed back to the caller
	## so they can be faded into the tyre as the wheel speeds up - the same blur
	## a photograph of a spinning wheel shows.
	var mi := mesh as MeshInstance3D
	if mi == null or mi.mesh == null:
		return {}
	var aabb: AABB = mi.mesh.get_aabb()
	var half_width: float = maxf(aabb.size.x * 0.5, 0.12)
	var compound: Color = Color(0.85, 0.12, 0.14) if livery != "crimson" else Color(0.92, 0.78, 0.12)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = compound
	band_mat.roughness = 0.65
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.46, 0.47, 0.50)
	# A mirror-smooth rim sparkles frame to frame at speed: the highlight jumps
	# between pixels. Roughness 0.45 keeps the metal look without the flicker.
	rim_mat.metallic = 0.70
	rim_mat.roughness = 0.45
	var decal := StandardMaterial3D.new()
	decal.albedo_color = Color(0.86, 0.87, 0.88)
	decal.roughness = 0.5
	# Both faces get the details: from the cockpit the driver looks at the INNER
	# sidewall of the front wheels, while a chase or side camera sees the outer
	# one. Putting them on only one side made the wheels look featureless from
	# the cockpit - and a featureless slick looks like it never turns.
	for outward in [1.0, -1.0]:
		var face_x: float = outward * (half_width + 0.006)
		var side_name: String = "Out" if outward > 0.0 else "In"
		# sidewall band
		var ring := MeshInstance3D.new()
		ring.name = "CompoundBand" + side_name
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.66
		torus.outer_radius = radius * 0.82
		torus.rings = 20
		torus.ring_segments = 8
		ring.mesh = torus
		ring.material_override = band_mat
		ring.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		ring.position = Vector3(face_x, 0.0, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(ring)
		# rim spokes
		for i in 6:
			var a: float = TAU * float(i) / 6.0
			var spoke := MeshInstance3D.new()
			spoke.name = "Spoke%s%d" % [side_name, i]
			var box := BoxMesh.new()
			box.size = Vector3(0.012, radius * 0.92, 0.030)
			spoke.mesh = box
			spoke.material_override = rim_mat
			spoke.position = Vector3(face_x, cos(a) * radius * 0.44, sin(a) * radius * 0.44)
			spoke.rotation = Vector3(-a, 0.0, 0.0)
			spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.add_child(spoke)
		# a bright decal so even a slow turn is unmistakable
		var badge := MeshInstance3D.new()
		badge.name = "TyreDecal" + side_name
		var decal_box := BoxMesh.new()
		decal_box.size = Vector3(0.005, 0.045, 0.11)
		badge.mesh = decal_box
		badge.material_override = decal
		badge.position = Vector3(face_x, radius * 0.55, 0.0)
		badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(badge)
	return {"rim": rim_mat, "decal": decal, "band": band_mat}


func wheel_roles() -> Dictionary:
	## Debug/test helper: role -> local hub position.
	var out: Dictionary = {}
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := get_node_or_null(name) as VehicleWheel3D
		if w:
			out[name] = w.position - Vector3(0.0, REST, 0.0)
	return out


func _animate_wheels(delta: float, forward_speed: float) -> void:
	var radius: float = maxf(_wheel_radius_avg, 0.1)
	var roll_rate: float = forward_speed / radius
	_wheel_roll = fposmod(_wheel_roll + roll_rate * delta, TAU)
	for item in _wheel_meshes:
		var vis: Node3D = item["vis"]
		var wheel: VehicleWheel3D = item["wheel"]
		if vis == null or not is_instance_valid(vis) or wheel == null:
			continue
		# VehicleWheel3D.transform is Y(yaw) * X(roll). An X rotation leaves the
		# X axis alone, so reading the node's own x axis yields the steering
		# angle and nothing else - the same angle the physics uses, with no sign
		# to guess at.
		var yaw: float = _wheel_yaw(wheel)
		vis.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _wheel_roll)
		_blur_tyre_details(item, roll_rate)


## Fade the asymmetric tyre markings as the wheel spins up.
##
## A wheel at 200 km/h turns about two full revolutions between two rendered
## frames, so a crisp spoke star or sticker cannot read as rotation - it can only
## shimmer. Fading it into the tyre as the angular speed rises is what makes the
## wheel look like it spins instead of flickering.
func _blur_tyre_details(item: Dictionary, roll_rate: float) -> void:
	var blur: float = clampf((absf(roll_rate) - 22.0) / 95.0, 0.0, 1.0)
	var rim: StandardMaterial3D = item.get("rim_mat")
	if rim:
		rim.albedo_color = Color(0.46, 0.47, 0.50).lerp(Color(0.055, 0.055, 0.062), blur)
		rim.roughness = lerpf(0.45, 0.95, blur)
		rim.metallic = lerpf(0.70, 0.10, blur)
	var decal: StandardMaterial3D = item.get("decal_mat")
	if decal:
		decal.albedo_color = Color(0.86, 0.87, 0.88).lerp(Color(0.09, 0.09, 0.10), blur)


## Steering angle carried by a VehicleWheel3D node, in radians.
func _wheel_yaw(wheel: Node3D) -> float:
	var x: Vector3 = wheel.transform.basis.x
	return atan2(-x.z, x.x)


## Rolling angle Godot applies to the wheel node itself, in radians. Used by the
## tests to prove the visual carrier is not fighting the physics node.
func wheel_node_roll(wheel: Node3D) -> float:
	var b: Basis = wheel.transform.basis
	var yaw: float = atan2(-b.x.z, b.x.x)
	var r: Basis = Basis(Vector3.UP, -yaw) * b
	return atan2(r.y.z, r.y.y)


func _find_token(node: Node, token: String) -> Node3D:
	if token in node.name and node is Node3D:
		return node as Node3D
	for c in node.get_children():
		var r := _find_token(c, token)
		if r:
			return r
	return null


func _unhandled_input(event: InputEvent) -> void:
	if is_ai:
		return
	if event.is_action_pressed("toggle_assists"):
		assists["auto_gearbox"] = not bool(assists.get("auto_gearbox", true))
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_PERIOD:
			_on_shift_up()
		elif event.physical_keycode == KEY_Q or event.physical_keycode == KEY_COMMA:
			_on_shift_down()


func apply_throttle(amount: float) -> void:
	set_meta("script_throttle", clampf(amount, 0.0, 1.0))


func apply_brake(amount: float) -> void:
	## Scripted brake input, used by the headless tests.
	set_meta("script_brake", clampf(amount, 0.0, 1.0))


func _on_shift_up() -> void:
	if gearbox and gearbox.request_shift(true):
		if feedback:
			feedback.poke("shift", 0.35)
		if ffb:
			ffb.poke("shift", 0.45)


func _on_shift_down() -> void:
	if gearbox and gearbox.request_shift(false):
		if feedback:
			feedback.poke("shift", 0.35)
		if ffb:
			ffb.poke("shift", 0.45)


## A wall hurts the hands first: the impact goes straight to the wheel.
func _on_crash(severity: float, kind: String) -> void:
	if feedback:
		feedback.poke("crash" if kind == "wall" else "contact", severity)
	if ffb:
		ffb.poke("crash" if kind == "wall" else "contact", severity)


## Was das echte Lenkrad als Lenkbefehl liefert.
##
## Mit eingestelltem Lenkbereich (F1 faehrt 400 Grad statt der 900 des G29)
## liefert `g29_input` zwei Werte: `steer_soft` ist der Ausschlag bis zum
## Anschlag, `steer_lock` der Druck darueber hinaus. Ein Test-Stub ohne diese
## Eigenschaften faellt auf das alte `steer` zurueck.
func _wheel_steer() -> float:
	if g29 == null:
		return 0.0
	if "steer_soft" in g29:
		return float(g29.steer_soft)
	return float(g29.steer)


func _wheel_lock() -> float:
	if g29 == null or not ("steer_lock" in g29):
		return 0.0
	return clampf(float(g29.steer_lock), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if gearbox == null or surfaces == null or tyres == null or crash == null or feedback == null:
		return
	var forward_vel: float = global_transform.basis.z.dot(linear_velocity)
	speed_kmh = linear_velocity.length() * 3.6
	var steer_in := 0.0
	var throttle_in := 0.0
	var brake_in := 0.0
	var clutch_in := 0.0

	if not is_ai and g29 and g29.has_driver_input():
		auto_drive = false
	if not is_ai and (
		Input.get_action_strength("throttle") > 0.15
		or Input.get_action_strength("brake") > 0.15
		or abs(Input.get_axis("steer_left", "steer_right")) > 0.25
	):
		auto_drive = false
	if not is_ai and Input.is_action_just_pressed("toggle_auto"):
		if g29 and g29.cal_phase > 0 and g29.cal_phase < 5:
			pass
		else:
			auto_drive = not auto_drive
	if not is_ai and Input.is_action_just_pressed("reset_car"):
		_reset()

	# --- what is under the tyres --------------------------------------------
	# The track carries no material information, so the surface comes from the
	# car's lateral offset to the racing line (see scripts/surfaces.gd).
	var surface: Dictionary = surfaces.sample(global_position, _line_hint) if surfaces else {}
	if not surface.is_empty():
		_line_hint = int(surface["index"])
		surface_name = String(surface["name"])
	# Der Querabstand ist die einzige Groesse, die "neben der Strecke" von
	# "weit gefahren" unterscheidet (scripts/surfaces.gd).
	surface_offset = float(surface.get("offset", 0.0)) if not surface.is_empty() else 0.0
	surface_rumble = float(surface.get("rumble", 0.0))
	var surface_grip: float = float(surface.get("grip", 1.0))

	if auto_drive or is_ai:
		var ai: Dictionary = _auto_inputs()
		steer_in = ai.steer
		throttle_in = ai.throttle
		brake_in = ai.brake
		clutch_in = 0.0
	else:
		steer_in = Input.get_axis("steer_left", "steer_right")
		throttle_in = Input.get_action_strength("throttle")
		brake_in = Input.get_action_strength("brake")
		if g29 and g29.connected:
			var ws: float = _wheel_steer()
			if absf(ws) > 0.04:
				steer_in = ws
			throttle_in = max(throttle_in, g29.throttle)
			brake_in = max(brake_in, g29.brake)
			clutch_in = g29.clutch
			if g29.clutch > 0.4:
				clutch_assist = false
		if has_meta("script_throttle"):
			throttle_in = float(get_meta("script_throttle"))
			clutch_in = 0.0
			clutch_assist = true
		if has_meta("headless_gas"):
			throttle_in = 0.85
			clutch_in = 0.0
			clutch_assist = true
		if has_meta("script_brake"):
			brake_in = float(get_meta("script_brake"))

	# Speed-sensitive steering: F1 lock-to-lock tightens at speed.
	var spd: float = abs(forward_vel)
	var steer_limit: float = max_steer * lerp(1.0, 0.22, clampf(spd / 70.0, 0.0, 1.0))
	# The driver side of the game is "positive = right": the G29 calibration
	# measures full lock to the right as +1, D / Right Arrow map to +1 and the
	# rim in the cockpit turns clockwise for +1. This hull, however, drives
	# along +Z - the opposite of Godot's own -Z vehicle forward - so a POSITIVE
	# VehicleWheel3D.steering pushes the nose towards +X, which is the driver's
	# LEFT. Mirror the command exactly once, here, so that turning the wheel to
	# the right really turns the car to the right.
	var steer_cmd: float = clampf(steer_in, -1.0, 1.0)
	steering = lerp(steering, -steer_cmd * steer_limit, clampf(delta * 10.0, 0.0, 1.0))
	last_steer = steer_cmd
	# Wie weit draengt der Fahrer ueber den Lenkanschlag hinaus? (0 = frei)
	lock_pressure = _wheel_lock()
	_animate_wheels(delta, forward_vel)

	var engage := 1.0 - clampf(clutch_in, 0.0, 1.0)
	if clutch_assist and clutch_in < 0.1:
		engage = 1.0
	if spd < 0.8 and throttle_in < 0.04 and clutch_in < 0.1:
		engage = 0.0

	# --- tyres first --------------------------------------------------------
	# The tyre model is asked BEFORE the engine, because what the rear tyres can
	# take decides how much torque the driver is allowed to use.
	# Local frame used throughout: +Z is forward, +X is the driver's LEFT and a
	# positive yaw rate turns left - the same convention as `steering`.
	var accel_vec: Vector3 = (linear_velocity - _prev_vel) / maxf(delta, 0.0001)
	var lat_accel: float = accel_vec.dot(global_transform.basis.x.normalized())
	long_accel = accel_vec.dot(global_transform.basis.z.normalized())
	lateral_g = lat_accel / 9.81
	_prev_vel = linear_velocity
	var lateral_speed: float = linear_velocity.dot(global_transform.basis.x.normalized())
	var tyre: Dictionary = tyres.update(delta, {
		"speed": spd,
		"forward_speed": forward_vel,
		"lateral_speed": lateral_speed,
		"steer": last_steer,
		"steer_angle": steering,
		"throttle": throttle_in,
		"brake": brake_in,
		"surface": surface,
		"yaw_rate": angular_velocity.y,
		"damage": float(crash.damage) if crash else 0.0,
		"traction_control": bool(assists.get("traction_control", true)),
	})

	# --- drivetrain ---------------------------------------------------------
	# The gearbox owns ratios, revs and shifting. `auto` is true for the AI and
	# for the player while the automatic gearbox assist is on; switching it off
	# makes the paddles (or Q/E) the only way to change gear.
	var gb: Dictionary = gearbox.update(delta, {
		"speed": maxf(forward_vel, 0.0),
		"throttle": throttle_in,
		"brake": brake_in,
		"clutch": 1.0 - engage,
		"auto": auto_drive or is_ai or bool(assists.get("auto_gearbox", true)),
		"surface_grip": surface_grip,
	})
	gear = int(gb["gear"])
	rpm = float(gb["rpm"])
	engine_force = float(gb["engine_force"])
	if int(gb["shift_event"]) != 0 and feedback:
		feedback.poke("shift", 0.4)
		if ffb:
			ffb.poke("shift", 0.45)
	# A damaged car is slower: broken bodywork costs drag and the engine
	# cannot be used at full power.
	if crash and crash.damage > 0.0:
		engine_force *= 1.0 - 0.45 * crash.damage
	# Traction control: the rear tyres are already past their peak, so the
	# torque is cut instead of being turned into wheelspin.
	var torque_cut: float = float(tyre.get("throttle_cut", 0.0))
	if torque_cut > 0.0 and engine_force > 0.0:
		engine_force *= 1.0 - torque_cut
	var brake_force: float = brake_in * BRAKE_MAX
	if brake_in > 0.08:
		engine_force = min(engine_force, 0.0)
	brake = brake_force

	# --- apply the grip the tyres have left ---------------------------------
	_apply_wheel_grip(tyre, surface)
	slip = float(tyre["slip"])
	downforce = float(tyre["downforce"])
	surface_drag = float(surface.get("drag", 0.0))
	_apply_surface_drag(delta)
	_apply_aero_drag(delta, tyre)

	# --- what the driver feels and what the tub took -------------------------
	crash.update(delta, surface, forward_vel)
	# Was macht die Strecke senkrecht mit dem Auto? Genau das fehlt sonst am
	# Lenkrad: im F1-Spiel wird die Kraft **ueber einer Kuppe kurz leicht** (die
	# Vorderachse wird entlastet), und eine Bodenwelle gibt einen kurzen Stoss.
	# Beides kommt aus einer Groesse, die die Physik schon liefert: der
	# senkrechten Beschleunigung. 1.0 g = das Auto steht auf seinen Raedern,
	# darunter hebt es ab (Kuppe), darueber wird die Feder gestaucht (Welle).
	# Die Zahl wird gefiltert (die Aufhaengung ist hart, roh zappelt sie) und
	# ein Stoss nur bei steigender Flanke ausgeloest, mit Sperrzeit.
	var raw_vert_g: float = 1.0
	if _vert_ready:
		raw_vert_g = (linear_velocity.y - _prev_vel_y) / maxf(delta, 0.0001) / 9.81 + 1.0
	_vert_ready = true
	_prev_vel_y = linear_velocity.y
	vertical_g += (clampf(raw_vert_g, -1.0, 4.0) - vertical_g) * clampf(delta / 0.08, 0.0, 1.0)
	_bump_cd = maxf(_bump_cd - delta, 0.0)
	var compress: float = clampf((vertical_g - COMPRESS_G) / 0.9, 0.0, 1.0)
	if compress > 0.0 and _bump_cd <= 0.0 and spd > 12.0:
		_bump_cd = 0.35
		if feedback:
			feedback.poke("bump", clampf(0.25 + 0.45 * compress, 0.0, 1.0))
		if ffb:
			ffb.poke("bump", clampf(0.25 + 0.45 * compress, 0.0, 1.0))
	# Everything the driver feels comes from this one context: what the front
	# axle is doing, what is under it and what the driver is asking for. The
	# real wheel (`ffb`, UDP to tools/g29_ffb.py) and the in-game feedback
	# (HUD, camera, gamepad) read the same numbers.
	var feel: Dictionary = {
		"steer": last_steer,
		"steer_angle": steering,
		"speed": spd,
		"lateral_g": lateral_g,
		"vertical_g": vertical_g,
		"yaw_rate": angular_velocity.y,
		"surface": surface,
		"slip": slip,
		"slip_front": float(tyre.get("slip_front", 0.0)),
		"slip_rear": float(tyre.get("slip_rear", 0.0)),
		"front_grip": float(tyre.get("front_grip", 1.0)),
		"rear_grip": float(tyre.get("rear_grip", 1.0)),
		"downforce": downforce,
		"understeer": float(tyre.get("understeer", 0.0)),
		"oversteer": float(tyre.get("oversteer", 0.0)),
		"throttle": throttle_in,
		"brake": brake_in,
		"lock_pressure": lock_pressure,
		"traction_control": bool(assists.get("traction_control", true)),
		"crash": crash.last_impact_ms,
		"damage": crash.damage,
	}
	feedback.update(delta, feel)
	# Force feedback for the real wheel (tools/g29_ffb.py listens on UDP).
	if ffb:
		ffb.update(delta, feel)

	_rejoin_cd = maxf(_rejoin_cd - delta, 0.0)
	# Past the runoff apron there is no collision surface at all. Without this
	# the car free-falls for seconds on end (the lap-drive telemetry used to
	# show the player at y = -30 m still doing 175 km/h) and only came back by
	# tumbling into the "car is upside down" reset.
	if global_position.y < VOID_Y and _rejoin_cd <= 0.0:
		rejoin_to_line()
	_watch_stuck(delta)


## Ein Auto, das im Kies liegen bleibt, kommt von allein nicht mehr weg.
##
## Gemessen am 21.09.2026 mit `tests/probe_lap_ffb.gd`: KI-Auto **und**
## Autopilot des Spielerautos fahren nach rund 46 s einmal weit hinaus, bleiben
## bei 13,9 m Querabstand mit 0 km/h im Kies liegen - und stehen dort bis zum
## Ende der Messung, 45 s lang, ohne dass etwas passiert. Der Rundentest
## (`test_lap_drive.gd`) sah das nie, weil er nach 40 s endet. Ein Auto, das
## neben der Strecke steht, ist kein Rennen: wer autonom faehrt, wird nach
## `STUCK_AFTER` Sekunden auf die Linie zurueckgesetzt.
##
## Nur fuer autonome Autos: wer selbst am Lenkrad sitzt, entscheidet selbst, ob
## er rueckwaerts faehrt oder den Reset benutzt. Ein zurueckgesetztes Auto ist
## sichtbar (`rejoin_count`) und wird deshalb auch geprueft.
func _watch_stuck(delta: float) -> void:
	var autonomous: bool = is_ai or auto_drive
	var far: bool = absf(surface_offset) >= STUCK_OFFSET
	if not autonomous or not far or _rejoin_cd > 0.0:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	var stopped: bool = linear_velocity.length() < STUCK_SPEED
	if (stopped and _stuck_time >= STUCK_AFTER) or _stuck_time >= STUCK_AFTER_MOVING:
		rejoin_to_line()
		_stuck_time = 0.0
	if global_transform.basis.y.dot(Vector3.UP) < 0.25:
		_reset()


func _rpm_for_gear(g: int) -> float:
	var fwd: float = max(global_transform.basis.z.dot(linear_velocity), 0.0)
	return clampf(IDLE_RPM + fwd * RATIOS[g] * 95.0, IDLE_RPM, REDLINE)


func _torque_at(r: float) -> float:
	# Peak around 11k, drop to limiter.
	var n: float = clampf((r - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
	var curve: float = sin(n * PI)
	if n > 0.92:
		curve *= 0.35
	return POWER * max(curve, 0.12)


## Hand the tyre model's verdict to the four wheels.
##
## `downforce` is the aero load factor the car used to compute inline (it grows
## with v^2), and `front_grip` / `rear_grip` are what is left after slip angle,
## throttle and the surface have taken their share.
##
## The base numbers are the friction COEFFICIENT the physics uses, so they are
## the car's low-speed grip in g. A slick makes about 1.6-1.8 g before the aero
## load arrives; the tyre model multiplies the aero on top of that.
const FRICTION_FRONT := 1.9
const FRICTION_REAR := 2.1


func _apply_wheel_grip(tyre: Dictionary, surface: Dictionary) -> void:
	var down: float = float(tyre.get("downforce", 1.0))
	var damage: float = float(crash.damage) if crash else 0.0
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w: VehicleWheel3D = get_node_or_null(name)
		if w == null:
			continue
		var front: bool = name.begins_with("Wheel_F")
		var base: float = FRICTION_FRONT if front else FRICTION_REAR
		var grip: float = float(tyre["front_grip"] if front else tyre["rear_grip"])
		if damage > 0.0:
			grip *= 1.0 - 0.30 * damage
		w.wheel_friction_slip = base * down * grip
	# The surface's own pull: on grass and gravel the car is dragged back even
	# while it still rolls, which is why running wide costs so much time.
	surface_drag = float(surface.get("drag", 0.0))


## Grass and gravel do not only take grip away, they pull the car back.
##
## Applied as a central force instead of an engine force, so it does not depend
## on the tyres biting - a car sliding sideways on grass still loses forward
## speed. It must NOT be applied by writing `linear_velocity`: that resets the
## body state the vehicle solver is building on, and the car then loses its
## suspension load and simply sinks onto the floor (measured on a flat plane:
## a car that could not exceed 4 km/h with a 4000 N drive force).
func _apply_surface_drag(delta: float) -> void:
	if surface_drag <= 0.01 or linear_velocity.length() < 0.6:
		return
	var fwd: Vector3 = global_transform.basis.z.normalized()
	var v_long: float = fwd.dot(linear_velocity)
	if absf(v_long) < 0.05:
		return
	# Fade the drag in as the car starts rolling: at a standstill it would
	# otherwise push the car backwards.
	var fade: float = clampf(absf(v_long) / 4.0, 0.0, 1.0)
	apply_central_force(-fwd * signf(v_long) * mass * surface_drag * fade)


## Aerodynamic drag, applied against the direction of travel.
##
## Without it the top speed is whatever the gearbox can pull, which on a 400 m
## straight means a Formula car that never stops accelerating. `tyre_model`
## supplies F = 0.5 * rho * CdA * v^2 (CdA ~ 1.35 m^2 for an F1 car in race
## trim) in Newton, and this turns it into the deceleration a body of `mass`
## feels.
func _apply_aero_drag(_delta: float, tyre: Dictionary) -> void:
	aero_drag_n = float(tyre.get("drag", 0.0))
	var v: float = linear_velocity.length()
	if aero_drag_n <= 1.0 or v < 1.0:
		return
	apply_central_force(-(linear_velocity / v) * aero_drag_n)


## Hand the car the ideal line. The AI drives it and reads its corner speeds
## from it; null (or a stub) leaves the AI on the geometric centre line.
func set_ideal_line(ideal) -> void:
	if ideal != null and ideal.points.size() >= 8:
		ideal_line = ideal
	else:
		ideal_line = null


## `F`: automatic gearbox and traction control are one switch, the way an F1
## game's "assists" profile works. The paddles (or Q/E) always work.
func toggle_assists() -> Dictionary:
	var on: bool = not bool(assists.get("auto_gearbox", true))
	assists["auto_gearbox"] = on
	assists["traction_control"] = on
	return assists


func assists_label() -> String:
	var auto: bool = bool(assists.get("auto_gearbox", true))
	var tcs: bool = bool(assists.get("traction_control", true))
	if auto and tcs:
		return "AUTO + TC"
	if auto:
		return "AUTO"
	if tcs:
		return "TC"
	return "MANUELL"


func _ai_shift() -> void:
	if rpm > 11200.0 and gear < MAX_GEAR:
		gear += 1
	elif rpm < 7000.0 and gear > 1:
		gear -= 1


func _auto_inputs() -> Dictionary:
	var result := {"steer": 0.0, "throttle": 0.55, "brake": 0.0}
	var have_ideal: bool = ideal_line != null and ideal_line.points.size() >= 8
	if racing_line == null or racing_line.points.size() == 0:
		return result
	var speed: float = linear_velocity.length()
	var look: float = lerp(8.0, 30.0, clampf(speed / 55.0, 0.0, 1.0))
	# The line index from this tick's surface sample keeps this a window search
	# instead of a full 1440 point walk on every physics frame.
	var here: int = _line_hint if _line_hint >= 0 else racing_line.closest_index(global_position)
	var target: Vector3
	var v_target: float = -1.0
	if have_ideal:
		# The hint tracks where the CAR is, not where it is aiming: feeding the
		# aim index back in advances the hint by the look-ahead distance on
		# every tick, and after a second the AI is steering at a corner half a
		# lap away (measured: hint 20 -> 444 in 60 ticks).
		if _ideal_hint < 0:
			_ideal_hint = ideal_line.closest_index(global_position)
		else:
			_ideal_hint = ideal_line.closest_index_near(global_position, _ideal_hint)
		var aim: Dictionary = ideal_line.sample_ahead(global_position, look, _ideal_hint)
		if not aim.is_empty():
			target = aim["point"]
			v_target = _ideal_speed_limit(speed, aim)
	if target == Vector3.ZERO:
		target = racing_line.point_at_s(racing_line.s[here] + look)
	var local: Vector3 = to_local(target)
	var angle: float = atan2(local.x, local.z)
	# Driver convention: positive = right. A target sitting on the car's local
	# +X is on the driver's LEFT (the nose is +Z), so it needs a negative
	# command. Without the minus the AI steers away from the racing line.
	result.steer = clampf(-angle / max_steer, -1.0, 1.0)
	if v_target > 0.0:
		# Follow the corner speed the line prescribes. `_ideal_speed_limit()`
		# has already taken the braking distance into account, so this is a
		# plain speed follower and not a corner detector.
		var err: float = v_target - speed
		result.throttle = clampf(0.4 + err * 0.25, 0.0, 1.0)
		if err < -0.4:
			result.throttle = 0.0
			result.brake = clampf(-err * 0.09, 0.0, 1.0)
		return result
	var curve: float = absf(racing_line.flat_tangent(here).signed_angle_to(
		racing_line.flat_tangent(wrapi(here + 12, 0, racing_line.tangents.size())), Vector3.UP))
	var throttle: float = 0.95
	throttle -= clampf(abs(angle) * 1.35, 0.0, 0.8)
	throttle -= clampf(curve * 0.85, 0.0, 0.7)
	result.throttle = clampf(throttle, 0.0, 1.0)
	if abs(angle) > 0.28 and speed > 16.0:
		result.brake = clampf((abs(angle) - 0.28) * 1.8 + curve * 0.5, 0.0, 0.95)
		result.throttle = 0.0
	elif curve > 0.35 and speed > 28.0:
		result.brake = clampf(curve * 0.55, 0.0, 0.7)
		result.throttle = min(result.throttle, 0.25)
	return result


## How fast the car may still be going now and still make every corner in the
## braking horizon: v_now = sqrt(v_i^2 + 2 * a * distance_i), minimised over
## the points ahead. This is what lets the AI brake at the right point for a
## hairpin instead of only noticing the corner it is already in.
func _ideal_speed_limit(speed: float, aim: Dictionary) -> float:
	const BRAKE_A := 24.0     ## m/s^2 the AI plans with (just under the limit)
	const STEP := 10.0        ## m between planning samples
	var horizon: float = clampf(speed * speed / (2.0 * BRAKE_A), 20.0, 190.0)
	var limit: float = float(aim.get("target_speed", -1.0))
	var d: float = 0.0
	while d < horizon:
		d += STEP
		var point: Dictionary = ideal_line.sample_ahead(global_position, d, _ideal_hint)
		if point.is_empty():
			break
		var v_i: float = float(point["target_speed"])
		limit = minf(limit, sqrt(v_i * v_i + 2.0 * BRAKE_A * d))
	return limit


func _reset() -> void:
	reset_count += 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_transform
	engine_force = 0.0
	brake = 10.0
	gear = 1
	rpm = IDLE_RPM
	clutch_assist = true
	if gearbox:
		gearbox.reset()
	if crash:
		crash.reset()
	if feedback:
		feedback.poke("reset", 0.0)


func rejoin_to_line() -> void:
	## Put the car back on the racing line facing the way round, keeping the
	## current gear. Used when a car has fallen out of the world.
	rejoin_count += 1
	_rejoin_cd = 0.5
	var target: Transform3D = spawn_transform
	if racing_line != null and racing_line.points.size() > 0:
		var i: int = racing_line.closest_index(global_position)
		var t: Vector3 = racing_line.tangents[i]
		t.y = 0.0
		if t.length() < 0.001:
			t = Vector3(0, 0, -1)
		# The car's forward axis is +Z, so the basis has to look along -t.
		var basis := Basis.looking_at(-t.normalized(), Vector3.UP)
		target = Transform3D(basis, racing_line.points[i] + Vector3(0.0, 0.35, 0.0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = target
	engine_force = 0.0
	brake = 0.0
	# Stationary on the line: a high gear at idle gives ~0.5 m/s^2 and the car
	# crawls away in 8th, so start the rejoin from first.
	gear = 1
	rpm = IDLE_RPM
	_shift_cd = 0.0
