extends CanvasLayer
## Race HUD: gear, speed, rpm LEDs, and the pedal/mapping readout the driver
## needs to see that gas really is gas after calibrating the G29.

var car
var g29
## The cockpit camera, so the HUD can step aside while the driver looks at the
## dashboard: the centre cluster would sit right on top of the steering wheel.
var cam
var _gear: Label
var _speed: Label
var _rpm: Label
var _hint: Label
var _mapping: Label
var _warn: Label
var _cal: Label
var _leds: HBoxContainer
var _bars: Dictionary = {}   ## "throttle"/"brake"/"clutch" -> ColorRect fill

const PEDALS := [
	{"key": "throttle", "label": "GAS", "color": Color(0.20, 0.85, 0.35)},
	{"key": "brake", "label": "BREMSE", "color": Color(0.90, 0.20, 0.20)},
	{"key": "clutch", "label": "KUPPLUNG", "color": Color(0.30, 0.55, 0.95)},
]


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_cal = _label(root, 28, Color(1, 0.85, 0.2))
	_cal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cal.offset_top = 48
	_cal.offset_left = -460
	_cal.offset_right = 460
	_cal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_leds = HBoxContainer.new()
	_leds.alignment = BoxContainer.ALIGNMENT_CENTER
	_leds.add_theme_constant_override("separation", 4)
	root.add_child(_leds)
	_leds.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_leds.offset_bottom = -118
	_leds.offset_top = -138
	_leds.offset_left = -160
	_leds.offset_right = 160
	for i in 15:
		var led := ColorRect.new()
		led.custom_minimum_size = Vector2(16, 10)
		led.color = Color(0.12, 0.12, 0.12)
		_leds.add_child(led)

	_gear = _label(root, 72, Color(0.95, 0.95, 0.97))
	_gear.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gear.offset_bottom = -36
	_gear.offset_top = -110
	_gear.offset_left = -40
	_gear.offset_right = 40
	_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_speed = _label(root, 22, Color(0.85, 0.88, 0.9))
	_speed.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speed.offset_bottom = -14
	_speed.offset_top = -40
	_speed.offset_left = -80
	_speed.offset_right = 80
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_rpm = _label(root, 16, Color(0.7, 0.72, 0.75))
	_rpm.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_rpm.offset_right = -28
	_rpm.offset_bottom = -28
	_rpm.offset_left = -280
	_rpm.offset_top = -52
	_rpm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_build_pedal_panel(root)

	_mapping = _label(root, 13, Color(0.62, 0.66, 0.7))
	_mapping.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_mapping.offset_left = 24
	_mapping.offset_top = -44
	_mapping.offset_bottom = -26
	_mapping.offset_right = 620

	_warn = _label(root, 14, Color(1.0, 0.45, 0.35))
	_warn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_warn.offset_left = 24
	_warn.offset_top = -66
	_warn.offset_bottom = -48
	_warn.offset_right = 640

	_hint = _label(root, 13, Color(0.65, 0.67, 0.7))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 24
	_hint.offset_top = -24
	_hint.offset_bottom = -6
	_hint.offset_right = 720
	_hint.text = "Esc = Menü   C = Kamera   R = Reset   Enter = Auto-Pilot   Paddles/Q-E = schalten"


func _build_pedal_panel(root: Control) -> void:
	var panel := VBoxContainer.new()
	panel.name = "Pedals"
	panel.add_theme_constant_override("separation", 3)
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_bottom = -74
	panel.offset_top = -190
	panel.offset_right = 264
	for spec in PEDALS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var name_label := Label.new()
		name_label.text = spec["label"]
		name_label.custom_minimum_size = Vector2(86, 0)
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color(0.78, 0.80, 0.83))
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		name_label.add_theme_constant_override("outline_size", 6)
		row.add_child(name_label)
		var track := ColorRect.new()
		track.color = Color(0.08, 0.08, 0.10, 0.75)
		track.custom_minimum_size = Vector2(140, 14)
		row.add_child(track)
		var fill := ColorRect.new()
		fill.color = spec["color"]
		fill.size = Vector2(0, 14)
		fill.position = Vector2.ZERO
		track.add_child(fill)
		_bars[spec["key"]] = {"fill": fill, "track": track}


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	if car == null:
		return
	var calibrating: bool = g29 != null and int(g29.get("cal_phase")) > 0 and int(g29.get("cal_phase")) < 5
	if calibrating:
		_cal.text = String(g29.get("cal_hint")) + "\nKalibrierung läuft — Esc bricht ab, Enter überspringt"
	else:
		_cal.text = ""

	_gear.text = str(car.gear)
	_speed.text = "%d km/h" % int(round(car.speed_kmh))
	_rpm.text = "%d rpm" % int(round(car.rpm))
	_paint_leds(car.rpm)
	# In the cockpit view the dashboard shows gear, speed and shift lights, so
	# the floating centre cluster is hidden - the reference shot has the HUD at
	# the edges of the frame only.
	var cockpit_view: bool = cam != null and int(cam.get("mode")) == 0
	_gear.visible = not cockpit_view
	_speed.visible = not cockpit_view
	_leds.visible = not cockpit_view
	_update_pedals()


func _update_pedals() -> void:
	var connected: bool = g29 != null and bool(g29.get("connected"))
	var live: bool = true
	if g29 and g29.get("axes_live") != null:
		live = bool(g29.get("axes_live"))
	# A powered-off G29 enumerates and then sends a flat 0.0 on every axis, which
	# looks exactly like "all pedals released". Only real reports count.
	if live and g29 and g29.has_method("has_axis_data"):
		live = bool(g29.call("has_axis_data"))
	for key in _bars.keys():
		var entry: Dictionary = _bars[key]
		var track: ColorRect = entry["track"]
		var fill: ColorRect = entry["fill"]
		var value: float = float(g29.get(key)) if g29 else 0.0
		if not connected:
			value = 0.0
		fill.size = Vector2(track.size.x * clampf(value, 0.0, 1.0), fill.size.y)
		var c: Color = Color(0.30, 0.55, 0.95) if key == "clutch" else (
			Color(0.90, 0.20, 0.20) if key == "brake" else Color(0.20, 0.85, 0.35))
		fill.color = c if (connected and live) else c.darkened(0.55)

	if not connected:
		_mapping.text = "Kein G29 — Tastatur: W Gas · S Bremse · A/D lenken"
		_warn.text = ""
		return
	if not live:
		_warn.text = "G29 ohne Achsendaten — Netzteil und Pedalkabel prüfen"
	else:
		_warn.text = ""
	_mapping.text = "Gas a%d%s · Bremse a%d%s · Kupplung a%d%s · Lenkrad a%d%s" % [
		_axis("throttle_axis"), _inv("invert_throttle"),
		_axis("brake_axis"), _inv("invert_brake"),
		_axis("clutch_axis"), _inv("invert_clutch"),
		_axis("steer_axis"), _inv("steer_invert", true),
	]


func _axis(prop: String) -> int:
	var v = g29.get(prop)
	return int(v) if v != null else -1


func _inv(prop: String, is_steer: bool = false) -> String:
	var v = g29.get(prop)
	if v == null:
		return ""
	var on := bool(v)
	if is_steer:
		return " inv" if on else ""
	return " inv" if on else ""


func _paint_leds(rpm: float) -> void:
	var n: float = clampf((rpm - 4200.0) / (12500.0 - 4200.0), 0.0, 1.0)
	var lit := int(round(n * 15.0))
	for i in 15:
		var led: ColorRect = _leds.get_child(i)
		if i < lit:
			if i < 8:
				led.color = Color(0.15, 0.85, 0.35)
			elif i < 12:
				led.color = Color(0.95, 0.75, 0.1)
			else:
				led.color = Color(0.95, 0.12, 0.12)
		else:
			led.color = Color(0.1, 0.1, 0.11, 0.7)
