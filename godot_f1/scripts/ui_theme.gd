extends RefCounted
## Shared look helpers for the Apex Circuit UI.
## Everything is built from Control nodes + StyleBoxFlat — no external assets.

const ACCENT := Color(0.98, 0.27, 0.11)
const ACCENT_BRIGHT := Color(1.0, 0.44, 0.18)
const BG_DEEP := Color(0.03, 0.035, 0.05, 0.88)
const PANEL_BG := Color(0.065, 0.075, 0.095, 0.95)
const SURFACE := Color(0.11, 0.12, 0.15, 0.95)
const SURFACE_HOVER := Color(0.17, 0.19, 0.23, 0.98)
const SURFACE_PRESSED := Color(0.66, 0.17, 0.08, 1.0)
const LINE := Color(0.27, 0.30, 0.36, 1.0)
const TEXT := Color(0.95, 0.96, 0.98)
const TEXT_DIM := Color(0.66, 0.70, 0.76)
const TEXT_ON_ACCENT := Color(0.08, 0.05, 0.04)
const GOOD := Color(0.34, 0.85, 0.48)
const WARN := Color(1.0, 0.74, 0.22)


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


static func panel_style() -> StyleBoxFlat:
	var sb := box(PANEL_BG, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55), 2, 18)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 34
	sb.content_margin_bottom = 34
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 26
	return sb


static func label(l: Label, size: int, color: Color = TEXT) -> Label:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8 if size >= 40 else 0)
	return l


static func title(l: Label, size: int = 88) -> Label:
	label(l, size, TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l


static func button(b: Button, primary: bool = false, size: int = 30) -> Button:
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", size)

	var normal: StyleBoxFlat = box(ACCENT, ACCENT_BRIGHT, 2, 12) if primary else box(SURFACE, LINE, 2, 12)
	var hover: StyleBoxFlat = box(ACCENT_BRIGHT, TEXT, 2, 12) if primary else box(SURFACE_HOVER, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), 3, 12)
	var pressed: StyleBoxFlat = box(SURFACE_PRESSED, TEXT, 2, 12) if primary else box(SURFACE_PRESSED, TEXT, 2, 12)
	var focus: StyleBoxFlat = box(Color(0, 0, 0, 0), TEXT, 3, 12)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	var disabled := box(Color(0.08, 0.09, 0.11, 0.9), Color(0.2, 0.22, 0.26), 1, 12)
	for sb in [normal, hover, pressed, disabled]:
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", TEXT_ON_ACCENT if primary else TEXT)
	b.add_theme_color_override("font_focus_color", TEXT_ON_ACCENT if primary else TEXT)
	b.add_theme_color_override("font_hover_color", TEXT if primary else TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.53))
	return b


static func bar(pb: ProgressBar) -> ProgressBar:
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = 50.0
	pb.custom_minimum_size = Vector2(300, 18)
	pb.add_theme_stylebox_override("background", box(Color(0.05, 0.06, 0.075, 1.0), LINE, 1, 6))
	pb.add_theme_stylebox_override("fill", box(ACCENT_BRIGHT, Color(0, 0, 0, 0), 0, 6))
	return pb
