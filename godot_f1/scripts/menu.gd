extends CanvasLayer
## Apex Circuit menu system: start menu, in-race pause menu, settings screen and
## the G29 calibration flow ("press the button, then move the control").
##
## The input module (scripts/g29_input.gd) is owned by another workstream and may
## temporarily be a stub, so every call into it is guarded and degrades to a
## keyboard-only readout instead of crashing.

const UI := preload("res://scripts/ui_theme.gd")

enum Screen { NONE, START, PAUSE, SETTINGS, CALIBRATE }

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
var _cal_title: Label
var _cal_hint_label: Label
var _cal_note: Label
var _pause_note: Label
var _start_status: Label
var _steer_toggle: Button
var _axis_rows: Array = []
var _cal_axis_rows: Array = []
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
	var parts := _new_screen("Settings", Vector2(1240, 760))
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
	var defaults := _make_button(right, "Kalibrierung zurücksetzen", false, 0, 26)
	defaults.pressed.connect(_reset_to_defaults)
	_steer_toggle = _make_button(right, "Lenkrad invertieren: NEIN", false, 0, 26)
	_steer_toggle.pressed.connect(_toggle_steer_invert)
	_spacer(right, 6)
	var back := _make_button(right, "Zurück", false, 0, 28)
	back.pressed.connect(_on_back)

	var hint := Label.new()
	hint.text = "Kalibrieren: Knopf drücken, dann das genannte Pedal durchtreten bzw. das Lenkrad drehen — das Spiel erkennt die Achse und speichert sie."
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_first_focus[Screen.SETTINGS] = throttle
	return scr


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
	var ok := _g29_call("reset_to_defaults")
	ok = _g29_call("save_profile") or ok
	_note(_cal_note, "Kalibrierung verworfen — die erkannten Achsen bleiben erhalten, die Zuordnung lernt neu." if ok else "Eingabe-Modul nicht verfügbar — Tastatur: W A S D.", 2.6)


func _toggle_steer_invert() -> void:
	var axis: int = _g29_int("steer_axis", 0)
	var want: bool = not _g29_bool("steer_invert", false)
	if _g29_call("apply_manual", ["steer", axis, want]):
		_g29_call("save_profile")
		_note(_cal_note, "Lenkrad invertiert: %s (gespeichert)." % ("JA" if want else "NEIN"), 2.4)
	else:
		_note(_cal_note, "Eingabe-Modul nicht verfügbar — Lenkrad-Invertierung wirkungslos.", 2.6)


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
		_refresh_mapping()
	elif screen == Screen.CALIBRATE:
		_update_readout()
		_poll_calibration()
	elif screen == Screen.START:
		_refresh_start_status()


func _update_readout() -> void:
	var snapshot := _snapshot()
	var connected: bool = _g29_bool("connected", false)
	_update_status_label(connected)
	var mapped: Dictionary = {}
	var keys := ["steer_axis", "throttle_axis", "brake_axis", "clutch_axis"]
	for key in keys:
		if _g29_has(key):
			mapped[_g29_int(key, -1)] = true
	for i in AXIS_COUNT:
		var value: float = snapshot[i]
		if not connected:
			value = 0.0
		var highlight: bool = connected and mapped.has(i)
		_set_row(_axis_rows, i, value, connected, highlight)
		_set_row(_cal_axis_rows, i, value, connected, highlight)


func _update_status_label(connected: bool) -> void:
	## Root agent: surface the input module's device diagnostics (a G29 that
	## enumerates but sends no axis data is the classic "nothing works" case).
	if _status_label == null:
		return
	var hint := str(_g29_get("hardware_hint", ""))
	if not connected:
		_status_label.text = "Kein G29 erkannt — Tastatur: W = Gas, S = Bremse, A/D = Lenken."
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
	var lines := PackedStringArray()
	lines.append("Gas = Achse %d (%s)" % [_g29_int("throttle_axis", 1), _invert_word(_g29_bool("invert_throttle", true))])
	lines.append("Bremse = Achse %d (%s)" % [_g29_int("brake_axis", 2), _invert_word(_g29_bool("invert_brake", true))])
	lines.append("Kupplung = Achse %d (%s)" % [_g29_int("clutch_axis", 3), _invert_word(_g29_bool("invert_clutch", true))])
	lines.append("Lenkrad = Achse %d (%s)" % [_g29_int("steer_axis", 0), _invert_word(_g29_bool("steer_invert", false))])
	_mapping_label.text = "\n".join(lines)
	if _steer_toggle != null:
		_steer_toggle.text = "Lenkrad invertieren: %s" % ("JA" if _g29_bool("steer_invert", false) else "NEIN")


func _invert_word(inverted: bool) -> String:
	return "invertiert" if inverted else "normal"


func _refresh_start_status() -> void:
	if _start_status == null:
		return
	if _g29_bool("connected", false):
		_start_status.text = "G29 verbunden: %s" % str(_g29_get("device_name", "Logitech G29"))
		_start_status.add_theme_color_override("font_color", UI.GOOD)
	else:
		_start_status.text = "Kein G29 erkannt — Tastatur: W = Gas, S = Bremse, A/D = Lenken"
		_start_status.add_theme_color_override("font_color", UI.WARN)


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
