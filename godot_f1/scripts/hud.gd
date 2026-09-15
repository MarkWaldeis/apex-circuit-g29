extends CanvasLayer

var car
var g29
var _speed: Label
var _mode: Label
var _wheel: Label
var _help: Label


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_speed = _make_label(root, Vector2(40, 40), 42)
	_mode = _make_label(root, Vector2(40, 100), 22)
	_wheel = _make_label(root, Vector2(40, 136), 18)
	_help = _make_label(root, Vector2(40, -90), 16)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(40, -90)
	_help.text = "W/S Gas/Bremse   A/D Lenken   Enter Auto   R Reset   C Kamera   Esc Ende"


func _make_label(parent: Control, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	if car == null:
		return
	_speed.text = "%d km/h" % int(round(car.speed_kmh))
	if car.is_ai:
		_mode.text = "AI"
	elif car.auto_drive:
		_mode.text = "AUTO-PILOT  (Enter = G29 / Tastatur)"
	else:
		_mode.text = "MANUAL"
	if g29 and g29.connected:
		_wheel.text = "Lenkrad: %s   Steer %.2f  Gas %.2f  Bremse %.2f" % [g29.device_name, g29.steer, g29.throttle, g29.brake]
	else:
		_wheel.text = "Kein G29 erkannt — Tastatur aktiv (WASD)"
