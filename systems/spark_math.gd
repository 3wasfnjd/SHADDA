class_name SparkMath
extends RefCounted
## Spark behaviour numbers and the continuous pressure curve, kept free of
## scene nodes so they can be unit tested headless.

const MATCH_SECONDS := 300.0
const FIRST_SPAWN := 2.0
const GAP_START := 6.5
const GAP_END := 2.4
const ALIVE_START := 2
const ALIVE_END := 6

## Game modes: each has its own family of critters and spawn mix.
const MODES := ["sparks", "snakes", "drones", "sling"]

## Per-kind tuning. radius in metres, speed m/s, mass relative to a kind-1
## spark, drain_time seconds orbiting the gem before leaving with a shard.
static func stats(kind: String) -> Dictionary:
	match kind:
		# --- sparks ---
		"zip":
			return {"family": "spark", "radius": 0.085, "speed": 2.6, "mass": 0.55, "weave": 0.9, "weave_hz": 2.6, "drain_time": 1.2, "color": Neon.CYAN, "dive": 4.0}
		"brute":
			return {"family": "spark", "radius": 0.2, "speed": 0.9, "mass": 4.0, "weave": 0.15, "weave_hz": 0.6, "drain_time": 3.5, "color": Neon.VIOLET, "dive": 0.0}
		"splitter":
			return {"family": "spark", "radius": 0.13, "speed": 1.5, "mass": 1.0, "weave": 0.5, "weave_hz": 1.4, "drain_time": 2.0, "color": Color(0.35, 1.0, 0.45), "dive": 0.0}
		"mote":
			return {"family": "spark", "radius": 0.06, "speed": 2.2, "mass": 0.35, "weave": 0.6, "weave_hz": 3.0, "drain_time": 0.9, "color": Color(0.6, 1.0, 0.6), "dive": 3.0}
		# --- snakes: crawl on the floor, long bodies, lose segments when yanked ---
		"snake":
			return {"family": "snake", "radius": 0.08, "speed": 1.1, "mass": 1.6, "weave": 0.35, "weave_hz": 1.2, "drain_time": 3.0, "color": Color(0.4, 1.0, 0.5), "dive": 0.0, "segments": 9}
		"viper":
			return {"family": "snake", "radius": 0.065, "speed": 1.9, "mass": 1.0, "weave": 0.6, "weave_hz": 2.2, "drain_time": 2.0, "color": Neon.AMBER, "dive": 5.0, "segments": 7}
		"python":
			return {"family": "snake", "radius": 0.11, "speed": 0.7, "mass": 4.5, "weave": 0.2, "weave_hz": 0.8, "drain_time": 4.0, "color": Neon.VIOLET, "dive": 0.0, "segments": 13}
		# --- drones: hover high, bank into turns, carry shards out of windows/doors ---
		"drone":
			return {"family": "drone", "radius": 0.11, "speed": 1.6, "mass": 1.1, "weave": 0.4, "weave_hz": 1.1, "drain_time": 2.4, "color": Neon.CYAN, "dive": 6.0}
		"wasp":
			return {"family": "drone", "radius": 0.08, "speed": 2.8, "mass": 0.6, "weave": 0.8, "weave_hz": 2.4, "drain_time": 1.4, "color": Neon.AMBER, "dive": 3.5}
		"hauler":
			return {"family": "drone", "radius": 0.18, "speed": 0.9, "mass": 3.6, "weave": 0.15, "weave_hz": 0.5, "drain_time": 3.6, "color": Neon.VIOLET, "dive": 0.0}
		# --- sling: bouncing balls that roll at the gem; rope them and fling them ---
		"ball":
			return {"family": "ball", "radius": 0.14, "speed": 1.4, "mass": 1.2, "weave": 0.0, "weave_hz": 0.0, "drain_time": 2.0, "color": Neon.AMBER, "dive": 0.0}
		"pebble":
			return {"family": "ball", "radius": 0.09, "speed": 2.4, "mass": 0.6, "weave": 0.0, "weave_hz": 0.0, "drain_time": 1.3, "color": Neon.CYAN, "dive": 0.0}
		"boulder":
			return {"family": "ball", "radius": 0.24, "speed": 0.8, "mass": 5.0, "weave": 0.0, "weave_hz": 0.0, "drain_time": 3.5, "color": Neon.VIOLET, "dive": 0.0}
		_:
			return {"family": "spark", "radius": 0.12, "speed": 1.6, "mass": 1.0, "weave": 0.45, "weave_hz": 1.3, "drain_time": 2.2, "color": Neon.AMBER, "dive": 5.5}


## Per-mode spawn table: [basic, fast, splitter-or-null, heavy].
static func mode_kinds(mode: String) -> Array:
	match mode:
		"snakes":
			return ["snake", "viper", "", "python"]
		"drones":
			return ["drone", "wasp", "", "hauler"]
		"sling":
			return ["ball", "pebble", "", "boulder"]
		_:
			return ["ember", "zip", "splitter", "brute"]


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


static func pick(time: float, roll: float, mode: String = "sparks") -> String:
	var w := weights(time)
	var kinds := mode_kinds(mode)
	var slots := ["ember", "zip", "splitter", "brute"]
	var total := 0.0
	for i in range(4):
		if kinds[i] != "":
			total += w[slots[i]]
	var r := roll * total
	for i in range(4):
		if kinds[i] == "":
			continue
		r -= w[slots[i]]
		if r <= 0.0:
			return kinds[i]
	return kinds[0]


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
