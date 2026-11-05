extends SceneTree
## Free flight (no room scan): plane parked on the floor ahead, flown by stick
## inputs, no enemies ever arrive, and a crash puts a fresh plane back on the floor.

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
	assert(battle.enemies.is_empty() and not battle._waves_started, "no enemies in free flight")
	plane.take_hit(999.0)
	var back := false
	for i in range(72 * 8):
		battle.update_controls(1.0 / 72.0, head.global_position, Vector3.FORWARD, {}, 0.0, 0.0)
		await physics_frame
		if plane.on_ground() and plane.hp == WarMath.PLANE_HP:
			back = true
			break
	assert(back and battle.phase == Battle.Phase.PLAYING, "fresh plane after a crash")
	print("PASS: free flight — parked ahead, hand flown 15 s, no enemies, respawn after a crash")
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 120.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
