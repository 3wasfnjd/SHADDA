extends SceneTree
## Full match at fast-forward: menu → placing → five waves (breaches open one
## by one) → crowned boss with hp → win → results with stars and a new best.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	var head := XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0)
	root.add_child(head)
	var hands: Array[Gauntlet] = []
	for i in range(2):
		var g := Gauntlet.create(i)
		g.position = Vector3(-0.25 if i == 0 else 0.25, 1.2, -0.4)
		root.add_child(g)
		hands.append(g)
	var director := HuntDirector.new()
	root.add_child(director)
	director.build(head, hands)
	director.save.path = "user://sharara_flow_test.json"
	director.save.data = {}
	var mounts := [
		{"origin": Vector3(0, 0, -2.8), "normal": Vector3(0, 0, 1), "width": 3.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(2.2, 0, -0.5), "normal": Vector3(-1, 0, 0), "width": 3.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(-0.8, 2.5, -1.4), "normal": Vector3.DOWN, "width": 2.0, "height": 0.0, "kind": "ceiling"},
		{"origin": Vector3(0, 0, 0.9), "normal": Vector3(0, 0, 1), "width": 0.9, "height": 2.0, "kind": "door"},
	]
	director.on_room_ready(mounts, 0.0, true)
	assert(director.phase == HuntDirector.Phase.MENU)
	assert(director.active_cracks().size() == 4)
	for c in director.cracks:
		assert(not c.is_open(), "no breach before the match")
	# Menu: aim at the play button and pull the trigger.
	for i in range(3):
		await process_frame
	var from := head.global_position
	var to_play: Vector3 = director._play_button.global_position - from
	director.aim_hover(1, from, to_play.normalized())
	assert(director._hover_index[1] == 100, "aim hovers the play button")
	assert(director.aim_select(from, to_play.normalized()))
	assert(director.phase == HuntDirector.Phase.PLACING)
	director._phase_time = 1.0
	assert(director.aim_select(from, Vector3.FORWARD), "trigger drops the gem")
	assert(director.phase == HuntDirector.Phase.PLAYING and director.wave == 0)
	var open_count := func() -> int:
		var n := 0
		for c in director.cracks:
			if c.is_open():
				n += 1
		return n
	assert(open_count.call() == 1, "wave one opens one breach")
	var seen_waves := {}
	var boss_seen := false
	var boss_hits := 0
	for frame in range(6000):
		await process_frame
		if director.phase != HuntDirector.Phase.PLAYING:
			break
		seen_waves[director.wave] = open_count.call()
		director._next_spawn = 0.0
		if director._wave_break > 0.0:
			director._wave_break = SparkMath.WAVE_BREAK
		director.gem.energy = 1.0
		for s in director.sparks.duplicate():
			if not is_instance_valid(s) or s.state == Spark.State.DEAD or s.state == Spark.State.EMERGE:
				continue
			if s.is_boss:
				boss_seen = true
				assert(s.radius > SparkMath.stats(s.kind).radius * 2.0, "boss is big")
				s.hit("catch")
				boss_hits += 1
			else:
				s.hit("crush")
	assert(director.phase == HuntDirector.Phase.RESULTS, "match finished, phase=%d wave=%d" % [director.phase, director.wave])
	assert(director.survived and director.stars_won == 3)
	assert(seen_waves.size() == 5, "played all five waves")
	assert(seen_waves[0] == 1 and seen_waves[1] == 2 and seen_waves[2] == 3 and seen_waves[3] == 4, "breaches open one more per wave: %s" % str(seen_waves))
	assert(boss_seen and boss_hits >= SparkMath.BOSS_HP, "boss took %d hits" % boss_hits)
	assert(director.score > 2500 and director.new_best, "score %d" % director.score)
	assert(director.save.best(director.mode) == director.score)
	for c in director.cracks:
		assert(c.mode == Crack.Mode.CLOSING or not c.is_open(), "breaches close after the match")
	# Results: buttons appear, B goes home, the menu shows the new best.
	director._results_reveal = 2.0
	await process_frame
	assert(director._retry_button.visible and director._home_button.visible)
	director.on_button(&"by_button", 0)
	assert(director.phase == HuntDirector.Phase.MENU)
	assert(director._mascot_best[0].text == str(director.score))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(director.save.path))
	print("PASS: match flow — menu, placing, 5 waves, breaches 1→4, boss %d hp, win, 3 stars, best %d, home" % [SparkMath.BOSS_HP, director.score])
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 120.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
