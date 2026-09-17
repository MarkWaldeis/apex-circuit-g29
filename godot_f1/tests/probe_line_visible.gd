extends SceneTree
## ROOT diagnostic: is the racing-line ribbon actually on screen, and where does
## it sit relative to the centre line? Writes captures/line_on.png and
## captures/line_off.png and prints the pixel difference between them.

const OUT_DIR := "C:/Users/Mark Waldeis/Desktop/grok f1 try/godot_f1/captures"

var main: Node3D
var frames: int = 0
var _on: Image


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	match frames:
		20:
			var m = main.get("menu")
			if m and m.has_method("resume_game"):
				m.resume_game()
			var player = main.get("player")
			if player:
				player.set_meta("headless_gas", true)
			var guide = main.get("guide")
			if guide:
				print("GUIDE enabled=", guide.is_enabled(), " segments=", guide.visible_segments)
				var ideal = main.get("ideal")
				var line = main.get("line")
				var max_off := 0.0
				for i in ideal.offsets.size():
					max_off = maxf(max_off, absf(ideal.offsets[i]))
				print("IDEAL points=", ideal.points.size(), " max_offset=", snapped(max_off, 0.001))
				for i in range(0, ideal.points.size(), 120):
					var off: float = line.offset_at(ideal.points[i], i)
					print("  pt[%d] world=%s centre_offset=%.3f" % [i, ideal.points[i], off])
		230:
			_on = _capture()
			print("CAPTURE on err=", _on.save_png(OUT_DIR + "/line_on.png") if _on else -1)
			var guide2 = main.get("guide")
			if guide2:
				guide2.set_enabled(false)
		300:
			var off_img := _capture()
			print("CAPTURE off err=", off_img.save_png(OUT_DIR + "/line_off.png") if off_img else -1)
			if _on and off_img:
				print("PIXELDIFF differing_pixels=", _diff(_on, off_img))
			quit(0)


func _capture() -> Image:
	return get_root().get_viewport().get_texture().get_image()


func _diff(a: Image, b: Image) -> int:
	var n := 0
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d: float = absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			if d > 0.12:
				n += 1
	return n
