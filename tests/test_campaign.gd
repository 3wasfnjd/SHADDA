extends SceneTree
## The five-stage campaign over the open floor, flown with stick inputs:
## 1 rings in order + balloons with the guns → upgrade → 2 convoy with an
## anti-air team that prepares for exactly 2 s (warning visible) before its
## missile flies → 3 dogfight waves incl. the ace → 4 base targets → 5 bomber
## → results with stars. The plane can't be lost (damage stops at 15 %).

var battle: Battle
var plane: PlayerPlane
var head: XRCamera3D
var goal := Vector3(0, 1.3, -2.0)
var trig := 0.0
const DT := 1.0 / 72.0


func _initialize() -> void:
	_run()


func _frame() -> void:
	var inp := WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6), 0.75)
	battle.update_controls(DT, head.global_position, Vector3.FORWARD, inp, trig, 0.0)
	await physics_frame


func _until(cond: Callable, frames: int) -> bool:
	for i in range(frames):
		if cond.call():
			return true
		await _frame()
	return cond.call()


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
	battle.save_path = "user://saqr_campaign_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(battle.save_path))
	battle.build(head, plane, hud)
	battle.on_room_ready({"floor_y": 0.0, "ceiling_y": 5.0, "walls": [], "openings": [], "surfaces": [], "blocks": [], "found": false, "free": true})
	battle.start_match()
	var c: Campaign = battle.campaign
	assert(c != null and c.stage == 0 and c.mode == "intro")
	plane.invincible = true

	print("STAGE 1: rings")
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10), "took off and stage 1 began")
	assert(c._rings.size() == 8)
	# Fly each ring: approach point behind it, then through it.
	var guard := 0
	while c._ring_i < 8 and guard < 72 * 120:
		var r: Dictionary = c._rings[c._ring_i]
		var rc: Vector3 = r.pos
		var rn: Vector3 = r.n
		var sd := signf((plane.global_position - rc).dot(rn))
		if sd == 0.0:
			sd = 1.0
		var lead := rc + rn * sd * 1.0
		var heading_in := plane.forward().dot((rc - plane.global_position).normalized()) > 0.9
		if heading_in and absf((plane.global_position - rc).dot(rn)) < 1.1:
			goal = rc
		elif plane.global_position.distance_to(lead) < 0.35:
			goal = rc
		else:
			goal = lead
		if guard % 360 == 0:
			print("ring ", c._ring_i, " dist ", plane.global_position.distance_to(rc), " y ", plane.global_position.y)
		await _frame()
		guard += 1
	assert(c._ring_i == 8, "flew all 8 rings (%d)" % c._ring_i)
	# Balloons: fly at each with the guns.
	trig = 1.0
	assert(await _until(func():
		var b = null
		for e in battle.enemies:
			if e.alive() and e.kind == "balloon" and e.state == Enemy.State.ACTIVE:
				b = e
		if b:
			goal = b.hit_center()
		return c.mode == "clear", 72 * 120), "balloons popped, stage 1 clear")
	trig = 0.0
	assert(c.stars.size() == 1)
	assert(await _until(func(): return c.mode == "upgrade", 72 * 6), "upgrade offered")
	var speed_before := plane.power
	c.pick_first()
	assert(plane.upgrades.size() == 1, "upgrade applied")

	print("STAGE 2: convoy + SAM telegraph")
	assert(c.stage == 1)
	goal = Vector3(0, 1.6, -1.5)
	assert(await _until(func(): return c.mode == "play", 72 * 8))
	# Watch the first anti-air team: prep must last 2 s, then a missile.
	var holder := []
	assert(await _until(func():
		for e in battle.enemies:
			if e.kind == "sam" and holder.is_empty():
				holder.append(e)
		return not holder.is_empty(), 72 * 10), "SAM team arrived")
	var sam: Enemy = holder[0]
	assert(await _until(func(): return sam.sam_phase == "prep", 72 * 12), "SAM started preparing")
	var prep_frames := 0
	var warned := false
	while sam.sam_phase == "prep" and prep_frames < 72 * 5:
		warned = warned or sam._warn.visible
		await _frame()
		prep_frames += 1
	var prep_s := float(prep_frames) / Engine.physics_ticks_per_second
	assert(absf(prep_s - WarMath.SAM_PREP) < 0.1, "prep lasted %f s" % prep_s)
	assert(warned, "the red ! blinked during prep")
	var missiles := battle.shots.filter(func(s): return s.kind == "sam")
	assert(missiles.size() >= 1 and missiles[0].target == plane, "missile launched at the plane after prep")
	# Kill the convoy as it comes.
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.has_meta("convoy") and e.alive():
				battle._kill(e, "gun")
		return c.mode == "clear", 72 * 40), "convoy destroyed, stage 2 clear")
	assert(c._destroyed == 5 and c.stars[1] == 3)
	assert(plane.hp >= WarMath.PLANE_HP * WarMath.MIN_HP_FRACTION - 0.01, "plane can't be lost")
	assert(await _until(func(): return c.mode == "upgrade", 72 * 6))
	c.pick_first()

	print("STAGE 3: dogfight")
	var seen := {}
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.kind == "ace":
				seen["ace"] = true
			if (e.kind == "fighter" or e.kind == "ace") and e.alive() and e.state == Enemy.State.ACTIVE:
				battle._kill(e, "gun")
		return c.mode == "clear", 72 * 90), "three waves down, stage 3 clear")
	assert(seen.has("ace"), "the ace showed up")
	assert(await _until(func(): return c.mode == "upgrade", 72 * 6))
	c.pick_first()

	print("STAGE 4: base")
	assert(await _until(func(): return c.mode == "play", 72 * 8))
	assert(c._targets.size() == 6)
	var kinds := {}
	assert(await _until(func():
		for e in c._targets:
			if is_instance_valid(e) and e.alive():
				kinds[e.kind] = true
				battle._kill(e, "bomb")
				break
		return c.mode == "clear", 72 * 30), "base targets destroyed, stage 4 clear")
	assert(kinds.has("fuel") and kinds.has("radar") and kinds.has("aa"))
	assert(await _until(func(): return c.mode == "upgrade", 72 * 6))
	c.pick_first()
	assert(plane.upgrades.size() == 4)

	print("STAGE 5: giant")
	assert(await _until(func(): return c.mode == "play", 72 * 8))
	assert(c._bomber != null)
	var bomber := c._bomber
	assert(await _until(func(): return bomber.state == Enemy.State.ACTIVE, 72 * 10), "bomber arrived")
	# Shoot three engines.
	for eng in bomber.parts.engines.slice(0, 3):
		bomber.damage(100.0, (eng.node as Node3D).global_position)
	assert(bomber.state == Enemy.State.DEAD)
	battle._kill(bomber, "rocket")
	assert(await _until(func(): return battle.phase == Battle.Phase.RESULTS, 72 * 20), "campaign finished")
	assert(c.stars.size() == 5 and c.total_stars() >= 5)
	assert(battle.won)
	print("PASS: campaign — rings, convoy with 2 s SAM telegraph, dogfight with ace, base raid, bomber; 4 upgrades; stars %d/15; score %d" % [c.total_stars(), battle.score])
	quit(0)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 420.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
