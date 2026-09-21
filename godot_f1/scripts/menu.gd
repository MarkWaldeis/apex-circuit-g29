extends CanvasLayer
## Apex Circuit menu system: start menu, in-race pause menu, settings screen and
## the G29 calibration flow ("press the button, then move the control").
##
## The input module (scripts/g29_input.gd) is owned by another workstream and may
## temporarily be a stub, so every call into it is guarded and degrades to a
## keyboard-only readout instead of crashing.

const UI := preload("res://scripts/ui_theme.gd")

enum Screen { NONE, START, PAUSE, SETTINGS, CALIBRATE, FFB }

const AXIS_COUNT := 8

var player: Node = null
var g29: Node = null
var main: Node = null

var screen: int = Screen.NONE

var _return_to: int = Screen.START
var _cal_which: String = ""
var _cal_active_seen: bool = false
var _cal_finished: bool = false
var _cal_unavailable: bool = false
var _headless: bool = false

var _root: Control
var _screens: Dictionary = {}
var _first_focus: Dictionary = {}
var _status_label: Label
var _mapping_label: Label
var _settings_note: Label
var _cal_title: Label
var _cal_hint_label: Label
var _cal_note: Label
var _pause_note: Label
var _start_status: Label
var _steer_toggle: Button
var _swap_button: Button
var _assist_button: Button
var _line_button: Button
var _axis_rows: Array = []
var _cal_axis_rows: Array = []
## "throttle"/"brake"/"clutch" -> {name, bar, value, axis} of the settings rows
## that show what the game really receives and let the driver move a pedal to
## another axis without running the whole calibration again.
var _pedal_rows: Dictionary = {}
## Force-Feedback-Seite: die Knoepfe und die Live-Anzeige.
var _ffb_rows: Dictionary = {}
var _ffb_live: Label
var _ffb_note: Label
var _ffb_gain_button: Button
var _ffb_damper_button: Button
var _ffb_rotation_button: Button
var _ffb_enabled_button: Button
var _ffb_effects_button: Button
var _ffb_ontrack_button: Button
var _ffb_kerb_button: Button
var _ffb_offtrack_button: Button
var _ffb_invert_button: Button
var _note_serial: int = 0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_show_screen(Screen.NONE)


func setup(p_player, p_g29, p_main) -> void:
	player = p_player
	g29 = p_g29
	main = p_main
	_connect_g29()


## Headless runs (tests, smoke runs) never wait in the menu.
func headless_autostart() -> void:
	_headless = true
	_root.visible = false
	if get_tree() != null:
		get_tree().paused = false
	print("MENU headless autostart")


func open_start_menu() -> void:
	if _headless:
		return
	_cal_finished = true
	_show_screen(Screen.START)


func resume_game() -> void:
	if _headless:
		return
	_show_screen(Screen.NONE)


func is_in_menu() -> bool:
	return screen != Screen.NONE


func _unhandled_input(event: InputEvent) -> void:
	if _headless:
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _on_back() -> void:
	match screen:
		Screen.CALIBRATE:
			_cancel_calibration()
		Screen.FFB:
			_show_screen(Screen.SETTINGS)
		Screen.SETTINGS:
			_show_screen(_return_to)
		Screen.PAUSE:
			resume_game()
		Screen.START:
			pass ## already the top level
		_:
			_show_screen(Screen.PAUSE)


# ---------------------------------------------------------------- UI building


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MenuRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = UI.BG_DEEP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_screens[Screen.START] = _build_start()
	_screens[Screen.PAUSE] = _build_pause()
	_screens[Screen.SETTINGS] = _build_settings()
	_screens[Screen.CALIBRATE] = _build_calibrate()
	_screens[Screen.FFB] = _build_ffb()
	for key in _screens.keys():
		var scr: Control = _screens[key]
		scr.visible = false


## Returns [screen_root, content_column].
func _new_screen(screen_name: String, min_size: Vector2) -> Array:
	var scr := Control.new()
	scr.name = screen_name
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scr)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_style())
	panel.custom_minimum_size = min_size
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	return [scr, col]


func _heading(col: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	UI.title(l, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return l


func _sub(col: Control, text: String, size: int = 22, color: Color = UI.ACCENT_BRIGHT) -> Label:
	var l := Label.new()
	l.text = text
	UI.label(l, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	return l


func _spacer(col: Control, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)


func _make_button(parent: Control, text: String, primary: bool, width: int = 0, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	UI.button(b, primary, size)
	if width > 0:
		b.custom_minimum_size = Vector2(width, b.custom_minimum_size.y)
	parent.add_child(b)
	return b


func _build_start() -> Control:
	var parts := _new_screen("StartMenu", Vector2(860, 640))
	var scr: Control = parts[0]
	var col: Control = parts[1]

	_heading(col, "APEX CIRCUIT", 84)
	_sub(col, "Formel 1 für Logitech G29", 24)
	_spacer(col, 26)

	var drive := _make_button(col, "Fahren", true, 460, 34)
	drive.pressed.connect(resume_game)
	var settings := _make_button(col, "Einstellungen", false, 460)
	settings.pressed.connect(_open_settings.bind(Screen.START))
	var quit := _make_button(col, "Beenden", false, 460)
	quit.pressed.connect(_quit_game)

	_spacer(col, 22)
	_start_status = Label.new()
	UI.label(_start_status, 19, UI.TEXT_DIM)
	_start_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_start_status)

	var hint := Label.new()
	hint.text = "Enter / Pfeiltasten oder Maus · Esc öffnet im Rennen das Pausenmenü"
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_first_focus[Screen.START] = drive
	return scr


func _build_pause() -> Control:
	var parts := _new_screen("PauseMenu", Vector2(720, 700))
	var scr: Control = parts[0]
	var col: Control = parts[1]

	_heading(col, "PAUSE", 68)
	_sub(col, "Rennen angehalten", 22, UI.TEXT_DIM)
	_spacer(col, 12)

	var resume := _make_button(col, "Weiter", true, 420, 32)
	resume.pressed.connect(resume_game)
	var settings := _make_button(col, "Einstellungen", false, 420, 28)
	settings.pressed.connect(_open_settings.bind(Screen.PAUSE))
	var reset := _make_button(col, "Fahrzeug zurücksetzen", false, 420, 28)
	reset.pressed.connect(_reset_car)
	var restart := _make_button(col, "Neustart", false, 420, 28)
	restart.pressed.connect(_restart_race)
	var to_start := _make_button(col, "Hauptmenü", false, 420, 28)
	to_start.pressed.connect(_back_to_start)
	var quit := _make_button(col, "Beenden", false, 420, 28)
	quit.pressed.connect(_quit_game)

	_pause_note = Label.new()
	UI.label(_pause_note, 18, UI.GOOD)
	_pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pause_note)

	var hint := Label.new()
	hint.text = "Esc = zurück ins Rennen · R setzt das Auto auf die Strecke"
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_first_focus[Screen.PAUSE] = resume
	return scr


func _build_settings() -> Control:
	var parts := _new_screen("Settings", Vector2(1240, 900))
	var scr: Control = parts[0]
	var col: Control = parts[1]

	_heading(col, "Einstellungen", 52)
	_sub(col, "Lenkrad & Pedale", 22)
	_spacer(col, 8)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 46)
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(600, 0)
	row.add_child(left)

	_status_label = Label.new()
	UI.label(_status_label, 20, UI.TEXT_DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status_label)

	var bars_title := Label.new()
	bars_title.text = "Live-Werte der Achsen (a0 … a7)"
	UI.label(bars_title, 17, UI.TEXT_DIM)
	left.add_child(bars_title)

	_axis_rows = _make_axis_rows(left)

	_spacer(left, 6)
	_mapping_label = Label.new()
	UI.label(_mapping_label, 19, UI.TEXT)
	_mapping_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_mapping_label)

	_spacer(left, 6)
	var pedal_title := Label.new()
	pedal_title.text = "Was im Spiel ankommt — falsches Pedal? Hier die Achse umstellen"
	UI.label(pedal_title, 17, UI.TEXT_DIM)
	left.add_child(pedal_title)
	_pedal_rows = _make_pedal_rows(left)

	_settings_note = Label.new()
	UI.label(_settings_note, 18, UI.ACCENT_BRIGHT)
	_settings_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_settings_note)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(500, 0)
	row.add_child(right)

	var throttle := _make_button(right, "Gas kalibrieren", true, 0, 26)
	throttle.pressed.connect(_start_calibration.bind("throttle"))
	var brake := _make_button(right, "Bremse kalibrieren", false, 0, 26)
	brake.pressed.connect(_start_calibration.bind("brake"))
	var clutch := _make_button(right, "Kupplung kalibrieren", false, 0, 26)
	clutch.pressed.connect(_start_calibration.bind("clutch"))
	var steer := _make_button(right, "Lenkrad kalibrieren", false, 0, 26)
	steer.pressed.connect(_start_calibration.bind("steer"))
	var all := _make_button(right, "Alles kalibrieren", false, 0, 26)
	all.pressed.connect(_start_calibration.bind("all"))
	_swap_button = _make_button(right, "Gas ⟷ Bremse tauschen", false, 0, 26)
	_swap_button.pressed.connect(_swap_pedals)
	var defaults := _make_button(right, "Kalibrierung zurücksetzen", false, 0, 26)
	defaults.pressed.connect(_reset_to_defaults)
	_steer_toggle = _make_button(right, "Lenkrad invertieren: NEIN", false, 0, 26)
	_steer_toggle.pressed.connect(_toggle_steer_invert)
	var ffb_button := _make_button(right, "Force Feedback (Lenkrad-Gefühl) …", false, 0, 26)
	ffb_button.pressed.connect(_open_ffb)
	_spacer(right, 10)
	# Fahrhilfen: der Wagen fährt sich mit Automatik und Traktionskontrolle
	# ruhiger, ohne ist er der ehrliche Formel-1-Wagen. Beides geht auch im
	# Rennen mit `F`, damit man es nicht erst im Menü einschalten muss.
	var assist_title := Label.new()
	assist_title.text = "Fahrhilfen (im Rennen: F)"
	UI.label(assist_title, 17, UI.TEXT_DIM)
	right.add_child(assist_title)
	_assist_button = _make_button(right, "Automatik + TC", false, 0, 26)
	_assist_button.pressed.connect(_toggle_assists)
	_line_button = _make_button(right, "Ideallinie: AN  (im Rennen: L)", false, 0, 26)
	_line_button.pressed.connect(_toggle_line)
	_refresh_assist_button()
	_spacer(right, 6)
	var back := _make_button(right, "Zurück", false, 0, 28)
	back.pressed.connect(_on_back)

	var hint := Label.new()
	hint.text = "Kalibrieren: Knopf drücken, dann das genannte Pedal durchtreten bzw. das Lenkrad drehen — das Spiel erkennt die Achse und speichert sie. Trittst du Gas und oben füllt sich trotzdem die Bremse, tausche die beiden oder stelle die Achse von Hand um."
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_first_focus[Screen.SETTINGS] = throttle
	return scr


## Die Force-Feedback-Seite: genau die Regler, die auch das offizielle Spiel
## hat (Stärke, Dämpfung, Effekte, Lenkbereich) - mit einer Live-Anzeige, die
## zeigt, was gerade wirklich ans Lenkrad geht. Details und Messwerte stehen in
## docs/FFB_F1_STYLE_PLAN.md.
func _build_ffb() -> Control:
	var parts := _new_screen("Ffb", Vector2(1100, 820))
	var scr: Control = parts[0]
	var col: Control = parts[1]

	_heading(col, "Force Feedback", 52)
	_sub(col, "Das Lenkrad-Gefühl wie im offiziellen Formel-1-Spiel", 22)
	_spacer(col, 10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 46)
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(560, 0)
	row.add_child(left)

	_ffb_enabled_button = _make_button(left, "Force Feedback: AN", true, 0, 26)
	_ffb_enabled_button.pressed.connect(_cycle_ffb_enabled)
	_ffb_gain_button = _make_button(left, "Stärke: 75 %", false, 0, 26)
	_ffb_gain_button.pressed.connect(_cycle_ffb_gain)
	_ffb_damper_button = _make_button(left, "Dämpfung: MITTEL", false, 0, 26)
	_ffb_damper_button.pressed.connect(_cycle_ffb_damper)
	_ffb_effects_button = _make_button(left, "Rütteln (Kerb/Gelände): AN", false, 0, 26)
	_ffb_effects_button.pressed.connect(_cycle_ffb_effects)
	_ffb_ontrack_button = _make_button(left, "On Track Effects: 100 %", false, 0, 26)
	_ffb_ontrack_button.pressed.connect(_cycle_ffb_ontrack)
	_ffb_kerb_button = _make_button(left, "Rumble Strip Effects: 100 %", false, 0, 26)
	_ffb_kerb_button.pressed.connect(_cycle_ffb_kerb)
	_ffb_offtrack_button = _make_button(left, "Off Track Effects: 100 %", false, 0, 26)
	_ffb_offtrack_button.pressed.connect(_cycle_ffb_offtrack)
	_ffb_rotation_button = _make_button(left, "Lenkbereich: 400°", false, 0, 26)
	_ffb_rotation_button.pressed.connect(_cycle_ffb_rotation)
	_ffb_invert_button = _make_button(left, "Kraftrichtung: normal", false, 0, 26)
	_ffb_invert_button.pressed.connect(_toggle_ffb_invert)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(430, 0)
	row.add_child(right)

	_spacer(right, 4)
	var live_title := Label.new()
	live_title.text = "Was gerade ans Lenkrad geht"
	UI.label(live_title, 18, UI.TEXT_DIM)
	right.add_child(live_title)
	_ffb_live = Label.new()
	UI.label(_ffb_live, 20, UI.ACCENT_BRIGHT)
	_ffb_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_ffb_live)

	_spacer(right, 10)
	var back := _make_button(right, "Zurück", false, 0, 28)
	back.pressed.connect(_on_back)

	var hint := Label.new()
	hint.text = ("Im Logitech G HUB: Betriebsbereich 900°, Zentrierfeder AUS, "
		+ "Dämpfung so niedrig wie möglich — sonst kommt von den feinen Signalen "
		+ "nichts an. Den Kraft-Helfer startet „Apex Circuit FFB starten.cmd“ "
		+ "(oder „python tools/g29_ffb.py“); er ist optional, das Spiel läuft "
		+ "auch ohne ihn. Fühlt es sich verkehrt herum an, drehe die "
		+ "Kraftrichtung um.\n\n"
		+ "Stärke, Lenkbereich und die drei Rüttel-Regler (On Track / Rumble "
		+ "Strip / Off Track) sind dieselben wie im offiziellen Spiel; "
		+ "400° ist dort die Formel-1-Einstellung. Jedes Rüttel-Band wirkt "
		+ "für sich: den Kerb leiser stellen lässt das Kies-Mahlen stehen. "
		+ "Das Spiel bildet diesen "
		+ "Bereich auf die 900° des G29 ab und baut den Anschlag selbst "
		+ "(Soft Lock) — man spürt die Wand.")
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_ffb_note = Label.new()
	UI.label(_ffb_note, 18, UI.ACCENT_BRIGHT)
	_ffb_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_ffb_note)

	_refresh_ffb_buttons()
	_first_focus[Screen.FFB] = _ffb_enabled_button
	return scr


func _open_ffb() -> void:
	_refresh_ffb_buttons()
	_show_screen(Screen.FFB)


func _ffb_settings():
	if main == null:
		return null
	return main.get("ffb_settings")


func _refresh_ffb_buttons() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	if _ffb_enabled_button:
		_ffb_enabled_button.text = "Force Feedback: %s" % s.enabled_label()
	if _ffb_gain_button:
		_ffb_gain_button.text = "Stärke: %s" % s.gain_label()
	if _ffb_damper_button:
		_ffb_damper_button.text = "Dämpfung: %s" % s.damper_label()
	if _ffb_effects_button:
		_ffb_effects_button.text = "Rütteln (Kerb/Gelände): %s" % s.effects_label()
	if _ffb_ontrack_button:
		_ffb_ontrack_button.text = "On Track Effects (Asphalt): %s" % s.ontrack_label()
	if _ffb_kerb_button:
		_ffb_kerb_button.text = "Rumble Strip Effects (Kerb): %s" % s.kerb_label()
	if _ffb_offtrack_button:
		_ffb_offtrack_button.text = "Off Track Effects (Kies): %s" % s.offtrack_label()
	if _ffb_rotation_button:
		_ffb_rotation_button.text = "Lenkbereich: %s" % s.rotation_label()
	if _ffb_invert_button:
		_ffb_invert_button.text = "Kraftrichtung: %s" % ("umgekehrt" if s.invert else "normal")
		# Wenn die Selbstmessung schon ein Ergebnis hat, steht es dabei - sonst
		# sieht der Fahrer nur einen Schalter und weiss nicht, woher der Wert
		# kommt. Gemessen wird waehrend des Fahrens (ffb_link.gd).
		var link = player.get("ffb") if player != null else null
		if link != null:
			var measured: int = int(link.get("direction_aligned"))
			if measured >= 0:
				_ffb_invert_button.text += " (gemessen: %s)" % (
					"gleichläufig" if measured == 1 else "gegenläufig")
			elif not bool(link.get("auto_direction")):
				_ffb_invert_button.text += " (vom Fahrer)"


func _ffb_live_text() -> String:
	var car = player
	if car == null:
		return "—"
	var link = car.get("ffb")
	if link == null:
		return "kein Lenkradkanal"
	var st: Dictionary = link.last_state
	var percent: float = absf(float(st.get("torque", 0.0))) * 100.0
	var text := "Kraft %3.0f %%   Dämpfung %2.0f %%   Rütteln %2.0f %% @ %2.0f Hz\nSignal: %s" % [
		percent,
		float(st.get("damper", 0.0)) * 100.0,
		float(st.get("rumble", 0.0)) * 100.0,
		float(st.get("rumble_hz", 0.0)),
		str(st.get("source", "-"))]
	if float(st.get("clip", 0.0)) > 0.15:
		text += "   ⚠ AM ANSCHLAG (Kraft kürzen)"
	var s = _ffb_settings()
	if s != null and not bool(s.enabled):
		text = "Force Feedback ist AUS.\n" + text
	return text


func _update_ffb_live() -> void:
	if _ffb_live:
		_ffb_live.text = _ffb_live_text()


func _cycle_ffb_enabled() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.toggle_enabled()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Force Feedback %s." % s.enabled_label(), 3.0)


func _cycle_ffb_gain() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_gain()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Stärke %s — im offiziellen Spiel liegt der Bereich bei 40-70 %%. "
		% s.gain_label(), 4.0)


func _cycle_ffb_damper() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_damper()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Dämpfung %s — hoch heißt ruhig, aber taub; niedrig heißt "
		% s.damper_label() + "lebendig, aber zappelig.", 4.0)


func _cycle_ffb_effects() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.toggle_effects()
	_refresh_ffb_buttons()


## Die drei Bänder des offiziellen Spiels. Jeder Regler wirkt nur auf sein
## eigenes Rütteln: Kerb leiser machen lässt das Kies-Mahlen stehen - genau
## wie "Rumble Strip Effects" und "Off Track Effects" im F1-Menü.
func _cycle_ffb_ontrack() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_ontrack_effects()
	_refresh_ffb_buttons()
	_note(_ffb_note, "On Track Effects %s — die feine Asphalt-Textur bei Tempo."
		% s.ontrack_label(), 4.0)


func _cycle_ffb_kerb() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_kerb_effects()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Rumble Strip Effects %s — das harte, schnelle Rütteln auf dem Kerb."
		% s.kerb_label(), 4.0)


func _cycle_ffb_offtrack() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_offtrack_effects()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Off Track Effects %s — das grobe Mahlen auf Kies und Gras."
		% s.offtrack_label(), 4.0)


func _cycle_ffb_rotation() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	s.cycle_rotation()
	_refresh_ffb_buttons()
	_note(_ffb_note, "Lenkbereich %s. Wichtig: im G HUB auf 900° lassen, "
		% s.rotation_label() + "das Spiel macht den Anschlag selbst.", 4.0)


func _toggle_ffb_invert() -> void:
	var s = _ffb_settings()
	if s == null:
		return
	# Ueber `set_invert`: damit steht in der Datei, dass diese Richtung vom
	# Fahrer kommt, und die Selbstmessung (`ffb_link.gd::measure_direction`)
	# dreht sie nicht mehr um.
	s.set_invert(not bool(s.invert), "fahrer")
	var link = player.get("ffb") if player != null else null
	if link != null:
		link.auto_direction = false
	_refresh_ffb_buttons()
	_note(_ffb_note, "Kraftrichtung %s (vom Fahrer, Automatik aus)." % ("umgekehrt" if s.invert else "normal"), 3.0)


func _build_calibrate() -> Control:
	var parts := _new_screen("Calibrate", Vector2(980, 720))
	var scr: Control = parts[0]
	var col: Control = parts[1]

	_cal_title = _heading(col, "Kalibrierung", 46)

	_cal_hint_label = Label.new()
	UI.label(_cal_hint_label, 32, UI.ACCENT_BRIGHT)
	_cal_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cal_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cal_hint_label.custom_minimum_size = Vector2(0, 120)
	col.add_child(_cal_hint_label)

	var bars_title := Label.new()
	bars_title.text = "Live-Werte der Achsen (a0 … a7)"
	UI.label(bars_title, 17, UI.TEXT_DIM)
	bars_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(bars_title)

	var bars_holder := VBoxContainer.new()
	bars_holder.add_theme_constant_override("separation", 10)
	col.add_child(bars_holder)
	_cal_axis_rows = _make_axis_rows(bars_holder)

	_cal_note = Label.new()
	UI.label(_cal_note, 18, UI.TEXT_DIM)
	_cal_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_cal_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	var cancel := _make_button(buttons, "Abbrechen (Esc)", false, 300, 28)
	cancel.pressed.connect(_cancel_calibration)
	var defaults := _make_button(buttons, "Ohne Kalibrierung weiter", false, 340, 28)
	defaults.pressed.connect(_use_defaults_from_calibration)

	_first_focus[Screen.CALIBRATE] = cancel
	return scr


func _make_axis_rows(parent: Control) -> Array:
	var rows: Array = []
	for i in AXIS_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)

		var name_label := Label.new()
		name_label.text = "a%d" % i
		UI.label(name_label, 17, UI.TEXT_DIM)
		name_label.custom_minimum_size = Vector2(46, 0)
		row.add_child(name_label)

		var bar := UI.bar(ProgressBar.new())
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		var value_label := Label.new()
		value_label.text = "0.00"
		UI.label(value_label, 17, UI.TEXT_DIM)
		value_label.custom_minimum_size = Vector2(84, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		rows.append({"name": name_label, "bar": bar, "value": value_label})
	return rows


## One row per pedal: the mapped value the game will use, plus a button that
## walks that pedal through the axes a0…a7. Colouring the row makes it obvious
## which pedal the driver is moving right now.
func _make_pedal_rows(parent: Control) -> Dictionary:
	var rows: Dictionary = {}
	for entry in [["throttle", "Gas"], ["brake", "Bremse"], ["clutch", "Kupplung"]]:
		var which: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)

		var name_label := Label.new()
		name_label.text = entry[1]
		UI.label(name_label, 19, UI.TEXT)
		name_label.custom_minimum_size = Vector2(116, 0)
		row.add_child(name_label)

		var bar := UI.bar(ProgressBar.new())
		bar.value = 0.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)

		var value_label := Label.new()
		value_label.text = "0 %"
		UI.label(value_label, 18, UI.TEXT_DIM)
		value_label.custom_minimum_size = Vector2(72, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		var axis_button := Button.new()
		UI.button(axis_button, false, 17)
		axis_button.custom_minimum_size = Vector2(170, 52)
		axis_button.pressed.connect(_cycle_pedal_axis.bind(which))
		row.add_child(axis_button)

		rows[which] = {"name": name_label, "bar": bar, "value": value_label, "axis": axis_button}
	return rows


# ------------------------------------------------------------- input module IO


func _connect_g29() -> void:
	if not is_instance_valid(g29):
		return
	if g29.has_signal("calibrated") and not g29.is_connected("calibrated", _on_calibrated):
		g29.connect("calibrated", _on_calibrated)
	if g29.has_signal("calibration_step_changed") and not g29.is_connected("calibration_step_changed", _on_calibration_step):
		g29.connect("calibration_step_changed", _on_calibration_step)
	if g29.has_signal("connection_changed") and not g29.is_connected("connection_changed", _on_connection_changed):
		g29.connect("connection_changed", _on_connection_changed)


func _g29_get(prop: String, fallback):
	if not is_instance_valid(g29):
		return fallback
	var v = g29.get(prop)
	return fallback if v == null else v


func _g29_int(prop: String, fallback: int) -> int:
	return int(_g29_get(prop, fallback))


func _g29_bool(prop: String, fallback: bool) -> bool:
	return bool(_g29_get(prop, fallback))


func _g29_has(prop: String) -> bool:
	return is_instance_valid(g29) and g29.get(prop) != null


func _g29_call(method: String, args: Array = []) -> bool:
	if not is_instance_valid(g29) or not g29.has_method(method):
		return false
	g29.callv(method, args)
	return true


## "Connected" is not enough: a G29 without power enumerates and then reports a
## flat 0.0 on every axis. Only real data may be shown as a live value.
func _g29_axis_data() -> bool:
	if is_instance_valid(g29) and g29.has_method("has_axis_data"):
		return bool(g29.call("has_axis_data"))
	return _g29_bool("connected", false) and _g29_bool("axes_live", true)


func _snapshot() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(AXIS_COUNT)
	if is_instance_valid(g29) and g29.has_method("axis_snapshot"):
		var raw = g29.call("axis_snapshot")
		if raw is PackedFloat32Array:
			var packed: PackedFloat32Array = raw
			for i in mini(AXIS_COUNT, packed.size()):
				out[i] = clampf(packed[i], -1.0, 1.0)
			return out
		if raw is Array:
			var plain: Array = raw
			for i in mini(AXIS_COUNT, plain.size()):
				out[i] = clampf(float(plain[i]), -1.0, 1.0)
			return out
	var dev: int = _g29_int("device", -1)
	if dev >= 0:
		for i in AXIS_COUNT:
			out[i] = clampf(Input.get_joy_axis(dev, i), -1.0, 1.0)
	return out


func _on_connection_changed(_connected: bool, _device_name: String) -> void:
	## Values are polled every frame — nothing to do beyond a friendly refresh.
	pass


func _on_calibration_step(_step: int, hint: String) -> void:
	if _cal_hint_label != null and hint != "":
		_cal_hint_label.text = hint


func _on_calibrated() -> void:
	_finish_calibration()


# -------------------------------------------------------------------- screens


func _show_screen(target: int) -> void:
	screen = target
	if _root == null:
		return
	_root.visible = target != Screen.NONE
	for key in _screens.keys():
		var scr: Control = _screens[key]
		scr.visible = int(key) == target
	if get_tree() != null:
		get_tree().paused = target != Screen.NONE
	if target == Screen.NONE:
		_release_focus()
	else:
		_grab_first_focus(target)
	if target == Screen.START:
		_refresh_start_status()


func _grab_first_focus(target: int) -> void:
	var btn = _first_focus.get(target)
	if btn is Control:
		btn.call_deferred("grab_focus")


func _release_focus() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _open_settings(return_to: int) -> void:
	_return_to = return_to
	_show_screen(Screen.SETTINGS)


func _back_to_start() -> void:
	_show_screen(Screen.START)


func _quit_game() -> void:
	get_tree().quit()


func _restart_race() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.reload_current_scene()


func _reset_car() -> void:
	var ok := false
	if player != null and is_instance_valid(player) and player.has_method("_reset"):
		player.call("_reset")
		ok = true
	if ok:
		_note(_pause_note, "Fahrzeug zurückgesetzt.", 2.2)
	else:
		_note(_pause_note, "Zurücksetzen ist in diesem Build nicht möglich.", 2.2)


func _reset_to_defaults() -> void:
	_apply_reset_to_defaults()


## Fahrhilfen an/aus: genau derselbe Schalter wie `F` im Rennen, damit Menü und
## Taste nie unterschiedliche Dinge erzählen.
func _toggle_assists() -> void:
	if player != null and player.has_method("toggle_assists"):
		player.toggle_assists()
	_refresh_assist_button()


func _toggle_line() -> void:
	if main == null:
		return
	var guide = main.get("guide")
	if guide == null or not guide.has_method("set_enabled"):
		return
	guide.set_enabled(not guide.is_enabled())
	_line_button.text = "Ideallinie: %s  (im Rennen: L)" % ("AN" if guide.is_enabled() else "AUS")


func _refresh_assist_button() -> void:
	if _assist_button == null:
		return
	if player != null and player.has_method("assists_label"):
		_assist_button.text = "Fahrhilfen: %s  (im Rennen: F)" % String(player.assists_label())
	else:
		_assist_button.text = "Fahrhilfen"


func _apply_reset_to_defaults() -> void:
	var ok := _g29_call("reset_to_defaults")
	ok = _g29_call("save_profile") or ok
	_note_visible("Kalibrierung verworfen — die erkannten Achsen bleiben erhalten, die Zuordnung lernt neu." if ok else "Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)


func _toggle_steer_invert() -> void:
	var axis: int = _g29_int("steer_axis", 0)
	var want: bool = not _g29_bool("steer_invert", false)
	if _g29_call("apply_manual", ["steer", axis, want]):
		_g29_call("save_profile")
		_note_visible("Lenkrad invertiert: %s (gespeichert)." % ("JA" if want else "NEIN"), 2.4)
	else:
		_note_visible("Eingabe-Modul nicht verfügbar — Lenkrad-Invertierung wirkungslos.", 2.6)


## Move one pedal through the axes a0 … a7 by hand. The input module keeps the
## rest position of the new axis and learns the pressed end on the next press,
## so a manual assignment can never end up mirrored either.
func _cycle_pedal_axis(which: String) -> void:
	if not _g29_has(which + "_axis"):
		_note_visible("Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)
		return
	var current: int = _g29_int(which + "_axis", -1)
	var next_axis: int = _next_free_axis(which, current)
	if _g29_call("apply_manual", [which, next_axis, true]):
		_refresh_mapping()
		_refresh_pedal_rows()
		_note_visible("%s liegt jetzt auf Achse a%d — Pedal einmal ganz durchtreten, dann lernt das Spiel den Weg." % [
			_which_name(which), next_axis], 4.0)
	else:
		_note_visible("Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)


## Walk to the next axis that no other control uses, so a pedal can never land
## on the steering axis or on top of another pedal by accident.
func _next_free_axis(which: String, current: int) -> int:
	var used: Array = [_g29_int("steer_axis", -1)]
	for other in ["throttle", "brake", "clutch"]:
		if other != which:
			used.append(_g29_int(other + "_axis", -1))
	var axis: int = current if current >= 0 else -1
	for _step in AXIS_COUNT:
		axis = (axis + 1) % AXIS_COUNT
		if not used.has(axis):
			return axis
	return current if current >= 0 else 0


func _swap_pedals() -> void:
	if not _g29_has("throttle_axis") or not _g29_has("brake_axis"):
		_note_visible("Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)
		return
	var gas: int = _g29_int("throttle_axis", -1)
	var bremse: int = _g29_int("brake_axis", -1)
	if gas < 0 or bremse < 0 or gas == bremse:
		_note_visible("Tauschen nicht möglich — Gas und Bremse liegen auf derselben Achse a%d." % gas, 3.4)
		return
	var ok := _g29_call("apply_manual", ["throttle", bremse, true])
	ok = _g29_call("apply_manual", ["brake", gas, true]) and ok
	ok = _g29_call("save_profile") and ok
	_refresh_mapping()
	_refresh_pedal_rows()
	if ok:
		_note_visible("Getauscht: Gas = a%d, Bremse = a%d (gespeichert)." % [bremse, gas], 3.4)
	else:
		_note_visible("Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)


func _start_calibration(which: String) -> void:
	_cal_which = which
	_cal_finished = false
	_cal_active_seen = false
	_cal_unavailable = false
	_cal_title.text = "Kalibrierung: %s" % _which_name(which)
	_cal_hint_label.text = "Bereit …"
	_cal_note.text = ""
	_show_screen(Screen.CALIBRATE)

	var started := false
	match which:
		"throttle", "brake", "clutch":
			started = _g29_call("begin_pedal_calibration", [which])
		"steer":
			started = _g29_call("begin_steer_calibration")
		"all":
			started = _g29_call("begin_calibration")
	if not started:
		_cal_unavailable = true
		_cal_hint_label.text = "Eingabe-Modul nicht verfügbar"
		_cal_note.text = "Dieser Build liest noch kein G29 — Tastatur: W = Gas, S = Bremse, A/D = Lenken."
		await get_tree().create_timer(2.6).timeout
		if is_inside_tree() and screen == Screen.CALIBRATE:
			_show_screen(Screen.SETTINGS)
		_cal_unavailable = false


func _cancel_calibration() -> void:
	_g29_call("cancel_calibration")
	_cal_finished = true
	if screen == Screen.CALIBRATE:
		_show_screen(Screen.SETTINGS)


func _use_defaults_from_calibration() -> void:
	if _g29_call("skip_calibration"):
		_g29_call("save_profile")
		_cal_finished = true
		_cal_hint_label.text = "Ohne Kalibrierung weiter — die Pedale werden automatisch geschätzt"
		await get_tree().create_timer(0.8).timeout
		if is_inside_tree() and screen == Screen.CALIBRATE:
			_show_screen(Screen.SETTINGS)
	else:
		_cancel_calibration()


func _finish_calibration() -> void:
	if _cal_finished:
		return
	_cal_finished = true
	_g29_call("save_profile")
	if _cal_hint_label != null:
		_cal_hint_label.text = "Fertig"
	if _cal_note != null:
		_cal_note.text = "Zuordnung erkannt und gespeichert."
	await get_tree().create_timer(0.9).timeout
	if is_inside_tree() and screen == Screen.CALIBRATE:
		_show_screen(Screen.SETTINGS)


func _which_name(which: String) -> String:
	match which:
		"throttle":
			return "Gas"
		"brake":
			return "Bremse"
		"clutch":
			return "Kupplung"
		"steer":
			return "Lenkrad"
		_:
			return "alles"


# -------------------------------------------------------------------- updates


func _process(_delta: float) -> void:
	if _headless or screen == Screen.NONE:
		return
	if screen == Screen.SETTINGS:
		_update_readout()
		_refresh_pedal_rows()
		_refresh_mapping()
	elif screen == Screen.CALIBRATE:
		_update_readout()
		_poll_calibration()
	elif screen == Screen.FFB:
		_update_ffb_live()
	elif screen == Screen.START:
		_refresh_start_status()


func _update_readout() -> void:
	var snapshot := _snapshot()
	var connected: bool = _g29_bool("connected", false)
	_update_status_label(connected)
	var live: bool = connected and _g29_axis_data()
	var mapped: Dictionary = {}
	var keys := ["steer_axis", "throttle_axis", "brake_axis", "clutch_axis"]
	for key in keys:
		if _g29_has(key):
			mapped[_g29_int(key, -1)] = true
	for i in AXIS_COUNT:
		var value: float = snapshot[i]
		if not live:
			value = 0.0
		var highlight: bool = live and mapped.has(i)
		_set_row(_axis_rows, i, value, live, highlight)
		_set_row(_cal_axis_rows, i, value, live, highlight)


func _update_status_label(connected: bool) -> void:
	## Root agent: surface the input module's device diagnostics (a G29 that
	## enumerates but sends no axis data is the classic "nothing works" case).
	if _status_label == null:
		return
	var hint := str(_g29_get("hardware_hint", ""))
	if not connected:
		_status_label.text = "Kein G29 erkannt — Tastatur: W = Gas, S = Bremse, A/D = Lenken."
		_status_label.add_theme_color_override("font_color", UI.WARN)
	elif not _g29_axis_data():
		_status_label.text = ("G29 verbunden (%s), aber noch keine Achsendaten — "
			+ "Lenkrad oder Pedal einmal bewegen. Läuft der Kraft-Helfer schon, "
			+ "Spiel neu starten: das Spiel muss das Lenkrad zuerst öffnen. "
			+ "Sonst Netzteil und Pedalkabel prüfen.") % str(
				_g29_get("device_name", "G29"))
		_status_label.add_theme_color_override("font_color", UI.WARN)
	elif hint != "":
		_status_label.text = hint
		_status_label.add_theme_color_override("font_color", UI.WARN)
	else:
		_status_label.text = "G29 verbunden: %s" % str(_g29_get("device_name", "G29"))
		_status_label.add_theme_color_override("font_color", UI.GOOD)


func _set_row(rows: Array, index: int, value: float, valid: bool, highlight: bool) -> void:
	if index >= rows.size():
		return
	var row: Dictionary = rows[index]
	var bar: ProgressBar = row["bar"]
	var value_label: Label = row["value"]
	var name_label: Label = row["name"]
	if valid:
		bar.value = (clampf(value, -1.0, 1.0) + 1.0) * 50.0
		value_label.text = "%+.2f" % value
	else:
		bar.value = 0.0
		value_label.text = "—"
	value_label.add_theme_color_override("font_color", UI.TEXT if valid else UI.TEXT_DIM)
	name_label.add_theme_color_override("font_color", UI.ACCENT_BRIGHT if highlight else UI.TEXT_DIM)


func _refresh_mapping() -> void:
	if _mapping_label == null:
		return
	if not _g29_has("throttle_axis") and not _g29_has("steer_axis"):
		_mapping_label.text = "Eingabe-Modul: nicht verfügbar.\nTastatur: W = Gas, S = Bremse, A/D = Lenken."
		return
	_mapping_label.text = "Lenkrad = Achse a%d (%s)" % [
		_g29_int("steer_axis", 0), _invert_word(_g29_bool("steer_invert", false))]
	if _steer_toggle != null:
		_steer_toggle.text = "Lenkrad invertieren: %s" % ("JA" if _g29_bool("steer_invert", false) else "NEIN")


func _refresh_pedal_rows() -> void:
	if _pedal_rows.is_empty():
		return
	var connected: bool = _g29_bool("connected", false)
	for which in _pedal_rows.keys():
		var row: Dictionary = _pedal_rows[which]
		var bar: ProgressBar = row["bar"]
		var value_label: Label = row["value"]
		var name_label: Label = row["name"]
		var axis_button: Button = row["axis"]
		var axis: int = _g29_int(which + "_axis", -1)
		var value: float = clampf(float(_g29_get(which, 0.0)), 0.0, 1.0)
		var live: bool = connected and _g29_axis_data() and _g29_bool("axes_live", true)
		if live:
			bar.value = value * 100.0
			value_label.text = "%d %%" % int(round(value * 100.0))
			# Highlight the pedal that is actually being pressed right now.
			name_label.add_theme_color_override("font_color",
				UI.ACCENT_BRIGHT if value > 0.05 else UI.TEXT)
		else:
			bar.value = 0.0
			value_label.text = "—"
			name_label.add_theme_color_override("font_color", UI.TEXT_DIM)
		value_label.add_theme_color_override("font_color",
			UI.ACCENT_BRIGHT if (live and value > 0.05) else UI.TEXT_DIM)
		axis_button.text = ("Achse a%d ändern" % axis) if axis >= 0 else "Achse —"


## Notes belong on the screen the driver is actually looking at; the calibrate
## screen owns `_cal_note`, everything else is shown under the pedal rows.
func _note_visible(text: String, seconds: float) -> void:
	_note(_cal_note if screen == Screen.CALIBRATE else _settings_note, text, seconds)


func _invert_word(inverted: bool) -> String:
	return "invertiert" if inverted else "normal"


func _refresh_start_status() -> void:
	if _start_status == null:
		return
	if not _g29_bool("connected", false):
		_start_status.text = "Kein G29 erkannt — Tastatur: W = Gas, S = Bremse, A/D = Lenken"
		_start_status.add_theme_color_override("font_color", UI.WARN)
	elif not _g29_axis_data():
		_start_status.text = "G29 verbunden, aber ohne Achsendaten — Netzteil und Pedalkabel prüfen"
		_start_status.add_theme_color_override("font_color", UI.WARN)
	else:
		_start_status.text = "G29 verbunden: %s" % str(_g29_get("device_name", "Logitech G29"))
		_start_status.add_theme_color_override("font_color", UI.GOOD)


func _poll_calibration() -> void:
	if _cal_finished or _cal_unavailable:
		return
	var phase: int = _g29_int("cal_phase", 0)
	var hint := str(_g29_get("cal_hint", ""))
	if hint != "":
		_cal_hint_label.text = hint
	elif phase == 0:
		_cal_hint_label.text = "Warte auf Eingabe …"
	if phase >= 5:
		_finish_calibration()
	elif phase > 0:
		_cal_active_seen = true
	elif _cal_active_seen:
		## Module idled again without signalling: accept and persist.
		_finish_calibration()


func _note(label: Label, text: String, seconds: float) -> void:
	if label == null or not is_inside_tree():
		return
	label.text = text
	_note_serial += 1
	var serial := _note_serial
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree() and is_instance_valid(label) and serial == _note_serial:
		label.text = ""
