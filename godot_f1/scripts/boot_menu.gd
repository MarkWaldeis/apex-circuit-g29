extends CanvasLayer
## Weltwahl beim Start: F1-Grand-Prix (bestehende Strecke) oder Fahrschule
## (neue Welt mit normalem Auto, H-Schaltung, Übungsplatz und Stadt).
## Wird als Hauptscene geladen (project.godot: run/main_scene).

const UI = preload("res://scripts/ui_theme.gd")

const F1_SCENE := "res://scenes/main.tscn"
const SCHOOL_SCENE := "res://scenes/school.tscn"


func _ready() -> void:
	layer = 60
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = UI.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_style())
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	var title := Label.new()
	title.text = "APEX CIRCUIT"
	UI.title(title, 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Welt wählen — für Logitech G29 (Lenkrad · Pedale · Schalthebel)"
	UI.label(sub, 22, UI.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var f1 := Button.new()
	f1.text = "F1 Grand Prix\nRennstrecke · 350 km/h · sequentielle Schaltung"
	UI.button(f1, true, 30)
	f1.custom_minimum_size = Vector2(560, 96)
	f1.pressed.connect(_pick.bind(F1_SCENE))
	col.add_child(f1)

	var school := Button.new()
	school.text = "Fahrschule\nStadt & Übungsplatz · H-Schaltung · Kupplung · Blinker"
	UI.button(school, true, 30)
	school.custom_minimum_size = Vector2(560, 96)
	school.pressed.connect(_pick.bind(SCHOOL_SCENE))
	col.add_child(school)

	var quit := Button.new()
	quit.text = "Beenden"
	UI.button(quit, false, 26)
	quit.custom_minimum_size = Vector2(560, 52)
	quit.pressed.connect(get_tree().quit)
	col.add_child(quit)

	var hint := Label.new()
	hint.text = "Die Schaltwippe des G29 sitzt rechts am Rad: Schieber nach rechts = H-Modus"
	UI.label(hint, 16, UI.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	f1.grab_focus()
	get_tree().paused = false
	if DisplayServer.get_name() == "headless":
		# Headless-Tests laden die Szenen direkt.
		pass


func _pick(scene: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
