extends RefCounted
## Tyre grip: how much of the available friction each axle really has.
##
## OWNER: ROOT. VehicleBody3D has one friction number per wheel and no slip
## curve, so this module turns speed, downforce, steering demand, throttle and
## surface into per-axle friction targets plus the downforce and drag the car
## should carry. Deliberately a pure calculator: no node access.

var front_grip: float = 1.0
var rear_grip: float = 1.0
var slip: float = 0.0
var understeer: float = 0.0
var oversteer: float = 0.0
var downforce: float = 0.0
var drag: float = 0.0
var lateral_g: float = 0.0
var car
var line


func setup(owner_car, racing_line) -> void:
	car = owner_car
	line = racing_line


func update(_delta: float, ctx: Dictionary) -> Dictionary:
	var speed: float = maxf(float(ctx.get("speed", 0.0)), 0.0)
	var steer: float = absf(float(ctx.get("steer", 0.0)))
	var throttle: float = clampf(float(ctx.get("throttle", 0.0)), 0.0, 1.0)
	var brake: float = clampf(float(ctx.get("brake", 0.0)), 0.0, 1.0)
	var surface: Dictionary = ctx.get("surface", {})
	var grip_mul: float = float(surface.get("grip", 1.0))
	var v: float = clampf(speed / 75.0, 0.0, 1.0)
	downforce = 1.0 + 1.15 * v * v
	if brake > 0.2:
		downforce *= 0.92
	if steer > 0.35 and speed > 25.0:
		downforce *= lerpf(1.0, 0.78, clampf((steer - 0.35) * 2.0, 0.0, 1.0))
	understeer = clampf((steer - 0.55) * (speed / 60.0), 0.0, 0.6)
	oversteer = clampf((throttle - 0.6) * (speed / 40.0), 0.0, 0.6)
	front_grip = grip_mul * (1.0 - understeer * 0.25)
	rear_grip = grip_mul * (1.0 - oversteer * 0.22)
	slip = clampf(maxf(understeer, oversteer) * 1.6, 0.0, 1.0)
	lateral_g = 0.0
	drag = 0.0
	return {
		"front_grip": front_grip,
		"rear_grip": rear_grip,
		"slip": slip,
		"understeer": understeer,
		"oversteer": oversteer,
		"downforce": downforce,
		"drag": drag,
		"lateral_g": lateral_g,
	}
