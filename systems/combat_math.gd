class_name CombatMath
extends RefCounted
## Pure, testable arithmetic for SAQR: hit tests, lock-on cones, homing
## steering, room bounds, waves and scoring. No nodes, no rendering.

# --- player jet --------------------------------------------------------------
const JET_RADIUS := 0.11          # hit sphere of the player's jet (m)
const JET_LEAD := 0.30            # jet flies this far ahead of the hand along the aim ray
const JET_ARMOR := 100.0

# --- weapons -------------------------------------------------------------------
const CANNON_RATE := 14.0         # rounds per second (alternating barrels)
const CANNON_SPEED := 34.0        # m/s — crosses a room in ~0.1 s
const CANNON_DAMAGE := 1.0
const CANNON_SPREAD_DEG := 0.35   # tiny: this is a precise gun

const MISSILE_STOCK := 8
const MISSILE_RELOAD := 2.5       # seconds per missile
const MISSILE_LOCKS := 4
const LOCK_CONE_DEG := 16.0
const LOCK_RANGE := 6.0
const LOCK_TIME := 0.28           # seconds per new lock while grip is held
const MISSILE_SPEED := 5.5
const MISSILE_TURN := 7.0         # rad/s
const MISSILE_DAMAGE := 6.0
const MISSILE_LIFE := 4.0

const BOMB_STOCK := 6
const BOMB_RELOAD := 3.0
const BOMB_RADIUS := 0.42
const BOMB_DAMAGE := 12.0
const GRAVITY := 9.8

const FLARE_STOCK := 6
const FLARE_RELOAD := 3.0
const FLARE_LURE := 1.4           # enemy missiles within this distance chase the flare

const LASER_DPS := 9.0
const LASER_HEAT := 0.42          # heat per second while firing (overheats in ~2.4 s)
const LASER_COOL := 0.5
const LASER_RANGE := 7.0

# --- enemies -------------------------------------------------------------------
## kind → {hp, radius, points, speed}
const ENEMIES := {
	"target":  {"hp": 1.0,  "radius": 0.11, "points": 50,   "speed": 0.0},
	"drone":   {"hp": 3.0,  "radius": 0.10, "points": 100,  "speed": 0.9},
	"fighter": {"hp": 5.0,  "radius": 0.11, "points": 200,  "speed": 1.6},
	"tank":    {"hp": 7.0,  "radius": 0.13, "points": 250,  "speed": 0.22},
	"boss":    {"hp": 70.0, "radius": 0.34, "points": 2000, "speed": 0.35},
}
const PELLET_DAMAGE := 7.0
const PELLET_SPEED := 2.4
const ENEMY_MISSILE_DAMAGE := 18.0
const ENEMY_MISSILE_SPEED := 2.6
const ENEMY_MISSILE_TURN := 2.2
const FLAK_DAMAGE := 9.0
const FLAK_SPEED := 3.2

## Five waves; the fifth is the boss. Each entry: kind → count.
const WAVES := [
	{"target": 6, "drone": 2},
	{"drone": 5, "tank": 1},
	{"drone": 3, "fighter": 2, "tank": 1},
	{"drone": 4, "fighter": 3, "tank": 2},
	{"boss": 1, "drone": 2},
]
const BREAK_SECONDS := 4.0
const COMBO_WINDOW := 2.5
const COMBO_MAX := 3.0


## Distance along a segment p0→p1 where it first enters a sphere, as a 0..1
## fraction, or -1 when it misses. Exact, so fast rounds never tunnel.
static func segment_sphere(p0: Vector3, p1: Vector3, center: Vector3, radius: float) -> float:
	var d := p1 - p0
	var len2 := d.length_squared()
	if len2 < 1e-10:
		return 0.0 if p0.distance_to(center) <= radius else -1.0
	var m := p0 - center
	var b := m.dot(d)
	var c := m.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	if b > 0.0:
		return -1.0
	var disc := b * b - len2 * c
	if disc < 0.0:
		return -1.0
	var t := (-b - sqrt(disc)) / len2
	return t if t <= 1.0 else -1.0


## Distance along an infinite ray to a sphere, or INF.
static func ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var m := origin - center
	var b := m.dot(dir)
	var c := m.length_squared() - radius * radius
	if c > 0.0 and b > 0.0:
		return INF
	var disc := b * b - c
	if disc < 0.0:
		return INF
	return maxf(0.0, -b - sqrt(disc))


## True when `point` sits inside the lock cone in front of the jet.
static func in_lock_cone(origin: Vector3, forward: Vector3, point: Vector3, cone_deg: float = LOCK_CONE_DEG, max_range: float = LOCK_RANGE) -> bool:
	var to := point - origin
	var dist := to.length()
	if dist < 0.05 or dist > max_range:
		return false
	return forward.normalized().dot(to / dist) >= cos(deg_to_rad(cone_deg))


## Angle (degrees) between the jet's nose and a point; used to pick the best lock.
static func off_axis_deg(origin: Vector3, forward: Vector3, point: Vector3) -> float:
	var to := (point - origin).normalized()
	return rad_to_deg(acos(clampf(forward.normalized().dot(to), -1.0, 1.0)))


## Rotates a heading toward a target with a capped turn rate. Returns the new
## unit heading.
static func steer(heading: Vector3, to_target: Vector3, turn_rate: float, delta: float) -> Vector3:
	var h := heading.normalized()
	if to_target.length_squared() < 1e-8:
		return h
	var want := to_target.normalized()
	var angle := h.angle_to(want)
	var max_step := turn_rate * delta
	if angle <= max_step or angle < 1e-5:
		return want
	var axis := h.cross(want)
	if axis.length_squared() < 1e-10:
		axis = Vector3.UP if absf(h.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return h.rotated(axis.normalized(), max_step).normalized()


## Where a falling bomb lands (y = floor_y) given its release point and velocity.
static func bomb_impact(p: Vector3, v: Vector3, floor_y: float, gravity: float = GRAVITY) -> Vector3:
	var h := p.y - floor_y
	if h <= 0.0:
		return Vector3(p.x, floor_y, p.z)
	# h + v.y t - g t²/2 = 0
	var t := (v.y + sqrt(v.y * v.y + 2.0 * gravity * h)) / gravity
	return Vector3(p.x + v.x * t, floor_y, p.z + v.z * t)


## Linear falloff blast damage.
static func blast_damage(distance: float, radius: float, damage: float) -> float:
	if distance >= radius:
		return 0.0
	return damage * (1.0 - 0.6 * distance / radius)


## Combo multiplier after `streak` quick kills: ×1, ×1.25, ×1.5 … capped at ×3.
static func combo(streak: int) -> float:
	return minf(COMBO_MAX, 1.0 + 0.25 * maxf(0, streak - 1))


static func points(kind: String, multiplier: float, weapon: String = "") -> int:
	var base: float = ENEMIES[kind].points
	if weapon == "bomb" and kind == "tank":
		base *= 1.5
	elif weapon == "missile" and kind == "fighter":
		base *= 1.25
	return int(round(base * multiplier))


## Stars from armour left at the end: 3 at ≥70 %, 2 at ≥40 %, 1 if alive.
static func stars(armor_fraction: float, won: bool) -> int:
	if not won:
		return 0
	if armor_fraction >= 0.7:
		return 3
	if armor_fraction >= 0.4:
		return 2
	return 1


static func wave_total(wave: int) -> int:
	var total := 0
	for k in WAVES[wave]:
		total += int(WAVES[wave][k])
	return total


## The playable box of the room, built from wall mounts. Walls supply the XZ
## extent; the ceiling mount (if any) the height. Falls back to a 3.2 m box
## around the player when the room has no data.
## Returns {min: Vector3, max: Vector3}.
static func room_box(mounts: Array, floor_y: float, center: Vector3) -> Dictionary:
	var lo := Vector3(INF, floor_y, INF)
	var hi := Vector3(-INF, floor_y + 2.5, -INF)
	var walls := 0
	for m in mounts:
		if m.kind == "ceiling":
			hi.y = maxf(floor_y + 1.9, m.origin.y)
			continue
		var o: Vector3 = m.origin
		var n: Vector3 = m.normal
		var side := Vector3(-n.z, 0, n.x) * (float(m.width) * 0.5)
		for p in [o + side, o - side]:
			lo.x = minf(lo.x, p.x)
			lo.z = minf(lo.z, p.z)
			hi.x = maxf(hi.x, p.x)
			hi.z = maxf(hi.z, p.z)
		walls += 1
	if walls < 2 or hi.x - lo.x < 1.2 or hi.z - lo.z < 1.2:
		lo = Vector3(center.x - 1.6, floor_y, center.z - 1.6)
		hi = Vector3(center.x + 1.6, maxf(hi.y, floor_y + 2.3), center.z + 1.6)
	# Rooms bigger than this make the fight drift too far from the player.
	var mid := (lo + hi) * 0.5
	var half := Vector3(minf((hi.x - lo.x) * 0.5, 3.0), 0, minf((hi.z - lo.z) * 0.5, 3.0))
	return {"min": Vector3(mid.x - half.x, lo.y, mid.z - half.z), "max": Vector3(mid.x + half.x, hi.y, mid.z + half.z)}


## Clamp a flying point into the box, `margin` metres inside every face.
static func clamp_into(p: Vector3, box: Dictionary, margin: float, min_height: float = 0.5) -> Vector3:
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	return Vector3(
		clampf(p.x, lo.x + margin, hi.x - margin),
		clampf(p.y, lo.y + min_height, hi.y - margin),
		clampf(p.z, lo.z + margin, hi.z - margin))


static func inside(p: Vector3, box: Dictionary, slack: float = 0.25) -> bool:
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	return p.x > lo.x - slack and p.x < hi.x + slack and p.y > lo.y - slack and p.y < hi.y + slack and p.z > lo.z - slack and p.z < hi.z + slack


## Critically damped spring step (used for the jet following the hand).
## Returns [new_position, new_velocity].
static func spring(pos: Vector3, vel: Vector3, target: Vector3, omega: float, delta: float) -> Array:
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := pos - target
	var temp := (vel + change * omega) * delta
	var new_vel := (vel - temp * omega) * e
	var new_pos := target + (change + temp) * e
	return [new_pos, new_vel]
