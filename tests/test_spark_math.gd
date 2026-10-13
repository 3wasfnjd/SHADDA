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
	assert(early.keys() == ["ember"], "only embers at the start: %s" % early.keys())
	var late := {}
	for i in range(200):
		late[SparkMath.pick(250.0, i / 200.0)] = true
	assert(late.has("zip") and late.has("brute") and late.has("splitter"), "late mix: %s" % late.keys())
	assert(SparkMath.energy_rate(0) > 0.0 and SparkMath.energy_rate(2) < SparkMath.energy_rate(1))
	var w := SparkMath.weave_offset(1.0, 0.5, 1.0, 0.0)
	assert(absf(w.x) <= 0.5 and absf(w.y) <= 0.25 and w.z == 0.0)
	var o := SparkMath.orbit_point(Vector3(1, 0.5, 1), 0.0, 0.6, 0.1)
	assert(o.is_equal_approx(Vector3(1.6, 0.6, 1.0)))
	print("PASS: spark math — stats, pressure curve, mix, weave, orbit")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 30.0:
		printerr("FAIL: timeout"); quit(1)
	return false
