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
		inp = WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6), 0.75, plane.easy_flight)
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


func M(id: String) -> int:
	return Missions.index_of(id)


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
	assert(_press(Lang.t("missions_map")) and menus.screen == "missions")
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
		return c.index == M("training") + 1, 72 * 150), "balloons popped → straight on to mission 2, no menu")
	trig = 0.0
	assert(battle.phase == Battle.Phase.PLAYING and not menus.is_open() and plane.airborne(), "still flying, no board between missions")
	assert(c.mode == "intro" and c.continuing)
	assert(await _until(func(): return c.mode == "play", 72 * 6), "mission 2 began in the air")
	assert(await _until(func(): return battle.enemies.any(func(e): return e.kind == "fighter"), 72 * 4))
	for e in battle.enemies:
		if e.kind == "fighter":
			var depth: float = (e.global_position - battle.arena_origin).dot(battle.arena_fwd)
			assert(depth > 3.0, "enemies come in from in front of the player (%.1f m ahead)" % depth)
	# Sparring fighters stay in front of the headset.
	await _until(func(): return false, 72 * 6)
	for e in battle.enemies:
		if e.kind == "fighter" and e.alive() and e.state == Enemy.State.ACTIVE:
			assert((e.global_position - battle.arena_origin).dot(battle.arena_fwd) > 0.3, "fighter stayed in front")
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
	battle.start_mission(M("patrol"))
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
		return c.index == M("patrol") + 1, 72 * 40), "patrol cleared → on to the convoy")
	assert(Profile.mission("patrol").done and not menus.is_open())
	assert(battle.get_children().any(func(n): return n is Debris), "shot-down fighters broke into pieces")

	print("STAGE: mission 3 — convoy, 2 s anti-air telegraph, flares")
	Profile.equip("bombs")
	battle.start_mission(M("convoy"))
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
		return c.index == M("convoy") + 1, 72 * 50), "convoy destroyed")
	assert(Profile.stars_of("convoy") == 3)

	print("STAGE: mission 4 — escort")
	battle.start_mission(M("escort"))
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
		return c.index == M("escort") + 1, 72 * 30), "escort complete")

	print("STAGE: mission 5 — burning skies with the incendiary quad")
	Profile.equip("quad")
	battle.start_mission(M("dogfight"))
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
		return c.index == M("dogfight") + 1, 72 * 100), "three waves down")
	assert(seen.has("ace") and burned[0], "the ace showed up; incendiary set a fighter alight")

	print("STAGE: mission 6 — base raid")
	battle.start_mission(M("base"))
	c = battle.campaign
	assert(c._targets.size() == 6)
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	assert(await _until(func():
		for e in c._targets:
			if is_instance_valid(e) and e.alive():
				battle._kill(e, "bomb")
				break
		return c.index == M("base") + 1, 72 * 30), "base destroyed")

	print("STAGE: mission 7 — hold the airfield (dive bombers)")
	Profile.equip("mines")
	battle.start_mission(M("airfield"))
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
		return c.index == M("airfield") + 1, 72 * 60), "airfield held")

	print("STAGE: mission 8 — the giant at dusk")
	battle.start_mission(M("giant"))
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
	assert(menus.screen == "debrief", "the end of the sortie shows the debrief")

	print("STAGE: a lost objective is flown again at once")
	battle.start_mission(M("escort"))
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	battle.damage_friend(c._cargo, 999.0, c._cargo.global_position)
	assert(await _until(func(): return c.mode == "failed", 72 * 3), "objective lost")
	assert(await _until(func(): return c.mode == "play" and c.index == M("escort") and c._cargo != null and is_instance_valid(c._cargo), 72 * 14), "escort restarted in the air")
	assert(not menus.is_open() and battle.phase == Battle.Phase.PLAYING)

	print("STAGE: new — helicopter nest (pop up from the floor, hover in front, shoot)")
	battle.start_mission(M("heli_nest"))
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var heli_h := []
	assert(await _until(func():
		for e in battle.enemies:
			if e.kind == "heli" and heli_h.is_empty():
				heli_h.append(e)
		return not heli_h.is_empty(), 72 * 6), "helicopters spawned")
	var h: Enemy = heli_h[0]
	var y_start: float = h.global_position.y
	assert(y_start < battle.floor_y + 0.2, "a helicopter starts on the floor")
	assert(await _until(func(): return h.state == Enemy.State.ACTIVE, 72 * 8), "it rose to its hover point")
	assert(h.global_position.y > battle.floor_y + 0.7 and (h.global_position - battle.arena_origin).dot(battle.arena_fwd) > 0.9, "hovering in front of the player")
	var fired := [false]
	assert(await _until(func():
		fired[0] = battle.shots.any(func(sh): return sh.hostile)
		return fired[0], 72 * 6), "helicopter opens fire")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive() and e.kind in ["heli", "sam", "soldier"]:
				battle._kill(e, "gun")
		return c.index == M("heli_nest") + 1, 72 * 60), "three helicopter waves down")

	print("STAGE: new — missile storm (survive; missiles beaten)")
	battle.start_mission(M("missile_storm"))
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.2, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	assert(await _until(func(): return battle.shots.any(func(sh): return sh.kind == "sam"), 72 * 12), "missiles in the air")
	var m0 := battle.missiles_beaten
	var sm: Shot = battle.shots.filter(func(sh): return sh.kind == "sam")[0]
	sm.global_position = battle.arena_center + Vector3(0, 2.2, 0)   # clear of its launcher
	sm.prev = sm.global_position
	var shot := battle.player_fire("bullet", sm.global_position - Vector3(0, 0, 0.1), Vector3.BACK, Vector3.ZERO, null)
	shot.prev = sm.global_position - Vector3(0, 0, 0.1)
	shot.global_position = sm.global_position + Vector3(0, 0, 0.05)
	battle._resolve(shot)
	assert(battle.missiles_beaten == m0 + 1, "shooting a missile down counts")
	c.t = Campaign.STORM_TIME
	assert(await _until(func(): return c.index == M("missile_storm") + 1, 72 * 8), "storm survived")

	print("STAGE: new — iron raiders (armour, homing rockets)")
	battle.start_mission(M("raiders"))
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var rh := []
	assert(await _until(func():
		for e in battle.enemies:
			if e.kind == "raider" and e.state == Enemy.State.ACTIVE and rh.is_empty():
				rh.append(e)
		return not rh.is_empty(), 72 * 10), "raiders arrived")
	var rd: Enemy = rh[0]
	var hp0: float = rd.hp
	var b2 := battle.player_fire("bullet", rd.hit_center() - Vector3(0, 0, 0.3), Vector3.BACK, Vector3.ZERO, null)
	b2.prev = rd.hit_center() - Vector3(0, 0, 0.3)
	b2.global_position = rd.hit_center() + Vector3(0, 0, 0.05)
	var full: float = b2.damage
	battle._resolve(b2)
	assert(absf((hp0 - rd.hp) - full * WarMath.GUN_ARMOR.raider) < 0.01, "armour halves plain bullets (%.2f of %.2f)" % [hp0 - rd.hp, full])
	rd.flight.pos = plane.global_position - plane.forward() * 1.5
	rd.flight.fwd = plane.forward()
	rd.global_position = rd.flight.pos
	rd.global_basis = Basis.looking_at(plane.forward(), Vector3.UP)
	rd._rocket_t = 0.0
	var before_sams := battle.shots.filter(func(sh): return sh.kind == "sam").size()
	rd._raider_rockets(0.01)
	assert(battle.shots.filter(func(sh): return sh.kind == "sam").size() == before_sams + 1, "raider fires a homing rocket")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive() and e.kind in ["raider", "heli"]:
				battle._kill(e, "rocket")
		return c.index == M("raiders") + 1, 72 * 60), "raiders defeated")

	print("STAGE: new — flying fortress (side cannons, missiles, three engines)")
	battle.start_mission(M("fortress"))
	c = battle.campaign
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	var fort: Enemy = c._fortress
	assert(fort != null and fort.kind == "gunship" and fort.parts.side_guns.size() == 2)
	assert(await _until(func(): return fort.state == Enemy.State.ACTIVE, 72 * 14), "fortress arrived")
	assert(await _until(func(): return battle.shots.any(func(sh): return sh.kind == "flak"), 72 * 6), "side cannons fire flak")
	for eng in fort.parts.engines.slice(0, 3):
		fort.damage(200.0, (eng.node as Node3D).global_position)
	assert(fort.state == Enemy.State.DEAD)
	battle._kill(fort, "rocket")
	assert(await _until(func():
		for e in battle.enemies.duplicate():
			if e.alive() and e.kind == "heli":
				battle._kill(e, "gun")
		return c.index == M("fortress") + 1, 72 * 20), "fortress down")

	print("STAGE: new weapons — minigun, rocket swarm, napalm")
	Profile.progress.coins = 9000
	for it in ["minigun", "swarm", "napalm"]:
		menus._buy_or_equip(it)
		assert(Profile.owns(it))
	Profile.equip("minigun")
	Profile.equip("swarm")
	battle.start_mission(M("dogfight"))
	c = battle.campaign
	assert(plane.gun_kind == "minigun" and plane.special == "swarm")
	goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	assert(await _until(func(): return c.mode == "play", 72 * 10))
	assert(await _until(func(): return battle.enemies.any(func(e): return e.kind == "fighter" and e.state == Enemy.State.ACTIVE), 72 * 12))
	var tf: Enemy = battle.enemies.filter(func(e): return e.kind == "fighter" and e.state == Enemy.State.ACTIVE)[0]
	plane.flight.pos = tf.hit_center() - (tf.flight.fwd as Vector3) * 1.2
	plane.flight.basis = Basis.looking_at(tf.flight.fwd, Vector3.UP)
	plane._apply_pose()
	var rockets0 := battle.shots.filter(func(sh): return sh.kind == "rocket").size()
	assert(plane.fire_swarm(), "swarm fired")
	var swarm_shots: Array = battle.shots.filter(func(sh): return sh.kind == "rocket")
	assert(swarm_shots.size() == rockets0 + WarMath.SWARM_ROCKETS and swarm_shots.any(func(sh): return sh.target == tf), "six mini rockets, homing on the fighter")
	Profile.equip("napalm")
	plane.refresh_loadout()
	assert(plane.special == "napalm")
	var tank: Enemy = battle.spawn_at("tank", battle.arena_center, -battle.arena_fwd)
	var thp: float = tank.hp
	battle._fire_zones.append({"at": tank.global_position, "t": 2.0, "fx": 0.0})
	await _until(func(): return false, 72)
	assert(not tank.alive() or tank.hp < thp - 1.5, "napalm burns what stands in it")

	print("STAGE: pause")
	battle.start_mission(M("training"))
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
	battle.start_mission(M("dogfight"))
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
	battle.start_mission(M("dogfight"))
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
	print("PASS: campaign v1.1 — menus, 12 missions (helicopters, missile storm, armoured raiders, flying fortress), hangar + new weapons, 2 s anti-air telegraph, flares, escort, dive bombers, dusk, pause, breakup + bail-out, settings (%d★, %d gold left)" % [Profile.total_stars(), int(Profile.progress.coins)])
	quit(0)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 540000:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
