extends SceneTree
var failures: Array[String] = []
var world: Node3D
var game: ShaddaArena
var cfg: Dictionary
var checks: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")
func steps(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func make_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
	world = Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 6
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5,.2,5)
	shape.shape = box
	shape.position.y = -.1
	floor.add_child(shape)
	world.add_child(floor)
	game = ShaddaArena.new()
	world.add_child(game)
	game.setup(cfg,Transform3D.IDENTITY)
	await steps(2)
func run() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/playtest.json"))
	for start in range(5):
		for finish in range(5):
			var state := ShaddaBatteryState.new()
			state.state = start as ShaddaBatteryState.State
			var allowed: bool = finish in ShaddaBatteryState.ALLOWED[start]
			check(state.transition(finish as ShaddaBatteryState.State,1,2) == allowed,"transition %d -> %d"%[start,finish])
	var state := ShaddaBatteryState.new()
	state.reset(1)
	check(not state.transition(ShaddaBatteryState.State.LOST),"undocking is never permanent loss")
	check(not state.transition(ShaddaBatteryState.State.PLAYER),"held state requires owner")
	check(ShaddaTether.spring_force(.4,.5,10,80,11,65)==0,"slack cannot push")
	check(ShaddaTether.spring_force(9,.5,100,80,11,65)==65,"spring force capped")
	await make_world()
	game.enemy.mode = ShaddaThief.Mode.DISABLED
	game.enemy.freeze = true
	var b := game.batteries[0]
	check(game.batteries.size()==3 and game.counts()==Vector2i(3,0),"three unique docked batteries")
	b.state.transition(ShaddaBatteryState.State.GROUND)
	b.freeze = false
	b.global_position = Vector3(-.5,.9,0)
	var min_y := 99.0
	var max_speed := 0.0
	for i in range(540):
		await steps(1)
		min_y = minf(min_y,b.global_position.y)
		max_speed = maxf(max_speed,b.linear_velocity.length())
	check(min_y > .022,"battery does not cross floor: %.3f"%min_y)
	check(max_speed <= 3.15,"battery speed limit: %.3f"%max_speed)
	check(b.linear_velocity.length() < .15,"battery settles after fall")
	var anchors: Array[Node3D] = []
	for i in range(2):
		var anchor := Node3D.new()
		world.add_child(anchor)
		anchor.position = Vector3(-.3 if i==0 else .3,1.1,1.0)
		anchors.append(anchor)
		var cell := game.batteries[i]
		check(game.grab(i,cell,cell.global_position,anchor),"independent hand %d grab"%i)
	await steps(45)
	check(game.batteries[1].state.state==ShaddaBatteryState.State.PLAYER,"pickup does not instantly redock")
	game.release_hand(0)
	check(game.tethers[1].active,"left release preserves right tether")
	game.tethers[1].reel = 1.0
	await steps(180)
	check(game.batteries[1].global_position.distance_to(anchors[1].global_position)<1.0,"reel actually pulls body")
	anchors[1].position.x += .6
	await steps(3)
	check(not game.tethers[1].active,"tracking jump releases without impulse")
	game.release_hand(1)
	# Return a genuinely stolen cell; no copy is ever spawned.
	b.state.state = ShaddaBatteryState.State.GROUND
	b.global_transform = Transform3D(Basis.IDENTITY,Vector3(-.45,.35,.30))
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	check(b.stolen(),"robot owns stolen battery")
	check(game.grab(0,b,b.global_position,anchors[0]),"player can contest robot grip")
	game.tethers[0].rest_length = .1
	await steps(40)
	check(b.state.state==ShaddaBatteryState.State.PLAYER,"physical tension frees stolen cell")
	check(game.return_to_station(0),"explicit station tether accepted")
	await steps(1080)
	check(b.state.state==ShaddaBatteryState.State.DOCKED,"return reaches real socket; state=%d pos=%s"%[b.state.state,b.position])
	check(game.rescues==1,"rescue counted exactly once")
	check(game.batteries.size()==3,"no duplicated cells after rescue")
	game.safe_resume()
	check(game.batteries[1].linear_velocity==Vector3.ZERO,"resume clears residual velocities")
	# A real obstacle must break a tether instead of pulling through it.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 6
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.1,2,2)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(.6,.8,0)
	var anchor := Node3D.new()
	world.add_child(anchor)
	anchor.position = Vector3(.9,.4,0)
	var rope := ShaddaTether.new()
	world.add_child(rope)
	rope.attach(b,b.global_position,anchor,cfg)
	await steps(40)
	check(not rope.active,"confirmed wall interrupts tether")
	await make_world()
	var peak_enemy_speed := 0.0
	for i in range(11000):
		await steps(1)
		peak_enemy_speed = maxf(peak_enemy_speed,game.enemy.linear_velocity.length())
		if i%1800==0:
			print("ROUND: t=",game.elapsed," steals=",game.enemy.steal_count," counts=",game.counts()," pos=",game.enemy.position)
		if game.finished:
			break
	check(game.enemy.steal_count>=1,"autonomous enemy really steals")
	check(game.finished,"no-player round has bounded end")
	check(game.counts().y>=1,"enemy can escape with a battery")
	check(peak_enemy_speed<=2.35,"enemy speed bounded")
	var report := {"checks":checks,"failures":failures,"battery_floor_min_y":min_y,"battery_peak_speed":max_speed,"enemy_peak_speed":peak_enemy_speed,"no_player_steals":game.enemy.steal_count,"no_player_lost":game.counts().y,"no_player_elapsed":game.elapsed,"quest_tested":false}
	DirAccess.make_dir_recursive_absolute("res://build")
	var file := FileAccess.open("res://build/gameplay-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
