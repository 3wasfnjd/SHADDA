extends SceneTree
## Free flight (no room scan): plane parked on the floor ahead, flown by stick
## inputs in a wide open sky; sparring fighters fly in, evade and shoot for
## show; the plane cannot be hurt; chasing one down with the guns scores and
## a new one comes; slow flight sinks gently; a forced crash respawns.

var battle: Battle
var plane: PlayerPlane
var head: XRCamera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var arena := Node3D.new()
	get_root().add_child(arena)
	head = XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0)
	arena.add_child(head)
	var hud := Hud.new()
	arena.add_child(hud)
	battle = Battle.new()
	arena.add_child(battle)
	plane = PlayerPlane.new()
	battle.add_child(plane)
	battle.save_path = "user://saqr_free_test.json"
	battle.build(head, plane, hud)
	battle.on_room_ready({"floor_y": 0.0, "ceiling_y": 3.0, "walls": [], "openings": [], "surfaces": [], "blocks": [], "found": false, "free": true})
	assert(battle.free_flight and battle.phase == Battle.Phase.MENU)
	assert(plane.global_position.z < -1.0 and absf(plane.global_position.y - plane.gear_height) < 1e-3, "parked on the floor in front")
	battle.start_match()
	var goal := Vector3(0, 1.3, -2.5)
	for i in range(72 * 15):
		var inp := WarMath.autopilot(plane.flight, goal)
		battle.update_controls(1.0 / 72.0, head.global_position, Vector3.FORWARD, inp, 0.0, 0.0)
		await physics_frame
		if plane.airborne() and plane.global_position.distance_to(goal) < 0.4:
			goal = Vector3(randf_range(-2, 2), randf_range(0.8, 2.0), randf_range(-2.5, 1.5))
	assert(plane.airborne(), "flying")
	assert(not battle._waves_started, "no war waves in free flight")
	assert(battle.enemies.size() >= 1 and battle.enemies.all(func(e): return e.practice), "sparring fighters arrived")
	assert(plane.hp == WarMath.PLANE_HP, "nothing hurts the plane")
	# Chase one down with the guns.
	var score0 := battle.score
	var ok := false
	for i in range(72 * 40):
		var target = null
		for e in battle.enemies:
			if e.alive() and e.state == Enemy.State.ACTIVE:
				target = e
				break
		var g: Vector3 = target.hit_center() if target else Vector3(0, 1.4, -2)
		var inp := WarMath.autopilot(plane.flight, g)
		battle.update_controls(1.0 / 72.0, head.global_position, Vector3.FORWARD, inp, 1.0, 0.0)
		await physics_frame
		if battle.score > score0:
			ok = true
			break
	assert(ok, "shot down a sparring fighter")
	assert(plane.hp == WarMath.PLANE_HP)
	# Throttle closed in the air: it glides down gently, never drops hard.
	plane.flight = {"pos": Vector3(0, 2.0, -2), "basis": Basis.looking_at(Vector3.FORWARD, Vector3.UP), "speed": 0.9, "sink": 0.0, "ground": false}
	var worst := 0.0
	var prev_y := 2.0
	for i in range(72 * 4):
		battle.update_controls(1.0 / 72.0, head.global_position, Vector3.FORWARD, {"throttle": 0.0, "pitch": 0.0, "roll": 0.0, "yaw": 0.0}, 0.0, 0.0)
		await physics_frame
		worst = maxf(worst, (prev_y - plane.global_position.y) * 72.0)
		prev_y = plane.global_position.y
	assert(worst < 0.5, "gentle descent (%f m/s)" % worst)
	# Forced crash → fresh plane on the floor.
	plane.invincible = false
	plane.take_hit(999.0)
	var back := false
	for i in range(72 * 8):
		battle.update_controls(1.0 / 72.0, head.global_position, Vector3.FORWARD, {}, 0.0, 0.0)
		await physics_frame
		if plane.on_ground() and plane.hp == WarMath.PLANE_HP:
			back = true
			break
	assert(back and battle.phase == Battle.Phase.PLAYING, "fresh plane after a crash")
	plane.invincible = true
	print("PASS: free flight — wide sky, hand flown, sparring fighters chased and shot down, invincible, gentle glide, respawn")
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 240.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
