class_name TetherMath
extends RefCounted
## Pure tether/rope arithmetic, kept free of scene nodes so it can be unit
## tested headless. All distances are metres, all times seconds.

const MIN_REST := 0.45          # the rope never reels shorter than this
const REEL_SPEED := 1.0         # m/s of rope reeled in at full grip
const SLACK_BAND := 0.55        # metres of stretch between taut and snapping
const SPRING := 18.0            # pull acceleration per metre of stretch (mass 1)
const MAX_DRAG := 1.6           # m/s cap on rope-induced speed
const SNAP_HOLD := 0.8          # seconds at full tension before the rope snaps
const STUN_TENSION := 0.9       # tension at which a robot drops what it carries


## New rope length after the player reels in with the given grip (0..1).
static func reel(rest_length: float, grip: float, delta: float) -> float:
	return maxf(MIN_REST, rest_length - clampf(grip, 0.0, 1.0) * REEL_SPEED * delta)


## 0 = slack, 1 = about to snap.
static func tension(distance: float, rest_length: float) -> float:
	return clampf((distance - rest_length) / SLACK_BAND, 0.0, 1.0)


## Horizontal pull applied to the robot this frame (velocity delta, m/s).
static func pull_velocity(hand: Vector3, anchor: Vector3, rest_length: float, mass: float, delta: float) -> Vector3:
	var to_hand := hand - anchor
	var distance := to_hand.length()
	if distance <= rest_length or distance < 0.001:
		return Vector3.ZERO
	var stretch := distance - rest_length
	var direction := to_hand / distance
	return direction * minf(stretch * SPRING / maxf(mass, 0.2) * delta, MAX_DRAG * delta * 6.0)


## Tracks how long the rope has been at full tension; returns true once it must snap.
static func snap_timer(previous: float, tension_value: float, delta: float) -> float:
	if tension_value >= 0.999:
		return previous + delta
	return maxf(0.0, previous - delta * 2.0)


static func should_snap(timer: float) -> bool:
	return timer >= SNAP_HOLD


## Rope colour from cyan (slack) through amber (stretched) to white-hot (snapping).
static func rope_color(tension_value: float) -> Color:
	if tension_value < 0.5:
		return Neon.CYAN.lerp(Neon.AMBER, tension_value * 2.0)
	return Neon.AMBER.lerp(Neon.WHITE, (tension_value - 0.5) * 2.0)


## Points along a sagging rope between two anchors. Sag grows with slack.
static func rope_points(from: Vector3, to: Vector3, rest_length: float, segments: int, wobble: float = 0.0, time: float = 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	var distance := from.distance_to(to)
	var slack := maxf(0.0, rest_length - distance)
	var sag := minf(0.45, slack * 0.5)
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := from.lerp(to, t)
		var bulge := 4.0 * t * (1.0 - t)
		p.y -= sag * bulge
		if wobble > 0.0:
			p += Vector3(sin(time * 23.0 + t * 19.0), cos(time * 17.0 + t * 13.0), sin(time * 29.0 + t * 7.0)) * wobble * bulge
		points.append(p)
	return points


## Haptic amplitude for the hand holding a rope.
static func haptic_amplitude(tension_value: float, reeling: bool) -> float:
	var base := 0.12 if reeling else 0.0
	return clampf(base + tension_value * 0.7, 0.0, 1.0)
