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

## Helmet cam: in the cockpit opening at the driver's eye height, looking down
## the nose at the asphalt.
##
## The numbers below are not eyeballed. tests/probe_framing.gd projects every
## landmark through a real Camera3D and solves them so the view lands on the
## same frame position as the F1 cockpit reference picture:
##   horizon y = 30 %, wheel x = 29.5..70.5 % / top y = 55.5 %,
##   halo bar y = 15.8 %, mirror glass y = 44.5 %, dash panel y = 40..53 %.
## tests/test_cockpit_framing.gd keeps them there.
## The lens has to clear the airbox: the body's own silhouette is 1.21 m high
## just behind the driver (measured on car_crimson.glb), so anything lower
## puts the camera inside the bodywork and fills the frame with red shell.
const HELMET := Vector3(0.0, 1.29, 0.05)
const LOOK := Vector3(0.0, -1.971, 16.0)
const FOV_COCKPIT := 54.0

## Cockpit props, in camera space: in front of the lens (negative Z).
const WHEEL_LOCAL := Vector3(0.0, -0.118, -0.404)
const WHEEL_WIDTH := 0.30          ## a real Formula wheel is about 0.30 m wide
const WHEEL_TILT := deg_to_rad(-24.0)
## How far the visible steering wheel turns for full lock (radians).
const WHEEL_TURN := 2.1

const DASH_LOCAL := Vector3(0.0, 0.020, -0.55)
const DASH_SIZE := Vector2(0.27, 0.076)
const DASH_TILT := deg_to_rad(-16.0)

const HALO_LOCAL := Vector3(0.0, 0.175, -0.50)
const HALO_WIDTH := 0.924
const HALO_THICK := 0.034

const MIRROR_LOCAL := Vector3(0.368, 0.026, -0.46)
const MIRROR_SIZE := Vector2(0.118, 0.064)

const CHASE_LOCAL := Vector3(0.0, 2.50, -7.60)
const CHASE_LOOK_LOCAL := Vector3(0.0, 0.45, 12.0)
const HELI_LOCAL := Vector3(0.0, 42.0, 18.0)


static func hull_aabb() -> AABB:
	return AABB(HULL_MIN, HULL_MAX - HULL_MIN)


static func is_outside_hull(local_origin: Vector3) -> bool:
	return not hull_aabb().grow(0.08).has_point(local_origin)


static func cockpit_look_delta() -> Vector3:
	return LOOK - HELMET


static func cockpit_basis() -> Basis:
	## The lens looks along its own -Z and the cockpit props are built in that
	## space, so this basis is what points the view down the nose.
	return Basis.looking_at((LOOK - HELMET).normalized(), Vector3.UP)


static func cockpit_transform() -> Transform3D:
	return Transform3D(cockpit_basis(), HELMET)


static func cockpit_pitch_deg() -> float:
	## Downward tilt of the lens in degrees, positive when looking at the road.
	return rad_to_deg(asin(clampf(-cockpit_basis().z.y, -1.0, 1.0)))


static func wheel_is_in_front_of_lens() -> bool:
	return WHEEL_LOCAL.z < -0.2


static func cockpit_looks_forward() -> bool:
	return cockpit_look_delta().z > 1.0


static func chase_looks_forward() -> bool:
	return (CHASE_LOOK_LOCAL - CHASE_LOCAL).z > 1.0


static func world_origin(car_xf: Transform3D, local: Vector3) -> Vector3:
	return car_xf * local
