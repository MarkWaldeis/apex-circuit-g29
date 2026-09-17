extends RefCounted
## The gearbox: ratios, torque, and when the driver is allowed to change gear.
##
## OWNER: agent GEARBOX. The numbers below are the ones car_controller.gd used
## before the split, so the rest of the game keeps working while the module is
## rewritten into a real sequential F1 gearbox. The API is fixed:
## docs/DRIVE_FEEL_PLAN.md.

const MAX_GEAR := 8
const IDLE_RPM := 4200.0
const REDLINE := 12500.0
const POWER := 3200.0
const RATIOS := [0.0, 3.4, 2.7, 2.2, 1.85, 1.58, 1.38, 1.22, 1.08]
const UPSHIFT_RPM := 9000.0
const SHIFT_TIME := 0.12

var gear: int = 1
var rpm: float = IDLE_RPM
var shift_cd: float = 0.0
var last_event: int = 0


func setup(seed_rpm: float = IDLE_RPM) -> void:
	gear = 1
	rpm = seed_rpm
	shift_cd = 0.0


func reset() -> void:
	gear = 1
	rpm = IDLE_RPM
	shift_cd = 0.0


func ratio(g: int) -> float:
	return float(RATIOS[clampi(g, 1, MAX_GEAR)])


func force_gear(g: int) -> void:
	gear = clampi(g, 1, MAX_GEAR)


func request_shift(up: bool) -> bool:
	if shift_cd > 0.0:
		return false
	if up and gear < MAX_GEAR:
		gear += 1
		shift_cd = SHIFT_TIME
		last_event = 1
		return true
	if not up and gear > 1:
		gear -= 1
		shift_cd = SHIFT_TIME
		last_event = -1
		return true
	return false


func torque_at(r: float) -> float:
	var n: float = clampf((r - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
	var curve: float = sin(n * PI)
	if n > 0.92:
		curve *= 0.35
	return POWER * maxf(curve, 0.12)


func update(delta: float, ctx: Dictionary) -> Dictionary:
	last_event = 0
	shift_cd = maxf(shift_cd - delta, 0.0)
	var speed: float = maxf(float(ctx.get("speed", 0.0)), 0.0)
	var throttle: float = clampf(float(ctx.get("throttle", 0.0)), 0.0, 1.0)
	var auto: bool = bool(ctx.get("auto", false))
	var engage: float = 1.0 - clampf(float(ctx.get("clutch", 0.0)), 0.0, 1.0)

	var speed_rpm: float = clampf(IDLE_RPM + speed * ratio(gear) * 95.0, IDLE_RPM, REDLINE)
	var rev_rpm: float = IDLE_RPM + throttle * (REDLINE - IDLE_RPM)
	if engage < 0.35:
		rpm = lerpf(rpm, rev_rpm, clampf(delta * 7.0, 0.0, 1.0))
	else:
		rpm = lerpf(rpm, speed_rpm, clampf(delta * 8.0, 0.0, 1.0))
	rpm = clampf(rpm, IDLE_RPM, REDLINE + 200.0)

	var torque: float = torque_at(rpm) * throttle * engage
	if auto and rpm >= UPSHIFT_RPM and gear < MAX_GEAR and shift_cd <= 0.0:
		request_shift(true)
	if auto and rpm < 7000.0 and gear > 1 and shift_cd <= 0.0:
		request_shift(false)
	if rpm >= REDLINE - 80.0:
		torque *= 0.12
	var engine_force: float = torque * ratio(gear)
	if throttle < 0.05 and engage > 0.6 and speed > 8.0:
		engine_force = -minf(speed * 18.0 * ratio(gear) * 0.15, 420.0)
	return {
		"engine_force": engine_force,
		"rpm": rpm,
		"gear": gear,
		"shift_event": last_event,
	}
