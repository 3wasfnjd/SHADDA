class_name SpawnDirector
extends RefCounted
## Continuous pressure curve for one match — no rounds, no announcements.
## Raiders arrive one at a time at first; the gap shrinks and the mix hardens
## with time. Pure logic so it can be unit tested headless.

const MATCH_SECONDS := 360.0        # survive this long and the rifts seal
const FIRST_SPAWN := 4.0
const GAP_START := 16.0
const GAP_END := 6.5
const ALIVE_START := 1
const ALIVE_END := 3

var time: float = 0.0
var next_spawn: float = FIRST_SPAWN
var alive: int = 0
var spawned: int = 0
var finished: bool = false
var _rng := RandomNumberGenerator.new()


func start(seed: int = 0) -> void:
	time = 0.0
	next_spawn = FIRST_SPAWN
	alive = 0
	spawned = 0
	finished = false
	_rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())


func progress() -> float:
	return clampf(time / MATCH_SECONDS, 0.0, 1.0)


func gap() -> float:
	return lerpf(GAP_START, GAP_END, progress())


func max_alive() -> int:
	return int(round(lerpf(ALIVE_START, ALIVE_END, progress())))


## Which raider comes next, weighted by how far the match has gone.
func pick_kind() -> String:
	var p := progress()
	var weights := {"A": 1.0, "B": clampf((time - 50.0) / 40.0, 0.0, 1.0) * 1.1, "C": clampf((time - 120.0) / 60.0, 0.0, 1.0) * 0.8, "D": clampf((time - 170.0) / 60.0, 0.0, 1.0) * 0.9}
	if p > 0.7:
		weights["A"] = 0.6
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := _rng.randf() * total
	for k in ["A", "B", "C", "D"]:
		roll -= weights[k]
		if roll <= 0.0:
			return k
	return "A"


## Advances the clock; returns the kind to spawn now, or "" for none.
func tick(delta: float) -> String:
	if finished:
		return ""
	time += delta
	if time >= MATCH_SECONDS:
		finished = true
		return ""
	if time >= next_spawn and alive < max_alive():
		next_spawn = time + gap()
		alive += 1
		spawned += 1
		return pick_kind()
	return ""


func robot_gone() -> void:
	alive = maxi(0, alive - 1)


static func robot_stats(kind: String) -> Dictionary:
	match kind:
		"B":
			return {"speed": 1.15, "accel": 2.2, "turn": 4.0, "mass": 0.75, "hover": 0.0, "steal_time": 1.4, "gait": "wheels"}
		"C":
			return {"speed": 0.42, "accel": 0.9, "turn": 1.6, "mass": 4.5, "hover": 0.0, "steal_time": 3.2, "gait": "biped"}
		"D":
			return {"speed": 0.8, "accel": 1.6, "turn": 2.6, "mass": 0.9, "hover": 1.3, "steal_time": 2.0, "gait": "flyer"}
		_:
			return {"speed": 0.62, "accel": 1.4, "turn": 2.8, "mass": 1.2, "hover": 0.0, "steal_time": 2.2, "gait": "biped"}
