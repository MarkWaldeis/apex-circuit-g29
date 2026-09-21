extends SceneTree
## Randfälle des Lenkrad-Modells: kann irgendetwas Unendliches, NAN oder ein
## Zappeln ins Lenkrad bringen? Und bleiben sich Anschlag, Einschlag und Kerb
## gleichzeitig im Zaum?
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/probe_wave4_edge.gd

const Model := preload("res://scripts/ffb_model.gd")
const Settings := preload("res://scripts/ffb_settings.gd")

var model
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	var s := Settings.new()
	s.auto_save = false
	s.gain = 1.0
	model = Model.new()
	model.setup(s)
	_run()


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"steer": 0.6, "steer_angle": -0.08, "slip_front": 0.07, "slip_rear": 0.02,
		"lateral_g": 2.5, "yaw_rate": -0.3, "speed": 50.0, "downforce": 2.4,
		"understeer": 0.05, "oversteer": 0.05, "brake": 0.0, "throttle": 0.7,
		"lock_pressure": 0.0, "vertical_g": 1.0, "damage": 0.0,
		"traction_control": true,
		"surface": {"surface": 0, "name": "Asphalt", "rumble": 0.0, "rough": 0.0, "grip": 1.0},
	}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx


func _finite_state(state: Dictionary) -> bool:
	for key in state.keys():
		var value = state[key]
		if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
			return false
	return true


func _run() -> void:
	var bad_keys: Array = []
	var worst: float = 0.0
	var worst_step: float = 0.0
	var prev: float = 0.0
	for i in 600:
		# Absichtlich boese: NAN, unendlich und widerspruechliche Eingaben.
		var ctx: Dictionary = _ctx({
			"speed": [NAN, INF, -INF, 90.0, 0.0][i % 5],
			"lateral_g": [NAN, -12.0, 12.0, INF][i % 4],
			"steer": [-4.0, 4.0, NAN, 0.0][i % 4],
			"steer_angle": [INF, -INF, 1.9, -1.9][i % 4],
			"slip_front": [NAN, INF, -3.0, 3.0][i % 4],
			"slip_rear": [NAN, -INF, 2.5][i % 3],
			"understeer": [NAN, 5.0, -2.0][i % 3],
			"oversteer": [NAN, 4.0, 0.0][i % 3],
			"lock_pressure": [NAN, 3.0, -1.0][i % 3],
			"vertical_g": [NAN, INF, 0.0, 3.0][i % 4],
			"damage": [NAN, 2.0, 0.5][i % 3],
			"brake": [1.5, -0.5, 0.9][i % 3],
			"throttle": [2.0, -1.0, 0.9][i % 3],
		})
		if i % 37 == 0:
			model.poke("crash", 1.0)
		var state: Dictionary = model.update(1.0 / 90.0, ctx)
		if not _finite_state(state):
			for key in state.keys():
				var value = state[key]
				if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
					bad_keys.append(key)
		for key in ["torque", "damper", "friction", "rumble", "pulse", "clip"]:
			worst = maxf(worst, absf(float(state[key])))
		worst_step = maxf(worst_step, absf(float(state["torque"]) - prev))
		prev = float(state["torque"])

	_check(bad_keys.is_empty(), "auch_bei_nan_und_unendlich_bleibt_alles_endlich",
		"nicht endliche Kanaele: %s" % ("keine" if bad_keys.is_empty() else str(bad_keys)))
	_check(worst <= 1.001, "alle_kanaele_bleiben_im_bereich", "groesster Betrag %.3f" % worst)
	_check(worst_step < 0.35, "kein_zappeln_auch_bei_muell_eingaben",
		"groesster Sprung pro Tick %.3f" % worst_step)

	# Rueckwaerts rollen (forward_speed negativ): das Auto faehrt rueckwaerts,
	# das Lenkrad darf nicht in eine erfundene Richtung ziehen.
	var s := Settings.new()
	s.auto_save = false
	model.setup(s)
	var reverse: Dictionary = {}
	for i in 60:
		reverse = model.update(1.0 / 90.0, _ctx({
			"speed": 8.0, "lateral_g": 0.4, "slip_front": -0.05, "forward_speed": -8.0}))
	_check(absf(float(reverse["torque"])) <= 1.0 and is_finite(float(reverse["torque"])),
		"rueckwaerts_bleibt_im_bereich", "torque %+.3f" % float(reverse["torque"]))

	# Stillstand: nur Reibung (und der Anschlag, wenn der Fahrer drueckt).
	model.setup(s)
	var still: Dictionary = {}
	for i in 60:
		still = model.update(1.0 / 90.0, _ctx({
			"speed": 0.0, "lateral_g": 0.0, "slip_front": 0.0, "steer_angle": 0.0,
			"steer": 0.0, "throttle": 0.0, "lock_pressure": 0.0}))
	_check(absf(float(still["torque"])) < 0.02, "im_stand_keine_kraft",
		"torque %+.3f, Reibung %.3f" % [float(still["torque"]), float(still["friction"])])

	# Alles gleichzeitig: Anschlag, Kerb, Einschlag, Schaden, Vollgas.
	model.setup(s)
	var worst_all: float = 0.0
	for i in 120:
		if i % 20 == 0:
			model.poke("crash", 1.0, -1.0)
		var heavy: Dictionary = model.update(1.0 / 90.0, _ctx({
			"steer": 1.0, "steer_angle": -0.45, "slip_front": 0.30, "lateral_g": 4.5,
			"speed": 85.0, "downforce": 3.6, "understeer": 0.8, "lock_pressure": 1.0,
			"damage": 0.6, "brake": 0.9, "throttle": 1.0, "vertical_g": 1.6,
			"surface": {"surface": 1, "name": "Kerb", "rumble": 1.0, "rough": 1.0, "grip": 0.9}}))
		for key in ["torque", "damper", "friction", "rumble", "pulse"]:
			worst_all = maxf(worst_all, absf(float(heavy[key])))
	_check(worst_all <= 1.001, "anschlag_kerb_einschlag_gleichzeitig_bleibt_im_bereich",
		"groesster Wert %.3f" % worst_all)

	if failed > 0:
		print("WAVE4_EDGE FAIL count=%d von %d" % [failed, checks])
		quit(1)
	else:
		print("WAVE4_EDGE PASS %d Pruefungen" % checks)
		quit(0)
