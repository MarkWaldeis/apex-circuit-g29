extends SceneTree
## Hardware-Diagnose: in welche Richtung dreht eine POSITIVE Kraft das Lenkrad?
##
## Das Spiel definiert "rechts = +1" (Kalibrierung, Cockpit-Lenkrad, Physik).
## Der Helfer `tools/g29_ffb.py` schickt eine positive Grundkraft als positive
## DirectInput-Kraft. Ob die das Rad nach rechts oder links dreht, ist von
## aussen nicht zu sehen - hier wird es gemessen: das Spiel gibt eine bekannte
## Kraft, und dasselbe Spiel liest, wohin das Rad geht.
##
## Fensterlauf (headless werden keine Joysticks aufgezaehlt):
##   godot --path godot_f1 --resolution 320x200 --script tests/probe_ffb_steer.gd
## oder mit gestartetem Helfer:
##   powershell -File tools/ffb_direction_check.ps1

const PHASES := [
	{"name": "Ruhe (keine Kraft)", "torque": 0.0, "seconds": 1.5},
	{"name": "positive Kraft +0.35", "torque": 0.35, "seconds": 3.0},
	{"name": "Ruhe", "torque": 0.0, "seconds": 1.0},
	{"name": "negative Kraft -0.35", "torque": -0.35, "seconds": 3.0},
	{"name": "loslassen", "torque": 0.0, "seconds": 1.0},
]

var main: Node3D
var g29
var ffb
var phase: int = 0
var phase_frames: int = 0
var sums: Array = []
var counts: Array = []
var samples: Array = []
var raw_sums: Array = []
var raw_samples: Array = []
var failed: int = 0


func _initialize() -> void:
	# Diesen Lauf darf das echte Lenkrad-Profil nicht anfassen: der Test kann
	# nicht headless laufen (headless zaehlt Godot keine Joysticks auf), der
	# Headless-Schutz in save_profile() greift also nicht. Gemessen am
	# 21.09.2026 schrieb dieser Lauf sonst user://g29_profile.json neu.
	OS.set_environment("APEX_G29_PROFILE", "user://g29_profile_diag.json")
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	g29 = main.get("g29")
	# Ohne diesen Schritt bleibt das Spiel im Startmenue stehen, der Baum ist
	# pausiert und der Wagen rechnet gar nicht - dann sendet das Spiel **kein
	# einziges Paket**, der Helfer legt keine Kraft an, das Lenkrad bewegt sich
	# nicht und dieser Test meldet "das Lenkrad bewegt sich nicht", obwohl in
	# Wahrheit nie eine Kraft gesendet wurde. Gemessen am 21.09.2026:
	# tools/ffb_bridge.log zeigte waehrend des ganzen Laufs `0 Pakete [idle]`.
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	var player = main.get("player")
	if player == null:
		print("FFB_STEER FAIL no player car")
		quit(1)
		return
	# Der Wagen soll nicht auf das vom Lenkrad bewegte Steuer reagieren: der
	# Autopilot faehrt, gemessen wird nur, was das Lenkrad tut.
	player.auto_drive = true
	ffb = player.get("ffb")
	if ffb == null:
		print("FFB_STEER FAIL the player car has no force-feedback link")
		quit(1)
		return
	if g29 == null or not g29.get("connected"):
		print("FFB_STEER FAIL no wheel connected (G29 an? Netzteil dran?)")
		quit(1)
		return
	ffb.force_torque_override = 0.0
	for i in PHASES.size():
		sums.append(0.0)
		counts.append(0)
		raw_sums.append(0.0)
	var raw: PackedFloat32Array = g29.axis_snapshot() if g29.has_method("axis_snapshot") else PackedFloat32Array()
	print("FFB_STEER device=", g29.get("device_name"),
		" live=", g29.get("axes_live"),
		" data=", g29.has_axis_data() if g29.has_method("has_axis_data") else "?",
		" a0=", raw[0] if raw.size() > 0 else 0.0)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	if phase >= PHASES.size():
		return
	var current: Dictionary = PHASES[phase]
	ffb.force_torque_override = float(current["torque"])
	var s: float = float(g29.get("steer_soft")) if "steer_soft" in g29 else float(g29.get("steer"))
	sums[phase] = float(sums[phase]) + s
	# Rohwert der Lenkachse mitmessen: nur so ist von aussen zu sehen, ob das
	# Rad ueberhaupt still steht oder ob es der Kraft folgt - und in welche
	# Richtung. Ohne diese Zahl meldet der Test "bewegt sich nicht", auch wenn
	# die Kraft sehr wohl anliegt (Steuerbefehl durch Totzone/Soft Lock 0).
	var snap: PackedFloat32Array = g29.axis_snapshot() if g29.has_method("axis_snapshot") else PackedFloat32Array()
	if snap.size() > 0:
		raw_sums[phase] = float(raw_sums[phase]) + snap[0]
	counts[phase] = int(counts[phase]) + 1
	phase_frames += 1
	var want: int = int(round(float(current["seconds"]) * 90.0))
	if phase_frames >= want:
		var mean: float = float(sums[phase]) / maxf(float(counts[phase]), 1.0)
		var mean_raw: float = float(raw_sums[phase]) / maxf(float(counts[phase]), 1.0)
		samples.append(mean)
		raw_samples.append(mean_raw)
		print("FFB_STEER phase=%d %s: Mittelwert Lenkung %+.3f (Achse %+.3f) ueber %d Ticks" % [
			phase, String(current["name"]), mean, mean_raw, int(counts[phase])])
		phase += 1
		phase_frames = 0
		if phase >= PHASES.size():
			_report()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _report() -> void:
	ffb.force_torque_override = 0.0
	var rest: float = float(samples[0])
	var pos: float = float(samples[1])
	var neg: float = float(samples[3])
	var moved: float = maxf(absf(pos - rest), absf(neg - rest))
	var raw_moved: float = 0.0
	if raw_samples.size() == PHASES.size():
		raw_moved = maxf(absf(float(raw_samples[1]) - float(raw_samples[0])),
			absf(float(raw_samples[3]) - float(raw_samples[0])))
	_check(moved > 0.03, "das_lenkrad_bewegt_sich_ueberhaupt",
		"Ruhe %+.3f, +Kraft %+.3f, -Kraft %+.3f" % [rest, pos, neg])
	_check(raw_moved > 0.05, "die_achse_folgt_der_kraft",
		"Achse Ruhe %+.3f, +Kraft %+.3f, -Kraft %+.3f" % [
			float(raw_samples[0]) if raw_samples.size() > 0 else 0.0,
			float(raw_samples[1]) if raw_samples.size() > 1 else 0.0,
			float(raw_samples[3]) if raw_samples.size() > 3 else 0.0])
	# Ohne Achsendaten gibt es kein Ergebnis. Frueher stand hier trotzdem
	# "positive Kraft dreht nach LINKS" - ein Fehlalarm, der wie eine Messung
	# aussieht (genau der Fall "G29 liefert keine Reports").
	if raw_moved <= 0.05:
		print("FFB_STEER ERGEBNIS: UNBEKANNT - das Lenkrad hat sich nicht bewegt "
			+ "(keine Achsendaten, Netzteil?, Rad festgehalten?). Keine Aussage "
			+ "ueber die Kraftrichtung.")
	elif float(raw_samples[1]) > float(raw_samples[3]):
		print("FFB_STEER ERGEBNIS: positive Kraft dreht nach RECHTS (+1) - "
			+ "die Kraftrichtung des Modells passt ohne Umdrehen.")
	else:
		print("FFB_STEER ERGEBNIS: positive Kraft dreht nach LINKS - im Menue "
			+ "'Kraftrichtung: umgekehrt' waehlen (oder der Helfer laeuft mit --invert).")
	print("FFB_STEER done failed=%d" % failed)
	quit(1 if failed > 0 else 0)
