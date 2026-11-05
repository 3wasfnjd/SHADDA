class_name WarMath
extends RefCounted
## Pure, testable arithmetic: flight model, exact hit tests, lock cone, room
## geometry (walls with openings), waves and scoring. No nodes.

# --- player plane -------------------------------------------------------------
const PLANE_RADIUS := 0.12
const PLANE_HP := 100.0
const CRUISE := 1.35            # m/s — a toy plane crossing a room
const BOOST := 2.2
const MIN_SPEED := 0.75
const TURN_RATE := 2.7          # rad/s at cruise
const CLIMB_LIMIT := 0.62       # max |y| of the flight direction
const TAKEOFF_SPEED := 0.95
const GEAR_HEIGHT := 0.045      # wheels-to-centre when parked
const WALL_LOOKAHEAD := 0.55
const WALL_MARGIN := 0.32

# --- weapons -------------------------------------------------------------------
const GUN_RATE := 16.0
const BULLET_SPEED := 9.0       # slow enough to see the tracers stream
const BULLET_DAMAGE := 1.0
const ROCKETS := 6
const ROCKET_RELOAD := 2.4
const ROCKET_SPEED := 4.2
const ROCKET_TURN := 5.0
const ROCKET_DAMAGE := 6.0
const LOCKS := 4
const LOCK_CONE_DEG := 18.0
const LOCK_RANGE := 4.5
const LOCK_TIME := 0.3
const BOMBS := 3
const BOMB_RELOAD := 4.0
const BOMB_RADIUS := 0.38
const BOMB_DAMAGE := 14.0
const GRAVITY := 9.8
const ROLL_TIME := 0.7
const ROLL_COOLDOWN := 2.2
const BOOST_SECONDS := 2.5
const BOOST_RECHARGE := 0.35    # fraction per second

# --- enemies ---------------------------------------------------------------------
const ENEMIES := {
	"balloon":   {"hp": 2.0,  "radius": 0.11, "points": 50},
	"fighter":   {"hp": 5.0,  "radius": 0.12, "points": 200},
	"transport": {"hp": 10.0, "radius": 0.17, "points": 300},
	"tank":      {"hp": 8.0,  "radius": 0.11, "points": 250},
	"aa":        {"hp": 6.0,  "radius": 0.10, "points": 200},
	"bomber":    {"hp": 30.0, "radius": 0.30, "points": 2000},
}
const ENEMY_BULLET_DAMAGE := 3.0
const ENEMY_BULLET_SPEED := 6.0
const SHELL_DAMAGE := 12.0
const SHELL_SPEED := 4.5
const SHELL_GRAVITY := 4.9      # cartoon shells float a little
const FLAK_DAMAGE := 9.0
const FLAK_SPEED := 3.6
const ENGINE_HP := 10.0
const CRASH_DAMAGE := 12.0

## Five waves; the fifth is the bomber.
const WAVES := [
	{"balloon": 5, "fighter": 1},
	{"fighter": 3, "transport": 1},
	{"tank": 2, "fighter": 2, "balloon": 2},
	{"transport": 1, "tank": 2, "fighter": 3},
	{"bomber": 1, "fighter": 2},
]
const BREAK_SECONDS := 4.0
const COMBO_WINDOW := 2.5
const COMBO_MAX := 3.0


# --- flight ------------------------------------------------------------------------

## One flight step shared by the player and enemy planes.
## state: {pos: Vector3, fwd: Vector3 (unit), speed: float, bank: float}
## Returns the same dictionary, updated. The plane always flies forward; it
## turns toward `goal` at a capped rate, slows on climbs, speeds on dives,
## banks into turns and steers away from the room box before reaching it.
static func fly(state: Dictionary, goal: Vector3, wanted_speed: float, delta: float, box: Dictionary, turn_rate: float = TURN_RATE) -> Dictionary:
	var pos: Vector3 = state.pos
	var fwd: Vector3 = state.fwd
	var speed: float = state.speed
	var to := goal - pos
	var want := fwd if to.length() < 0.2 else to.normalized()
	want = (want + avoid(pos, fwd, box)).normalized()
	want.y = clampf(want.y, -CLIMB_LIMIT, CLIMB_LIMIT)
	want = want.normalized()
	var new_fwd := steer(fwd, want, turn_rate * clampf(1.6 - speed / (CRUISE * 2.0), 0.7, 1.3), delta)
	new_fwd.y = clampf(new_fwd.y, -CLIMB_LIMIT, CLIMB_LIMIT)
	new_fwd = new_fwd.normalized()
	# Energy: climbing costs speed, diving adds it.
	speed = move_toward(speed, wanted_speed, 1.6 * delta)
	speed += (-new_fwd.y * 2.4) * delta
	speed = maxf(speed, MIN_SPEED)
	var yaw_rate := Vector2(fwd.x, fwd.z).angle_to(Vector2(new_fwd.x, new_fwd.z)) / maxf(delta, 1e-4)
	var bank: float = state.bank
	bank = lerpf(bank, clampf(yaw_rate * 0.42, -1.25, 1.25), minf(1.0, delta * 6.0))
	var np := pos + new_fwd * speed * delta
	# Hard edge: never leave the box; slide along the face and turn away.
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	for axis in [0, 1, 2]:
		var inset := 0.1 if axis != 1 else 0.08
		if np[axis] < lo[axis] + inset:
			np[axis] = lo[axis] + inset
			if new_fwd[axis] < 0.0:
				new_fwd[axis] = -new_fwd[axis] * 0.3
		elif np[axis] > hi[axis] - inset:
			np[axis] = hi[axis] - inset
			if new_fwd[axis] > 0.0:
				new_fwd[axis] = -new_fwd[axis] * 0.3
	new_fwd = new_fwd.normalized()
	return {"pos": np, "fwd": new_fwd, "speed": speed, "bank": bank}


## Push-away vector from the box faces the plane is heading into.
static func avoid(pos: Vector3, fwd: Vector3, box: Dictionary) -> Vector3:
	var ahead := pos + fwd * WALL_LOOKAHEAD
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	var push := Vector3.ZERO
	for axis in [0, 1, 2]:
		var low_margin := WALL_MARGIN if axis != 1 else 0.28
		var d_lo: float = ahead[axis] - lo[axis]
		var d_hi: float = hi[axis] - ahead[axis]
		if d_lo < low_margin:
			push[axis] += (low_margin - d_lo) / low_margin * 3.0
		if d_hi < WALL_MARGIN:
			push[axis] -= (WALL_MARGIN - d_hi) / WALL_MARGIN * 3.0
	return push


## The visual basis of a flying plane: nose along fwd, rolled by bank (+ extra roll).
static func plane_basis(fwd: Vector3, bank: float, extra_roll: float = 0.0) -> Basis:
	var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.BACK
	return Basis.looking_at(fwd, up) * Basis(Vector3.FORWARD, -bank + extra_roll)


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


## Where the player is pointing: the aim ray's hit point pulled back toward the
## player and kept off the floor, so the plane chases a point it can reach.
static func steer_point(origin: Vector3, dir: Vector3, hit_distance: float, box: Dictionary) -> Vector3:
	var d := clampf(hit_distance - 0.35, 0.6, 3.5)
	return clamp_into(origin + dir.normalized() * d, box, WALL_MARGIN, 0.3)


# --- hits ----------------------------------------------------------------------------

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


static func in_cone(origin: Vector3, forward: Vector3, point: Vector3, cone_deg: float = LOCK_CONE_DEG, max_range: float = LOCK_RANGE) -> bool:
	var to := point - origin
	var dist := to.length()
	if dist < 0.05 or dist > max_range:
		return false
	return forward.normalized().dot(to / dist) >= cos(deg_to_rad(cone_deg))


static func off_axis_deg(origin: Vector3, forward: Vector3, point: Vector3) -> float:
	return rad_to_deg(acos(clampf(forward.normalized().dot((point - origin).normalized()), -1.0, 1.0)))


## Where a falling bomb lands on a surface at height `ground_y`.
static func bomb_impact(p: Vector3, v: Vector3, ground_y: float, gravity: float = GRAVITY) -> Vector3:
	var h := p.y - ground_y
	if h <= 0.0:
		return Vector3(p.x, ground_y, p.z)
	var t := (v.y + sqrt(v.y * v.y + 2.0 * gravity * h)) / gravity
	return Vector3(p.x + v.x * t, ground_y, p.z + v.z * t)


## Launch direction for a shell at `speed` to pass through `target` (low arc),
## or the straight line when out of reach.
static func ballistic_dir(from: Vector3, target: Vector3, speed: float, gravity: float = GRAVITY) -> Vector3:
	var d := target - from
	var flat := Vector2(d.x, d.z)
	var x := flat.length()
	var y := d.y
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * x * x + 2.0 * y * v2)
	if disc < 0.0 or x < 1e-4:
		return d.normalized()
	var angle := atan((v2 - sqrt(disc)) / (gravity * x))
	var h := flat.normalized()
	return Vector3(h.x * cos(angle), sin(angle), h.y * cos(angle)).normalized()


static func blast_damage(distance: float, radius: float, damage: float) -> float:
	if distance >= radius:
		return 0.0
	return damage * (1.0 - 0.6 * distance / radius)


static func combo(streak: int) -> float:
	return minf(COMBO_MAX, 1.0 + 0.25 * maxf(0, streak - 1))


static func points(kind: String, multiplier: float, weapon: String = "") -> int:
	var base: float = ENEMIES[kind].points
	if weapon == "bomb" and (kind == "tank" or kind == "aa"):
		base *= 1.5
	elif weapon == "gun" and kind == "fighter":
		base *= 1.25   # a gun kill in a dogfight is worth more
	return int(round(base * multiplier))


static func stars(hp_fraction: float, won: bool) -> int:
	if not won:
		return 0
	if hp_fraction >= 0.7:
		return 3
	if hp_fraction >= 0.4:
		return 2
	return 1


static func wave_total(wave: int) -> int:
	var total := 0
	for k in WAVES[wave]:
		total += int(WAVES[wave][k])
	return total


# --- room ----------------------------------------------------------------------------

## The flyable box from the room's walls (floor to ceiling). Falls back to a
## 3.2 m box around the player when there are no walls.
static func room_box(walls: Array, floor_y: float, ceiling_y: float, center: Vector3) -> Dictionary:
	var lo := Vector3(INF, floor_y, INF)
	var hi := Vector3(-INF, ceiling_y, -INF)
	for w in walls:
		var n: Vector3 = w.normal
		var side := Vector3(-n.z, 0, n.x) * (float(w.width) * 0.5)
		for p in [w.origin + side, w.origin - side]:
			lo.x = minf(lo.x, p.x)
			lo.z = minf(lo.z, p.z)
			hi.x = maxf(hi.x, p.x)
			hi.z = maxf(hi.z, p.z)
	if walls.size() < 2 or hi.x - lo.x < 1.4 or hi.z - lo.z < 1.4:
		lo = Vector3(center.x - 1.6, floor_y, center.z - 1.6)
		hi = Vector3(center.x + 1.6, ceiling_y, center.z + 1.6)
	return {"min": lo, "max": hi}


static func clamp_into(p: Vector3, box: Dictionary, margin: float, min_height: float = 0.3) -> Vector3:
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	return Vector3(
		clampf(p.x, lo.x + margin, hi.x - margin),
		clampf(p.y, lo.y + min_height, hi.y - margin * 0.7),
		clampf(p.z, lo.z + margin, hi.z - margin))


static func inside(p: Vector3, box: Dictionary, slack: float = 0.25) -> bool:
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	return p.x > lo.x - slack and p.x < hi.x + slack and p.y > lo.y - slack and p.y < hi.y + slack and p.z > lo.z - slack and p.z < hi.z + slack


## A wall rectangle minus its openings, as non-overlapping rectangles (Rect2 in
## the wall's own XY plane). Used to build the depth-only wall occluder so
## things behind the real wall disappear while doors and windows stay open.
static func rect_minus_holes(outer: Rect2, holes: Array) -> Array:
	var xs := [outer.position.x, outer.end.x]
	var ys := [outer.position.y, outer.end.y]
	var clipped: Array = []
	for h in holes:
		var c: Rect2 = (h as Rect2).intersection(outer)
		if c.size.x <= 0.001 or c.size.y <= 0.001:
			continue
		clipped.append(c)
		xs.append_array([c.position.x, c.end.x])
		ys.append_array([c.position.y, c.end.y])
	xs.sort()
	ys.sort()
	var out: Array = []
	for i in range(xs.size() - 1):
		for j in range(ys.size() - 1):
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if cell.size.x <= 1e-5 or cell.size.y <= 1e-5:
				continue
			var mid := cell.get_center()
			var in_hole := false
			for c in clipped:
				if (c as Rect2).has_point(mid):
					in_hole = true
					break
			if not in_hole:
				out.append(cell)
	return out
