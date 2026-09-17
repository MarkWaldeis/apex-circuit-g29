extends SceneTree
## Diagnostic: what does the machine actually see on the joystick bus?
## Prints device names, axis/button counts and raw axis values without needing
## the input module (useful to prove the G29 rest positions and pedal polarity).

var frames: int = 0
var mins := {}
var maxs := {}


func _initialize() -> void:
	var pads: Array = Input.get_connected_joypads()
	print("G29_PROBE devices=", pads.size())
	for id in pads:
		var name := Input.get_joy_name(id)
		print("G29_PROBE id=", id, " name=", name)
		var line := "G29_PROBE raw:"
		for a in 12:
			line += " a%d=%.3f" % [a, Input.get_joy_axis(id, a)]
		print(line)
		var pressed := "G29_PROBE buttons_down:"
		var any := false
		for b in 24:
			if Input.is_joy_button_pressed(id, b):
				pressed += " %d" % b
				any = true
		print(pressed if any else "G29_PROBE buttons_down: none")
	if pads.is_empty():
		print("G29_PROBE no joystick connected")
		quit(0)
		return
	# Watch the axes for two seconds: a completely frozen 0.000 on every axis
	# would mean the device is not actually delivering data.
	process_frame.connect(_sample)


func _sample() -> void:
	frames += 1
	for a in 6:
		var v: float = Input.get_joy_axis(0, a)
		mins[a] = minf(float(mins.get(a, v)), v)
		maxs[a] = maxf(float(maxs.get(a, v)), v)
	if frames < 120:
		return
	var line := "G29_PROBE 2s range:"
	for a in 6:
		line += " a%d=[%.3f..%.3f]" % [a, mins[a], maxs[a]]
	print(line)
	quit(0)
