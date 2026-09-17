extends CanvasLayer
## Der Hinweis, den nur die Ideallinie geben kann: was jetzt zu tun ist und wie
## weit es bis zum Bremsbeginn noch ist.
##
## Untergrund, Schaden und die Crash-Warnung stehen schon in `scripts/hud.gd`
## (Ebene 10); hier kommt nichts davon ein zweites Mal hin. Diese Ebene liegt
## darunter (layer 9) und bleibt schlank.
##
## OWNER: ROOT.

var car
var ideal

var _hint: Label


func setup(p_car, p_ideal, _p_g29 = null) -> void:
	car = p_car
	ideal = p_ideal


func _ready() -> void:
	layer = 9
	var root := Control.new()
	root.name = "LineHintRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 8)
	root.add_child(_hint)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -320
	_hint.offset_right = 320
	_hint.offset_top = -196
	_hint.offset_bottom = -164
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = ""


func _process(_delta: float) -> void:
	if car == null or ideal == null or ideal.points.size() < 8:
		_hint.text = ""
		return
	var hint: int = int(car.get("_ideal_hint"))
	var index: int = ideal.closest_index_near(car.global_position, hint) if hint >= 0 else ideal.closest_index(car.global_position)
	var phase: int = ideal.phase[index]
	if phase == ideal.BRAKE:
		_hint.text = "JETZT BREMSEN"
		_hint.add_theme_color_override("font_color", Color(1.0, 0.28, 0.22))
		return
	var to_brake: float = ideal.brake_distance_from(index)
	if to_brake < 180.0:
		_hint.text = "BREMSEN IN %d m" % int(round(to_brake))
		_hint.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28))
	elif phase == ideal.LIFT:
		_hint.text = "LUPFEN"
		_hint.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	else:
		_hint.text = ""
