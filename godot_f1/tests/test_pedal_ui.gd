extends SceneTree
## Gating test for the settings screen: the driver can move a pedal to another
## axis by hand, swap gas and brake with one click, and the screen shows the
## value the game really uses for each pedal.
##
## The bug this guards against: the game detected the wrong axis, so pressing
## the throttle lit up the brake, and the driver had no way to correct it other
## than running the whole calibration again.

const G29 = preload("res://scripts/g29_input.gd")
const Menu = preload("res://scripts/menu.gd")

const PROFILE := "user://g29_ui_test.json"

var g
var menu
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1
		print("FAIL ", label, " ", detail)


func _run() -> void:
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))

	g = G29.new()
	g.auto_load_profile = false
	g.profile_path = PROFILE
	g.enable_sim()
	root.add_child(g)

	menu = Menu.new()
	menu.name = "Menu"
	root.add_child(menu)
	menu.setup(null, g, null)
	menu._show_screen(Menu.Screen.SETTINGS)

	_rows_exist()
	_cycle_moves_the_axis()
	_swap_pedals()
	_mapped_values_follow_the_swap()
	_same_axis_is_refused()
	_the_choice_is_persisted()
	_back_paths()

	if failed > 0:
		print("PEDAL_UI FAIL count=", failed)
		quit(1)
	else:
		print("PEDAL_UI PASS")
		quit(0)


func _rows_exist() -> void:
	_check(menu.screen == Menu.Screen.SETTINGS, "the_settings_screen_is_open")
	_check(menu._pedal_rows.size() == 3, "every_pedal_has_a_row",
		"rows=%d" % menu._pedal_rows.size())
	for which in ["throttle", "brake", "clutch"]:
		var row: Dictionary = menu._pedal_rows.get(which, {})
		_check(row.has("bar") and row.has("value") and row.has("axis"),
			"row_%s_is_complete" % which)
	_check(menu._swap_button != null, "there_is_a_swap_button")


func _cycle_moves_the_axis() -> void:
	g.steer_axis = 0
	g.throttle_axis = 1
	g.brake_axis = 2
	g.clutch_axis = 3
	var button: Button = menu._pedal_rows["throttle"]["axis"]
	button.emit_signal("pressed")
	_check(g.throttle_axis == 4, "the_axis_button_skips_the_taken_axes",
		"a1 -> a%d (a0 Lenkrad, a2 Bremse, a3 Kupplung belegt)" % g.throttle_axis)
	menu._refresh_pedal_rows()
	_check(str(menu._pedal_rows["throttle"]["axis"].text).contains("a4"),
		"the_button_shows_the_new_axis",
		str(menu._pedal_rows["throttle"]["axis"].text))
	button.emit_signal("pressed")
	_check(g.throttle_axis == 5, "clicking_again_walks_further",
		"a%d" % g.throttle_axis)


func _swap_pedals() -> void:
	g.throttle_axis = 2
	g.brake_axis = 3
	menu._swap_button.emit_signal("pressed")
	_check(g.throttle_axis == 3 and g.brake_axis == 2,
		"the_swap_button_swaps_gas_and_brake",
		"gas=a%d brake=a%d" % [g.throttle_axis, g.brake_axis])


## After the swap the very same physical pedal has to show up as gas and the
## other one as brake - otherwise the screen would be lying to the driver.
func _mapped_values_follow_the_swap() -> void:
	for i in 8:
		g.sim_set(i, 0.0)
	# A G29 rests at +1.0 on every pedal axis.
	g.sim_set(g.throttle_axis, 1.0)
	g.sim_set(g.brake_axis, 1.0)
	g.sim_set(g.clutch_axis, 1.0)
	g.step(0.02)
	g.step(0.02)
	_check(g.throttle < 0.02 and g.brake < 0.02, "released_pedals_read_zero",
		"gas=%.2f brake=%.2f" % [g.throttle, g.brake])

	g.sim_set(g.throttle_axis, 0.40)
	g.step(0.02)
	menu._refresh_pedal_rows()
	var gas: String = str(menu._pedal_rows["throttle"]["value"].text)
	var bremse: String = str(menu._pedal_rows["brake"]["value"].text)
	_check(g.throttle > 0.9, "pressing_the_throttle_axis_gives_full_gas",
		"throttle=%.2f" % g.throttle)
	_check(g.brake < 0.05, "the_brake_does_not_move_along", "brake=%.2f" % g.brake)
	_check(gas.begins_with("100"), "the_gas_row_shows_it", "row=%s" % gas)
	_check(bremse.begins_with("0"), "the_brake_row_stays_empty", "row=%s" % bremse)


func _same_axis_is_refused() -> void:
	g.throttle_axis = 4
	g.brake_axis = 4
	menu._swap_button.emit_signal("pressed")
	_check(g.throttle_axis == 4 and g.brake_axis == 4,
		"swapping_two_identical_axes_is_refused",
		"gas=a%d brake=a%d" % [g.throttle_axis, g.brake_axis])


func _the_choice_is_persisted() -> void:
	g.throttle_axis = 3
	g.brake_axis = 2
	menu._swap_button.emit_signal("pressed")  # gas=a2, brake=a3
	_check(FileAccess.file_exists(PROFILE), "the_profile_file_was_written", PROFILE)
	if not FileAccess.file_exists(PROFILE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	_check(typeof(parsed) == TYPE_DICTIONARY, "the_profile_is_valid_json")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_check(int(d.get("throttle_axis", -1)) == g.throttle_axis
		and int(d.get("brake_axis", -1)) == g.brake_axis,
		"the_chosen_axes_are_saved",
		"file: gas=a%s brake=a%s / live: gas=a%d brake=a%d" % [
			str(d.get("throttle_axis", -1)), str(d.get("brake_axis", -1)),
			g.throttle_axis, g.brake_axis])


## "every menu can be left again" - the same paths the driver walks.
func _back_paths() -> void:
	menu._open_settings(Menu.Screen.START)
	_check(menu.screen == Menu.Screen.SETTINGS, "settings_open")
	menu._on_back()
	_check(menu.screen == Menu.Screen.START, "back_reaches_the_start_menu",
		"screen=%d" % menu.screen)

	menu._open_settings(Menu.Screen.START)
	menu._start_calibration("throttle")
	_check(menu.screen == Menu.Screen.CALIBRATE, "a_calibration_starts")
	menu._cancel_calibration()
	_check(menu.screen == Menu.Screen.SETTINGS, "cancelling_leads_back")
	_check(g.cal_phase == 0, "the_cancelled_calibration_is_idle",
		"phase=%d" % g.cal_phase)
