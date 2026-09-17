extends RefCounted
## Tyre grip and aero load: how much of the available friction each axle
## really has, and what the car does when one end runs out of it.
##
## OWNER: ROOT.
##
## `VehicleBody3D` gives one friction number per wheel and no slip curve at
## all, so a Formula car has to be built out of what the engine does offer:
##
##   * `wheel_friction_slip` is a friction CEILING (force = load x ceiling), so
##     downforce is applied by raising that ceiling with v^2, exactly like the
##     aero load would.
##   * the aero gain is sub-linear (`AERO_EXP`), because a tyre carrying more
##     load does not return proportionally more grip - the first thing that has
##     to feel right is that a fast corner is not four times as fast as a slow
##     one.
##   * front and rear axle are treated separately through the classic bicycle
##     model (slip angles from yaw rate and steering), which is what makes
##     understeer and oversteer separable at all.
##
## Everything here is a pure calculator: numbers in through `ctx`, numbers out.

## --- aero ------------------------------------------------------------------
## A 2010s Formula car makes roughly 3.5x its own weight in downforce at
## 300 km/h. `AERO_K` is the top of that curve, `AERO_EXP` the tyre's
## load-sensitivity discount on it.
const AERO_K := 3.2
const AERO_V_REF := 83.3          ## m/s, 300 km/h
const AERO_EXP := 0.82
## Aero balance moves rearward with speed: the faster the corner, the more the
## car understeers - and the more stable it is.
const FRONT_SHARE_SLOW := 0.50
const FRONT_SHARE_FAST := 0.44

## --- drag ------------------------------------------------------------------
## F = 0.5 * rho * CdA * v^2. An F1 car in race trim sits at CdA ~ 1.35 m^2,
## and that number is what turns "it accelerates forever" into a real top
## speed: with ~700 kW it caps the car a little above 300 km/h.
const AIR_DENSITY := 1.2
## Cd x A for a Formula car in race trim. 1.15 m^2 is the number that puts the
## top speed in the right place together with the gearbox ratios: measure with
## `tests/test_gearbox.gd`, which drives a full-throttle straight until the
## speed stops rising.
const CDA := 1.15

## --- tyres -----------------------------------------------------------------
## Slip angle (rad) at which the tyre makes its most lateral force. Radial
## slicks peak late and gently compared with a road tyre.
const PEAK_SLIP := 0.13
## How much of the grip is gone once the tyre is well past the peak, and how
## quickly: this falloff is what makes a slide catchable instead of a cliff.
const FALLOFF := 0.30
const MIN_GRIP := 0.42

## --- weight transfer and driver inputs -------------------------------------
## Braking and cornering share the same contact patch (the friction circle).
## Godot does not model it, so a car braking deep into a corner would keep full
## cornering grip - which is exactly what "arcade" feels like.
const BRAKE_STEER_SHARE := 0.30
const POWER_OVERSTEER := 0.38
const POWER_OVERSTEER_REF := 26.0  ## m/s, above this the rear tyres are safe
const TRAIL_STABILITY := 0.18

var car
var line

var front_grip: float = 1.0
var rear_grip: float = 1.0
var slip: float = 0.0
var understeer: float = 0.0
var oversteer: float = 0.0
var downforce: float = 0.0
var drag: float = 0.0
var lateral_g: float = 0.0
## Torque cut the traction control asks for (0 = none, 1 = all of it).
var throttle_cut: float = 0.0
## Slip angles actually used this tick, for the HUD and the tests.
var slip_front: float = 0.0
var slip_rear: float = 0.0


func setup(owner_car, racing_line) -> void:
	car = owner_car
	line = racing_line


func update(_delta: float, ctx: Dictionary) -> Dictionary:
	var speed: float = maxf(float(ctx.get("speed", 0.0)), 0.0)
	var vx: float = float(ctx.get("forward_speed", 0.0))
	var vy: float = float(ctx.get("lateral_speed", 0.0))
	var yaw: float = float(ctx.get("yaw_rate", 0.0))
	var steer_rad: float = float(ctx.get("steer_angle", 0.0))
	var throttle: float = clampf(float(ctx.get("throttle", 0.0)), 0.0, 1.0)
	var brake: float = clampf(float(ctx.get("brake", 0.0)), 0.0, 1.0)
	var grip_mul: float = float(ctx.get("surface", {}).get("grip", 1.0))
	var damage: float = clampf(float(ctx.get("damage", 0.0)), 0.0, 1.0)
	var tcs: bool = bool(ctx.get("traction_control", true))

	# --- aero load ----------------------------------------------------------
	var v_ratio: float = clampf(speed / AERO_V_REF, 0.0, 1.2)
	downforce = pow(1.0 + AERO_K * v_ratio * v_ratio, AERO_EXP)
	if brake > 0.2:
		# Standing on the nose costs a little aero: the diffuser stalls.
		downforce *= 0.94
	var front_share: float = lerpf(FRONT_SHARE_SLOW, FRONT_SHARE_FAST, clampf(v_ratio, 0.0, 1.0))

	# --- slip angles (bicycle model) ----------------------------------------
	# Wheelbase geometry of this car: front axle +1.43 m, rear axle -2.00 m,
	# centre of mass at -0.42 m, so the levers are 1.85 m and 1.58 m.
	var v_ref: float = maxf(absf(vx), 4.0)
	var forward_sign: float = 1.0 if vx >= 0.0 else -1.0
	slip_front = atan2(vy + yaw * 1.85, v_ref) - forward_sign * steer_rad
	slip_rear = atan2(vy - yaw * 1.58, v_ref)

	var share_lost: float = BRAKE_STEER_SHARE * brake * clampf(absf(steer_rad) / 0.20, 0.0, 1.0)
	var power_slide: float = POWER_OVERSTEER * throttle * clampf(
		1.0 - speed / POWER_OVERSTEER_REF, 0.0, 1.0)
	# A car that is already sideways loses rear grip faster than a straight
	# one - this is what makes a slide grow instead of politely stopping.
	power_slide = minf(power_slide + maxf(absf(slip_rear) - PEAK_SLIP, 0.0) * 0.6, 0.75)

	var mu_front: float = _grip_factor(slip_front) * (1.0 - share_lost)
	var mu_rear: float = _grip_factor(slip_rear) * (1.0 - power_slide)
	# Load sensitivity: the heavily loaded end works at a slightly worse
	# coefficient than the light end, which keeps the balance alive under
	# braking instead of being perfectly symmetric.
	mu_front *= pow(front_share, 0.10)
	mu_rear *= pow(1.0 - front_share, 0.10)
	front_grip = grip_mul * mu_front * (1.0 - 0.30 * damage)
	rear_grip = grip_mul * mu_rear * (1.0 - 0.30 * damage)

	understeer = clampf(maxf(absf(slip_front) - PEAK_SLIP, 0.0) / (PEAK_SLIP * 2.0), 0.0, 1.0)
	oversteer = clampf(maxf(absf(slip_rear) - PEAK_SLIP, 0.0) / (PEAK_SLIP * 2.0), 0.0, 1.0)
	slip = clampf(maxf(understeer, oversteer), 0.0, 1.0)
	# Aerodynamic drag in Newton, opposing the direction of travel:
	# F = 0.5 * rho * CdA * v^2. The chassis turns this into a deceleration
	# (`car_controller._apply_aero_drag`), so the mass lives in exactly one
	# place and the top speed becomes a real number instead of "however fast
	# the gearbox can pull".
	drag = 0.5 * AIR_DENSITY * CDA * speed * speed

	# --- traction control ---------------------------------------------------
	# Wheel spin is not observable here (the physics wheel always rolls), so the
	# assist works off the rear slip demand and the throttle instead.
	throttle_cut = 0.0
	if tcs:
		throttle_cut = clampf(oversteer * 1.4 + power_slide * 0.6, 0.0, 0.85)

	# --- stability ----------------------------------------------------------
	# A big yaw rate at speed costs rear grip: an F1 car does not snap-spin out
	# of a fast corner because of its aero, but it does spin if provoked.
	var yaw_excess: float = maxf(absf(yaw) - 1.6, 0.0) * 0.05
	rear_grip *= clampf(1.0 - yaw_excess - TRAIL_STABILITY * brake * oversteer, 0.4, 1.0)
	return {
		"front_grip": front_grip,
		"rear_grip": rear_grip,
		"slip": slip,
		"understeer": understeer,
		"oversteer": oversteer,
		"downforce": downforce,
		"drag": drag,
		"lateral_g": lateral_g,
		"throttle_cut": throttle_cut,
		"slip_front": slip_front,
		"slip_rear": slip_rear,
	}


## Lateral force a slick can still make at this slip angle, as a fraction of
## its peak. Rises to 1.0 at PEAK_SLIP, then falls away - gently at first,
## which is the part that makes a slide catchable.
func _grip_factor(slip_angle: float) -> float:
	var x: float = absf(slip_angle) / PEAK_SLIP
	if x <= 1.0:
		return 1.0
	return maxf(1.0 - FALLOFF * (x - 1.0), MIN_GRIP)
