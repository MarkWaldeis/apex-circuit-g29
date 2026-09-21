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
## Zaehler fuer den Aussetzer: wie viele Ticks sah das Spiel keine Achse, wie
## lang war der laengste Zusammenhang - und passierte es waehrend der FAHRT
## (dann spuerbar) oder nur in der Pause (dann harmlos)?
var _went_blind: bool = false
var _blind_ticks: int = 0
var _blind_run: int = 0
var _blind_run_max: int = 0
var _blind_while_driving: int = 0
## Getrennt nach Phase: 0 = erste Fahrt, 1 = Pause, 2 = nach dem Zurueckholen.
var _blind_p0: int = 0
var _blind_p1: int = 0
var _blind_p2: int = 0


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
		_blind_ticks += 1
		_blind_run += 1
		_blind_run_max = maxi(_blind_run_max, _blind_run)
		if phase == 0 or phase == 2:
			_blind_while_driving += 1
		if phase == 0:
			_blind_p0 += 1
		elif phase == 1:
			_blind_p1 += 1
		else:
			_blind_p2 += 1
	else:
		_blind_run = 0
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
		print("REACQ Aussetzer: %d Ticks ohne Achsdaten, laengster %.0f ms, "
			% [_blind_ticks, 1000.0 * float(_blind_run_max) / 90.0]
			+ "davon waehrend der Fahrt: %d" % _blind_while_driving)
		print("REACQ Verteilung: Phase0 (erste Fahrt) %d, Pause %d, Phase2 (nach dem "
			% [_blind_p0, _blind_p1]
			+ "Zurueckholen) %d Ticks" % _blind_p2)
		# Entscheidend ist Phase 2: nach dem Zurueckholen darf kein Aussetzer
		# auftreten. Die Ticks in Phase 0 sind die bekannte Anlaufphase - das
		# G29 meldet erst, wenn sich das Rad bewegt (`_have_data` verlangt
		# |Achse| > 0,02), und ohne Netzteil waeren es Nullen, die nicht als
		# Messung gelten duerfen. Genau deshalb bleibt das so.
		if bool(g29.has_axis_data()) and _blind_p2 == 0:
			print("REACQ PASS das Spiel liest die Achse ueber die Freigabe hinweg "
				+ "weiter (Spanne im Nachlauf %.3f, nur zur Info)" % (span_max - span_min))
		else:
			print("REACQ FAIL nach dem Zurueckholen fehlten Achsdaten: "
				+ "%d Ticks (Phase0 %d, Pause %d), laengster %.0f ms" % [
					_blind_p2, _blind_p0, _blind_p1, 1000.0 * float(_blind_run_max) / 90.0])
		quit(0)
