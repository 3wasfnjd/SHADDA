extends SceneTree
## Headless mini-match through the real classes: room mounts, gaze placement,
## spawn, approach, drain, rope, yank (shard drop), crush, splitter, loss, replay.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	var head := XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0)
	head.rotation_degrees.x = -30.0
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
	assert(director.phase == HuntDirector.Phase.SCANNING)
	var mounts := [
		{"origin": Vector3(0, 0, -2.5), "normal": Vector3(0, 0, 1), "width": 0.9, "height": 2.0, "kind": "door"},
		{"origin": Vector3(2.0, 0, 0), "normal": Vector3(-1, 0, 0), "width": 3.0, "height": 2.5, "kind": "wall"},
	]
	director.on_room_ready(mounts, 0.02, true)
	assert(director.phase == HuntDirector.Phase.MENU and director.active_cracks().size() == 2)
	director.on_button(&"ax_button", 1)
	assert(director.phase == HuntDirector.Phase.PLACING)
	assert(director.cracks[0].spawn_point().z > -2.5, "crack spawns on the room side of the door")
	for i in range(30):
		await process_frame
	var d := Vector2(director.gem.global_position.x, director.gem.global_position.z).length()
	assert(d >= 1.0 and d <= 3.0, "gem hovers at %0.2f m" % d)
	director._phase_time = 1.0
	director.on_button(&"ax_button", 1)
	assert(director.phase == HuntDirector.Phase.PLAYING and not director.gem.placing)
	assert(director.cracks[0].is_open(), "wave one opened a breach")
	director._next_spawn = 0.0
	await process_frame
	await process_frame
	director.auto_spawn = false
	assert(director.sparks.size() == 1, "first spark spawned: %d" % director.sparks.size())
	var spark: Spark = director.sparks[0]
	assert(spark.kind == "ember")
	# Flies to the gem and starts draining.
	for i in range(900):
		await physics_frame
		if spark.state == Spark.State.DRAIN:
			break
	assert(spark.state == Spark.State.DRAIN, "spark reached the gem, state=%d" % spark.state)
	var e0 := director.gem.energy
	for i in range(90):
		await physics_frame
	assert(director.gem.energy < e0, "draining lowers energy")
	# Rope it.
	var right := hands[1]
	_aim(right, spark.global_position)
	assert(right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin()) == spark, "rope found the spark")
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED)
	# Let it finish draining and grab a shard, then yank → shard dropped, stunned.
	for i in range(900):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
		if spark.has_shard:
			break
	assert(spark.has_shard, "spark took a shard")
	var flags := {"dropped": false}
	spark.shard_dropped.connect(func(_s, _p): flags["dropped"] = true)
	right.tether.rest_length = TetherMath.MIN_REST
	var away: Vector3 = spark.global_position - right.hand_position()
	spark.global_position += away.normalized() * 1.5
	for i in range(120):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
		if flags["dropped"]:
			break
	assert(flags["dropped"] and not spark.has_shard, "yank made it drop the shard")
	assert(spark.state == Spark.State.STUN)
	# Crush within reach.
	spark.global_position = right.hand_position() + Vector3(0.2, 0, 0)
	right._try_crush()
	assert(spark.state == Spark.State.DEAD, "crushed")
	await physics_frame
	assert(director.kills == 1 and director.sparks.is_empty())
	assert(director.score > 0, "crushing scored points")
	# Splitter yank → two motes.
	var splitter := director._spawn("splitter")
	splitter.state = Spark.State.APPROACH
	_aim(right, splitter.global_position)
	assert(right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin()) == splitter)
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	right.tether.rest_length = TetherMath.MIN_REST
	splitter.global_position += (splitter.global_position - right.hand_position()).normalized() * 1.5
	for i in range(120):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
		if splitter.state == Spark.State.DEAD:
			break
	await physics_frame
	var motes := 0
	for s in director.sparks:
		if is_instance_valid(s) and s.kind == "mote":
			motes += 1
	assert(motes == 2, "splitter split into two motes, got %d" % motes)
	# Loss and replay.
	director.gem.energy = 0.0
	director._check_end()
	assert(director.phase == HuntDirector.Phase.RESULTS and not director.gem.alive and director.stars_won == 0)
	director._results_reveal = 2.0
	director.on_button(&"ax_button", 1)
	assert(director.phase == HuntDirector.Phase.PLACING and director.gem.placing and director.sparks.is_empty())
	print("PASS: hunt smoke — mounts, placement, spawn, drain, rope, yank, crush, split, loss, results, replay")
	quit(0)


func _aim(hand: Gauntlet, point: Vector3) -> void:
	hand.global_basis = Basis.looking_at(point - hand.global_position, Vector3.UP)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 60.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
