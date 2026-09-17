extends SceneTree
## End-to-end proof for the force feedback channel.
##
## The game cannot make a G29 move by itself (Godot has no FFB API), so the
## whole feature rests on one seam: `scripts/ffb_link.gd` has to put the right
## numbers on UDP 127.0.0.1:5601, where `tools/g29_ffb.py` picks them up and
## turns them into real force.
##
## This test plays the part of that helper: it opens the port the helper
## listens on, drives the real scene headless and checks the packets that
## arrive. A silent seam (packets never sent, wrong keys, values out of range)
## fails here instead of failing at the wheel.
##
##   powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_ffb_link.gd

const PORT := 5601

var listener: PacketPeerUDP
var main: Node3D
var car
var frames: int = 0
var packets: int = 0
var bad: int = 0
var max_force: float = 0.0
var max_damp: float = 0.0
var max_rumble: float = 0.0
var seen_keys: Dictionary = {}
var failed: int = 0


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	listener = PacketPeerUDP.new()
	if listener.bind(PORT, "127.0.0.1") != OK:
		print("FFB SKIP port %d busy (another listener running)" % PORT)
		quit(0)
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	car = main.get("player")
	var menu = main.get("menu")
	if menu and menu.has_method("headless_autostart"):
		menu.headless_autostart()
	if car:
		car.set_meta("script_throttle", 0.95)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	_drain()
	if frames == 150:
		# Force the driver to steer so the self-aligning torque has something to
		# push against, and provoke a gear shift event.
		if car:
			car.steering = 0.18
	if frames == 260:
		if car and car.ffb:
			car.ffb.poke("shift", 0.6)
	if frames >= 320:
		_drain()
		_report()


func _drain() -> void:
	if listener == null:
		return
	while listener.get_available_packet_count() > 0:
		var raw: PackedByteArray = listener.get_packet()
		var txt: String = raw.get_string_from_utf8()
		var data = JSON.parse_string(txt)
		if typeof(data) != TYPE_DICTIONARY:
			bad += 1
			continue
		packets += 1
		var d: Dictionary = data
		for key in ["v", "force", "damp", "fric", "rumble", "pulse"]:
			seen_keys[key] = true
			if not d.has(key):
				bad += 1
		max_force = maxf(max_force, absf(float(d.get("force", 0.0))))
		max_damp = maxf(max_damp, float(d.get("damp", 0.0)))
		max_rumble = maxf(max_rumble, float(d.get("rumble", 0.0)))
		if absf(float(d.get("force", 0.0))) > 1.001:
			bad += 1
		if float(d.get("damp", 0.0)) < 0.0 or float(d.get("damp", 0.0)) > 1.001:
			bad += 1


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, " ", detail)
	else:
		push_error("FAIL %s %s" % [label, detail])
		failed += 1


func _report() -> void:
	var sender_ok: bool = car != null and car.ffb != null and int(car.ffb.sent_packets) > 50
	_check(packets > 40, "udp_packets_arrive", "%d Pakete in %.1f s" % [
		packets, float(frames) / float(Engine.physics_ticks_per_second)])
	_check(sender_ok, "the_car_sends_at_60_hz",
		"sent=%d" % (int(car.ffb.sent_packets) if car and car.ffb else -1))
	_check(bad == 0, "packets_are_well_formed", "bad=%d" % bad)
	_check(seen_keys.size() >= 6, "protocol_keys_present", str(seen_keys.keys()))
	_check(max_force > 0.02, "self_aligning_torque_is_sent", "max_force=%.3f" % max_force)
	_check(max_damp > 0.2, "damping_grows_with_speed", "max_damp=%.3f" % max_damp)
	_check(max_rumble >= 0.0, "rumble_channel_available", "max_rumble=%.3f" % max_rumble)
	if failed > 0:
		print("FFB FAIL count=", failed)
		quit(1)
	else:
		print("FFB PASS packets=", packets, " sent=", int(car.ffb.sent_packets))
		quit(0)
