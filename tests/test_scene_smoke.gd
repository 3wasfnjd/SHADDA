extends SceneTree
## Instantiates the real gameplay classes headless (no XR, no rendering) and
## runs a scripted mini-match: spawn, steal, rope, drop, dock, capture.
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
		var side := "left" if i == 0 else "right"
		var g := Gauntlet.create(i, load("res://assets/models/runtime/shadda_gauntlet_%s.glb" % side))
		g.position = Vector3(-0.25 if i == 0 else 0.25, 1.2, -0.4)
		root.add_child(g)
		hands.append(g)
	var director := GameDirector.new()
	root.add_child(director)
	director.build(head, hands, load("res://assets/ui/DejaVuSans.ttf"))
	assert(director.station.docked_count() == 3)
	assert(director.rifts.size() == 3)
	assert(absf(director.station.position.length() - GameDirector.STATION_DISTANCE) < 0.01)
	assert(director.station.position.z < 0.0 and director.station.position.x > 0.0, "station front-right of the player")
	for rift in director.rifts:
		assert(absf(rift.position.length() - GameDirector.RIFT_DISTANCE) < 0.01)
	# Manual floor correction moves the whole arena; raiders follow it.
	director.adjust_floor(1.0, 1.0)
	assert(director.floor_offset > 0.2 and is_equal_approx(director.position.y, director.floor_offset))
	director.adjust_floor(-1.0, 1.0)
	director.position.y = 0.0
	director.floor_offset = 0.0
	director.start_match()
	assert(director.phase == GameDirector.Phase.PLAYING)
	await process_frame
	await physics_frame
	assert(director.robots.size() == 1, "first raider spawned")
	var robot: Robot = director.robots[0]
	assert(robot.kind == "A" and robot.state == Robot.State.EMERGE)
	# Fast-forward the emerge and walk.
	for i in range(900):
		await physics_frame
		if robot.state == Robot.State.FLEE:
			break
	assert(robot.cell != null, "raider stole a cell, state=%d" % robot.state)
	assert(director.station.docked_count() == 2)
	# Rope it from the right hand: aim straight at the crown.
	var right := hands[1]
	_aim(right, robot)
	var to_robot := robot.tether_anchor().global_position - right.tether_origin.global_position
	assert(right.aim_direction().dot(to_robot.normalized()) > 0.97, "aim axis points at the raider: %s" % right.aim_direction().dot(to_robot.normalized()))
	var hit := right.tether.fire(right.aim_direction(), director.robots)
	assert(hit == robot, "tether found the raider")
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED, "tether attached")
	# Yank: a rope far shorter than the distance means full tension; the raider
	# drops the cell and is stunned, and the rope snaps off it.
	var flags := {"dropped": false}
	robot.cell_dropped.connect(func(_r, _c): flags["dropped"] = true)
	right.tether.rest_length = TetherMath.MIN_REST
	var away: Vector3 = robot.global_position - right.hand_position()
	away.y = 0.0
	robot.global_position += away.normalized() * 1.2
	for i in range(120):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
		if flags["dropped"]:
			break
	assert(flags["dropped"], "high tension forced the drop")
	assert(robot.state == Robot.State.STUN, "stunned, state=%d" % robot.state)
	assert(robot.tethers.is_empty(), "rope snapped off the raider")
	var loose: PowerCell = null
	for cell in director.station.cells:
		if cell.state == PowerCell.State.LOOSE:
			loose = cell
	assert(loose != null and loose.get_parent() == director, "dropped cell lives in the arena")
	# Player picks it up and docks it.
	right.held_cell = null
	loose.global_position = right.hand_position() - (loose.grab_position() - loose.global_position)
	right.grip = 0.0
	right._update_cell(0.016, director.station.cells, director.station)
	assert(right.held_cell == null, "no grab without grip")
	right.grip = 1.0
	right._update_cell(0.016, director.station.cells, director.station)
	assert(right.held_cell == loose, "grip grabbed the loose cell")
	var free_socket := director.station.nearest_free_socket(director.station.global_position, 1.0)
	assert(free_socket >= 0)
	right.global_position += director.station.sockets[free_socket].global_position - right.hand_position()
	right.grip = 1.0
	right._update_cell(0.016, director.station.cells, director.station)
	assert(right.held_cell == null and director.station.docked_count() == 3, "cell docked back")
	assert(director.score >= GameDirector.SCORE_RESCUE)
	# Capture: a roped raider inside the ring is defeated.
	for i in range(300):
		await physics_frame
		if robot.state != Robot.State.STUN:
			break
	_aim(right, robot)
	var hit2 := right.tether.fire(right.aim_direction(), director.robots)
	assert(hit2 == robot)
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED)
	robot.global_position = Vector3(0.2, 0, -0.2)
	robot.defeated.connect(func(_r): flags["captured"] = true)
	await physics_frame
	await physics_frame
	assert(flags.get("captured", false), "dragging a roped raider into the ring defeats it")
	assert(director.captures == 1 and director.score >= GameDirector.SCORE_CAPTURE + GameDirector.SCORE_RESCUE)
	# Losing: mark every cell lost.
	for cell in director.station.cells:
		cell.mark_lost()
	director._check_end()
	assert(director.phase == GameDirector.Phase.LOST)
	director._result_time = 2.0
	director.on_button(&"ax_button", 1)
	assert(director.phase == GameDirector.Phase.PLAYING and director.station.docked_count() == 3, "replay resets the match")
	print("PASS: scene smoke — spawn, steal, rope, drop, dock, capture, lose, replay")
	quit(0)

## Point the gauntlet's fingers (-Z of the hand node) at the raider's crown.
func _aim(hand: Gauntlet, robot: Robot) -> void:
	var to: Vector3 = robot.tether_anchor().global_position - hand.global_position
	hand.global_basis = Basis.looking_at(to, Vector3.UP)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
