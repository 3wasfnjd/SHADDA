class_name RoundPlan
extends RefCounted
## Wave schedule for one SHADDA match. Pure data + timing, no scene nodes, so
## the whole progression can be unit tested headless.

const MAX_ALIVE := 3
const REST_BETWEEN_WAVES := 8.0

## Each spawn: seconds after the wave starts, robot kind.
const WAVES := [
	{"name": "الجولة ١ — الاستطلاع", "spawns": [[0.0, "A"], [7.0, "A"]]},
	{"name": "الجولة ٢ — النشّالون", "spawns": [[0.0, "B"], [4.0, "A"], [10.0, "B"]]},
	{"name": "الجولة ٣ — الثقيل", "spawns": [[0.0, "C"], [6.0, "B"], [12.0, "B"], [16.0, "A"]]},
	{"name": "الجولة ٤ — المتسلقون", "spawns": [[0.0, "D"], [5.0, "D"], [10.0, "B"], [14.0, "A"]]},
	{"name": "الجولة ٥ — الكماشة", "spawns": [[0.0, "C"], [7.0, "C"], [11.0, "D"], [15.0, "B"], [19.0, "B"]]},
	{"name": "الجولة ٦ — الاقتحام الأخير", "spawns": [[0.0, "C"], [5.0, "D"], [9.0, "B"], [13.0, "B"], [17.0, "A"], [21.0, "D"]]},
]

enum Phase { IDLE, WAVE, REST, FINISHED }

var phase: int = Phase.IDLE
var wave_index: int = -1
var wave_time: float = 0.0
var rest_time: float = 0.0
var _queue: Array = []          # [[at, kind], ...] still to spawn in this wave
var alive: int = 0
var spawned_total: int = 0


func wave_count() -> int:
	return WAVES.size()


func wave_name() -> String:
	if wave_index < 0 or wave_index >= WAVES.size():
		return ""
	return WAVES[wave_index]["name"]


func start() -> void:
	phase = Phase.IDLE
	wave_index = -1
	alive = 0
	spawned_total = 0
	_begin_next_wave()


func _begin_next_wave() -> void:
	wave_index += 1
	if wave_index >= WAVES.size():
		phase = Phase.FINISHED
		return
	phase = Phase.WAVE
	wave_time = 0.0
	_queue = WAVES[wave_index]["spawns"].duplicate(true)


## Advances the schedule. Returns the kinds that must spawn this tick.
func tick(delta: float) -> Array:
	var spawns: Array = []
	match phase:
		Phase.WAVE:
			wave_time += delta
			while not _queue.is_empty() and _queue[0][0] <= wave_time and alive + spawns.size() < MAX_ALIVE:
				spawns.append(_queue.pop_front()[1])
			if _queue.is_empty() and alive == 0 and spawns.is_empty():
				phase = Phase.REST
				rest_time = 0.0
		Phase.REST:
			rest_time += delta
			if rest_time >= REST_BETWEEN_WAVES:
				_begin_next_wave()
	spawned_total += spawns.size()
	alive += spawns.size()
	return spawns


func robot_gone() -> void:
	alive = maxi(0, alive - 1)


func pending_in_wave() -> int:
	return _queue.size()


func finished() -> bool:
	return phase == Phase.FINISHED


func rest_remaining() -> float:
	return maxf(0.0, REST_BETWEEN_WAVES - rest_time) if phase == Phase.REST else 0.0


## Rough length of a full match assuming each raider lives ~45 s (walk, steal, flee, stuns).
static func estimated_seconds(robot_life: float = 45.0) -> float:
	var total := 0.0
	for w in WAVES:
		var last_spawn: float = w["spawns"][w["spawns"].size() - 1][0]
		total += last_spawn + robot_life + REST_BETWEEN_WAVES
	return total


static func robot_stats(kind: String) -> Dictionary:
	match kind:
		"B":
			return {"speed": 1.25, "mass": 0.75, "hover": 0.0, "steal_time": 1.2, "label": "النشّال"}
		"C":
			return {"speed": 0.48, "mass": 4.5, "hover": 0.0, "steal_time": 3.0, "label": "القبيل"}
		"D":
			return {"speed": 0.85, "mass": 0.9, "hover": 1.35, "steal_time": 1.8, "label": "المتسلق"}
		_:
			return {"speed": 0.72, "mass": 1.1, "hover": 0.0, "steal_time": 2.0, "label": "الحارس"}
