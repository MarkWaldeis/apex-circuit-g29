extends SceneTree
## Measures the driving feel the way a driver would describe it: how hard the
## car pulls, how hard it stops, how much cornering force it makes. Numbers
## first, opinions after.
##
##   godot --headless --path godot_f1 --script tests/probe_feel.gd

var main: Node3D
var frames: int = 0
var t100: float = -1.0
var brake_from: float = 0.0
var brake_frame: int = 0
var peak_decel_g: float = 0.0
var brake_prev_speed: float = 0.0
var ai_max_lat_g: float = 0.0
var ai_max_slip: float = 0.0
var ai_max_speed: float = 0.0
var ai_prev_vel: Vector3 = Vector3.ZERO
var top_speed: float = 0.0
var top_gear: int = 0
var _prev_vel: Vector3 = Vector3.ZERO
var over3: int = 0
var over5: int = 0
var ai_max_lat_speed_g: float = 0.0
var ai_max_lat_speed: float = 0.0
var high_speed_max_g: float = 0.0
var frame_lat: Array = []


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	physics_frame.connect(_on_phys)


func _on_phys() -> void:
	frames += 1
	var player = main.get("player")
	var ai = main.get("ai_car")
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if player == null:
		return
	# 0-100 km/h on the main straight.
	if frames < 900:
		player.apply_throttle(1.0)
	else:
		player.apply_throttle(0.0)
	if frames in [10, 30, 60, 90, 150, 300]:
		var tcut: float = float(player.tyres.throttle_cut)
		var wl = player.get_node_or_null("Wheel_RL")
		var wr = player.get_node_or_null("Wheel_RR")
		var wf = player.get_node_or_null("Wheel_FL")
		print("WHEEL f=%d RL(c=%s skid=%.2f rpm=%.1f) RR(c=%s skid=%.2f) FL(c=%s skid=%.2f) fwd=%.2f vel=%s" % [
			frames,
			str(wl.is_in_contact()) if wl else "?", wl.get_skidinfo() if wl else -1.0,
			wl.get_rpm() if wl else -1.0,
			str(wr.is_in_contact()) if wr else "?", wr.get_skidinfo() if wr else -1.0,
			str(wf.is_in_contact()) if wf else "?", wf.get_skidinfo() if wf else -1.0,
			player.global_transform.basis.z.dot(player.linear_velocity), str(player.linear_velocity)])
		print("TICK f=%d kmh=%.1f gear=%d rpm=%.0f force=%.0f cut=%.2f fg=%.2f rg=%.2f dmg=%.2f drag=%.0f surf=%s brake=%.1f y=%.2f pitch=%.3f" % [
			frames, player.speed_kmh, player.gear, player.rpm, player.engine_force, tcut,
			float(player.tyres.front_grip), float(player.tyres.rear_grip),
			float(player.crash.damage), float(player.aero_drag_n),
			String(player.surface_name), float(player.brake), float(player.global_position.y),
			float(player.body_pitch)])
	if frames == 900:
		brake_from = player.speed_kmh
		brake_frame = frames
		brake_prev_speed = player.speed_kmh
		player.apply_brake(1.0)
	if frames > 900 and frames < 1100:
		var decel: float = (brake_prev_speed - player.speed_kmh) / 3.6 / dt
		peak_decel_g = maxf(peak_decel_g, decel / 9.81)
		brake_prev_speed = player.speed_kmh
	if frames == 1100:
		player.apply_brake(0.0)
	var accel_vec: Vector3 = (player.linear_velocity - _prev_vel) / dt
	_prev_vel = player.linear_velocity
	if t100 < 0.0 and player.speed_kmh >= 100.0:
		t100 = float(frames) * dt
	if player.speed_kmh > top_speed:
		top_speed = player.speed_kmh
		top_gear = player.gear
	if ai:
		ai_max_speed = maxf(ai_max_speed, ai.speed_kmh)
		var crashed: bool = ai.get("crash") != null and float(ai.get("crash").last_impact_ms) > 0.5
		if ai.speed_kmh > 30.0 and not crashed:
			var ai_accel: Vector3 = (ai.linear_velocity - ai_prev_vel) / dt
			var lat: float = absf(ai_accel.dot(ai.global_transform.basis.x.normalized())) / 9.81
			ai_max_lat_g = maxf(ai_max_lat_g, lat)
			ai_max_slip = maxf(ai_max_slip, float(ai.get("slip")))
			if lat > 3.0:
				over3 += 1
			if lat > 5.0:
				over5 += 1
			if lat > ai_max_lat_speed_g:
				ai_max_lat_speed_g = lat
				ai_max_lat_speed = ai.speed_kmh
			if ai.speed_kmh > 120.0 and lat > high_speed_max_g:
				high_speed_max_g = lat
			frame_lat.append(lat)
		ai_prev_vel = ai.linear_velocity
	if frames >= 2400:
		frame_lat.sort()
		var p95: float = frame_lat[int(float(frame_lat.size() - 1) * 0.95)] if frame_lat.size() > 20 else 0.0
		print("FEEL 0-100 %.2f s" % t100)
		print("FEEL top speed %.1f km/h in gear %d (player)" % [top_speed, top_gear])
		print("FEEL brake from %.1f km/h peak %.2f g" % [brake_from, peak_decel_g])
		print("FEEL ai max lateral %.2f g, max slip %.2f, max speed %.1f km/h" % [
			ai_max_lat_g, ai_max_slip, ai_max_speed])
		print("FEEL ai lateral p95 %.2f g, frames>3g %d, >5g %d, >120km/h max %.2f g" % [
			p95, over3, over5, high_speed_max_g])
		print("FEEL ai biggest lateral %.2f g at %.1f km/h" % [ai_max_lat_speed_g, ai_max_lat_speed])
		quit(0)
