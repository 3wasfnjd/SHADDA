extends SceneTree
## SAQR v1.0 end to end, headless, flown with stick inputs where it matters:
## menus (main → campaign → briefing → controls card) · mission 1 flown by
## the autopilot through all 8 rings and the balloons → debrief with stars
## and gold · the hangar (buy, equip) · every other mission completed or
## failed on its own rules (convoy with the 2 s anti-air telegraph, escort,
## airfield dive bombers hitting hangars, dusk giant) · new weapons
## (incendiary, 20 mm, air mines, Thunderbolt, flares) · pause · settings
## and language · being shot down: the plane breaks apart, the pilot bails
## out, and the mission fails.

var battle: Battle
var plane: PlayerPlane
var menus: Menus
var head: XRCamera3D
var goal := Vector3(0, 1.3, -2.0)
var trig := 0.0
var fly := true
const DT := 1.0 / 72.0


func _initialize() -> void:
	_run()


func _frame() -> void:
	var inp := {}
	if fly:
		inp = WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6), 0.75)
	battle.update_controls(DT, head.global_position, Vector3.FORWARD, inp, trig, 0.0)
	await physics_frame


func _until(cond: Callable, frames: int) -> bool:
	for i in range(frames):
		if cond.call():
			return true
		await _frame()
	return cond.call()


## Presses the board button whose label reads `text` (or the n-th card).
func _press(text: String) -> bool:
	if not menus.is_open():
		return false
	for w in menus.panel.widgets:
		if w.kind == "button" and w.enabled and w.label and (w.label as Label3D).text == text:
			(w.action as Callable).call()
			return true
	return false


func _card(i: int) -> bool:
	var cards: Array = menus.panel.widgets.filter(func(w): return w.kind == "button" and w.label == null and w.has("hint"))
	if i >= cards.size() or not cards[i].enabled:
		return false
	(cards[i].action as Callable).call()
	return true


func _win_now(i: int) -> void:
	battle.start_mission(i)
	await _until(func(): return battle.campaign.mode == "play" or battle.campaign.id in ["convoy", "base", "airfield"], 72 * 10)


func _run() -> void:
	await process_frame
	Profile.path = "user://saqr_profile_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))
	Profile.load_profile()
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
	menus = Menus.new()
	arena.add_child(menus)
	menus.head = head
	menus.battle = battle
	battle.menus = menus
	battle.build(head, plane, hud)
	battle.on_room_ready({"floor_y": 0.0, "ceiling_y": 5.0, "walls": [], "openings": [], "surfaces": [], "blocks": [], "found": false, "free": true})

	print("STAGE: menus")
	assert(battle.phase == Battle.Phase.MENU and menus.screen == "main", "main menu on the board")
	assert(_press(Lang.t("campaign")) and menus.screen == "missions")
	assert(not _card(1), "mission 2 is locked at first")
	assert(_card(0) and menus.screen == "brief")
	assert(_press(Lang.t("start")) and menus.screen == "controls", "first take-off shows the controls card")
	assert(_press(Lang.t("start")) and battle.phase == Battle.Phase.PLAYING and not menus.is_open())
	# The laser hits the board: point straight at the centre of a fresh board.
	menus.open("main")
	var hitp = menus.panel.hit(head.global_position, (menus.panel.global_position - head.global_position).normalized())
	assert(hitp != null and (hitp as Vector2).length() < 0.01, "pointer meets the board")
	menus.close()

	print("STAGE: mission 1 — flight school, flown by hand (autopilot sticks)")
	var c: Campaign = battle.campaign
	assert(c.id == "training" and c.mode == "intro")
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10), "took off, mission began")
	assert(c._rings.size() == 8)
	var guard := 0
	while c._ring_i < 8 and guard < 72 * 150:
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
		await _frame()
		guard += 1
	assert(c._ring_i == 8, "flew all 8 rings (%d)" % c._ring_i)
	trig = 1.0
	assert(await _until(func():
		var b = null
		for e in battle.enemies:
			if e.alive() and e.kind == "balloon" and e.state == Enemy.State.ACTIVE:
				b = e
		if b:
			goal = b.hit_center()
		return battle.phase == Battle.Phase.RESULTS, 72 * 150), "balloons popped → debrief")
	trig = 0.0
	assert(menus.screen == "debrief")
	var m1 := Profile.mission("training")
	assert(m1.done and int(m1.stars) >= 1 and Profile.progress.coins > 0, "stars and gold recorded")
	assert(battle.shots_fired > 0 and battle.shots_hit > 0, "accuracy counted")
	print("  mission 1: %d★, %d gold, accuracy %d/%d" % [int(m1.stars), int(Profile.progress.coins), battle.shots_hit, battle.shots_fired])

	print("STAGE: hangar")
	Profile.progress.coins = 5000
	menus.open("hangar", {"tab": "upgrades"})
	var before := Profile.level("engine")
	menus._buy("engine")
	assert(Profile.level("engine") == before + 1, "engine upgraded")
	menus.open("hangar", {"tab": "weapons"})
	for it in ["quad", "cannon", "cluster", "mines", "lightning", "flares"]:
		menus._buy_or_equip(it)
		assert(Profile.owns(it), "bought %s" % it)
	assert(Profile.progress.special == "lightning" and Profile.progress.gun == "cannon")

	print("STAGE: mission 2 — dawn patrol with the 20 mm cannon and the Thunderbolt")
	battle.start_mission(1)
	c = battle.campaign
	assert(plane.gun_kind == "cannon" and plane.special == "lightning" and plane.power > 1.0)
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	# Let a fighter come close, then call down the lightning.
	var zapped := [false]
	assert(await _until(func():
		for e in battle.enemies:
			if e.alive() and e.kind == "fighter" and e.state == Enemy.State.ACTIVE:
				plane.flight.pos = e.hit_center() - (e.flight.fwd as Vector3) * 0.6
				plane.flight.basis = Basis.looking_at(e.flight.fwd, Vector3.UP)
				plane._apply_pose()
				zapped[0] = plane.fire_lightning()
				return true
		return false, 72 * 12), "fighter arrived")
	assert(zapped[0] and battle.kills + int(battle.enemies.filter(func(e): return e.kind == "fighter" and e.hp < e.max_hp).size()) > 0, "lightning struck")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive() and e.state == Enemy.State.ACTIVE:
				battle._kill(e, "gun")
		return battle.phase == Battle.Phase.RESULTS, 72 * 40), "patrol cleared")
	assert(menus.screen == "debrief" and Profile.mission("patrol").done)
	assert(battle.get_children().any(func(n): return n is Debris), "shot-down fighters broke into pieces")

	print("STAGE: mission 3 — convoy, 2 s anti-air telegraph, flares")
	Profile.equip("bombs")
	battle.start_mission(2)
	c = battle.campaign
	goal = Vector3(0, 1.6, -1.5)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var holder := []
	assert(await _until(func():
		for e in battle.enemies:
			if e.kind == "sam" and holder.is_empty():
				holder.append(e)
		return not holder.is_empty(), 72 * 12), "SAM team arrived")
	var sam: Enemy = holder[0]
	assert(await _until(func(): return sam.sam_phase == "prep", 72 * 14), "SAM started preparing")
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
	(missiles[0] as Shot).global_position = plane.global_position - plane.forward() * 1.0
	plane._roll_cd = 0.0
	assert(plane.barrel_roll(), "roll")
	assert(missiles[0].target == null, "flares pulled the missile off")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.has_meta("convoy") and e.alive():
				battle._kill(e, "gun")
		return battle.phase == Battle.Phase.RESULTS, 72 * 50), "convoy destroyed")
	assert(Profile.stars_of("convoy") == 3)

	print("STAGE: mission 4 — escort")
	battle.start_mission(3)
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	assert(c._cargo != null and battle.friends.has(c._cargo))
	var hunted := [false]
	assert(await _until(func():
		for e in battle.enemies:
			if e.prey == c._cargo:
				hunted[0] = true
		return hunted[0], 72 * 8), "fighters go for the supply plane")
	var p0: Vector3 = c._cargo.global_position
	await _until(func(): return false, 72 * 2)
	assert(c._cargo.global_position.distance_to(p0) > 0.2, "supply plane flies its route")
	c.t = Campaign.ESCORT_TIME
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive():
				battle._kill(e, "gun")
		return battle.phase == Battle.Phase.RESULTS, 72 * 30), "escort complete")
	assert(menus.screen == "debrief")

	print("STAGE: mission 5 — burning skies with the incendiary quad")
	Profile.equip("quad")
	battle.start_mission(4)
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var burned := [false]
	var seen := {}
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.kind == "ace":
				seen["ace"] = true
			if (e.kind == "fighter" or e.kind == "ace") and e.alive() and e.state == Enemy.State.ACTIVE:
				if not burned[0]:
					var s := battle.player_fire("bullet", e.hit_center() - Vector3(0, 0, 0.3), Vector3.BACK, Vector3.ZERO, null, {"incendiary": true})
					s.global_position = e.hit_center() + Vector3(0, 0, -0.05)
					battle._resolve(s)
					burned[0] = e.burn_t > 0.0 or not e.alive()
				else:
					battle._kill(e, "gun")
		return battle.phase == Battle.Phase.RESULTS, 72 * 100), "three waves down")
	assert(seen.has("ace") and burned[0], "the ace showed up; incendiary set a fighter alight")

	print("STAGE: mission 6 — base raid")
	battle.start_mission(5)
	c = battle.campaign
	assert(c._targets.size() == 6)
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	assert(await _until(func():
		for e in c._targets:
			if is_instance_valid(e) and e.alive():
				battle._kill(e, "bomb")
				break
		return battle.phase == Battle.Phase.RESULTS, 72 * 30), "base destroyed")

	print("STAGE: mission 7 — hold the airfield (dive bombers)")
	Profile.equip("mines")
	battle.start_mission(6)
	c = battle.campaign
	assert(c._hangars.size() == 3)
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.4, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	# Let the first wave dive and bomb.
	var dove := [false]
	assert(await _until(func():
		for e in battle.enemies:
			if e.kind == "diver" and e._mode in ["dive", "pull"]:
				dove[0] = true
		var hurt := false
		for h in c._hangars:
			if h.hp < h.max_hp:
				hurt = true
		return dove[0] and hurt, 72 * 60), "a diver dived and its bomb hit a hangar")
	assert(plane.drop_mine() and battle.shots.any(func(s): return s.kind == "mine"), "air mine dropped")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive() and e.state == Enemy.State.ACTIVE:
				battle._kill(e, "gun")
		return battle.phase == Battle.Phase.RESULTS, 72 * 60), "airfield held")
	assert(menus.screen == "debrief" or menus.screen == "failed")

	print("STAGE: mission 8 — the giant at dusk")
	battle.start_mission(7)
	c = battle.campaign
	assert(battle.dusk, "dusk mission dims the room")
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var bomber := c._bomber
	assert(await _until(func(): return bomber.state == Enemy.State.ACTIVE, 72 * 12), "bomber arrived")
	for eng in bomber.parts.engines.slice(0, 3):
		bomber.damage(100.0, (eng.node as Node3D).global_position)
	battle._kill(bomber, "rocket")
	assert(await _until(func(): return battle.phase == Battle.Phase.RESULTS, 72 * 20), "campaign finished")
	assert(not battle.dusk or menus.screen == "debrief")

	print("STAGE: pause")
	battle.start_mission(0)
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	await _until(func(): return false, 30)
	battle.pause_game()
	assert(paused and menus.screen == "pause", "paused behind the pause board")
	var pos0 := plane.global_position
	await process_frame
	assert(plane.global_position == pos0)
	assert(_press(Lang.t("resume")) and not paused and not menus.is_open())

	print("STAGE: shot down on Normal → breaks apart, pilot bails out, mission failed")
	Profile.set_s("difficulty", "normal")
	battle.start_mission(4)
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	plane.take_hit(999.0)
	assert(plane.state == PlayerPlane.State.WRECKED and not plane.model.root.visible)
	assert(battle.get_children().filter(func(n): return n is Debris).size() >= 5, "the plane came apart into its pieces")
	assert(battle.get_children().any(func(n): return n is Debris.Chute), "the pilot is on his parachute")
	assert(await _until(func(): return battle.phase == Battle.Phase.RESULTS, 72 * 8), "mission over")
	assert(menus.screen == "failed" and not battle.won)

	print("STAGE: easy mode can't lose the plane")
	Profile.set_s("difficulty", "easy")
	battle.start_mission(4)
	plane.take_hit(999.0)
	assert(plane.alive() and plane.hp >= WarMath.PLANE_HP * WarMath.MIN_HP_FRACTION - 0.01)

	print("STAGE: settings and language")
	battle.quit_to_menu()
	menus.open("settings", {"tab": "game"})
	menus._set_opt("lang", "en")
	assert(Lang.t("campaign") == "Campaign" and not menus.panel.rtl)
	menus._set_opt("lang", "ar")
	assert(Lang.t("campaign") == "الحملة" and menus.panel.rtl)
	for tab in ["controls", "graphics", "audio"]:
		menus.open("settings", {"tab": tab})
		assert(menus.panel.widgets.size() > 4, "settings tab %s has controls" % tab)
	menus._set_live("music", 0.25)
	Profile.load_profile()
	assert(absf(float(Profile.get_s("music")) - 0.25) < 0.01, "settings saved")
	for scr in ["main", "missions", "hangar", "controls"]:
		menus.open(scr)
		assert(menus.is_open())
	print("PASS: campaign v1.0 — menus, 8 missions, hangar + new weapons, 2 s anti-air telegraph, flares, escort, dive bombers, dusk, pause, breakup + bail-out, settings (%d★, %d gold left)" % [Profile.total_stars(), int(Profile.progress.coins)])
	quit(0)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 540000:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
