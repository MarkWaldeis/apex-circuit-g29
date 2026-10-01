extends CanvasLayer
## HUD der Fahrschule: Tempo, Gang, Drehzahlband, Kupplungsschleifpunkt,
## Blinker, Fahrlehrer-Meldungen und die Übungsliste.
## `setup(car, g29, instructor)` einmal aufrufen; das HUD liest dann pro Frame.

const UI = preload("res://scripts/ui_theme.gd")

var car
var g29
var instructor

var _speed: Label
var _gear: Label
var _rpm_fill: ColorRect
var _rpm_bar: Control
var _limit_label: Label
var _clutch_bar: ColorRect
var _clutch_mark: ColorRect
var _coach: Label
var _tasks: Label
var _status: Label
var _ind_l: Label
var _ind_r: Label
var _stall_warn: Label
var _mirror_cam: Camera3D
var _mirror_l: Camera3D
var _mirror_r: Camera3D
var _blink_t: float = 0.0
var _coach_t: float = 0.0
var _coach_text: String = ""


func _ready() -> void:
	layer = 10
	_build()


func setup(p_car, p_g29, p_instructor) -> void:
	car = p_car
	g29 = p_g29
	instructor = p_instructor
	if instructor and instructor.has_signal("coached"):
		instructor.coached.connect(_on_coached)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Unten Mitte: Tempo + Gang + Drehzahl --------------------------------
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 4)
	bottom.position = Vector2(-170, -150)
	bottom.custom_minimum_size = Vector2(340, 140)
	root.add_child(bottom)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(row)

	_ind_l = Label.new()
	_ind_l.text = "◀"
	UI.label(_ind_l, 34, UI.TEXT_DIM)
	row.add_child(_ind_l)

	_speed = Label.new()
	_speed.text = "0"
	UI.title(_speed, 58)
	row.add_child(_speed)
	var kmh := Label.new()
	kmh.text = "km/h"
	UI.label(kmh, 22, UI.TEXT_DIM)
	row.add_child(kmh)

	_gear = Label.new()
	_gear.text = "N"
	UI.title(_gear, 46)
	row.add_child(_gear)

	_ind_r = Label.new()
	_ind_r.text = "▶"
	UI.label(_ind_r, 34, UI.TEXT_DIM)
	row.add_child(_ind_r)

	# Drehzahlband mit roter Zone ab 5000/min.
	_rpm_bar = Control.new()
	_rpm_bar.custom_minimum_size = Vector2(320, 14)
	bottom.add_child(_rpm_bar)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rpm_bar.add_child(bg)
	_rpm_fill = ColorRect.new()
	_rpm_fill.color = UI.ACCENT
	_rpm_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rpm_bar.add_child(_rpm_fill)
	var red := ColorRect.new()
	red.color = Color(0.85, 0.10, 0.10, 0.55)
	red.anchor_left = 0.80
	red.anchor_right = 1.0
	red.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	red.anchor_left = 0.80
	red.anchor_top = 0.0
	red.anchor_bottom = 1.0
	_rpm_bar.add_child(red)

	# Kupplungsweg: wie weit ist die Kupplung gedrückt (Schleifpunkt-Markierung).
	var clrow := HBoxContainer.new()
	clrow.add_theme_constant_override("separation", 8)
	clrow.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(clrow)
	var cllab := Label.new()
	cllab.text = "Kupplung"
	UI.label(cllab, 14, UI.TEXT_DIM)
	clrow.add_child(cllab)
	var clbar := Control.new()
	clbar.custom_minimum_size = Vector2(200, 10)
	clrow.add_child(clbar)
	var clbg := ColorRect.new()
	clbg.color = Color(0, 0, 0, 0.55)
	clbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	clbar.add_child(clbg)
	_clutch_bar = ColorRect.new()
	_clutch_bar.color = Color(0.40, 0.62, 0.95)
	_clutch_bar.anchor_bottom = 1.0
	clbar.add_child(_clutch_bar)
	# Schleifpunkt-Markierung (Pedal 0.72 = BITE_OUT im Getriebe).
	_clutch_mark = ColorRect.new()
	_clutch_mark.color = UI.WARN
	_clutch_mark.custom_minimum_size = Vector2(3, 10)
	_clutch_mark.anchor_top = 0.0
	_clutch_mark.anchor_bottom = 1.0
	_clutch_mark.anchor_left = 0.72
	_clutch_mark.anchor_right = 0.72
	clbar.add_child(_clutch_mark)

	# --- Oben Mitte: Fahrlehrer + Tempolimit ---------------------------------
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.position = Vector2(-260, 14)
	top.custom_minimum_size = Vector2(520, 120)
	root.add_child(top)

	var limitrow := HBoxContainer.new()
	limitrow.alignment = BoxContainer.ALIGNMENT_CENTER
	limitrow.add_theme_constant_override("separation", 10)
	top.add_child(limitrow)
	_limit_label = Label.new()
	UI.label(_limit_label, 20, UI.TEXT_DIM)
	limitrow.add_child(_limit_label)
	_status = Label.new()
	UI.label(_status, 20, UI.GOOD)
	limitrow.add_child(_status)

	# Innenspiegel oben mittig, Außenspiegel links/rechts am Bildschirmrand —
	# kleine Viewports mit eigenen Kameras, die hinter das Auto schauen.
	var mirror := _mirror_panel(Vector2i(360, 140), 64.0)
	top.add_child(mirror[0])
	_mirror_cam = mirror[1]

	var ml := _mirror_panel(Vector2i(240, 140), 58.0)
	ml[0].set_anchors_preset(Control.PRESET_CENTER_LEFT)
	ml[0].position = Vector2(12, 60)
	root.add_child(ml[0])
	_mirror_l = ml[1]

	var mr := _mirror_panel(Vector2i(240, 140), 58.0)
	mr[0].set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	mr[0].position = Vector2(-260, 60)
	root.add_child(mr[0])
	_mirror_r = mr[1]

	_coach = Label.new()
	UI.label(_coach, 24, UI.TEXT)
	_coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_coach)

	_stall_warn = Label.new()
	_stall_warn.text = "ABGEWÜRGT — Kupplung treten, dann hält der Motor"
	UI.label(_stall_warn, 20, UI.WARN)
	_stall_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stall_warn.visible = false
	top.add_child(_stall_warn)

	# --- Rechts: Übungsliste --------------------------------------------------
	var tasks_panel := PanelContainer.new()
	tasks_panel.add_theme_stylebox_override("panel", UI.box(UI.BG_DEEP, UI.LINE, 1, 10))
	tasks_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tasks_panel.position = Vector2(-380, 12)
	tasks_panel.custom_minimum_size = Vector2(360, 0)
	root.add_child(tasks_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tasks_panel.add_child(tv)
	var ttitle := Label.new()
	ttitle.text = "Ausbildung"
	UI.title(ttitle, 22)
	tv.add_child(ttitle)
	_tasks = Label.new()
	UI.label(_tasks, 17, UI.TEXT)
	_tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(_tasks)


func _mirror_panel(px: Vector2i, fov: float) -> Array:
	# [PanelContainer, Camera3D] — gerahmter Mini-Viewport mit Weltkamera.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.BG_DEEP, UI.LINE, 1, 6))
	panel.custom_minimum_size = Vector2(px.x + 8, px.y + 8)
	var sub_wrap := SubViewportContainer.new()
	sub_wrap.stretch = true
	sub_wrap.custom_minimum_size = Vector2(px)
	panel.add_child(sub_wrap)
	var vp := SubViewport.new()
	vp.size = px
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_wrap.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 400.0
	vp.add_child(cam)
	cam.current = true
	return [panel, cam]


func _on_coached(text: String, level: int) -> void:
	_coach_text = text
	_coach_t = 6.0 if level == 0 else 3.5
	var col: Color = [UI.TEXT, UI.WARN, Color(1.0, 0.35, 0.3)][clampi(level, 0, 2)]
	_coach.add_theme_color_override("font_color", col)


func _process(delta: float) -> void:
	if car == null:
		return
	_speed.text = str(int(round(car.speed_kmh)))
	_gear.text = car.gear_label() if car.has_method("gear_label") else str(car.gear)
	var frac: float = clampf(car.rpm / 6200.0, 0.0, 1.0)
	_rpm_fill.anchor_right = frac
	_rpm_fill.color = UI.WARN if frac > 0.80 else UI.ACCENT

	# Kupplungsbalken: Pedalstellung (1 = durchgetreten).
	var clutch_v := 0.0
	if g29:
		clutch_v = clampf(g29.clutch, 0.0, 1.0)
	if car.has_method("_clutch_pedal"):
		clutch_v = car._clutch_pedal()
	_clutch_bar.anchor_right = clutch_v

	# Blinker-Pfeile blinken.
	_blink_t += delta
	var on := fmod(_blink_t, 0.9) < 0.45
	var l_on := on and (bool(car.get("indicator_left")) or bool(car.get("hazard")))
	var r_on := on and (bool(car.get("indicator_right")) or bool(car.get("hazard")))
	_ind_l.add_theme_color_override("font_color", UI.ACCENT_BRIGHT if l_on else UI.TEXT_DIM)
	_ind_r.add_theme_color_override("font_color", UI.ACCENT_BRIGHT if r_on else UI.TEXT_DIM)

	# Tempolimit + Verwarnung.
	var limit := -1
	var speeding := false
	if instructor:
		limit = instructor.current_limit()
		speeding = instructor.is_speeding()
	_limit_label.text = ("Limit %d" % limit) if limit > 0 else "Übungsplatz"
	_limit_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if speeding else UI.TEXT_DIM)
	_status.text = "Motor aus" if car.get("stalled") else ("Handbremse" if car.get("handbrake_on") else "")

	_stall_warn.visible = bool(car.get("stalled"))

	# Fahrlehrer-Text läuft ab.
	_coach_t -= delta
	if _coach_t <= 0.0 and _coach_text != "":
		_coach_text = ""
		_coach.text = ""
	elif _coach_text != "":
		_coach.text = _coach_text

	# Übungsliste.
	if instructor and instructor.has_method("task_board"):
		_tasks.text = instructor.task_board()

	# Spiegel folgen dem Auto. Innenspiegel: von der Heckkante leicht geneigt
	# entlang -Z (das Auto fährt entlang +Z). Außenspiegel: seitlich an den
	# Türen, nach hinten-außen gerichtet — das Auto fährt mit vorne entlang
	# +Z, also liegt die linke Türseite bei +X.
	if _mirror_cam:
		_mirror_cam.global_transform = car.global_transform * Transform3D(
			Basis(Vector3.RIGHT, -0.07), Vector3(0.0, 1.75, -1.10))
	if _mirror_l:
		_mirror_l.global_transform = car.global_transform * Transform3D(
			Basis.looking_at(Vector3(0.62, -0.10, -0.78).normalized(), Vector3.UP),
			Vector3(1.05, 1.30, -0.40))
	if _mirror_r:
		_mirror_r.global_transform = car.global_transform * Transform3D(
			Basis.looking_at(Vector3(-0.62, -0.10, -0.78).normalized(), Vector3.UP),
			Vector3(-1.05, 1.30, -0.40))
