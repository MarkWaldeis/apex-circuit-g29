extends RefCounted
## A sequential eight-speed Formula 1 gearbox.
##
## OWNER: ROOT (the GEARBOX workstream never produced a file, so the root agent
## took this one over).
##
## What makes it feel like a Formula car rather than a car with a gear lever:
##
##   * Ratios are a geometric progression from a short, traction-limited first
##     to a long eighth that reaches ~330 km/h before the limiter - the ratios
##     themselves are the top-speed limiter, together with the aero drag.
##   * The engine makes its torque high up and the limiter really cuts: with the
##     automatic gearbox switched off (`F`) the car sits on the limiter in
##     whatever gear the driver left it in. Nothing shifts behind his back.
##   * A shift takes time and the torque is cut while it happens, so an upshift
##     is a felt event with a small pause, not a number changing.
##   * Downshifts are protected: a gear that would put the engine over the
##     limiter is refused, which is what stops the "brake, spin, engine gone"
##     failure mode of a naive implementation.
##   * Off the throttle the engine brakes the car; at a standstill the clutch
##     opens so the engine idles instead of stalling.
##
## The caller is `car_controller._physics_process()`; the API is frozen in
## docs/DRIVE_FEEL_PLAN.md.

const MAX_GEAR := 8
const IDLE_RPM := 4200.0
const REDLINE := 12500.0
const LIMITER_DROP := 400.0        ## rpm the limiter pulls when it cuts in

## Engine torque at the crank, in the same "engine force" units the physics
## body takes. Measured with tests/probe_thrust.gd: `engine_force` becomes
## roughly 1.58x its value as a force on the body, so this number is calibrated
## against the measured top speed rather than copied from a data sheet.
const PEAK_TORQUE := 7200.0
const TORQUE_PEAK_RPM := 11000.0
const TORQUE_FLOOR := 0.30         ## share of peak available at idle

## Lumped ratio: rpm = IDLE + speed_ms * RATIOS[g] * RPM_PER_MPS_UNIT.
## Geometric progression; first gear short enough to be traction limited,
## eighth reaching beyond 340 km/h at the limiter.
const RATIOS := [0.0, 3.60, 2.94, 2.40, 1.96, 1.60, 1.30, 1.06, 0.87]
const RPM_PER_MPS_UNIT := 95.0

const SHIFT_TIME_UP := 0.05
const SHIFT_TIME_DOWN := 0.07
## Automatic mode shifts where a driver would: up near peak power, down before
## the engine falls off its torque.
const AUTO_UPSHIFT_RPM := 11500.0
const AUTO_DOWNSHIFT_RPM := 8400.0
## A downshift is only allowed if the lower gear stays this far under the
## limiter afterwards.
const OVERREV_MARGIN := 300.0

var gear: int = 1
var rpm: float = IDLE_RPM
var shift_cd: float = 0.0
var last_event: int = 0
## Telemetry for the HUD and the tests.
var last_shift_time: float = -1.0
var shifts_up: int = 0
var shifts_down: int = 0
var refused_downshifts: int = 0
var limiter_hits: int = 0
var _time: float = 0.0


func setup(seed_rpm: float = IDLE_RPM) -> void:
	gear = 1
	rpm = seed_rpm
	shift_cd = 0.0
	last_event = 0
	shifts_up = 0
	shifts_down = 0
	refused_downshifts = 0
	limiter_hits = 0
	_time = 0.0


func reset() -> void:
	setup(IDLE_RPM)


func ratio(g: int) -> float:
	return float(RATIOS[clampi(g, 1, MAX_GEAR)])


func force_gear(g: int) -> void:
	gear = clampi(g, 1, MAX_GEAR)
	shift_cd = 0.0


## Rpm the engine would turn at this speed in this gear.
func rpm_for(g: int, speed: float) -> float:
	return clampf(IDLE_RPM + maxf(speed, 0.0) * ratio(g) * RPM_PER_MPS_UNIT,
		IDLE_RPM, REDLINE + 600.0)


## Would going to `g` over-rev the engine at this speed?
func would_overrev(g: int, speed: float) -> bool:
	return rpm_for(g, speed) > REDLINE - OVERREV_MARGIN


## The paddles, `Q`/`E` and the shift lights all come through here. The
## over-rev protection for downshifts is re-checked in `update()` with the real
## speed; this is the path the driver's hand takes.
func request_shift(up: bool) -> bool:
	if shift_cd > 0.0:
		return false
	if up:
		if gear >= MAX_GEAR:
			return false
		gear += 1
		shift_cd = SHIFT_TIME_UP
		shifts_up += 1
		last_event = 1
		last_shift_time = _time
		return true
	if gear <= 1:
		return false
	gear -= 1
	shift_cd = SHIFT_TIME_DOWN
	shifts_down += 1
	last_event = -1
	last_shift_time = _time
	return true


## Torque curve: rises to a peak at TORQUE_PEAK_RPM and falls away towards the
## limiter, with a floor at idle so the car can always creep away.
func torque_at(r: float) -> float:
	var n: float = clampf((r - IDLE_RPM) / (TORQUE_PEAK_RPM - IDLE_RPM), 0.0, 1.0)
	var rise: float = 1.0 - pow(1.0 - n, 2.0)          ## 0 -> 1, steep early
	var fall: float = 1.0
	if r > TORQUE_PEAK_RPM:
		var over: float = (r - TORQUE_PEAK_RPM) / maxf(REDLINE - TORQUE_PEAK_RPM, 1.0)
		fall = 1.0 - 0.32 * clampf(over, 0.0, 1.0)
	return PEAK_TORQUE * lerpf(TORQUE_FLOOR, 1.0, rise) * fall


func update(delta: float, ctx: Dictionary) -> Dictionary:
	_time += delta
	last_event = 0
	var was_shifting: bool = shift_cd > 0.0
	shift_cd = maxf(shift_cd - delta, 0.0)
	var speed: float = maxf(float(ctx.get("speed", 0.0)), 0.0)
	var throttle: float = clampf(float(ctx.get("throttle", 0.0)), 0.0, 1.0)
	var brake: float = clampf(float(ctx.get("brake", 0.0)), 0.0, 1.0)
	var auto: bool = bool(ctx.get("auto", false))
	var engage: float = 1.0 - clampf(float(ctx.get("clutch", 0.0)), 0.0, 1.0)

	# --- revs ---------------------------------------------------------------
	var geared_rpm: float = rpm_for(gear, speed)
	if engage < 0.35:
		# Clutch open: the engine is free to rev.
		rpm = lerpf(rpm, IDLE_RPM + throttle * (REDLINE - IDLE_RPM), clampf(delta * 9.0, 0.0, 1.0))
	else:
		rpm = lerpf(rpm, geared_rpm, clampf(delta * 14.0, 0.0, 1.0))
	rpm = clampf(rpm, IDLE_RPM, REDLINE + LIMITER_DROP)

	# --- automatic shifting --------------------------------------------------
	if auto and not was_shifting and shift_cd <= 0.0 and engage > 0.5:
		if rpm >= AUTO_UPSHIFT_RPM and gear < MAX_GEAR:
			request_shift(true)
		elif rpm <= AUTO_DOWNSHIFT_RPM and gear > 1:
			var target: int = gear - 1
			if would_overrev(target, speed):
				refused_downshifts += 1
			else:
				request_shift(false)

	# --- torque --------------------------------------------------------------
	var torque: float = torque_at(rpm) * throttle * engage
	if shift_cd > 0.0:
		# Torque cut while the gear is being changed.
		torque = 0.0
	if rpm >= REDLINE - 80.0:
		limiter_hits += 1
		torque *= 0.06
	var engine_force: float = torque * ratio(gear)

	# --- engine braking and anti-stall --------------------------------------
	if throttle < 0.05 and engage > 0.6:
		if speed < 2.0:
			# Rolling to a stop: the clutch opens and the engine idles. Without
			# this the car judders to a halt and stalls.
			engine_force = 0.0
			rpm = maxf(rpm, IDLE_RPM)
		else:
			var rev_share: float = clampf((rpm - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
			engine_force = -minf(600.0 + 2600.0 * rev_share, speed * 220.0) * 0.35
	if brake > 0.08:
		# Braking: no drive at all, engine braking stays.
		engine_force = minf(engine_force, 0.0)

	return {
		"engine_force": engine_force,
		"rpm": rpm,
		"gear": gear,
		"shift_event": last_event,
	}
