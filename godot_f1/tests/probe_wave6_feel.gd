extends SceneTree
## Dauerverträglichkeit: Was liegt über eine ganze Runde und über die Zeit
## wirklich am Lenkrad an - und gibt es einen Kanal, der zur Dauerberieselung
## wird?
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_wave6_feel.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

var model


func _initialize() -> void:
	var s := Settings.new()
	s.auto_save = false
	s.invert = false
	model = Model.new()
	model.setup(s)
	_run()


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"steer": 0.0, "steer_angle": 0.0, "slip_front": 0.0, "slip_rear": 0.0,
		"lateral_g": 0.0, "yaw_rate": 0.0, "speed": 60.0, "downforce": 2.6,
		"understeer": 0.0, "oversteer": 0.0, "brake": 0.0, "throttle": 0.8,
		"lock_pressure": 0.0, "vertical_g": 1.0, "damage": 0.0,
		"traction_control": true,
		"surface": {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0},
	}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx


func _settle(ctx: Dictionary, ticks: int = 40) -> Dictionary:
	var out: Dictionary = {}
	for i in ticks:
		out = model.update(1.0 / 90.0, ctx)
	return out


func _run() -> void:
	print("---- FFB_DAUER ----")

	# 1. Asphalt-Textur auf der Geraden: die Grundberieselung.
	var flat_road: Dictionary = _settle(_ctx())
	print("Geradeaus 216 km/h: Ruetteln %.3f @ %.0f Hz (Quelle %s), Daempfung %.3f" % [
		float(flat_road["rumble"]), float(flat_road["rumble_hz"]),
		String(flat_road["source"]), float(flat_road["damper"])])
	print("  -> bei 90 Hz sind das %.0f Ruettel-Zyklen pro Minute (%s)" % [
		60.0 * float(flat_road["rumble_hz"]), "leise" if float(flat_road["rumble"]) < 0.2 else "spuerbar"])

	# 2. Unwucht nach Schaden: haengt sie am Schaden oder bleibt sie stehen?
	print("Unwucht nach Schaden (Grundtempo 216 km/h):")
	for damage in [0.0, 0.05, 0.11, 0.22, 0.44, 0.66, 1.0]:
		var st: Dictionary = _settle(_ctx({"damage": damage}))
		print("  Schaden %.2f -> Ruetteln %.3f @ %.0f Hz (%s)" % [
			damage, float(st["rumble"]), float(st["rumble_hz"]), String(st["source"])])

	# 3. Was ist auf einer sauberen Runde die lauteste Dauerquelle?
	#    (Eine Runde besteht aus Geraden, Boegen, gelegentlich Kerb.)
	var clean_lap: Array = []
	for i in 1200:
		var phase: float = float(i) / 1200.0
		var corner: bool = sin(phase * TAU * 6.0) > 0.6
		var st: Dictionary = model.update(1.0 / 90.0, _ctx({
			"steer": 0.6 if corner else 0.0,
			"steer_angle": -0.09 if corner else 0.0,
			"slip_front": 0.07 if corner else 0.01,
			"lateral_g": 3.0 if corner else 0.1,
			"throttle": 0.4 if corner else 1.0,
		}))
		clean_lap.append(st)
	var loud: int = 0
	var quiet: int = 0
	var sum: float = 0.0
	var max_rumble: float = 0.0
	for st in clean_lap:
		sum += float(st["rumble"])
		max_rumble = maxf(max_rumble, float(st["rumble"]))
		if float(st["rumble"]) > 0.25:
			loud += 1
		else:
			quiet += 1
	print("Saubere Runde (13,3 s simuliert): Ruetteln Mittel %.3f, Spitze %.3f, "
		% [sum / float(clean_lap.size()), max_rumble]
		+ "%d Ticks ueber 0,25 (%d leise)" % [loud, quiet])

	# 4. Wie oft liegt die Grundkraft im normalen Fahren am Anschlag?
	var clipped: int = 0
	for st in clean_lap:
		if absf(float(st["torque"])) > 0.97:
			clipped += 1
	print("Grundkraft am Anschlag: %d von %d Ticks (%.1f %%)" % [
		clipped, clean_lap.size(), 100.0 * float(clipped) / float(clean_lap.size())])

	# 5. Soft Lock im Stand: kostet der Anschlag bei 400 Grad Kraft, wenn man
	#    rangiert?
	var parked: Dictionary = _settle(_ctx({
		"speed": 0.0, "steer": 1.0, "steer_angle": 0.0, "lateral_g": 0.0,
		"slip_front": 0.0, "lock_pressure": 1.0, "throttle": 0.0}))
	print("Rangieren am Anschlag: Kraft %+.3f, Reibung %.3f, Ruetteln %.3f" % [
		float(parked["torque"]), float(parked["friction"]), float(parked["rumble"])])
	print("---- ENDE FFB_DAUER ----")
	quit(0)
