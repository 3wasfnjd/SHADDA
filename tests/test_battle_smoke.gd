extends SceneTree
## Headless match through the real classes (no headset): room → bays on the
## walls → menu → cannon kills a wall target → missile lock kills a drone →
## bomb kills a tank → flares lure an enemy missile → pellets hurt the jet →
## laser heats up → jet destroyed → results → replay → full five-wave clear
## with the boss → save.

var arena: Node3D
var head: XRCamera3D
var jet: PlayerJet
var hud: WristHud
var director: BattleDirector
var trig_r := 0.0
var grip_r := 0.0
var trig_l := 0.0
var aim_from := Vector3(0.15, 1.35, -0.2)
var aim_at := Vector3(0, 1.4, -2)


func _initialize() -> void:
	_run()


func _frame() -> void:
	var dir := (aim_at - aim_from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK
	jet.fly(1.0 / 90.0, Transform3D(Basis.looking_at(dir, up), aim_from))
	director.update_controls(1.0 / 90.0, trig_r, grip_r, trig_l)
	await physics_frame


func _frames(n: int) -> void:
	for i in range(n):
		await _frame()


func _until(cond: Callable, limit: int) -> bool:
	for i in range(limit):
		if cond.call():
			return true
		await _frame()
	return cond.call()


func _gone(id: int) -> bool:
	var o = instance_from_id(id)
	return o == null or not (o as Enemy).alive()


func _point_at(e: Enemy) -> void:
	aim_at = e.hit_center()


func _run() -> void:
	await process_frame
	arena = Node3D.new()
	get_root().add_child(arena)
	head = XRCamera3D.new()
	head.position = Vector3(0, 1.6, 0)
	arena.add_child(head)
	head.current = true
	var left := Node3D.new()
	arena.add_child(left)
	hud = WristHud.new()
	left.add_child(hud)
	director = BattleDirector.new()
	arena.add_child(director)
	jet = PlayerJet.new()
	director.add_child(jet)
	director.build(head, jet, hud)
	director.save.path = "user://saqr_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(director.save.path))
	director.save.data = {}
	assert(director.phase == BattleDirector.Phase.SCANNING)
	var mounts := [
		{"origin": Vector3(0, 0, -2.5), "normal": Vector3(0, 0, 1), "width": 3.6, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(2.0, 0, -0.5), "normal": Vector3(-1, 0, 0), "width": 4.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(-2.0, 0, -0.5), "normal": Vector3(1, 0, 0), "width": 4.0, "height": 2.5, "kind": "wall"},
		{"origin": Vector3(0, 0, 1.5), "normal": Vector3(0, 0, -1), "width": 3.6, "height": 2.5, "kind": "door"},
	]
	director.on_room_ready(mounts, 0.0, true)
	assert(director.phase == BattleDirector.Phase.MENU)
	assert(director.hangars.size() == 3 and director.bays.size() == 2, "bays %d/%d" % [director.hangars.size(), director.bays.size()])
	for h in director.hangars:
		assert(absf(h.global_position.y - 1.3) < 1e-3, "air bay at chest height")
		var m: Dictionary = h.get_meta("mount")
		var off: Vector3 = h.global_position - m.origin
		assert(absf(off.dot(m.normal)) < 1e-3, "air bay flush on its wall")
	for b in director.bays:
		assert(absf(b.global_position.y - b.height * 0.5) < 1e-3, "ground bay on the floor")
	assert(director.use_box_walls, "no physics room here, so the box stands in for walls")
	await _frames(5)
	assert(jet.global_position.distance_to(aim_from + (aim_at - aim_from).normalized() * CombatMath.JET_LEAD) < 0.02, "jet flies a hand-length ahead")

	# Menu: aim at ▶ and pull the trigger.
	director.auto_spawn = false
	aim_at = director._menu_root.global_position
	await _frames(70)
	trig_r = 1.0
	await _frame()
	trig_r = 0.0
	await _frame()
	assert(director.phase == BattleDirector.Phase.PLAYING, "▶ pressed by aiming the jet")
	assert(director.wave == 0 and director._queue.size() == 8)
	director._queue.clear()

	# 1) Cannon vs a wall target.
	var t := director.spawn("target")
	var m0: Dictionary = mounts[0]
	assert(t.global_position.y > 0.9 and t.global_position.y < 1.9)
	assert(await _until(func(): return t.state == Enemy.State.ACTIVE, 90))
	_point_at(t)
	await _frames(20)
	trig_r = 1.0
	var tid := t.get_instance_id()
	assert(await _until(func(): return _gone(tid), 120), "cannon killed the target")
	trig_r = 0.0
	assert(director.score >= 50, "score %d" % director.score)
	await _frames(40)

	# 2) Missile lock vs a drone.
	var d := director.spawn("drone")
	assert(await _until(func(): return d.state == Enemy.State.ACTIVE, 200), "drone left its bay")
	assert(CombatMath.inside(d.global_position, director.box, 0.01), "drone inside the room")
	var stock := jet.missiles
	_point_at(d)
	grip_r = 1.0
	assert(await _until(func():
		_point_at(d)
		return jet.locks.size() == 1, 120), "locked")
	grip_r = 0.0
	await _frame()
	var did := d.get_instance_id()
	assert(await _until(func(): return _gone(did), 400), "missile killed the drone")
	assert(jet.missiles == stock - 1)

	# 3) Bomb vs a tank on the floor.
	var tk := director.spawn("tank")
	assert(await _until(func(): return tk.state == Enemy.State.ACTIVE, 300), "tank rolled out")
	assert(absf(tk.global_position.y) < 1e-3, "tank on the floor")
	await _frames(150)
	assert(director.has_ground_units())
	aim_from = tk.global_position + Vector3(0, 0.9, 0.3) - Vector3(0, 0, CombatMath.JET_LEAD)
	aim_at = aim_from + Vector3(0, 0, -1)
	await _frames(40)
	jet.velocity = Vector3.ZERO
	var p := CombatMath.bomb_impact(jet.global_position, jet.forward() * 0.5, 0.0)
	aim_from += Vector3(tk.global_position.x - p.x, 0, tk.global_position.z - p.z)
	aim_at = aim_from + Vector3(0, 0, -1)
	await _frames(60)
	var hp0 := tk.hp
	assert(jet.drop_bomb())
	var tkid := tk.get_instance_id()
	assert(await _until(func(): return _gone(tkid), 120), "bomb killed the tank")
	aim_from = Vector3(0.15, 1.35, -0.2)
	aim_at = Vector3(0, 1.4, -2)
	await _frames(30)

	# 4) Flares lure an enemy missile.
	var armor0 := jet.armor
	var em := director.enemy_fire("emissile", jet.global_position + Vector3(0, 0.2, -1.6), Vector3.BACK, jet)
	await _frames(25)
	assert(jet.pop_flares())
	var emid := em.get_instance_id()
	assert(await _until(func(): return instance_from_id(emid) == null or (instance_from_id(emid) as Shot).dead, 400))
	assert(jet.armor == armor0, "flares saved the jet (%f)" % jet.armor)

	# 5) A pellet straight at the jet hurts it.
	director.enemy_fire("pellet", jet.global_position + Vector3(0, 0, -1.0), Vector3.BACK, null)
	assert(await _until(func(): return jet.armor < armor0, 120), "pellet hit")

	# 6) Laser: heats up and kills a drone.
	var d2 := director.spawn("drone")
	assert(await _until(func(): return d2.state == Enemy.State.ACTIVE, 200))
	_point_at(d2)
	trig_l = 1.0
	var d2id := d2.get_instance_id()
	assert(await _until(func():
		if not _gone(d2id):
			_point_at(instance_from_id(d2id))
		return _gone(d2id), 400), "laser killed the drone")
	assert(jet.heat > 0.0)
	trig_l = 0.0
	await _frames(5)

	# 7) Jet destroyed → results.
	jet.take_hit(999.0)
	assert(jet.destroyed)
	assert(await _until(func(): return director.phase == BattleDirector.Phase.RESULTS, 400), "results after the crash")
	assert(not director.won)
	director._phase_time = 2.0
	director.on_button(&"ax_button", 1)
	assert(director.phase == BattleDirector.Phase.PLAYING and not jet.destroyed and jet.armor == CombatMath.JET_ARMOR, "replay")

	# 8) Full match: every wave spawns from the bays; we kill units as they arrive.
	director.auto_spawn = true
	var seen := {}
	var ok := await _until(func():
		for e in director.enemies.duplicate():
			seen[e.kind] = true
			if e.kind == "boss":
				assert(director.boss_bay != null)
			jet.armor = CombatMath.JET_ARMOR
			if e.state == Enemy.State.ACTIVE:
				director._kill(e, "cannon")
		return director.phase == BattleDirector.Phase.RESULTS, 90 * 120)
	assert(ok, "match finished; wave=%d" % director.wave)
	assert(director.won and seen.has("boss") and seen.has("fighter") and seen.has("tank") and seen.has("target"), "won with all kinds %s" % [seen])
	assert(director.save.best("raid") == director.score and director.score > 0)
	print("PASS: battle smoke — bays on walls, menu aim, cannon, lock+missile, bomb, flares, pellets, laser, crash, replay, 5 waves + boss, save (score %d)" % director.score)
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 240.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
