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

const IMPACT_MIN_MS := 3.0        ## below this it is a rub, not a crash
const IMPACT_FULL_MS := 26.0      ## severity 1.0 from here up
const DAMAGE_PER_CRASH := 0.22

var car
var surfaces
var damage: float = 0.0
var last_impact_ms: float = 0.0
var crash_count: int = 0
var _cooldown: float = 0.0
var _prev_speed: float = 0.0


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


func update(delta: float, _surface: Dictionary, forward_speed: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var lost: float = _prev_speed - forward_speed
	_prev_speed = forward_speed
	if car == null:
		return
	if _cooldown > 0.0 or lost < IMPACT_MIN_MS:
		return
	if car.get_contact_count() <= 0:
		return
	_register(lost, "wall")


func _register(impact: float, kind: String) -> void:
	last_impact_ms = impact
	crash_count += 1
	damage = clampf(damage + DAMAGE_PER_CRASH, 0.0, 1.0)
	_cooldown = 0.6
	var severity: float = clampf(impact / IMPACT_FULL_MS, 0.0, 1.0)
	crashed.emit(severity, kind)
