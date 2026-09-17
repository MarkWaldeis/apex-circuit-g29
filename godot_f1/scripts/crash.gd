extends RefCounted
## Crash detection and damage.
##
## The chassis collider is a real body, so a wall impact shows up as contacts
## and as a sudden loss of speed. Severity comes from the impact speed, not
## from the frame count, so scraping along a wall is cheap and a head-on hit is
## not.
##
## OWNER: agent CRASH.

signal crashed(severity: float, kind: String)

## A crash is measured over a SHORT WINDOW, not per physics tick.
##
## Godot's body solver spreads a wall impact over several ticks: measured in the
## real scene, a car driving straight into a barrier at 40 m/s lost its speed
## over about a second, so a per-tick threshold of 3 m/s never fired and the
## driver stopped dead at the wall with `crash_count` still 0. The window is
## what makes "I hit the wall" a real event.
##
## A window alone is not enough, because losing speed over 0.15 s is something
## the car does anyway: hard braking with drag over the same window costs
## roughly 1.5 m/s, so any raw threshold low enough for a light hit also fires
## on the braking zone for the first corner. What counts is the speed loss the
## car cannot explain - `_expected_loss()` subtracts what brakes, drag and the
## limiter already account for, and only the rest is damage.
const WINDOW := 0.15              ## s over which the speed loss is measured
## UNEXPLAINED speed lost inside the window. 3 m/s in 0.15 s is 2 g that
## nothing on the car can account for, which is a real hit; rubbing along a
## barrier stays below it.
const IMPACT_MIN_MS := 3.0
const IMPACT_FULL_MS := 18.0      ## severity 1.0 from here up
const DAMAGE_PER_CRASH := 0.22

var car
var surfaces
var damage: float = 0.0
var last_impact_ms: float = 0.0
var crash_count: int = 0
var _cooldown: float = 0.0
var _window_t: float = 0.0
var _window_speed: float = 0.0
var _window_ready: bool = false
var _contact_seen: bool = false
## Diagnostics for the tests: what the car would have lost without a wall, and
## what is left once that is subtracted.
var expected_loss_ms: float = 0.0
var unexplained_ms: float = 0.0


func setup(owner_car, surface_model) -> void:
	car = owner_car
	surfaces = surface_model
	if car:
		car.contact_monitor = true
		car.max_contacts_reported = 8


func reset() -> void:
	damage = 0.0
	last_impact_ms = 0.0
	crash_count = 0
	_cooldown = 0.0
	_window_ready = false
	_contact_seen = false
	expected_loss_ms = 0.0
	unexplained_ms = 0.0


func update(delta: float, _surface: Dictionary, forward_speed: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if car == null:
		return
	# The chassis is the only body with contacts - the wheels are ray casts, so
	# ordinary driving never touches anything and a contact really means "the
	# tub hit something".
	if car.get_contact_count() > 0:
		_contact_seen = true
	if not _window_ready:
		_window_speed = forward_speed
		_window_ready = true
		return
	_window_t += delta
	if _window_t < WINDOW:
		return
	var lost: float = _window_speed - forward_speed
	_window_speed = forward_speed
	_window_t = 0.0
	expected_loss_ms = _expected_loss(_contact_seen)
	unexplained_ms = lost - expected_loss_ms
	if _cooldown > 0.0:
		_contact_seen = false
		return
	if _contact_seen and unexplained_ms >= IMPACT_MIN_MS:
		_register(unexplained_ms, "wall")
	_contact_seen = false


## How much speed the car would have lost inside `WINDOW` with no wall in the
## way at all.
##
## The aerodynamic force is already computed by the car (`aero_drag_n`) and the
## surface's own drag is a constant deceleration, so neither has to be
## measured - only read. The roller term is what is left: with the brake pedal
## down the car decelerates on its own (measured in the real scene: about
## 10 m/s^2), without it only the limiter and the driveline slow the car down.
## `touching` is the honest name for the second term: the roller part of the
## deceleration drops as soon as the tub is in contact with something (the wall
## is doing the work), not when the driver presses the brake pedal.
func _expected_loss(touching: bool) -> float:
	if car == null:
		return 0.0
	var mass: float = maxf(float(car.mass), 1.0)
	var decel: float = float(car.aero_drag_n) / mass
	if surfaces and not surfaces._last.is_empty():
		decel += float(surfaces._last.get("drag", 0.0))
	var roller: float = 4.5 if touching else 10.0
	return (decel + roller) * WINDOW


func _register(impact: float, kind: String) -> void:
	last_impact_ms = impact
	crash_count += 1
	damage = clampf(damage + DAMAGE_PER_CRASH, 0.0, 1.0)
	_cooldown = 0.6
	var severity: float = clampf(impact / IMPACT_FULL_MS, 0.0, 1.0)
	crashed.emit(severity, kind)
