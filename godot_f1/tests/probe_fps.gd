extends SceneTree
## Performance check on the real scene: drives the player for a while and prints
## the frame rate for each camera mode. Used to judge the cost of the added
## lighting, glow and trackside props.

const OUT_DIR := ""

var main: Node3D
var frames: int = 0
var report_at: Array = [120, 240, 360, 480, 600]
var idx: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames == 20:
		var menu = main.get("menu")
		if menu and menu.has_method("headless_autostart"):
			menu.headless_autostart()
		var player = main.get("player")
		if player:
			player.set_meta("headless_gas", true)
	if frames == 200:
		var cam = main.get("cam")
		if cam:
			cam.mode = 1
	if frames == 400:
		var cam2 = main.get("cam")
		if cam2:
			cam2.mode = 2
	if idx < report_at.size() and frames == int(report_at[idx]):
		var cam3 = main.get("cam")
		print("FPS %d (camera mode %d, %s)" % [
			Engine.get_frames_per_second(),
			cam3.mode if cam3 else -1,
			DisplayServer.get_name()])
		idx += 1
	if frames > 620:
		quit(0)
