extends CanvasLayer

var car
var g29
var _gear: Label
var _speed: Label
var _rpm: Label
var _hint: Label
var _pedals: Label
var _cal: Label
var _leds: HBoxContainer


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_cal = _label(root, 28, Color(1, 0.85, 0.2))
	_cal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cal.offset_top = 48
	_cal.offset_left = -420
	_cal.offset_right = 420
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

	_pedals = _label(root, 15, Color(0.75, 0.78, 0.8))
	_pedals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pedals.offset_left = 24
	_pedals.offset_bottom = -24
	_pedals.offset_top = -72
	_pedals.offset_right = 520

	_hint = _label(root, 14, Color(0.65, 0.67, 0.7))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 24
	_hint.offset_bottom = -8
	_hint.offset_top = -26
	_hint.offset_right = 900
	_hint.text = "Rechtes Paddle hoch · linkes runter   Q/E schalten   C Kamera   R Reset"


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
	if g29 and g29.cal_phase > 0 and g29.cal_phase < 5:
		_cal.text = g29.cal_hint + "\nEnter = Standard-Mapping (rechts Gas, mitte Bremse, links Kupplung)"
		if Input.is_action_just_pressed("toggle_auto"):
			g29.skip_calibration()
	else:
		_cal.text = ""

	_gear.text = str(car.gear)
	_speed.text = "%d km/h" % int(round(car.speed_kmh))
	_rpm.text = "%d rpm" % int(round(car.rpm))
	_paint_leds(car.rpm)
	if g29 and g29.connected:
		_pedals.text = "Gas %.0f%%   Bremse %.0f%%   Kupplung %.0f%%\n%s" % [
			g29.throttle * 100.0, g29.brake * 100.0, g29.clutch * 100.0, g29.device_name
		]
	else:
		_pedals.text = "Kein G29 — W Gas  S Bremse  Q/E schalten"


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
