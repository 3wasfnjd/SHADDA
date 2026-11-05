extends SceneTree
## Headless room war through the real classes, the plane flown with stick
## inputs (an autopilot stands in for the player's hands): room with a window,
## a door and a table → plane parked on the floor → takeoff roll → flight →
## landing, repair and second takeoff → guns pop a balloon → rocket lock kills a fighter that flew in the
## window → cargo drop puts flak guns down → bomb kills one → tank drives in
## the door → barrel roll → shot down → crash → results → replay → all five
## waves with the bomber → save.

var arena: Node3D
var head: XRCamera3D
var plane: PlayerPlane
var hud: Hud
var battle: Battle
var aim_at := Vector3(0, 1.3, -1.0)
var tr := 0.0
var gr := 0.0
var manual = null          # stick inputs override for a step
var DT := 1.0 / 72.0


func _initialize() -> void:
	_run()


func _frame() -> void:
	var o := head.global_position + Vector3(0.15, -0.3, 0)
	var inp: Dictionary = manual if manual != null else WarMath.autopilot(plane.flight, WarMath.clamp_into(aim_at, battle.box, 0.6, 0.55))
	battle.update_controls(DT, o, (aim_at - o).normalized(), inp, tr, gr)
	await physics_frame


func _until(cond: Callable, limit: int) -> bool:
	for i in range(limit):
		if cond.call():
			return true
		await _frame()
	return cond.call()


func _gone(id: int) -> bool:
	var o = instance_from_id(id)
	return o == null or not (o as Enemy).alive()


func _run() -> void:
	await process_frame
	arena = Node3D.new()
	get_root().add_child(arena)
	head = XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0.6)
	arena.add_child(head)
	head.current = true
	var left := Node3D.new()
	arena.add_child(left)
	hud = Hud.new()
	left.add_child(hud)
	battle = Battle.new()
	arena.add_child(battle)
	plane = PlayerPlane.new()
	battle.add_child(plane)
	battle.save_path = "user://saqr_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(battle.save_path))
	battle.build(head, plane, hud)
	var room_desc: Dictionary = load("res://systems/app_bootstrap.gd").PREVIEW_ROOM.duplicate(true)
	battle.on_room_ready(room_desc)
	assert(battle.phase == Battle.Phase.MENU)
	assert(battle.room.openings.size() == 2 and battle.room.surfaces.size() == 1)
	assert(battle.room.get_child_count() > 6, "occluders built")
	assert(absf(battle.room.surface_below(Vector3(1.2, 2.0, -1.3)) - 0.74) < 1e-4, "table top")
	assert(plane.state == PlayerPlane.State.PARKED and absf(plane.global_position.y - plane.gear_height) < 1e-3, "parked on the floor")

	print("STAGE: Take off.")
	battle.auto_spawn = false
	battle.start_match()
	assert(plane.state == PlayerPlane.State.FLYING and plane.flight.ground)
	# Engine idles: with the throttle closed it stays put.
	manual = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0}
	await _until(func(): return false, 72)
	assert(plane.flight.speed < 0.01 and plane.on_ground(), "stays parked with the throttle closed")
	manual = null
	aim_at = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return plane.airborne(), 72 * 6), "rolled and lifted off")
	assert(battle._waves_started and battle.wave == 0)
	battle._queue.clear()
	print("STAGE: Fly to a spot by hand.")
	var target := Vector3(-0.8, 1.4, -1.4)
	aim_at = target
	var closest := INF
	for i in range(72 * 8):
		await _frame()
		closest = minf(closest, plane.global_position.distance_to(target))
		if closest < 0.3:
			break
	assert(closest < 0.3, "reached the spot (%f)" % closest)
	assert(plane.hp > 60.0, "no bad crashes on the way (%f)" % plane.hp)
	print("STAGE: Land on the floor, repair, take off again.")
	var pitch_down := Basis.looking_at(Vector3(0, -0.11, -1).normalized(), Vector3.UP)
	plane.flight = {"pos": Vector3(0.2, 0.3, 0.6), "basis": pitch_down, "speed": 0.75, "sink": 0.0, "ground": false}
	manual = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.35}
	assert(await _until(func(): return plane.on_ground(), 72 * 4), "touched down")
	plane.hp = 60.0
	manual = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0, "brake": true}
	assert(await _until(func(): return plane.flight.speed < 0.01, 72 * 4), "braked to a stop")
	var hp_landed := plane.hp
	await _until(func(): return false, 72)
	assert(plane.hp > hp_landed + 3.0 and plane.state == PlayerPlane.State.FLYING, "repairs while parked")
	manual = null
	aim_at = Vector3(0.2, 1.4, -1.2)
	assert(await _until(func(): return plane.airborne(), 72 * 6), "second takeoff")
	print("STAGE: A hard touchdown hurts.")
	var hp_before := plane.hp
	plane.flight = {"pos": Vector3(0.0, 0.5, -0.5), "basis": Basis.looking_at(Vector3(0, -0.8, -1).normalized(), Vector3.UP), "speed": 1.3, "sink": 0.0, "ground": false}
	manual = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 1.0}
	assert(await _until(func(): return plane.hp < hp_before, 72 * 3), "hard landing damages")
	manual = null
	plane.hp = WarMath.PLANE_HP
	aim_at = Vector3(0.0, 1.4, -1.0)
	await _until(func(): return plane.airborne() and plane.global_position.y > 0.9, 72 * 8)

	print("STAGE: Guns pop a balloon.")
	# Guns pop a balloon.
	var b := battle.spawn("balloon")
	b.set_meta("height", 1.3)
	b.rise_from(Vector3(-0.3, 0.0, -0.9))
	var bid := b.get_instance_id()
	assert(await _until(func(): return b.state == Enemy.State.ACTIVE, 72 * 4))
	# Line up a pass from 1.6 m out, then hold the trigger.
	var bc := b.hit_center()
	plane.flight = {"pos": bc + Vector3(0, 0, 1.6), "basis": Basis.looking_at(Vector3.FORWARD, Vector3.UP), "speed": 1.0, "sink": 0.0, "ground": false}
	tr = 1.0
	assert(await _until(func():
		if not _gone(bid):
			aim_at = (instance_from_id(bid) as Enemy).hit_center()
		return _gone(bid), 72 * 60), "guns popped the balloon")
	tr = 0.0
	assert(battle.score >= 50)

	print("STAGE: A fighter flies in through the window; rocket lock kills it.")
	# A fighter flies in through the window; rocket lock kills it.
	var f := battle.spawn("fighter")
	var fid := f.get_instance_id()
	var win: Dictionary = f.entry
	assert((f.global_position - (win.center as Vector3)).dot(win.normal) < 0.0, "starts behind its opening")
	assert(await _until(func(): return f.state == Enemy.State.ACTIVE, 72 * 4), "flew in")
	var rockets0 := plane.rockets
	gr = 1.0
	assert(await _until(func():
		if not _gone(fid):
			aim_at = (instance_from_id(fid) as Enemy).hit_center()
		return plane.locks.size() >= 1, 72 * 20), "locked the fighter")
	gr = 0.0
	plane.hp = WarMath.PLANE_HP
	assert(await _until(func():
		plane.hp = WarMath.PLANE_HP
		if not _gone(fid):
			aim_at = (instance_from_id(fid) as Enemy).hit_center()
			if plane.locks.size() >= 1:
				gr = 0.0
			elif plane._salvo.is_empty() and plane.rockets > 0:
				gr = 1.0
		return _gone(fid), 72 * 30), "rockets killed the fighter")
	gr = 0.0
	assert(plane.rockets < rockets0 or plane.rockets == WarMath.ROCKETS)

	print("STAGE: Cargo drop → flak guns on the table/floor.")
	# Cargo drop → flak guns on the table/floor.
	var t := battle.spawn("transport")
	assert(await _until(func():
		plane.hp = WarMath.PLANE_HP
		return battle.enemies.filter(func(e): return e.kind == "aa").size() >= 2, 72 * 40), "two flak guns landed")
	var aa: Enemy = battle.enemies.filter(func(e): return e.kind == "aa")[0]
	var ground := battle.room.surface_below(aa.global_position + Vector3(0, 0.1, 0))
	assert(absf(aa.global_position.y - ground) < 1e-3, "flak gun sits on a real surface")
	print("STAGE: Bomb it: fly level so the bomb lands on it.")
	# Bomb it: fly level so the bomb lands on it.
	var aid := aa.get_instance_id()
	var h := 0.75
	var fwd := Vector3(0, 0, -1)
	var fall := sqrt(2.0 * h / (WarMath.GRAVITY * 0.85))
	var spd := 1.0
	plane.flight = {"pos": aa.global_position + Vector3(0, h, 0) - fwd * spd * fall, "basis": Basis.looking_at(fwd, Vector3.UP), "speed": spd, "sink": 0.0, "ground": false}
	manual = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.9}
	await _frame()
	assert(plane.drop_bomb())
	assert(await _until(func(): return _gone(aid), 72 * 3), "bomb killed the flak gun")
	manual = null
	aim_at = Vector3(0.0, 1.4, -1.0)
	await _until(func(): return not is_instance_valid(t) or t.state != Enemy.State.ACTIVE, 72 * 20)

	print("STAGE: A tank drives in through the door onto the floor.")
	# A tank drives in through the door onto the floor.
	var tank := battle.spawn("tank")
	assert(await _until(func():
		plane.hp = WarMath.PLANE_HP
		return tank.state == Enemy.State.ACTIVE, 72 * 8), "tank came in: state=%d pos=%s" % [tank.state, tank.global_position])
	assert(absf(tank.global_position.y) < 1e-3 and WarMath.inside(tank.global_position, battle.box, 0.01), "tank on the floor in the room: %s" % [tank.global_position])

	print("STAGE: Barrel roll dodges most of a hit.")
	# Barrel roll dodges most of a hit.
	assert(plane.barrel_roll())
	var hp0 := plane.hp
	plane.take_hit(10.0)
	assert(hp0 - plane.hp < 3.0, "roll soaked the hit")

	print("STAGE: Shot down → crash → results.")
	# Shot down → crash → results.
	plane.take_hit(999.0)
	assert(plane.state == PlayerPlane.State.CRASHING)
	assert(await _until(func(): return battle.phase == Battle.Phase.RESULTS, 72 * 8), "results after the crash")
	assert(plane.state == PlayerPlane.State.WRECKED and not battle.won)
	battle._phase_t = 2.0
	battle.on_button(&"ax_button", 1)
	assert(battle.phase == Battle.Phase.PLAYING and plane.on_ground(), "replay from the floor")
	aim_at = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return plane.airborne(), 72 * 6))

	print("STAGE: Full war.")
	# Full war.
	aim_at = Vector3(0.0, 1.4, -1.0)
	battle.auto_spawn = true
	var seen := {}
	var ok := await _until(func():
		plane.hp = WarMath.PLANE_HP
		for e in battle.enemies.duplicate():
			seen[e.kind] = true
			if e.state == Enemy.State.ACTIVE:
				battle._kill(e, "gun")
		for c in battle.crates.duplicate():
			if (c.node as Node3D).global_position.y < 2.0:
				(c.node as Node3D).global_position.y = 0.0
		return battle.phase == Battle.Phase.RESULTS, 72 * 240)
	assert(ok, "war finished at wave %d" % battle.wave)
	assert(battle.won and seen.has("bomber") and seen.has("transport") and seen.has("tank") and seen.has("balloon"), "all kinds %s" % [seen])
	assert(int(battle.save.best) == battle.score and battle.score > 0)
	print("PASS: room war — parked, throttle, takeoff roll, hand flight, landing + repair + second takeoff, hard landing, guns, rocket lock, cargo drop on real surfaces, bomb, tank through the door, roll, crash, replay, 5 waves + bomber, save (%d)" % battle.score)
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 300.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
