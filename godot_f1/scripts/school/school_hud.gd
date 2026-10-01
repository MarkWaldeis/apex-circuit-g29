extends CanvasLayer

const CityLayout = preload("res://scripts/school/city_layout.gd")


## Kleine Uebersichtskarte unten rechts: Strassennetz, Uebungsplatz,
## KI-Verkehr und das eigene Auto — Orientierungsuebung wie Navi.
class SchoolMap extends Control:
	var car
	var traffic: Array = []

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var b := Rect2(Vector2(-260, -260), Vector2(520, 420))
		var s := Vector2(size.x / b.size.x, size.y / b.size.y)
		var to_px := func(p: Vector2) -> Vector2:
			return (p - b.position) * s
		# Uebungsplatzflaeche zuerst, damit die Zufahrt drueber liegt.
		var lr: Dictionary = CityLayout.lot()["rect"]
		var la: Vector2 = to_px.call(Vector2(float(lr["x0"]), float(lr["z0"])))
		var lb: Vector2 = to_px.call(Vector2(float(lr["x1"]), float(lr["z1"])))
		draw_rect(Rect2(la, lb - la), Color(0.30, 0.32, 0.38))
		for road in CityLayout.roads():
			draw_line(to_px.call(road["from"]), to_px.call(road["to"]),
				Color(0.62, 0.62, 0.66), 1.8)
		for tc in traffic:
			if is_instance_valid(tc):
				draw_circle(to_px.call(Vector2(tc.global_position.x,
					tc.global_position.z)), 2.4, Color(0.45, 0.75, 1.0))
		if car:
			var cp: Vector2 = to_px.call(Vector2(car.global_position.x,
				car.global_position.z))
			draw_circle(cp, 3.0, Color(1.0, 0.85, 0.2))
			var h: Vector2 = Vector2(car.global_transform.basis.z.x,
				car.global_transform.basis.z.z).normalized()
			draw_line(cp, cp + h * 6.5, Color(1.0, 0.85, 0.2), 1.6)
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
var _dist_label: Label
var _backup_panel: PanelContainer
var _map: SchoolMap
var _backup_cam: Camera3D
var _help: PanelContainer
var _mini_cam: Camera3D
var _blink_t: float = 0.0
var _coach_t: float = 0.0
var _coach_text: String = ""
var _license: Label
var _license_t: float = 0.0
var _license_shown := false
var _spot_t: float = 0.0
var _spot_shown: String = ""


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

	# Einparkhilfe: Abstandsanzeige direkt unter dem Innenspiegel.
	_dist_label = Label.new()
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.label(_dist_label, 18, UI.GOOD)
	_dist_label.visible = false
	top.add_child(_dist_label)

	# Rueckfahrkamera: blickt beim Rueckwaertsgang tief hinter das Auto —
	# erfasst Pylonen/Bordsteine, die der Spiegel nicht sieht.
	var bk := _mirror_panel(Vector2i(360, 170), 78.0)
	_backup_panel = bk[0]
	_backup_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_backup_panel.position = Vector2(-184, -320)
	_backup_panel.visible = false
	root.add_child(_backup_panel)
	_backup_cam = bk[1]

	# Minimap: Ortho-Kamera von oben, folgt dem Auto, Norden zeigt nach oben.
	var mm := _mirror_panel(Vector2i(190, 190), 60.0)
	mm[0].set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mm[0].position = Vector2(-202, -202)
	root.add_child(mm[0])
	_mini_cam = mm[1]
	_mini_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_mini_cam.size = 110.0
	_mini_cam.far = 320.0
	_mini_cam.basis = Basis(Vector3.RIGHT, -PI / 2.0)

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

	# Grosses Erfolgs-Banner, wenn die Prüfungsfahrt bestanden ist.
	_license = Label.new()
	_license.text = "FÜHRERSCHEIN BESTANDEN — Glückwunsch!"
	UI.title(_license, 30)
	_license.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
	_license.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_license.visible = false
	top.add_child(_license)

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

	# Minikarte unten rechts: Strassenplan + Position (Orientierung).
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel", UI.box(UI.BG_DEEP, UI.LINE, 1, 6))
	map_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_panel.position = Vector2(-186, -144)
	root.add_child(map_panel)
	_map = SchoolMap.new()
	_map.custom_minimum_size = Vector2(172, 130)
	map_panel.add_child(_map)

	# --- Hilfe-Overlay (F1): alle Tasten im Überblick --------------------------
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", UI.box(UI.BG_DEEP, UI.LINE, 1, 10))
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.position = Vector2(-230, -210)
	_help.custom_minimum_size = Vector2(460, 0)
	_help.visible = false
	root.add_child(_help)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	_help.add_child(hv)
	var htitle := Label.new()
	htitle.text = "Tasten (F1 schließt)"
	UI.title(htitle, 22)
	hv.add_child(htitle)
	var htext := Label.new()
	htext.text = (
		"WASD / Pfeile – Fahren\n"
		+ "1–6 Gänge · 0/N Leerlauf · V Rückwärts\n"
		+ "Q / E – Blinker links / rechts\n"
		+ "H – Warnblinker · D – Warndreieck · B – Hupe · Leertaste – Handbremse\n"
		+ "L – Abblendlicht · F – Fernlicht · U – Nacht · I – Nebel · M – Nässe · O – Glatteis\n"
		+ "Z – Zwischenbilanz · X – Schild erklären · G – mehr Verkehr\n"
		+ "T – zur nächsten Übung springen\n"
		+ "P – Prüfungsfahrt starten / beenden\n"
		+ "C – Kamera · R – zurücksetzen\n"
		+ "Esc – Menü · F1 – diese Hilfe"
	)
	UI.label(htext, 16, UI.TEXT)
	hv.add_child(htext)


func toggle_help() -> void:
	if _help:
		_help.visible = not _help.visible


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
	if _map:
		_map.car = car
		if instructor:
			_map.traffic = instructor.traffic
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
	var status_text := ""
	if car.get("stalled"):
		status_text = "Motor aus"
	elif car.get("handbrake_on"):
		status_text = "Handbremse"
	# Nach einem Uebungs-Teleport (T) kurz die Station einblenden.
	var spot_now := String(car.get("last_spot")) if car.get("last_spot") != null else ""
	if spot_now != "" and spot_now != _spot_shown:
		_spot_shown = spot_now
		_spot_t = 4.0
	_spot_t -= delta
	if _spot_t > 0.0:
		status_text = "Übung: %s" % _spot_shown
	# Laufende Pruefungsfahrt: Beanstandungszaehler hat Vorrang.
	if instructor and bool(instructor.exam.get("active")):
		status_text = "Prüfung: %d Beanstandung(en)" % int(instructor._exam_errs)
	var dmg: float = float(car.get("damage")) if car.get("damage") != null else 0.0
	if dmg > 0.05:
		status_text += ("  ·  " if status_text != "" else "") + "Schaden %d%%" % int(dmg * 100.0)
	_status.text = status_text

	_stall_warn.visible = bool(car.get("stalled"))
	if _stall_warn.visible:
		var g = car.get("g29")
		var wheel_on: bool = g != null and bool(g.connected)
		_stall_warn.text = "ABGEWÜRGT — Kupplung treten, dann hält der Motor" \
			if wheel_on else "ABGEWÜRGT — der Anlasser startet den Motor neu"

	# Bestandene Pruefungsfahrt -> einmalig das Fuehrerschein-Banner.
	if not _license_shown and instructor \
			and bool(instructor._tasks_done.get("pruefung", false)):
		_license_shown = true
		_license_t = 14.0
		_license.visible = true
	if _license.visible:
		_license_t -= delta
		if _license_t <= 0.0:
			_license.visible = false

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

	# Rueckfahrkamera oben am Heck, steil nach unten — Sicht auf die
	# ersten ~8 m hinter dem Stossfaenger.
	if _backup_panel:
		var rev: bool = car.gear == -1
		_backup_panel.visible = rev
		if rev and _backup_cam:
			_backup_cam.global_transform = car.global_transform * Transform3D(
				Basis(Vector3.RIGHT, -0.55), Vector3(0.0, 1.35, -2.05))

	# Minimap folgt dem Auto — Rotation bleibt auf Norden fixiert.
	if _mini_cam:
		_mini_cam.global_position = Vector3(
			car.global_position.x, 160.0, car.global_position.z)

	# Einparkhilfe: nur sichtbar, solange der Rueckwaertsgang drin ist.
	if _dist_label:
		if car.gear == -1 and car.has_method("rear_distance"):
			_dist_label.visible = true
			var d: float = car.rear_distance()
			if d >= 4.0:
				_dist_label.text = "hinten frei"
				_dist_label.add_theme_color_override("font_color", UI.GOOD)
			else:
				_dist_label.text = "%.1f m" % d
				var col: Color = UI.GOOD if d > 1.5 else (UI.WARN if d > 0.6 else Color(1.0, 0.35, 0.3))
				_dist_label.add_theme_color_override("font_color", col)
		else:
			_dist_label.visible = false
