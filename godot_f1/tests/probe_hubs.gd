extends SceneTree
## Are the four wheel hubs of the imported car symmetric? A hub that sits a
## centimetre further forward on one side makes the car pull at speed.

const F1Car = preload("res://scripts/car_controller.gd")


func _initialize() -> void:
	var car = F1Car.new()
	car.livery = "crimson"
	root.add_child(car)
	car.setup(null, null, Transform3D.IDENTITY)
	var roles: Dictionary = car.wheel_roles()
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var p: Vector3 = roles[key]
		print("HUB %s x=%.4f y=%.4f z=%.4f" % [key, p.x, p.y, p.z])
	var fl: Vector3 = roles["Wheel_FL"]
	var fr: Vector3 = roles["Wheel_FR"]
	var rl: Vector3 = roles["Wheel_RL"]
	var rr: Vector3 = roles["Wheel_RR"]
	print("HUB front dy=%.4f dz=%.4f  rear dy=%.4f dz=%.4f" % [
		fl.x + fr.x, absf(fl.z - fr.z), rl.x + rr.x, absf(rl.z - rr.z)])
	print("HUB track_front=%.4f track_rear=%.4f wheelbase=%.4f" % [
		fl.x - fr.x, rl.x - rr.x, absf(fl.z - rl.z)])
	quit(0)
