extends SceneTree
## Continuous pressure curve: first raider after FIRST_SPAWN, gaps shrink,
## concurrency grows, mix hardens, match finishes at MATCH_SECONDS.
func _initialize() -> void:
	var d := SpawnDirector.new()
	d.start(7)
	var first := ""
	var t := 0.0
	while first == "" and t < 10.0:
		first = d.tick(0.1)
		t += 0.1
	assert(first == "A", "first raider is the plain guard, got " + first)
	assert(absf(t - SpawnDirector.FIRST_SPAWN) < 0.2, "first spawn at %0.1f s" % t)
	# Early game: only one raider out at once.
	assert(d.tick(0.1) == "", "no second raider while the first is alive early on")
	assert(d.max_alive() == 1)
	d.robot_gone()
	# Later: wider mix and more raiders.
	var late := SpawnDirector.new()
	late.start(3)
	late.time = 240.0
	assert(late.max_alive() >= 2)
	assert(late.gap() < SpawnDirector.GAP_START and late.gap() >= SpawnDirector.GAP_END)
	var kinds := {}
	for i in range(300):
		kinds[late.pick_kind()] = true
	assert(kinds.has("B") and kinds.has("C") and kinds.has("D"), "late mix includes every raider: %s" % kinds.keys())
	# The whole match ends on its own.
	var full := SpawnDirector.new()
	full.start(1)
	var spawns := 0
	for i in range(int(SpawnDirector.MATCH_SECONDS / 0.5) + 2):
		if full.tick(0.5) != "":
			spawns += 1
			full.robot_gone()
	assert(full.finished, "match finished")
	assert(spawns >= 20 and spawns <= 60, "spawned %d raiders over a match" % spawns)
	for k in ["A", "B", "C", "D"]:
		var s := SpawnDirector.robot_stats(k)
		assert(s.speed > 0.0 and s.mass > 0.0 and s.accel > 0.0 and s.gait != "")
	print("PASS: spawn director — first at %0.1f s, %d raiders over %0.0f s, mix A/B/C/D" % [t, spawns, SpawnDirector.MATCH_SECONDS])
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
