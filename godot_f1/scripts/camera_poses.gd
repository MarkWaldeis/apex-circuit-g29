extends RefCounted
## Testable camera poses. Vehicle +Z is forward. Camera looks along local -Z.

## Body hull in vehicle space (visual after +Z remap). y=height, z=length.
const HULL_MIN := Vector3(-1.16, 0.0, -2.75)
const HULL_MAX := Vector3(1.16, 1.24, 2.75)

## Cockpit sits ABOVE the hull, looking down the nose at the asphalt.
const HELMET := Vector3(0.0, 1.55, 0.20)
const LOOK := Vector3(0.0, 0.55, 16.0)
## In front of a Camera3D lens (negative Z).
const WHEEL_LOCAL := Vector3(0.0, -0.24, -0.55)
const DASH_LOCAL := Vector3(0.0, -0.34, -0.42)

const CHASE_LOCAL := Vector3(0.0, 2.50, -7.60)
const CHASE_LOOK_LOCAL := Vector3(0.0, 0.45, 12.0)
const HELI_LOCAL := Vector3(0.0, 42.0, 18.0)


static func hull_aabb() -> AABB:
	return AABB(HULL_MIN, HULL_MAX - HULL_MIN)


static func is_outside_hull(local_origin: Vector3) -> bool:
	return not hull_aabb().grow(0.08).has_point(local_origin)


static func cockpit_look_delta() -> Vector3:
	return LOOK - HELMET


static func wheel_is_in_front_of_lens() -> bool:
	return WHEEL_LOCAL.z < -0.2


static func cockpit_looks_forward() -> bool:
	return cockpit_look_delta().z > 1.0


static func chase_looks_forward() -> bool:
	return (CHASE_LOOK_LOCAL - CHASE_LOCAL).z > 1.0


static func world_origin(car_xf: Transform3D, local: Vector3) -> Vector3:
	return car_xf * local
