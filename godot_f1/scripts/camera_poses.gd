extends RefCounted
## Testable camera poses.
##
## Vehicle space is the imported GLB space: the nose sits on +Z (front wing at
## +2.7, rear wing at -2.6, front axle +1.43, rear axle -2.00) and that is also
## the direction a positive engine_force pushes the hull. Cameras always look
## along their own local -Z, so anything mounted in front of the lens needs a
## negative local z.

## Body hull in vehicle space (measured on car_crimson.glb). y=height, z=length.
const HULL_MIN := Vector3(-1.16, 0.06, -2.75)
const HULL_MAX := Vector3(1.16, 1.21, 2.75)
## Axle heights, used by the orientation tests.
const FRONT_AXLE_Z := 1.434
const REAR_AXLE_Z := -2.005

## Helmet cam: just above the airbox, behind the driver's head, looking down the
## nose at the asphalt. The car's cockpit sits between the axles, so the camera
## must live there too - never at the tail behind the rear wing.
const HELMET := Vector3(0.0, 1.29, 0.05)
const LOOK := Vector3(0.0, 0.42, 16.0)
## Cockpit props, in camera space: in front of the lens (negative Z).
const WHEEL_LOCAL := Vector3(0.0, -0.16, -0.58)
const DASH_LOCAL := Vector3(0.0, -0.46, -0.80)
## How far the visible steering wheel turns for full lock (radians).
const WHEEL_TURN := 2.4

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
