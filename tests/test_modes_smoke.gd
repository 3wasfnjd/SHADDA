extends SceneTree
## Snakes, drones and sling: segments tear off on a yank, drones hover high,
## balls roll on the floor, get flung on rope release, and burst on a wall;
## a fast fist punches a drone; a dive bite stuns the hand.
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
	var mounts := [
		{"origin": Vector3(0, 0, -2.5), "normal": Vector3(0, 0, 1), "width": 3.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(0.5, 2.4, -0.5), "normal": Vector3.DOWN, "width": 3.0, "height": 0.0, "kind": "ceiling"},
	]
	director.on_room_ready(mounts, 0.0, true)
	assert(director.cracks[1].on_ceiling, "second crack sits on the ceiling")
	# Mode cycling with the stick shows a mascot and never floats mid-room.
	for i in range(5):
		await process_frame
	assert(director.mode == "sparks" and director._mascot != null and director._mascot.preview_only)
	director.cycle_mode(1.0, 0.1)
	assert(director.mode == "snakes")
	director.cycle_mode(1.0, 0.1)
	assert(director.mode == "snakes", "cooldown blocks a double step")
	director._mode_cooldown = 0.0
	director.cycle_mode(-1.0, 0.1)
	assert(director.mode == "sparks")
	director.set_mode("snakes")
	director.on_button(&"ax_button", 1)
	assert(director.phase == HuntDirector.Phase.PLAYING and director._mascot == null)
	var right := hands[1]
	# --- snake ---
	var snake := director._spawn("snake")
	snake.state = Spark.State.APPROACH
	for i in range(120):
		await physics_frame
	assert(snake.position.y < 0.2, "snake crawls on the floor, y=%0.2f" % snake.position.y)
	assert(snake._segments.size() == SparkMath.stats("snake").segments, "snake has a body")
	_aim(right, snake.global_position)
	assert(right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin()) == snake)
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	var before := snake.segments_left
	right.tether.rest_length = TetherMath.MIN_REST
	snake.global_position += (snake.global_position - right.hand_position()).normalized() * 1.5
	snake.position.y = snake.radius + 0.01
	for i in range(120):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
		if snake.segments_left < before:
			break
	assert(snake.segments_left == before - 3, "yank tore three segments off: %d → %d" % [before, snake.segments_left])
	right.tether.release()
	snake.crush()
	await physics_frame
	# --- drone + punch ---
	director.set_mode("drones")
	var drone := director._spawn("drone")
	drone.state = Spark.State.APPROACH
	for i in range(150):
		await physics_frame
	assert(drone.position.y > 0.9, "drone hovers high, y=%0.2f" % drone.position.y)
	assert(drone._rotors.size() == 4)
	right.global_position = drone.global_position + Vector3(-0.2, 0, 0)
	right.hand_velocity = Vector3(3.0, 0, 0)
	right.grip = 1.0
	right._try_punch(director.targets())
	assert(drone.state == Spark.State.DEAD, "a fast fist bursts the drone")
	# --- sling ---
	director.set_mode("sling")
	var ball := director._spawn("ball")
	ball.state = Spark.State.APPROACH
	for i in range(200):
		await physics_frame
	assert(absf(ball.position.y - (ball.radius + 0.01)) < 0.05, "ball rolls on the floor, y=%0.2f" % ball.position.y)
	right.global_position = Vector3(0.25, 1.2, -0.4)
	_aim(right, ball.global_position)
	assert(right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin()) == ball)
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	right.tether.rest_length = TetherMath.MIN_REST
	right.tether.tension = 0.8
	right.trigger = 1.0
	right._trigger_was_down = true
	right.update(1.0 / 90.0, 0.0, 0.0, director.targets(), true)
	assert(ball._flung > 0.0 and ball.velocity.length() > 3.0, "release flings the ball at %0.1f m/s" % ball.velocity.length())
	# --- bite stuns the hand ---
	right.bitten()
	right.update(0.016, 1.0, 0.0, director.targets(), true)
	assert(right._stunned > 0.0 and not right.tether.is_busy(), "bitten hand cannot fire")
	print("PASS: modes smoke — mascot, snakes (segments), drones (hover, punch), sling (roll, fling), bite")
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
