class_name Battle
extends Node3D
## The battlefield. Free flight (no room scan): the menus, then one campaign
## mission at a time (Campaign) → debrief. With a room scan: the room war —
## five waves through your real door and window → results.
## Owns all enemies, friendly units, shots, crates and pickups and resolves
## every hit.

enum Phase { SCANNING, MENU, PLAYING, RESULTS }

signal phase_changed(phase: int)

var phase: Phase = Phase.SCANNING
var head: Node3D
var plane: PlayerPlane
var hud: Hud
var audio: GameAudio
var room: Room
var save_path: String = "user://saqr_war.json"
var save: Dictionary = {}
var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var crates: Array = []          # {node, chute, target, vel}
var pickups: Array[Node3D] = []
var wave: int = 0
var in_break: bool = false
var score: int = 0
var streak: int = 0
var won: bool = false
var auto_spawn: bool = true
var free_flight: bool = false     # no room scan: the campaign plays over the open floor
var campaign: Campaign = null
var menus: Menus = null
var friends: Array[Enemy] = []      # escort plane, airfield hangars
var mission_index: int = 0
var kills: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var enemy_damage: float = 1.0       # difficulty
var paused: bool = false
var _crash_t: float = -1.0
var _callout: Label3D
var _callout_t: float = 0.0
var _warn_t: float = 0.0
var dusk: bool = false
# One continuous sortie: missions follow each other in the air, no menus between.
var sortie_from: int = 0
var missions_done: int = 0
var sortie_stars: int = 0
var sortie_gold: int = 0
var _next_t: float = -1.0
var _next_retry: bool = false
var _mission_score0: int = 0
var _behind_t: float = 0.0
# The battle area is a box in front of the player, never behind the headset.
var arena_origin: Vector3 = Vector3.ZERO
var arena_fwd: Vector3 = Vector3.FORWARD
var arena_side: Vector3 = Vector3.RIGHT
var arena_center: Vector3 = Vector3(0, 0, -2.2)
const ARENA_SIDE := 2.6
const ARENA_NEAR := 1.0
const ARENA_FAR := 4.6
var _arena_marks: Array = []
var _low_warned: bool = false
signal dusk_changed(on: bool)
var hands: Array = []            # XRControllers for rumble (optional)
var aim_origin: Vector3 = Vector3.ZERO
var aim_dir: Vector3 = Vector3.FORWARD
var _queue: Array = []
var _spawn_t: float = 0.0
var _phase_t: float = 0.0
var _break_t: float = 0.0
var _combo_t: float = 0.0
var _end_t: float = -1.0
var _waves_started: bool = false
var _respawn: bool = false
var _ui_root: Node3D
var _buttons: Array = []
var _trigger_was: float = 0.0
var _bomb_ring: MeshInstance3D
var _lock_marks: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var park_spot: Vector3 = Vector3.ZERO
var park_heading: Vector3 = Vector3.FORWARD

var box: Dictionary:
	get:
		return room.box if room else {"min": Vector3(-1.6, 0, -1.6), "max": Vector3(1.6, 2.5, 1.6)}
var floor_y: float:
	get:
		return room.floor_y if room else 0.0


func build(player_head: Node3D, player_plane: PlayerPlane, wrist: Hud) -> void:
	_rng.randomize()
	head = player_head
	plane = player_plane
	plane.battle = self
	hud = wrist
	hud.world = self
	audio = GameAudio.new()
	add_child(audio)
	room = Room.new()
	add_child(room)
	_load()
	_callout = UI.number("", 90, Color(1, 0.85, 0.3), false)
	_callout.font = UI.font("title")
	_callout.pixel_size = 0.0005
	_callout.top_level = true
	_callout.visible = false
	add_child(_callout)
	_bomb_ring = Toon.add(self, Toon.torus(0.07, 0.004, 28), Toon.flat(Color(1.0, 0.4, 0.15, 0.9)))
	_bomb_ring.visible = false
	for i in range(WarMath.LOCKS):
		var m := Node3D.new()
		Toon.add(m, Toon.torus(1.0, 0.09, 4), Toon.mat(Color(0.95, 0.15, 0.1), 0.4, 0.0), Vector3.ZERO, Vector3(90, 45, 0))
		m.visible = false
		add_child(m)
		_lock_marks.append(m)


func on_room_ready(description: Dictionary) -> void:
	free_flight = bool(description.get("free", false))
	plane.invincible = free_flight
	var physics: bool = bool(description.get("found", false)) and not bool(description.get("preview", false))
	room.setup(description, head_position(), physics)
	# Park the plane on the floor ahead of the player, nose away from them.
	var fwd := -head.global_basis.z if head else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	park_heading = fwd
	var spot := head_position() + fwd * 1.25
	spot = WarMath.clamp_into(spot, box, 0.55, 0.0)
	spot.y = room.surface_below(Vector3(spot.x, head_position().y, spot.z))
	park_spot = spot
	_set_phase(Phase.MENU)


# --- queries ---------------------------------------------------------------------------

func head_position() -> Vector3:
	return head.global_position if head else Vector3(0, 1.6, 0)


func box_center() -> Vector3:
	return room.center()


func player_position() -> Vector3:
	return plane.global_position


func player_velocity() -> Vector3:
	return plane.velocity


func player_airborne() -> bool:
	return plane.airborne() and phase == Phase.PLAYING


func surface_below(p: Vector3) -> float:
	return room.surface_below(p)


func wall_hit(a: Vector3, b: Vector3) -> Dictionary:
	return room.wall_hit(a, b)


func has_ground_units() -> bool:
	for e in enemies:
		if (e.kind == "tank" or e.kind == "aa") and e.alive():
			return true
	return false


## Nearest door/window for a transport to leave through.
func exit_opening(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for o in room.air_openings():
		var d := (o.center as Vector3).distance_to(from)
		if d < best_d:
			best_d = d
			best = o
	return best if not best.is_empty() else room.openings[0]


func ground_goal(from: Vector3, dir: Vector3) -> Vector3:
	var s: Dictionary = room.ground_spot(head_position())
	return s.point


func cue(name: String, at: Vector3, db: float = 0.0) -> void:
	if audio:
		audio.play(name, at, db)


## No camera shake in mixed reality (nausea) — rumble the hands instead.
func shake(amount: float) -> void:
	for h in hands:
		if h and h.get_is_active():
			h.trigger_haptic_pulse("haptic", 0.0, clampf(amount, 0.0, 1.0), 0.15 + amount * 0.2, 0.0)


# --- input ----------------------------------------------------------------------------

func on_button(action: StringName, hand_index: int) -> void:
	match phase:
		Phase.MENU:
			if action == &"ax_button" and _phase_t > 0.5 and not free_flight:
				start_match()
		Phase.PLAYING:
			if action == &"menu_button":
				if paused:
					resume()
				else:
					pause_game()
				return
			if paused:
				return
			if action == &"ax_button":
				plane.use_special()
			elif action == &"by_button":
				plane.barrel_roll()
		Phase.RESULTS:
			if _phase_t < 1.2 or free_flight:
				return
			if action == &"ax_button":
				start_match()
			elif action == &"by_button":
				_set_phase(Phase.MENU)


## Called every frame with the right controller's aim ray and the triggers.
## Called every frame: the right controller's aim ray (for the buttons), the
## stick inputs for the plane {pitch, roll, yaw, throttle_delta, boost, brake}
## and the right trigger/grip.
func update_controls(delta: float, origin: Vector3, dir: Vector3, inp: Dictionary, trigger_r: float, grip_r: float) -> void:
	aim_origin = origin
	aim_dir = dir.normalized()
	if paused:
		return
	var live := phase == Phase.PLAYING
	plane.tick(delta, inp if live else {}, trigger_r if live else 0.0, grip_r if live else 0.0)
	# Point-and-pull buttons.
	var pressed := trigger_r > 0.6 and _trigger_was <= 0.6
	_trigger_was = trigger_r
	for b in _buttons:
		if not is_instance_valid(b) or not b.is_visible_in_tree():
			continue
		var d: float = b.ray_distance(origin, aim_dir)
		var over: bool = d < b.radius * 1.3
		b.hovered = move_toward(b.hovered, 1.0 if over else 0.0, delta * 6.0)
		if pressed and over and _phase_t > 0.5:
			b.pressed = 1.0
			cue("click", b.global_position)
			b.get_meta("action").call()
			break


# --- phases ----------------------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	phase = p
	_phase_t = 0.0
	_clear_ui()
	match p:
		Phase.MENU:
			_clear_battlefield()
			set_dusk(false)
			plane.park(park_spot, park_heading, park_spot.y)
			hud.visible = false
			if free_flight and menus:
				menus.open("main")
			else:
				_build_menu()
			audio.play_music("menu")
		Phase.RESULTS:
			if not free_flight:
				_build_results()
			audio.play_music("menu")
	phase_changed.emit(p)


func start_match() -> void:
	start_mission(mission_index)


## Free flight: one campaign mission. With a room scan: the room war.
func start_mission(i: int) -> void:
	mission_index = clampi(i, 0, Missions.LIST.size() - 1)
	if paused:
		_unpause()
	if menus:
		menus.close()
	_clear_battlefield()
	kills = 0
	shots_fired = 0
	shots_hit = 0
	_crash_t = -1.0
	var diff := str(Profile.get_s("difficulty"))
	enemy_damage = {"easy": 0.6, "normal": 1.0, "hard": 1.4}.get(diff, 1.0)
	plane.invincible = diff == "easy"
	sortie_from = mission_index
	missions_done = 0
	sortie_stars = 0
	sortie_gold = 0
	_next_t = -1.0
	_mission_score0 = 0
	if free_flight:
		_set_arena()
	if plane.state != PlayerPlane.State.PARKED:
		plane.park(park_spot, park_heading, park_spot.y)
	score = 0
	streak = 0
	won = false
	wave = 0
	_end_t = -1.0
	_waves_started = false
	hud.visible = true
	hud.set_score(0)
	hud.set_combo(1.0)
	hud.set_wave(0, false)
	hud.show_waves(not free_flight)
	_low_warned = false
	_set_phase(Phase.PLAYING)
	plane.reset_upgrades()
	if free_flight:
		plane.apply_loadout()
	plane.start_engine()
	cue("engine_start", plane.global_position)
	audio.play_music("battle")
	if campaign:
		campaign.queue_free()
		campaign = null
	if free_flight:
		campaign = Campaign.new()
		add_child(campaign)
		campaign.begin(self, mission_index)


func restart_mission() -> void:
	start_mission(mission_index)


func quit_to_menu() -> void:
	if paused:
		_unpause()
	_set_phase(Phase.MENU)


func pause_game() -> void:
	if phase != Phase.PLAYING or paused:
		return
	paused = true
	get_tree().paused = true
	if menus:
		menus.open("pause")


func resume() -> void:
	if menus:
		menus.close()
	_unpause()
	if phase == Phase.PLAYING:
		plane.refresh_loadout()


func _unpause() -> void:
	paused = false
	get_tree().paused = false


## The campaign reports how the mission went.
func mission_over(victory: bool, stars: int, why: String) -> void:
	if phase != Phase.PLAYING:
		return
	var crashed := why == "plane_lost"
	var m0 := Missions.get_m(mission_index)
	var last := mission_index >= Missions.LIST.size() - 1
	if free_flight and campaign and not crashed:
		if victory:
			# Bank this mission and fly straight on to the next one.
			var mult0 := 1.5 if str(Profile.get_s("difficulty")) == "hard" else 1.0
			var gold := Profile.record(m0.id, stars, score - _mission_score0, mult0)
			missions_done += 1
			sortie_stars += stars
			sortie_gold += gold
			cue("win", head_position(), -4.0)
			if not last:
				campaign.show_result(stars, gold)
				_next_t = 3.4
				_next_retry = false
				return
		else:
			# Objective lost: the same challenge again, still in the air.
			_next_t = 3.0
			_next_retry = true
			return
	won = victory
	var hull := int(round(clampf(plane.hp / WarMath.PLANE_HP, 0.0, 1.0) * 100.0))
	var t := campaign.t if campaign else 0.0
	var acc := int(round(100.0 * shots_hit / maxf(1.0, shots_fired)))
	var m := Missions.get_m(mission_index)
	var result := {"index": mission_index, "won": victory, "stars": stars, "score": score, "time": t, "kills": kills, "accuracy": acc, "hull": hull, "reason": "plane_lost" if crashed else "", "why": why,
		"missions": missions_done, "sortie_stars": sortie_stars, "gold": sortie_gold, "sortie": free_flight}
	if victory and free_flight:
		result["coins"] = sortie_gold
		result["record"] = false
	elif victory:
		var best := int(Profile.mission(m.id).get("best", 0))
		result["record"] = score > best and best > 0
		var mult := 1.5 if str(Profile.get_s("difficulty")) == "hard" else 1.0
		result["coins"] = Profile.record(m.id, stars, score, mult)
		cue("win", head_position())
	plane.locks.clear()
	_set_phase(Phase.RESULTS)
	hud.visible = false
	# Back on the floor in front of you while you read the debrief.
	for sh in shots:
		sh.dead = true
	plane.park(park_spot, park_heading, park_spot.y)
	if menus:
		menus.open("debrief" if victory else "failed", result)


## Next mission (or the same one again) without landing or menus.
func _advance(i: int) -> void:
	mission_index = clampi(i, 0, Missions.LIST.size() - 1)
	for e in enemies.duplicate():
		if is_instance_valid(e):
			Fx.smoke(self, e.hit_center(), 0.04)
			e.queue_free()
	enemies.clear()
	for f in friends:
		if is_instance_valid(f):
			Fx.smoke(self, f.hit_center(), 0.05)
			f.queue_free()
	friends.clear()
	for s in shots:
		if s.hostile:
			s.dead = true
	plane.refresh_loadout()
	plane.repair(35.0)
	plane.rearm()
	_mission_score0 = score
	_low_warned = false
	campaign.clear()
	campaign.begin(self, mission_index, true)


## The battle box in front of the player: set once when the sortie starts.
func _set_arena() -> void:
	var hp := head_position()
	var f := -(head as Node3D).global_basis.z if head else Vector3.FORWARD
	f.y = 0.0
	arena_fwd = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
	arena_side = arena_fwd.cross(Vector3.UP).normalized()
	arena_origin = Vector3(hp.x, floor_y, hp.z)
	arena_center = arena_origin + arena_fwd * 2.4
	for m in _arena_marks:
		if is_instance_valid(m):
			m.queue_free()
	_arena_marks.clear()
	# Four amber corner brackets on the floor show where the fight is.
	for sx: float in [-1.0, 1.0]:
		for fz: float in [ARENA_NEAR, ARENA_FAR]:
			var holder := Node3D.new()
			add_child(holder)
			holder.global_position = arena_origin + arena_side * sx * ARENA_SIDE + arena_fwd * fz + Vector3(0, 0.003, 0)
			holder.global_basis = Basis.looking_at(-arena_fwd, Vector3.UP)
			var inward_x := -sx
			var inward_z := 1.0 if fz == ARENA_NEAR else -1.0
			var mat := Toon.flat(Color(1.0, 0.72, 0.2, 0.55))
			Toon.add(holder, Toon.block(Vector3(0.3, 0.002, 0.025)), mat, Vector3(inward_x * 0.15, 0, 0))
			Toon.add(holder, Toon.block(Vector3(0.025, 0.002, 0.3)), mat, Vector3(0, 0, -inward_z * 0.15))
			_arena_marks.append(holder)


## Keeps a point inside the battle area in front of the player.
func clamp_front(p: Vector3) -> Vector3:
	if not free_flight:
		return WarMath.clamp_into(p, box, 0.5, 0.6)
	var d := p - arena_origin
	var s := clampf(d.dot(arena_side), -ARENA_SIDE, ARENA_SIDE)
	var f := clampf(d.dot(arena_fwd), ARENA_NEAR, ARENA_FAR)
	var y := clampf(p.y, floor_y + 0.5, floor_y + 2.6)
	var out := arena_origin + arena_side * s + arena_fwd * f
	out.y = y
	return out


func arena_random(height_lo: float = 0.9, height_hi: float = 2.2) -> Vector3:
	var p := arena_origin + arena_side * _rng.randf_range(-ARENA_SIDE * 0.85, ARENA_SIDE * 0.85) + arena_fwd * _rng.randf_range(ARENA_NEAR + 0.4, ARENA_FAR - 0.3)
	p.y = floor_y + _rng.randf_range(height_lo, height_hi)
	return p


## Where enemy planes appear: far ahead, spread across the front.
func arena_entry(k: int) -> Vector3:
	var s := clampf(_rng.randf_range(-2.2, 2.2) + (k - 1) * 0.6, -2.6, 2.6)
	var p := arena_origin + arena_side * s + arena_fwd * _rng.randf_range(5.0, 5.8)
	p.y = floor_y + _rng.randf_range(1.3, 2.1)
	return p


func _check_behind(delta: float) -> void:
	_behind_t -= delta
	if not plane.airborne() or _behind_t > 0.0:
		return
	if (plane.global_position - arena_origin).dot(arena_fwd) < 0.2:
		_behind_t = 4.0
		callout(Lang.t("back_front"), Color(1.0, 0.75, 0.3), 2.0)


## A big line of text floating ahead of the eyes for a moment.
func callout(text: String, color: Color = Color(1, 0.85, 0.3), seconds: float = 1.8) -> void:
	_callout.text = text
	_callout.modulate = color
	_callout_t = seconds
	_callout.visible = true
	var cam := get_viewport().get_camera_3d()
	if cam:
		_callout.global_position = cam.global_position - cam.global_basis.z * 1.3 + Vector3(0, 0.28, 0)


func _step_callout(delta: float) -> void:
	if _callout_t <= 0.0:
		_callout.visible = false
		return
	_callout_t -= delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_basis.z
		f.y = clampf(f.y, -0.3, 0.3)
		var want := cam.global_position + f.normalized() * 1.3 + Vector3(0, 0.28, 0)
		_callout.global_position = _callout.global_position.lerp(want, minf(1.0, delta * 3.0))
		var to := cam.global_position - _callout.global_position
		if to.length() > 0.05:
			_callout.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)
	var a := clampf(_callout_t / 0.3, 0.0, 1.0)
	_callout.modulate.a = a
	_callout.outline_modulate.a = a


## Dusk: the real room dims and turns warm (Meta passthrough adjustment).
func set_dusk(on: bool) -> void:
	if dusk == on:
		return
	dusk = on
	dusk_changed.emit(on)


func on_airborne() -> void:
	if phase == Phase.PLAYING and not _waves_started and not free_flight:
		_waves_started = true
		_begin_wave(0)


func on_plane_destroyed() -> void:
	if phase == Phase.PLAYING:
		if campaign:
			_crash_t = 3.6
			return
		_end_t = 2.5
		_respawn = false


func _begin_wave(i: int) -> void:
	wave = i
	in_break = false
	_queue.clear()
	var spec: Dictionary = WarMath.WAVES[i]
	var rest: Array = []
	for k in ["bomber", "transport", "tank", "fighter", "balloon"]:
		for n in range(int(spec.get(k, 0))):
			rest.append(k)
	if spec.has("bomber"):
		audio.play_music("boss")
		_queue = rest
	else:
		var balloons := rest.filter(func(k): return k == "balloon")
		var others := rest.filter(func(k): return k != "balloon")
		others.shuffle()
		_queue = balloons + others
	_spawn_t = 1.0
	hud.set_wave(wave, false)
	cue("siren", head_position() + Vector3(0, 0.5, 0), -4.0)


func _process(delta: float) -> void:
	_phase_t += delta
	_watch_frame_rate(delta)


## If the headset can't keep up, thin out the effects automatically.
var _slow_t: float = 0.0
func _watch_frame_rate(delta: float) -> void:
	if phase != Phase.PLAYING or paused:
		return
	var target := float(Engine.physics_ticks_per_second)
	var vp := get_viewport()
	if vp and vp.use_xr:
		var xri := XRServer.primary_interface as OpenXRInterface
		if xri:
			target = xri.display_refresh_rate if xri.display_refresh_rate > 0.0 else target
	var fps := Engine.get_frames_per_second()
	_slow_t = _slow_t + delta if fps > 0 and fps < target * 0.8 else maxf(0.0, _slow_t - delta * 0.5)
	if _slow_t > 2.0:
		_slow_t = 0.0
		Fx.budget = maxi(40, int(Fx.budget * 0.7))
		Debris.effects_high = false


func _physics_process(delta: float) -> void:
	if phase == Phase.SCANNING:
		return
	_step_shots(delta)
	_step_crates(delta)
	for e in enemies.duplicate():
		if e.alive():
			e.tick(delta)
		elif e.state == Enemy.State.FALLING:
			e.tick(delta)
		if e.state == Enemy.State.ESCAPED:
			if campaign:
				campaign.on_escaped(e)
			enemies.erase(e)
			e.queue_free()
	for f in friends.duplicate():
		if is_instance_valid(f):
			f.tick(delta)
	_step_burns(delta)
	_step_pickups(delta)
	_update_marks()
	_step_callout(delta)
	if phase != Phase.PLAYING:
		return
	_missile_warning(delta)
	if campaign and plane.alive() and plane.hp < WarMath.PLANE_HP * 0.3 and not _low_warned and not plane.invincible:
		_low_warned = true
		callout(Lang.t("low_hull"), Color(1.0, 0.45, 0.3), 2.5)
		cue("alarm", plane.global_position, -4.0)
	elif plane.hp > WarMath.PLANE_HP * 0.6:
		_low_warned = false
	if _crash_t >= 0.0:
		_crash_t -= delta
		if _crash_t < 0.0:
			mission_over(false, 0, "plane_lost")
			return
	hud.set_plane(plane)
	var cam := get_viewport().get_camera_3d()
	hud.point_to(plane.global_position, cam, plane.alive())
	_combo_t -= delta
	if _combo_t <= 0.0 and streak > 0:
		streak = 0
		hud.set_combo(1.0)
	if _end_t >= 0.0:
		_end_t -= delta
		if _end_t <= 0.0:
			if _respawn:
				# Free flight: a fresh plane back on the floor in front of you.
				_end_t = -1.0
				_respawn = false
				Fx.clear_marks()
				plane.park(park_spot, park_heading, park_spot.y)
				plane.start_engine()
			else:
				_finish(false)
		return
	if campaign:
		if _next_t >= 0.0:
			_next_t -= delta
			if _next_t < 0.0:
				_advance(mission_index if _next_retry else mission_index + 1)
				return
		campaign.tick(delta)
		_check_behind(delta)
		return
	if not _waves_started:
		return
	if in_break:
		_break_t -= delta
		if _break_t <= 0.0:
			_begin_wave(wave + 1)
		return
	if auto_spawn:
		_spawn_t -= delta
		if _spawn_t <= 0.0 and not _queue.is_empty() and _alive_count() < 6:
			var k: String = _queue.pop_front()
			spawn(k)
			_spawn_t = 0.35 if k == "balloon" else _rng.randf_range(1.6, 2.6)
	if _queue.is_empty() and _alive_count() == 0 and crates.is_empty() and _phase_t > 1.0:
		_wave_cleared()


## Free flight: two enemy fighters to chase and dogfight; a new one flies in
## a moment after each kill. They shoot back for show only.
var _practice_t: float = 1.5
func _practice(delta: float) -> void:
	if not plane.airborne() and enemies.is_empty():
		return
	_practice_t -= delta
	if _practice_t <= 0.0 and _alive_count() < 2:
		_practice_t = 2.0
		var a := _rng.randf() * TAU
		var hp := head_position()
		var at := Vector3(hp.x + cos(a) * 4.5, floor_y + _rng.randf_range(1.2, 2.0), hp.z + sin(a) * 4.5)
		var n := (Vector3(hp.x, at.y, hp.z) - at).normalized()
		var e := Enemy.create("fighter")
		e.battle = self
		e.practice = true
		add_child(e)
		enemies.append(e)
		e.enter_through({"center": at + n * 0.55, "base": Vector3(at.x, floor_y, at.z), "normal": n, "width": 1.0, "height": 1.0})
		cue("plane_in", at)


func _alive_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive():
			n += 1
	return n


func _wave_cleared() -> void:
	if wave >= WarMath.WAVES.size() - 1:
		_finish(true)
		return
	in_break = true
	_break_t = WarMath.BREAK_SECONDS
	hud.set_wave(wave, true)
	plane.repair(15.0)
	cue("wave_clear", plane.global_position)


func _finish(victory: bool) -> void:
	won = victory
	cue("win" if victory else "loss", head_position())
	if victory:
		for e in enemies.duplicate():
			if e.alive():
				_explode(e)
	_set_phase(Phase.RESULTS)


# --- spawning ---------------------------------------------------------------------------

## Campaign spawns anywhere in the open: planes fly in from `pos` along
## `facing`; ground units stand at `pos` on whatever surface is there.
func spawn_at(kind: String, pos: Vector3, facing: Vector3) -> Enemy:
	var e := Enemy.create(kind)
	e.battle = self
	add_child(e)
	enemies.append(e)
	var f := facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	match kind:
		"fighter", "ace", "transport", "bomber":
			e.enter_through({"center": pos + f * 0.55, "base": Vector3(pos.x, floor_y, pos.z), "normal": f, "width": 1.0, "height": 1.0})
			cue("plane_in", pos, 2.0 if kind == "bomber" else 0.0)
		"balloon":
			var ground := surface_below(pos + Vector3(0, 0.5, 0))
			e.set_meta("height", maxf(0.4, pos.y - ground))
			e.rise_from(Vector3(pos.x, ground, pos.z))
			cue("inflate", pos, -8.0)
		_:
			var g := surface_below(Vector3(pos.x, pos.y + 0.5, pos.z))
			e.global_position = Vector3(pos.x, g, pos.z)
			var flat := Vector3(f.x, 0, f.z)
			if flat.length() > 0.01:
				e.look_at(e.global_position + flat.normalized(), Vector3.UP)
			e.state = Enemy.State.ACTIVE
	return e


## Friendly units the player protects: the escort cargo plane, hangars.
func spawn_friend(kind: String, pos: Vector3, facing: Vector3) -> Enemy:
	var e := Enemy.create(kind)
	e.battle = self
	e.friendly = true
	add_child(e)
	friends.append(e)
	var f := facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	if kind == "cargo":
		e.flight = {"pos": pos, "fwd": f, "speed": 0.5, "bank": 0.0}
		e.global_position = pos
		e.state = Enemy.State.ACTIVE
	else:
		var g := surface_below(Vector3(pos.x, pos.y + 0.5, pos.z))
		e.global_position = Vector3(pos.x, g, pos.z)
		var flat := Vector3(f.x, 0, f.z)
		if flat.length() > 0.01:
			e.look_at(e.global_position + flat.normalized(), Vector3.UP)
		e.state = Enemy.State.ACTIVE
	return e


func damage_friend(e: Enemy, amount: float, at: Vector3) -> void:
	if not e.alive():
		return
	e.hp -= amount
	e.hit_flash = 1.0
	if e.hp <= 0.0:
		e.state = Enemy.State.DEAD
		Fx.explosion(self, e.hit_center(), 0.12)
		cue("boom_big", e.hit_center(), 3.0)
		Fx.mark(self, Vector3(at.x, surface_below(at), at.z), Vector3.UP, 0.35)
		if e.kind == "cargo":
			Debris.from_model(self, e.parts.root, e.velocity * 0.4, e.hit_center(), "cargo")
			friends.erase(e)
			e.queue_free()
		else:
			e.ruin()
	else:
		cue("hit", at, -6.0)


func spawn(kind: String) -> Enemy:
	var e := Enemy.create(kind)
	e.battle = self
	add_child(e)
	enemies.append(e)
	match kind:
		"balloon":
			var s: Dictionary = room.ground_spot(head_position(), _rng.randf() < 0.5)
			var top := _rng.randf_range(floor_y + 1.0, minf(room.ceiling_y - 0.35, floor_y + 1.85))
			e.set_meta("height", maxf(0.4, top - float(s.point.y)))
			e.rise_from(s.point)
			cue("inflate", s.point, -6.0)
		"tank":
			var doors := room.doors()
			var o: Dictionary = doors[_rng.randi() % doors.size()] if not doors.is_empty() else room.openings[0]
			e.enter_through(o)
			cue("tank_in", o.base, -2.0)
		"transport":
			var o2: Dictionary = _pick_air_opening()
			e.enter_through(o2)
			for i in range(2):
				e.drops.append(room.ground_spot(head_position(), true).point)
			cue("plane_in", o2.center)
		_:
			var o3: Dictionary = _pick_air_opening()
			e.enter_through(o3)
			cue("plane_in", o3.center, 2.0 if kind == "bomber" else 0.0)
	return e


func _pick_air_opening() -> Dictionary:
	var air := room.air_openings()
	if air.is_empty():
		air = room.openings
	return air[_rng.randi() % air.size()]


## A supply crate leaves the transport's hatch and floats down on a parachute.
func drop_crate(from: Vector3, target: Vector3) -> void:
	var c := Models.crate()
	add_child(c.root)
	c.root.global_position = from
	(c.chute as Node3D).scale = Vector3.ONE * 0.2
	crates.append({"node": c.root, "chute": c.chute, "target": target, "t": 0.0, "hp": 2.0})


func _step_crates(delta: float) -> void:
	for i in range(crates.size() - 1, -1, -1):
		var c: Dictionary = crates[i]
		c.t += delta
		var n: Node3D = c.node
		var chute: Node3D = c.chute
		chute.scale = Vector3.ONE * minf(1.0, 0.2 + c.t * 2.5)
		var tgt: Vector3 = c.target
		var p := n.global_position
		var fall := 0.9 if c.t < 0.3 else 0.32
		p.y -= fall * delta
		p.x = move_toward(p.x, tgt.x, delta * 0.15)
		p.z = move_toward(p.z, tgt.z, delta * 0.15)
		n.global_position = p
		n.rotation.z = sin(c.t * 2.0) * 0.12
		n.rotation.x = cos(c.t * 1.7) * 0.1
		var ground := room.surface_below(p)
		if p.y <= ground:
			n.queue_free()
			crates.remove_at(i)
			var e := Enemy.create("aa")
			e.battle = self
			add_child(e)
			enemies.append(e)
			var face := head_position() - p
			e.land_at(Vector3(p.x, ground, p.z), face)
			Fx.smoke(self, Vector3(p.x, ground + 0.03, p.z), 0.05)
			cue("thud", p)


# --- firing -------------------------------------------------------------------------------

func player_fire(kind: String, from: Vector3, dir: Vector3, inherit: Vector3, target, spec: Dictionary = {}) -> Shot:
	var s := Shot.make(kind, from, dir, inherit if kind != "bullet" else inherit * 0.5)
	if kind == "bullet":
		s.damage *= plane.gun_damage * float(spec.get("damage", 1.0))
		s.incendiary = bool(spec.get("incendiary", false))
		s.explosive = float(spec.get("explosive", 0.0))
		shots_fired += 1
	s.target = target
	add_child(s)
	shots.append(s)
	return s


func enemy_fire(kind: String, from: Vector3, dir: Vector3, inherit: Vector3 = Vector3.ZERO) -> Shot:
	if phase != Phase.PLAYING or not plane.alive():
		return null
	var s := Shot.make(kind, from, dir, inherit)
	add_child(s)
	shots.append(s)
	s.damage *= enemy_damage
	cue({"ebullet": "enemy_gun", "shell": "cannon", "flak": "flak_fire", "ebomb": "bomb_drop", "sam": "rocket"}[kind], from, -8.0 if kind == "ebullet" else -3.0)
	return s


func _step_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s := shots[i]
		if not is_instance_valid(s):
			shots.remove_at(i)
			continue
		s.step(delta, self)
		if not s.dead:
			_resolve(s)
		if s.dead:
			if s.kind == "rocket" and s.life >= s.max_life:
				Fx.explosion(self, s.global_position, 0.04)
			shots.remove_at(i)
			s.queue_free()


func _resolve(s: Shot) -> void:
	var a := s.prev
	var b := s.global_position
	if s.hostile:
		_resolve_hostile(s, a, b)
		return
	if s.kind == "mine":
		for e in enemies:
			if e.alive() and e.kind in ["fighter", "ace", "diver", "transport", "bomber", "balloon"] and e.hit_center().distance_to(b) < e.radius + 0.07:
				_mine_blast(s)
				return
		return
	if s.kind == "bomb":
		var hit_e = null
		for e in enemies:
			if e.alive() and WarMath.segment_sphere(a, b, e.hit_center(), e.radius) >= 0.0:
				hit_e = e
		var w := wall_hit(a, b)
		if hit_e or not w.is_empty():
			var at: Vector3 = b if hit_e else w.position
			_blast(at, WarMath.BOMB_RADIUS, WarMath.BOMB_DAMAGE, "bomb")
			Fx.explosion(self, at + Vector3(0, 0.03, 0), 0.11)
			if plane.cluster:
				for k in range(4):
					var off := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5)) * 0.3
					var at2: Vector3 = at + off
					at2.y = surface_below(at2 + Vector3(0, 0.3, 0))
					_blast(at2, WarMath.BOMB_RADIUS * 0.6, WarMath.BOMB_DAMAGE * 0.6, "bomb")
					Fx.explosion(self, at2 + Vector3(0, 0.02, 0), 0.06)
			Fx.mark(self, at, w.get("normal", Vector3.UP), 0.32)
			cue("boom_big", at)
			shake(0.6)
			s.dead = true
		return
	var rad := 0.015 if s.kind == "bullet" else 0.03
	var best_t := 2.0
	var best_e = null
	var best_c := -1
	for e in enemies:
		if not e.alive():
			continue
		var t := WarMath.segment_sphere(a, b, e.hit_center(), e.radius + rad)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_e = e
	var best_shot: Shot = null
	if s.kind == "bullet":
		for o in shots:
			if o.dead or not o.can_be_shot():
				continue
			var t3 := WarMath.segment_sphere(a, b, o.global_position, 0.035)
			if t3 >= 0.0 and t3 < best_t:
				best_t = t3
				best_e = null
				best_shot = o
	for ci in range(crates.size()):
		var t2 := WarMath.segment_sphere(a, b, (crates[ci].node as Node3D).global_position + Vector3(0, 0.03, 0), 0.06)
		if t2 >= 0.0 and t2 < best_t:
			best_t = t2
			best_e = null
			best_shot = null
			best_c = ci
	var w := wall_hit(a, b)
	var wall_t := 2.0
	if not w.is_empty():
		wall_t = a.distance_to(w.position) / maxf(1e-6, a.distance_to(b))
	if best_t <= 1.0 and best_t < wall_t:
		var at := a.lerp(b, best_t)
		s.dead = true
		if best_shot:
			best_shot.dead = true
			Fx.explosion(self, best_shot.global_position, 0.05)
			cue("boom_small", at)
			_add_score(60, at)
			return
		if best_c >= 0:
			var c: Dictionary = crates[best_c]
			Fx.explosion(self, (c.node as Node3D).global_position, 0.06)
			cue("boom_small", at)
			(c.node as Node3D).queue_free()
			crates.remove_at(best_c)
			_add_score(75, at)
			return
		if s.kind == "rocket":
			Fx.explosion(self, at, 0.05)
			cue("boom_small", at)
			_blast(at, 0.15, s.damage * 0.4, "rocket", best_e)
			if best_e.alive() and best_e.damage(s.damage, at):
				_kill(best_e, "rocket")
		else:
			shots_hit += 1
			Fx.sparks(self, at, (a - b).normalized(), 3)
			cue("hit", at, -8.0)
			if s.explosive > 0.0:
				Fx.explosion(self, at, 0.03)
				cue("boom_small", at, -6.0)
				_blast(at, s.explosive, s.damage * 0.5, "gun", best_e)
			if s.incendiary and best_e.alive():
				best_e.burn_t = WarMath.BURN_SECONDS
			if best_e.alive() and best_e.damage(s.damage, at):
				_kill(best_e, "gun")
		return
	if not w.is_empty():
		s.dead = true
		if s.kind == "rocket":
			Fx.explosion(self, w.position, 0.05)
			Fx.mark(self, w.position, w.normal, 0.14)
			cue("boom_small", w.position)
			_blast(w.position, 0.18, s.damage * 0.5, "rocket")
		else:
			Fx.sparks(self, w.position, w.normal, 3)
			Fx.mark(self, w.position, w.normal, 0.014, true)
			if _rng.randf() < 0.25:
				cue("ricochet", w.position, -10.0)
		return
	if not WarMath.inside(b, box, 2.5):
		s.dead = true


func _mine_blast(s: Shot) -> void:
	s.dead = true
	var at := s.global_position
	Fx.explosion(self, at, 0.08)
	cue("boom_big", at, -2.0)
	_blast(at, WarMath.MINE_RADIUS, WarMath.MINE_DAMAGE, "mine")


## The Thunderbolt: lightning from the nose jumps between up to four enemies.
func lightning(from: Vector3, forward: Vector3) -> bool:
	var chain: Array = []
	var cur := from
	var reach := WarMath.LIGHTNING_RANGE
	for hop in range(4):
		var best = null
		var best_d := reach
		for e in enemies:
			if not e.alive() or chain.has(e):
				continue
			var d := e.hit_center().distance_to(cur)
			if hop == 0 and forward.dot((e.hit_center() - cur).normalized()) < 0.2:
				d *= 1.6
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			break
		chain.append(best)
		cur = best.hit_center()
		reach = WarMath.LIGHTNING_JUMP
	if chain.is_empty():
		Fx.bolt(self, from, from + forward * 0.8)
		cue("zap", from, -2.0)
		return false
	var prev := from
	var dmg := WarMath.LIGHTNING_DAMAGE
	for e in chain:
		var at: Vector3 = e.hit_center()
		Fx.bolt(self, prev, at)
		Fx.sparks(self, at, Vector3.UP, 6, Color(0.6, 0.85, 1.0))
		prev = at
		if e.alive() and e.damage(dmg, at):
			_kill(e, "lightning")
		dmg *= 0.85
	cue("zap", from, 2.0)
	shake(0.4)
	return true


## SAMs near a barrel roll chase the flares instead.
func flares(at: Vector3) -> void:
	for k in range(8):
		Fx.sparks(self, at, Vector3(randf_range(-1, 1), randf_range(-1.0, 0.2), randf_range(-1, 1)).normalized(), 2, Color(1.0, 0.75, 0.3))
	cue("flare", at, 0.0)
	for s in shots:
		if s.kind == "sam" and s.target == plane and s.global_position.distance_to(at) < WarMath.FLARE_RADIUS:
			s.target = null
			s.velocity = s.velocity.lerp((at + Vector3(0, -0.6, 0) - s.global_position).normalized() * s.velocity.length(), 0.6)
			_add_score(50, s.global_position)


func _resolve_hostile(s: Shot, a: Vector3, b: Vector3) -> void:
	var pp := plane.global_position
	match s.kind:
		"flak":
			if pp.distance_to(b) < 0.18 or (s.fuse > 0.0 and s.life * WarMath.FLAK_SPEED >= s.fuse):
				Fx.flak(self, b)
				cue("flak", b, -2.0)
				var dmg := WarMath.blast_damage(pp.distance_to(b), 0.22, s.damage)
				if dmg > 0.0:
					_hurt_plane(dmg, b)
				s.dead = true
				return
		"shell", "ebomb":
			var hit_plane := plane.alive() and WarMath.segment_sphere(a, b, pp, WarMath.PLANE_RADIUS) >= 0.0
			var w := wall_hit(a, b)
			var hit_friend = _friend_hit(a, b)
			if hit_friend != null and w.is_empty() and not hit_plane:
				w = {"position": b, "normal": Vector3.UP}
			if hit_plane or not w.is_empty():
				var at: Vector3 = b if hit_plane else w.position
				var big := s.kind == "ebomb"
				Fx.explosion(self, at, 0.09 if big else 0.05)
				Fx.mark(self, at, w.get("normal", Vector3.UP), 0.25 if big else 0.1)
				cue("boom_big" if big else "boom_small", at)
				var dmg2 := WarMath.blast_damage(pp.distance_to(at), 0.3 if big else 0.16, s.damage)
				if dmg2 > 0.0:
					_hurt_plane(dmg2, at)
				for f in friends.duplicate():
					var fd := WarMath.blast_damage(f.hit_center().distance_to(at), (0.3 if big else 0.16) + f.radius, WarMath.DIVE_BOMB_DAMAGE if big else s.damage * 0.5)
					if fd > 0.0:
						damage_friend(f, fd, at)
				s.dead = true
			return
	if s.kind == "sam" and s.target != null and plane.rolling() and pp.distance_to(b) < 0.45:
		s.target = null    # a barrel roll at the last moment shakes the missile off
		cue("whoosh", b)
		_add_score(50, b)
	var fh = _friend_hit(a, b)
	if fh != null:
		s.dead = true
		Fx.sparks(self, b, (a - b).normalized(), 3, Color(1.0, 0.5, 0.3))
		damage_friend(fh, s.damage * 0.3, b)
		return
	if plane.alive() and WarMath.segment_sphere(a, b, pp, WarMath.PLANE_RADIUS + (0.03 if s.kind == "sam" else 0.0)) >= 0.0:
		s.dead = true
		if s.kind == "sam":
			Fx.explosion(self, b, 0.06)
			cue("boom_small", b)
		_hurt_plane(s.damage, b)
		Fx.sparks(self, b, (a - b).normalized(), 4, Color(1.0, 0.5, 0.3))
		return
	var w2 := wall_hit(a, b)
	if not w2.is_empty():
		s.dead = true
		if s.kind == "sam":
			Fx.explosion(self, w2.position, 0.06)
			Fx.mark(self, w2.position, w2.normal, 0.12)
			cue("boom_small", w2.position)
		Fx.sparks(self, w2.position, w2.normal, 2)
		Fx.mark(self, w2.position, w2.normal, 0.012, true)
		return
	if not WarMath.inside(b, box, 2.5):
		s.dead = true


func _friend_hit(a: Vector3, b: Vector3):
	for f in friends:
		if f.alive() and WarMath.segment_sphere(a, b, f.hit_center(), f.radius) >= 0.0:
			return f
	return null


func _hurt_plane(amount: float, at: Vector3) -> void:
	if not plane.alive():
		return
	plane.take_hit(amount)
	cue("player_hit", at, -2.0)
	streak = 0
	hud.set_combo(1.0)
	shake(0.35)


func _blast(at: Vector3, radius: float, damage: float, weapon: String, skip = null) -> void:
	for e in enemies.duplicate():
		if e == skip or not e.alive():
			continue
		var dmg := WarMath.blast_damage(e.hit_center().distance_to(at), radius + e.radius, damage)
		if dmg > 0.0 and e.damage(dmg, at):
			_kill(e, weapon)


func _kill(e: Enemy, weapon: String) -> void:
	if e.kind != "balloon":
		kills += 1
	streak += 1
	_combo_t = WarMath.COMBO_WINDOW
	var mult := WarMath.combo(streak)
	hud.set_combo(mult)
	_add_score(WarMath.points(e.kind, mult, weapon), e.hit_center(), e.kind == "bomber")
	if e.kind in ["fighter", "ace", "tank", "aa", "transport", "truck"] and _rng.randf() < 0.18:
		_drop_repair(e.hit_center())
	if campaign:
		campaign.on_killed(e)
	if e.kind in ["fighter", "ace", "transport", "diver"]:
		# Shot-down planes spiral to the floor trailing smoke.
		plane.locks.erase(e)
		Fx.explosion(self, e.hit_center(), 0.04)
		cue("engine_die", e.hit_center(), -4.0)
		e.start_fall()
		return
	_explode(e)


func on_wreck_landed(e: Enemy) -> void:
	_explode(e)


func _explode(e: Enemy) -> void:
	e.state = Enemy.State.DEAD
	var at := e.hit_center()
	match e.kind:
		"balloon":
			Fx.explosion(self, at, 0.05)
			cue("pop", at)
		"fighter", "ace", "diver", "transport":
			Fx.explosion(self, at, 0.1)
			Fx.mark(self, Vector3(at.x, surface_below(at), at.z), Vector3.UP, 0.25)
			cue("boom_big", at)
			Debris.from_model(self, e.parts.root, e.velocity * 0.4, at, e.kind)
		"bomber":
			for i in range(5):
				Fx.explosion(self, at + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.3, 0.3)), 0.12)
			Debris.from_model(self, e.parts.root, e.velocity * 0.3, at, "bomber")
			Fx.explosion(self, at, 0.25)
			cue("boom_big", at, 6.0)
			shake(1.0)
		"tank", "aa", "truck", "sam":
			Fx.explosion(self, at, 0.1 if e.kind != "sam" else 0.07)
			Fx.mark(self, Vector3(at.x, surface_below(at), at.z), Vector3.UP, 0.3)
			cue("boom_big", at)
			if e.kind == "truck":
				# The crew jumps out and runs for cover.
				for i in range(2):
					var sd := spawn_at("soldier", e.global_position + Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.06, 0.06)), Vector3.FORWARD)
					var a := _rng.randf() * TAU
					sd.run_to = sd.global_position + Vector3(cos(a), 0, sin(a)) * 0.4
		"soldier":
			Fx.smoke(self, at, 0.03)
			Fx.sparks(self, at, Vector3.UP, 4, Color(1.0, 0.8, 0.3))
			cue("pop", at, -6.0)
		"radar":
			Fx.explosion(self, at, 0.14)
			Fx.explosion(self, at + Vector3(0, 0.12, 0), 0.08)
			cue("boom_big", at, 3.0)
			shake(0.6)
		"fuel":
			Fx.explosion(self, at, 0.18)
			Fx.mark(self, Vector3(at.x, surface_below(at), at.z), Vector3.UP, 0.45)
			cue("boom_big", at, 4.0)
			shake(0.8)
			# Chain reaction: neighbours within 50 cm catch the blast.
			call_deferred("_blast", at, 0.5, 10.0, "bomb", e)
		_:
			Fx.explosion(self, at, 0.08)
			cue("boom_big", at)
	plane.locks.erase(e)
	enemies.erase(e)
	e.queue_free()


func _add_score(points: int, at: Vector3, big: bool = false) -> void:
	score += points
	hud.set_score(score)
	hud.popup(at, points, big)


func _step_burns(delta: float) -> void:
	for e in enemies.duplicate():
		if e.burn_t <= 0.0 or not e.alive():
			continue
		e.burn_t -= delta
		e.set_meta("burn_fx", float(e.get_meta("burn_fx", 0.0)) - delta)
		if float(e.get_meta("burn_fx")) <= 0.0:
			e.set_meta("burn_fx", 0.07)
			Fx.flame(self, e.hit_center() + Vector3(randf_range(-0.03, 0.03), 0.01, randf_range(-0.03, 0.03)), e.radius * 0.25)
		if e.damage(WarMath.BURN_DPS * delta, Vector3.INF):
			_kill(e, "gun")


## A homing missile closing on the plane: wrist warning + quick beeps.
func _missile_warning(delta: float) -> void:
	var closest := INF
	for s in shots:
		if s.kind == "sam" and s.target == plane and not s.dead:
			closest = minf(closest, s.global_position.distance_to(plane.global_position))
	hud.set_missile(closest < 2.5)
	if closest < 2.5:
		_warn_t -= delta
		if _warn_t <= 0.0:
			_warn_t = clampf(closest * 0.12, 0.06, 0.3)
			cue("warning", plane.global_position, -4.0)
		if closest < 1.6 and _callout_t <= 0.0:
			callout(Lang.t("missile_warn"), Color(1.0, 0.3, 0.2), 1.0)


# --- pickups ----------------------------------------------------------------------------

func _drop_repair(at: Vector3) -> void:
	var p := Node3D.new()
	Toon.add(p, Toon.block(Vector3(0.06, 0.045, 0.045)), Toon.mat(Color(0.3, 0.75, 0.3), 0.4, 0.0018))
	Toon.add(p, Toon.block(Vector3(0.036, 0.01, 0.047)), Toon.mat(Models.WHITE, 0.3, 0.0))
	Toon.add(p, Toon.block(Vector3(0.01, 0.034, 0.047)), Toon.mat(Models.WHITE, 0.3, 0.0))
	p.set_meta("life", 0.0)
	add_child(p)
	p.global_position = WarMath.clamp_into(at, box, 0.3, 0.5)
	pickups.append(p)


func _step_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		var life: float = p.get_meta("life") + delta
		p.set_meta("life", life)
		p.rotate_y(delta * 2.0)
		p.global_position.y += sin(life * 3.0) * 0.02 * delta
		if phase == Phase.PLAYING and plane.alive() and p.global_position.distance_to(plane.global_position) < 0.16:
			plane.repair(25.0)
			cue("pickup", p.global_position)
			_add_score(20, p.global_position)
			p.queue_free()
			pickups.remove_at(i)
		elif life > 15.0:
			p.queue_free()
			pickups.remove_at(i)


func _update_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	for i in range(_lock_marks.size()):
		var m := _lock_marks[i]
		if i < plane.locks.size() and is_instance_valid(plane.locks[i]):
			var e: Enemy = plane.locks[i]
			m.visible = true
			m.global_position = e.hit_center()
			if cam:
				m.look_at(cam.global_position, Vector3.UP)
			m.scale = Vector3.ONE * e.radius * 1.3
			m.rotate_object_local(Vector3.FORWARD, Time.get_ticks_msec() * 0.004)
		else:
			m.visible = false
	# Bomb impact ring while there are ground targets.
	_bomb_ring.visible = phase == Phase.PLAYING and plane.airborne() and plane.bombs > 0 and has_ground_units()
	if _bomb_ring.visible:
		var p := plane.global_position
		var ground := surface_below(p)
		var hit := WarMath.bomb_impact(p, plane.velocity, ground, WarMath.GRAVITY * 0.85)
		ground = surface_below(Vector3(hit.x, p.y, hit.z))
		hit = WarMath.bomb_impact(p, plane.velocity, ground, WarMath.GRAVITY * 0.85)
		_bomb_ring.global_position = hit + Vector3(0, 0.004, 0)
		_bomb_ring.global_basis = Basis.IDENTITY


# --- menu and results ----------------------------------------------------------------------

func _clear_ui() -> void:
	if _ui_root and is_instance_valid(_ui_root):
		_ui_root.queue_free()
	_ui_root = null
	_buttons.clear()


func _ui_at(pos: Vector3) -> Node3D:
	_ui_root = Node3D.new()
	add_child(_ui_root)
	_ui_root.global_position = pos
	var to := head_position() - pos
	to.y = 0.0
	if to.length() > 0.05:
		_ui_root.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)
	return _ui_root


func _add_button(parent: Node3D, kind: String, color: Color, r: float, pos: Vector3, action: Callable) -> UI.Button3D:
	var b := UI.Button3D.new(kind, color, r)
	b.position = pos
	b.set_meta("action", action)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _build_menu() -> void:
	var root := _ui_at(park_spot + Vector3(0, 0.6, 0))
	_add_button(root, "play", Color(0.25, 0.75, 0.3), 0.085, Vector3.ZERO, start_match)
	var best := int(save.get("best", 0))
	if best > 0:
		var l := UI.number(str(best), 110, Color(1, 0.85, 0.2))
		l.position = Vector3(0, 0.15, 0)
		root.add_child(l)
	var stars := int(save.get("stars", 0))
	for i in range(3):
		var st := UI.icon("star", Color(1, 0.8, 0.15) if i < stars else Color(0.45, 0.45, 0.45), 0.05, 0.006)
		st.position = Vector3(-0.065 + i * 0.065, -0.14, 0)
		root.add_child(st)


func finish_campaign() -> void:
	_finish(true)


func _build_results() -> void:
	var fwd := -head.global_basis.z if head else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var root := _ui_at(head_position() + fwd * 1.1 + Vector3(0, -0.1, 0))
	var stars := WarMath.stars(plane.hp / WarMath.PLANE_HP, won)
	if campaign:
		stars = clampi(int(round(campaign.total_stars() / 5.0)), 0, 3)
	var record := score > int(save.get("best", 0))
	save["best"] = maxi(int(save.get("best", 0)), score)
	save["stars"] = maxi(int(save.get("stars", 0)), stars)
	_store()
	var l := UI.number(str(score), 200, Color(1, 0.85, 0.2) if record else Color(1, 1, 1))
	l.position = Vector3(0, 0.2, 0)
	root.add_child(l)
	for i in range(3):
		var st := UI.icon("star", Color(1, 0.8, 0.15) if i < stars else Color(0.45, 0.45, 0.45), 0.07, 0.008)
		st.position = Vector3(-0.09 + i * 0.09, 0.05, 0)
		root.add_child(st)
	_add_button(root, "retry", Color(0.25, 0.75, 0.3), 0.075, Vector3(-0.11, -0.12, 0), start_match)
	_add_button(root, "home", Color(0.3, 0.55, 0.9), 0.06, Vector3(0.11, -0.12, 0), func(): _set_phase(Phase.MENU))


func _clear_battlefield() -> void:
	if campaign:
		campaign.clear()
		campaign.queue_free()
		campaign = null
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for f in friends:
		if is_instance_valid(f):
			f.queue_free()
	friends.clear()
	Debris.clear_all()
	_callout_t = 0.0
	for s in shots:
		s.queue_free()
	shots.clear()
	for c in crates:
		(c.node as Node3D).queue_free()
	crates.clear()
	for p in pickups:
		p.queue_free()
	pickups.clear()
	hud.clear_popups()
	Fx.clear_marks()


func _load() -> void:
	save = {}
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				save = parsed


func _store() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
