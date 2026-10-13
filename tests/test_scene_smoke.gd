extends SceneTree
## Instantiates the real gameplay classes headless (no XR, no rendering) and
## runs a scripted mini-match: room fallback, placement, spawn, gait, steal,
## rope, yank, dropped cell physics, grab, dock, crush, loss, replay.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	var head := XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0)
	head.rotation_degrees.x = -25.0
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
	director.build(head, hands)
	assert(director.phase == GameDirector.Phase.SCANNING)
	# Room data with a door and two walls → rifts mounted on them.
	var mounts := [
		{"origin": Vector3(0, 0, -2.5), "normal": Vector3(0, 0, 1), "width": 0.9, "height": 2.0, "kind": "door"},
		{"origin": Vector3(2.0, 0, 0), "normal": Vector3(-1, 0, 0), "width": 3.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(-2.0, 0, 0.5), "normal": Vector3(1, 0, 0), "width": 2.5, "height": 2.5, "kind": "wall"},
	]
	director.on_room_ready(mounts, 0.02, true)
	assert(director.phase == GameDirector.Phase.PLACING)
	assert(director.room_found and director.active_rifts().size() == 3)
	assert(director.rifts[0].global_position.distance_to(Vector3(0, 0.02, -2.5)) < 0.01, "door rift at the door")
	assert(director.rifts[0].global_basis.z.dot(Vector3(0, 0, 1)) > 0.99, "rift faces into the room")
	assert(director.rifts[0].spawn_outside().z > director.rifts[0].spawn_inside().z, "raider exits into the room")
	assert(director.station.placing)
	# Station follows the gaze on the floor, between 0.9 and 3 m.
	for i in range(30):
		await process_frame
	var feet := Vector3(0, 0.02, 0)
	var d := Vector2(director.station.global_position.x, director.station.global_position.z).length()
	assert(d >= 0.9 and d <= 3.0, "station hovers at %0.2f m" % d)
	assert(absf(director.station.global_position.y - 0.02) < 0.01, "station sits on the scanned floor")
	# A drops the station and starts the match.
	director.on_button(&"ax_button", 1)
	assert(director.phase == GameDirector.Phase.PLAYING and not director.station.placing)
	assert(director.station.docked_count() == 3)
	director.spawner.next_spawn = 0.0
	for i in range(int(GameDirector.START_DELAY * 90) + 5):
		await physics_frame
	assert(director.robots.size() == 1, "first raider spawned: %d" % director.robots.size())
	var robot: Robot = director.robots[0]
	assert(robot.kind == "A" and robot.state == Robot.State.EMERGE)
	assert(robot.home_rift == director.rifts[0], "came through the door")
	# It walks: joints move while it moves.
	var hip: Node3D = robot._joints["RIG_Hip_L"]
	var hip_rest := hip.rotation.x
	var moved := false
	for i in range(900):
		await physics_frame
		if robot.state == Robot.State.SEEK and absf(hip.rotation.x - hip_rest) > 0.05:
			moved = true
		if robot.state == Robot.State.FLEE:
			break
	assert(moved, "procedural gait drives the hip joint")
	assert(robot.cell != null, "raider stole a cell, state=%d" % robot.state)
	assert(director.station.docked_count() == 2)
	# Rope it from the right hand along the aim direction.
	var right := hands[1]
	_aim(right, robot.tether_anchor().global_position)
	var hit := right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin())
	assert(hit == robot, "tether found the raider")
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED, "tether attached")
	# Yank: far shorter rope than distance → full tension → drop + tumble.
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
	assert(robot.state == Robot.State.TUMBLE, "tumbled, state=%d" % robot.state)
	right.tether.release()
	var loose: PowerCell = null
	for cell in director.station.cells:
		if cell.state == PowerCell.State.LOOSE:
			loose = cell
	assert(loose != null and loose.get_parent() == director and not loose.freeze, "dropped cell is a live rigid body in the arena")
	for i in range(120):
		await physics_frame
	assert(loose.global_position.y < 0.3 and loose.global_position.y > -0.2, "cell landed on the floor slab at y=%0.2f" % loose.global_position.y)
	# Rope can fish the cell: fire at it, reel, auto-grab when close.
	_aim(right, loose.tether_anchor().global_position)
	var hit2 := right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin())
	assert(hit2 == loose, "rope targets a loose cell")
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED and loose.tethers.size() == 1)
	right.tether.release()
	# Hand grab: generous radius, then dock into the free socket.
	loose.global_position = right.hand_position() + Vector3(0.2, 0, 0)
	right._update_cell(0.016, director.station.cells, director.station, true)
	assert(right.held_cell == loose, "grip grabbed the loose cell within 30 cm")
	var free_socket := director.station.nearest_free_socket(director.station.global_position, 1.0)
	assert(free_socket >= 0)
	right.global_position += director.station.sockets[free_socket].global_position - right.hand_position()
	right.grip = 1.0
	right._update_cell(0.016, director.station.cells, director.station, true)
	assert(right.held_cell == null and director.station.docked_count() == 3, "cell docked back")
	assert(director.rescues == 1)
	# Crush: a roped raider within arm's reach + grip → shutdown.
	for i in range(300):
		await physics_frame
		if robot.state != Robot.State.TUMBLE:
			break
	_aim(right, robot.tether_anchor().global_position)
	assert(right.tether.fire(right.aim_direction(), director.targets(), right.aim_origin()) == robot)
	for i in range(30):
		right.tether.update(1.0 / 90.0, 0.0)
		await physics_frame
	assert(right.tether.state == Tether.State.ATTACHED)
	right.global_position.y = 1.0
	robot.global_position = right.hand_position() + Vector3(0.25, 0, 0)
	robot.position.y = 0.0
	right._try_crush()
	assert(robot.state == Robot.State.DOWN, "crushed raider shuts down")
	assert(director.captures == 1)
	# Losing: every cell lost → station dark; A after 1.5 s → placement again.
	for cell in director.station.cells:
		cell.mark_lost()
	director._check_end()
	assert(director.phase == GameDirector.Phase.ENDED and not director.station.powered)
	director._end_timer = 2.0
	director.on_button(&"ax_button", 1)
	assert(director.phase == GameDirector.Phase.PLACING and director.station.placing, "replay goes back to placement")
	director.on_button(&"ax_button", 1)
	assert(director.phase == GameDirector.Phase.PLAYING and director.station.docked_count() == 3, "second match starts with three cells")
	print("PASS: scene smoke — room mounts, placement, gait, steal, rope, yank, cell physics, grab, dock, crush, loss, replay")
	quit(0)


## Point the aim pose at a target (the gauntlet node doubles as its aim node here).
func _aim(hand: Gauntlet, point: Vector3) -> void:
	hand.global_basis = Basis.looking_at(point - hand.global_position, Vector3.UP)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 60.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
