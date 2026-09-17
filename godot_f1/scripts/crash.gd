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
const WINDOW := 0.15              ## s over which the speed loss is measured
const IMPACT_MIN_MS := 3.0        ## speed lost inside the window: a rub below this
const IMPACT_FULL_MS := 18.0      ## severity 1.0 from here up
const DAMAGE_PER_CRASH := 0.22

var car
var surfaces
var damage: float = 0.0
var last_impact_ms: float = 0.0
var crash_count: int = 0
var _cooldown: float = 0.0
var _prev_speed: float = 0.0
var _window_t: float = 0.0
var _window_speed: float = 0.0
var _window_ready: bool = false
var _contact_seen: bool = false


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
	if _cooldown > 0.0:
		_contact_seen = false
		return
	if _contact_seen and lost >= IMPACT_MIN_MS:
		_register(lost, "wall")
	_contact_seen = false
	_prev_speed = forward_speed


func _register(impact: float, kind: String) -> void:
	last_impact_ms = impact
	crash_count += 1
	damage = clampf(damage + DAMAGE_PER_CRASH, 0.0, 1.0)
	_cooldown = 0.6
	var severity: float = clampf(impact / IMPACT_FULL_MS, 0.0, 1.0)
	crashed.emit(severity, kind)
