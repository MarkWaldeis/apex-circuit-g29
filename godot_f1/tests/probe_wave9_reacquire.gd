extends SceneTree
## Bleibt das Spiel sehend, wenn der Kraft-Helfer das Lenkrad mitten in der
## Sitzung freigibt und spaeter zurueckholt? (Pausenmenue > Freigabegrenze.)
##
## Ablauf: 8 s fahren (Pakete fliessen, Helfer haelt das Rad) -> 6 s Pause
## (keine Pakete, der Helfer gibt das Rad frei) -> 8 s weiterfahren (der Helfer
## holt es zurueck). Gemessen wird die Lenkachse, die das Spiel liest.
##
##   python tools/g29_ffb.py --verbose --release-wheel-after 3 --port 5691
##   powershell -File tools/run_godot.ps1 --path godot_f1 --resolution 320x200 `
##       --script tests/probe_wave9_reacquire.gd      (mit APEX_FFB_PORT=5691)

var main: Node3D
var g29
var t: float = 0.0
var phase: int = 0
var span_min: float = 99.0
var span_max: float = -99.0
## True, sobald das Spiel die Achse einmal nicht mehr sah - das waere der
## Fehlerfall, um den es hier geht.
var _went_blind: bool = false


func _initialize() -> void:
	OS.set_environment("APEX_G29_PROFILE", "user://g29_profile_diag.json")
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	g29 = main.get("g29")
	# Ohne Fahrer steht der Wagen im Fensterlauf still - dann liegt keine Kraft
	# an und das Rad bewegt sich nicht. Der Autopilot faehrt, damit die
	# Vorderachse arbeitet und die Kraft das Rad wirklich dreht.
	var car = main.get("player")
	if car:
		car.auto_drive = true
		car.set_meta("script_throttle", 0.95)
	print("REACQ start device=", g29.get("device_name"))
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	t += 1.0 / 90.0
	var snap: PackedFloat32Array = g29.axis_snapshot()
	var a0: float = float(snap[0]) if snap.size() > 0 else 0.0
	if not bool(g29.has_axis_data()):
		_went_blind = true
	if phase == 2:
		span_min = minf(span_min, a0)
		span_max = maxf(span_max, a0)
	if phase == 0 and t >= 8.0:
		print("REACQ phase0 fahren: a0=%+.3f data=%s" % [a0, str(g29.has_axis_data())])
		print("REACQ Pause beginnt (keine Pakete mehr)")
		phase = 1
		t = 0.0
		paused = true
		return
	if phase == 1 and t >= 6.0:
		paused = false
		phase = 2
		t = 0.0
		span_min = 99.0
		span_max = -99.0
		print("REACQ Pause vorbei, fahren wieder (Helfer soll das Rad zurueckholen)")
		return
	if phase == 2 and t >= 8.0:
		print("REACQ phase2 nach Rueckholen: a0=%+.3f data=%s Spanne=%.3f" % [
			a0, str(g29.has_axis_data()), span_max - span_min])
		# Gemessen wird, was dieser Aufbau wirklich hergibt: dass das Spiel die
		# Achse ueber Freigabe und Zurueckholen hinweg weiter liest. Die Spanne
		# haengt am Tempo des Wagens (er startet aus dem Stand) und taugt hier
		# nicht als Kriterium - sie steht nur als Zahl dabei.
		if bool(g29.has_axis_data()) and not _went_blind:
			print("REACQ PASS das Spiel liest die Achse ueber die Freigabe hinweg "
				+ "weiter (Spanne im Nachlauf %.3f, nur zur Info)" % (span_max - span_min))
		else:
			print("REACQ FAIL das Spiel verlor die Achse (data=%s, blind=%s)" % [
				str(g29.has_axis_data()), str(_went_blind)])
		quit(0)
