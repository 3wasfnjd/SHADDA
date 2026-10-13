class_name SparkMath
extends RefCounted
## Spark behaviour numbers and the continuous pressure curve, kept free of
## scene nodes so they can be unit tested headless.

const MATCH_SECONDS := 300.0
const FIRST_SPAWN := 3.0
const GAP_START := 9.0
const GAP_END := 3.2
const ALIVE_START := 1
const ALIVE_END := 5

## Per-kind tuning. radius in metres, speed m/s, mass relative to a kind-1
## spark, drain_time seconds orbiting the gem before leaving with a shard.
static func stats(kind: String) -> Dictionary:
	match kind:
		"zip":
			return {"radius": 0.085, "speed": 2.4, "mass": 0.55, "weave": 0.9, "weave_hz": 2.6, "drain_time": 1.2, "color": Neon.CYAN, "hp": 1}
		"brute":
			return {"radius": 0.2, "speed": 0.85, "mass": 4.0, "weave": 0.15, "weave_hz": 0.6, "drain_time": 3.5, "color": Neon.VIOLET, "hp": 1}
		"splitter":
			return {"radius": 0.13, "speed": 1.4, "mass": 1.0, "weave": 0.5, "weave_hz": 1.4, "drain_time": 2.0, "color": Color(0.35, 1.0, 0.45), "hp": 1}
		"mote":
			return {"radius": 0.06, "speed": 2.0, "mass": 0.35, "weave": 0.6, "weave_hz": 3.0, "drain_time": 0.9, "color": Color(0.6, 1.0, 0.6), "hp": 1}
		_:
			return {"radius": 0.12, "speed": 1.5, "mass": 1.0, "weave": 0.45, "weave_hz": 1.3, "drain_time": 2.2, "color": Neon.AMBER, "hp": 1}


static func progress(time: float) -> float:
	return clampf(time / MATCH_SECONDS, 0.0, 1.0)


static func gap(time: float) -> float:
	return lerpf(GAP_START, GAP_END, progress(time))


static func max_alive(time: float) -> int:
	return int(round(lerpf(ALIVE_START, ALIVE_END, progress(time))))


## Weighted mix: embers from the start, zips after 30 s, splitters after 75 s,
## brutes after 120 s.
static func weights(time: float) -> Dictionary:
	return {
		"ember": 1.0,
		"zip": clampf((time - 30.0) / 30.0, 0.0, 1.0) * 1.1,
		"splitter": clampf((time - 75.0) / 40.0, 0.0, 1.0) * 0.7,
		"brute": clampf((time - 120.0) / 60.0, 0.0, 1.0) * 0.6,
	}


static func pick(time: float, roll: float) -> String:
	var w := weights(time)
	var total := 0.0
	for k in w:
		total += w[k]
	var r := roll * total
	for k in ["ember", "zip", "splitter", "brute"]:
		r -= w[k]
		if r <= 0.0:
			return k
	return "ember"


## Weaving flight: a sideways/vertical wobble added to the straight path.
static func weave_offset(t: float, amplitude: float, hz: float, seed: float) -> Vector3:
	return Vector3(sin(t * hz * TAU + seed) * amplitude, cos(t * hz * 0.7 * TAU + seed * 1.3) * amplitude * 0.5, 0.0)


## Orbit point around the gem at a given angle and height.
static func orbit_point(center: Vector3, angle: float, radius: float, height: float) -> Vector3:
	return center + Vector3(cos(angle) * radius, height, sin(angle) * radius)


## Gem energy change per second: sparks orbiting drain, otherwise slow regen.
static func energy_rate(draining: int) -> float:
	return -0.03 * draining if draining > 0 else 0.012


const SHARD_LOSS := 0.12
