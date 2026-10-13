extends SceneTree
func _initialize() -> void:
	for k in ["ember", "zip", "brute", "splitter", "mote"]:
		var s := SparkMath.stats(k)
		assert(s.radius > 0.0 and s.speed > 0.0 and s.mass > 0.0 and s.drain_time > 0.0)
	assert(SparkMath.max_alive(0.0) == SparkMath.ALIVE_START and SparkMath.max_alive(SparkMath.MATCH_SECONDS) == SparkMath.ALIVE_END)
	for mode in SparkMath.MODES:
		var kinds := SparkMath.mode_kinds(mode)
		assert(kinds.size() == 4 and kinds[0] != "")
		for k in kinds:
			if k != "":
				assert(SparkMath.stats(k).has("family"))
		assert(SparkMath.pick(0.0, 0.5, mode) == kinds[0], "early picks the basic critter of " + mode)
		assert(SparkMath.pick(280.0, 0.99, mode) == kinds[3], "late roll reaches the heavy critter of " + mode)
	assert(SparkMath.gap(0.0) > SparkMath.gap(200.0))
	var early := {}
	for i in range(200):
		early[SparkMath.pick(0.0, i / 200.0)] = true
	assert(early.keys() == ["ember"], "only embers at the start: %s" % str(early.keys()))
	var late := {}
	for i in range(200):
		late[SparkMath.pick(250.0, i / 200.0)] = true
	assert(late.has("zip") and late.has("brute") and late.has("splitter"), "late mix: %s" % str(late.keys()))
	assert(SparkMath.energy_rate(0) > 0.0 and SparkMath.energy_rate(2) < SparkMath.energy_rate(1))
	var w := SparkMath.weave_offset(1.0, 0.5, 1.0, 0.0)
	assert(absf(w.x) <= 0.5 and absf(w.y) <= 0.25 and w.z == 0.0)
	var o := SparkMath.orbit_point(Vector3(1, 0.5, 1), 0.0, 0.6, 0.1)
	assert(o.is_equal_approx(Vector3(1.6, 0.6, 1.0)))
	# Waves: five, ending with a boss; more breaches as they climb.
	assert(SparkMath.WAVES.size() == 5 and SparkMath.WAVES[4].boss and not SparkMath.WAVES[0].boss)
	for i in range(1, 5):
		assert(SparkMath.WAVES[i].cracks >= SparkMath.WAVES[i - 1].cracks)
	for m in SparkMath.MODES:
		assert(SparkMath.wave_pick(0, 0.99, m) == SparkMath.mode_kinds(m)[0], "wave one is only the basic critter")
		for r in [0.0, 0.3, 0.6, 0.99]:
			assert(SparkMath.wave_pick(3, r, m) != "")
	# Scoring.
	assert(SparkMath.base_points("mote") < SparkMath.base_points("ember"))
	assert(SparkMath.base_points("ember", true) == 2500)
	assert(SparkMath.method_bonus("catch") > SparkMath.method_bonus("crush"))
	assert(SparkMath.combo_multiplier(1) == 1.0 and SparkMath.combo_multiplier(3) == 1.5 and SparkMath.combo_multiplier(50) == 3.0)
	assert(SparkMath.stars_for(false, 1.0) == 0 and SparkMath.stars_for(true, 0.9) == 3 and SparkMath.stars_for(true, 0.6) == 2 and SparkMath.stars_for(true, 0.1) == 1)
	# Save keeps the best per mode.
	var save := SaveData.new()
	save.path = "user://sharara_test.json"
	save.load_file()
	assert(save.record("snakes", 1200, 2))
	assert(not save.record("snakes", 900, 3), "lower score is not a new best")
	assert(save.best("snakes") == 1200 and save.stars("snakes") == 3, "stars keep the max")
	var again := SaveData.new()
	again.path = save.path
	again.load_file()
	assert(again.best("snakes") == 1200)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save.path))
	print("PASS: spark math — stats, pressure curve, mix, weave, orbit, waves, scoring, stars, save")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 30.0:
		printerr("FAIL: timeout"); quit(1)
	return false
