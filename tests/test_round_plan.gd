extends SceneTree
## Wave schedule: ordering, MAX_ALIVE cap, rest periods, finish, match length.
func _initialize() -> void:
	var plan := RoundPlan.new()
	plan.start()
	assert(plan.phase == RoundPlan.Phase.WAVE and plan.wave_index == 0)
	var first := plan.tick(0.0)
	assert(first == ["A"], str(first))
	assert(plan.alive == 1)
	var later := plan.tick(7.5)
	assert(later == ["A"], str(later))
	assert(plan.alive == 2 and plan.pending_in_wave() == 0)
	# Nothing rests while raiders are alive.
	plan.tick(1.0)
	assert(plan.phase == RoundPlan.Phase.WAVE)
	plan.robot_gone()
	plan.robot_gone()
	plan.tick(0.016)
	assert(plan.phase == RoundPlan.Phase.REST, "rest after wave cleared")
	plan.tick(RoundPlan.REST_BETWEEN_WAVES + 0.1)
	assert(plan.phase == RoundPlan.Phase.WAVE and plan.wave_index == 1, "second wave begins")
	# MAX_ALIVE cap: the last wave wants six raiders but only MAX_ALIVE may be out at once.
	var cap := RoundPlan.new()
	cap.start()
	cap.wave_index = RoundPlan.WAVES.size() - 2
	cap._begin_next_wave()
	var last_wave_size: int = RoundPlan.WAVES[RoundPlan.WAVES.size() - 1]["spawns"].size()
	var burst := cap.tick(60.0)
	assert(burst.size() == RoundPlan.MAX_ALIVE, str(burst))
	assert(cap.pending_in_wave() == last_wave_size - RoundPlan.MAX_ALIVE)
	cap.robot_gone()
	assert(cap.tick(0.1).size() == 1)
	# Clearing raiders drains the queue, then the wave rests and the plan finishes.
	while cap.pending_in_wave() > 0:
		cap.robot_gone()
		cap.tick(0.1)
	assert(cap.phase == RoundPlan.Phase.WAVE)
	cap.alive = 0
	cap.tick(0.1)
	assert(cap.phase == RoundPlan.Phase.REST)
	cap.tick(RoundPlan.REST_BETWEEN_WAVES)
	assert(cap.finished())
	# Robot stats cover every kind used by the schedule.
	for w in RoundPlan.WAVES:
		for s in w["spawns"]:
			var stats := RoundPlan.robot_stats(s[1])
			assert(stats.speed > 0.0 and stats.mass > 0.0)
	# Match length lands in the 5–10 minute target window.
	var seconds := RoundPlan.estimated_seconds()
	assert(seconds >= 300.0 and seconds <= 600.0, "estimated %0.0f s" % seconds)
	print("PASS: round plan — %d waves, ~%0.0f s estimated match" % [plan.wave_count(), seconds])
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
