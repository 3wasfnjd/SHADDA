class_name BattleDirector
extends Node3D
## The match: room → menu → five waves (the fifth a boss gunship) → results.
## Owns every enemy, shot, hangar and pickup; resolves all hits exactly.
## Everything hostile comes out of the room's real walls and floor.

enum Phase { SCANNING, MENU, PLAYING, RESULTS }

signal phase_changed(phase: int)

var phase: Phase = Phase.SCANNING
var head: Node3D
var jet: PlayerJet
var hud: WristHud
var audio: GameAudio
var save := SaveData.new()
var floor_y: float = 0.0
var box: Dictionary = {"min": Vector3(-1.6, 0, -1.6), "max": Vector3(1.6, 2.5, 1.6)}
var use_box_walls: bool = true
var mounts: Array = []
var hangars: Array[Hangar] = []         # air bays
var bays: Array[Hangar] = []            # ground bays
var boss_bay: Hangar = null
var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var pickups: Array[Node3D] = []
var wave: int = 0
var in_break: bool = false
var score: int = 0
var streak: int = 0
var won: bool = false
var auto_spawn: bool = true
var _queue: Array = []
var _spawn_timer: float = 0.0
var _phase_time: float = 0.0
var _break_timer: float = 0.0
var _combo_timer: float = 0.0
var _end_timer: float = -1.0
var _menu_root: Node3D
var _results_root: Node3D
var _buttons: Array = []
var _trigger_was: float = 0.0
var _lock_marks: Array[Node3D] = []
var _laser_scorch: float = 0.0
var _warn_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func build(player_head: Node3D, player_jet: PlayerJet, wrist: WristHud) -> void:
	head = player_head
	jet = player_jet
	jet.battle = self
	jet.weapons_live = false
	hud = wrist
	hud.world = self
	audio = GameAudio.new()
	add_child(audio)
	save.path = "user://saqr.json"
	save.load_file()
	_rng.randomize()
	for i in range(CombatMath.MISSILE_LOCKS):
		var mark := _make_lock_mark()
		add_child(mark)
		mark.visible = false
		_lock_marks.append(mark)


# --- room ---------------------------------------------------------------------

func on_room_ready(room_mounts: Array, room_floor_y: float, found_anything: bool) -> void:
	floor_y = room_floor_y
	mounts = room_mounts.duplicate()
	var center := head.global_position if head else Vector3.ZERO
	box = CombatMath.room_box(mounts, floor_y, center)
	var walls := mounts.filter(func(m): return m.kind != "ceiling")
	use_box_walls = not found_anything or walls.size() < 2 or not _has_room_colliders()
	if walls.size() < 2:
		mounts = _virtual_walls()
		walls = mounts
	_build_hangars(walls)
	_set_phase(Phase.MENU)


func _has_room_colliders() -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(head.global_position, head.global_position + Vector3(0, -3, 0), 1)
	return not space.intersect_ray(q).is_empty()


## Four walls on the edges of the fallback box (rooms without scene data).
func _virtual_walls() -> Array:
	var lo: Vector3 = box.min
	var hi: Vector3 = box.max
	var c := (lo + hi) * 0.5
	return [
		{"origin": Vector3(c.x, floor_y, lo.z), "normal": Vector3(0, 0, 1), "width": hi.x - lo.x, "height": 2.4, "kind": "wall"},
		{"origin": Vector3(hi.x, floor_y, c.z), "normal": Vector3(-1, 0, 0), "width": hi.z - lo.z, "height": 2.4, "kind": "wall"},
		{"origin": Vector3(lo.x, floor_y, c.z), "normal": Vector3(1, 0, 0), "width": hi.z - lo.z, "height": 2.4, "kind": "wall"},
		{"origin": Vector3(c.x, floor_y, hi.z), "normal": Vector3(0, 0, -1), "width": hi.x - lo.x, "height": 2.4, "kind": "wall"},
	]


func _build_hangars(walls: Array) -> void:
	for h in hangars + bays:
		h.queue_free()
	hangars.clear()
	bays.clear()
	# Prefer the walls the player is facing; spread bays over different walls.
	var fwd := -head.global_basis.z if head else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var hp := head.global_position if head else Vector3.ZERO
	var ranked := walls.duplicate()
	ranked.sort_custom(func(a, b):
		var da: float = (a.origin - hp).normalized().dot(fwd)
		var db: float = (b.origin - hp).normalized().dot(fwd)
		return da > db)
	for m in ranked:
		if hangars.size() >= 3:
			break
		if float(m.width) < 0.6 or float(m.get("height", 2.4)) < 1.6:
			continue
		var h := Hangar.create(false)
		add_child(h)
		h.mount(_wall_point(m, 0.0), m.normal, 1.3)
		h.set_meta("mount", m)
		hangars.append(h)
	for m in ranked:
		if bays.size() >= 2:
			break
		if float(m.width) < 1.2:
			continue
		var b := Hangar.create(true)
		add_child(b)
		var shift := 0.5 if bays.size() == 0 else -0.5
		b.mount(_wall_point(m, shift), m.normal, b.height * 0.5)
		bays.append(b)
	if hangars.is_empty() and not ranked.is_empty():
		var m0: Dictionary = ranked[0]
		var h0 := Hangar.create(false)
		add_child(h0)
		h0.mount(_wall_point(m0, 0.0), m0.normal, 1.3)
		hangars.append(h0)


## A point on a wall mount at floor level, `along` metres from its centre.
func _wall_point(m: Dictionary, along: float) -> Vector3:
	var n: Vector3 = m.normal
	var side := Vector3(-n.z, 0, n.x)
	var p: Vector3 = m.origin + side * along
	p.y = floor_y
	return p


# --- queries used by enemies and the jet -----------------------------------------

func head_position() -> Vector3:
	return head.global_position if head else Vector3(0, 1.6, 0)


func box_center() -> Vector3:
	return ((box.min as Vector3) + (box.max as Vector3)) * 0.5


func jet_position() -> Vector3:
	return jet.global_position


func jet_velocity() -> Vector3:
	return jet.velocity


func has_ground_units() -> bool:
	for e in enemies:
		if e.kind == "tank" and e.alive():
			return true
	return false


## First thing along a ray: an enemy (sphere), a real wall/floor (physics),
## or the room box when there is no scene data.
## Returns {distance, enemy, wall: bool, normal}.
func ray_scene(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var best := max_dist
	var hit_enemy = null
	var wall := false
	var normal := Vector3.ZERO
	for e in enemies:
		if not e.alive():
			continue
		var d := CombatMath.ray_sphere(origin, dir, e.hit_center(), e.radius)
		if d < best:
			best = d
			hit_enemy = e
	var w := _wall_hit(origin, origin + dir * best)
	if not w.is_empty():
		best = origin.distance_to(w.position)
		hit_enemy = null
		wall = true
		normal = w.normal
	return {"distance": best, "enemy": hit_enemy, "wall": wall, "normal": normal}


## Segment against the real room (physics layer 1) and, when the room has no
## scene data, against the box. Returns {} or {position, normal}.
func _wall_hit(a: Vector3, b: Vector3) -> Dictionary:
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			return {"position": r.position, "normal": r.normal}
	if b.y < floor_y and a.y >= floor_y:
		var t := (a.y - floor_y) / maxf(1e-6, a.y - b.y)
		return {"position": a.lerp(b, t), "normal": Vector3.UP}
	if use_box_walls:
		var lo: Vector3 = box.min
		var hi: Vector3 = box.max
		var best_t := 2.0
		var n := Vector3.ZERO
		var d := b - a
		for axis: int in [0, 1, 2]:
			if absf(d[axis]) < 1e-7:
				continue
			for face in [lo[axis], hi[axis]]:
				if axis == 1 and face == lo[axis]:
					continue   # floor handled above
				var t: float = (face - a[axis]) / d[axis]
				if t < 0.0 or t > 1.0 or t >= best_t:
					continue
				# Only count exits (moving outward through the face).
				if (face == hi[axis] and d[axis] > 0.0) or (face == lo[axis] and d[axis] < 0.0):
					best_t = t
					n = Vector3.ZERO
					n[axis] = -signf(d[axis])
		if best_t <= 1.0:
			return {"position": a + d * best_t, "normal": n}
	return {}


# --- firing -------------------------------------------------------------------------

func player_fire(kind: String, from: Vector3, dir: Vector3, inherit: Vector3, target) -> Shot:
	var s := Shot.make(kind, from, dir, inherit if kind != "bullet" else inherit * 0.3)
	s.target = target
	add_child(s)
	shots.append(s)
	return s


func enemy_fire(kind: String, from: Vector3, dir: Vector3, target) -> Shot:
	if phase != Phase.PLAYING or jet.destroyed:
		return null
	var s := Shot.make(kind, from, dir)
	s.target = target
	add_child(s)
	shots.append(s)
	cue("enemy_missile" if kind == "emissile" else ("flak" if kind == "flak" else "enemy_shot"), from, -6.0)
	return s


func cue(name: String, at: Vector3, db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, at, db)


func smoke_puff(at: Vector3, s: float) -> void:
	Fx.smoke(self, at, s)


func laser_hit(e: Enemy, dmg: float, point: Vector3) -> void:
	if e.damage(dmg):
		_kill(e, "laser")
	elif Engine.get_physics_frames() % 4 == 0:
		Fx.sparks(self, point, (jet.global_position - point).normalized(), Color(0.6, 0.95, 1.0), 2)


func laser_burn(point: Vector3, normal: Vector3, delta: float) -> void:
	_laser_scorch -= delta
	if Engine.get_physics_frames() % 5 == 0:
		Fx.sparks(self, point, normal, Color(0.6, 0.95, 1.0), 2)
	if _laser_scorch <= 0.0:
		_laser_scorch = 0.12
		Fx.scorch(self, point, normal, 0.025)


# --- input ----------------------------------------------------------------------------

func on_button(action: StringName, hand_index: int) -> void:
	match phase:
		Phase.MENU:
			if action == &"ax_button":
				start_match()
		Phase.PLAYING:
			if hand_index == 1 and action == &"ax_button":
				jet.drop_bomb()
			elif hand_index == 1 and action == &"by_button":
				jet.pop_flares()
			elif hand_index == 0 and action == &"ax_button":
				jet.pop_flares()
			elif hand_index == 0 and action == &"by_button":
				jet.drop_bomb()
		Phase.RESULTS:
			if _phase_time < 1.0:
				return
			if action == &"ax_button":
				start_match()
			elif action == &"by_button":
				_set_phase(Phase.MENU)


## Called by the bootstrap every frame with the right-hand aim pose already applied to the jet.
func update_controls(delta: float, trigger_r: float, grip_r: float, trigger_l: float) -> void:
	jet.control(delta, trigger_r, grip_r, trigger_l)
	# Aim-and-pull buttons in the menu and results.
	var pressed := trigger_r > 0.6 and _trigger_was <= 0.6
	_trigger_was = trigger_r
	for b in _buttons:
		if not is_instance_valid(b) or not b.is_visible_in_tree():
			continue
		var d: float = b.ray_distance(jet.nose(), jet.forward())
		b.hovered = move_toward(b.hovered, 1.0 if d < b.radius * 1.4 else 0.0, delta * 6.0)
		if pressed and d < b.radius * 1.4 and _phase_time > 0.6:
			b.pressed_flash = 1.0
			b.get_meta("action").call()
			break


# --- phases ----------------------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	phase = p
	_phase_time = 0.0
	_clear_ui()
	match p:
		Phase.MENU:
			jet.weapons_live = false
			jet.reset()
			hud.visible = false
			_build_menu()
			audio.play_music("menu")
		Phase.RESULTS:
			jet.weapons_live = false
			_build_results()
			audio.play_music("menu")
	phase_changed.emit(p)


func start_match() -> void:
	_clear_battlefield()
	jet.reset()
	jet.weapons_live = true
	score = 0
	streak = 0
	won = false
	wave = 0
	_end_timer = -1.0
	hud.visible = true
	hud.set_score(0)
	hud.set_combo(1.0)
	_set_phase(Phase.PLAYING)
	_begin_wave(0)
	audio.play_music("battle")


func _begin_wave(index: int) -> void:
	wave = index
	in_break = false
	_queue.clear()
	var spec: Dictionary = CombatMath.WAVES[index]
	# Targets first (they pop out fast), then the rest interleaved.
	for i in range(int(spec.get("target", 0))):
		_queue.append("target")
	var rest: Array = []
	for k in ["boss", "tank", "fighter", "drone"]:
		for i in range(int(spec.get(k, 0))):
			rest.append(k)
	if spec.has("boss"):
		_queue.append_array(rest)
		_prepare_boss_bay()
		audio.play_music("boss")
	else:
		rest.shuffle()
		_queue.append_array(rest)
	_spawn_timer = 0.8
	hud.set_wave(wave, false)


func _prepare_boss_bay() -> void:
	if boss_bay:
		return
	var best = null
	for m in mounts:
		if m.kind == "ceiling" or float(m.get("height", 2.4)) < 1.9:
			continue
		if best == null or float(m.width) > float(best.width):
			best = m
	if best == null:
		best = mounts[0]
	boss_bay = Hangar.create(false, true)
	add_child(boss_bay)
	# Beside the regular bay on that wall when there is room, otherwise centred higher.
	var along := 0.0
	for h in hangars:
		if h.has_meta("mount") and h.get_meta("mount") == best:
			along = 0.75 if float(best.width) >= 2.4 else 0.0
	boss_bay.mount(_wall_point(best, along), best.normal, 1.45 if along != 0.0 else 1.62)


func _process(delta: float) -> void:
	_phase_time += delta


func _physics_process(delta: float) -> void:
	if phase == Phase.SCANNING:
		return
	_step_shots(delta)
	for e in enemies:
		if e.alive():
			e.tick(delta)
	_step_pickups(delta)
	_update_lock_marks()
	if phase != Phase.PLAYING:
		return
	hud.set_jet(jet)
	_combo_timer -= delta
	if _combo_timer <= 0.0 and streak > 0:
		streak = 0
		hud.set_combo(1.0)
	var incoming := false
	for s in shots:
		if s.kind == "emissile" and not s.dead and s.target == jet:
			incoming = true
	hud.set_warning(incoming)
	if incoming:
		_warn_timer -= delta
		if _warn_timer <= 0.0:
			_warn_timer = 0.45
			cue("warning", jet.global_position, -8.0)
	if jet.destroyed:
		if _end_timer < 0.0:
			_end_timer = 2.2
			Fx.explosion(self, jet.global_position, 0.12)
			cue("boom_big", jet.global_position)
		_end_timer -= delta
		if _end_timer <= 0.0:
			_finish(false)
		return
	if in_break:
		_break_timer -= delta
		if _break_timer <= 0.0:
			_begin_wave(wave + 1)
		return
	if auto_spawn:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and not _queue.is_empty() and _alive_count() < 6:
			var k: String = _queue.pop_front()
			spawn(k)
			_spawn_timer = 0.3 if k == "target" else _rng.randf_range(1.0, 1.6)
	if _queue.is_empty() and _alive_count() == 0 and _phase_time > 0.5:
		_wave_cleared()


func _alive_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive():
			n += 1
	return n


func _wave_cleared() -> void:
	if wave >= CombatMath.WAVES.size() - 1:
		_finish(true)
		return
	in_break = true
	_break_timer = CombatMath.BREAK_SECONDS
	hud.set_wave(wave, true)
	cue("wave_clear", jet.global_position)
	jet.repair(15.0)


func _finish(victory: bool) -> void:
	won = victory
	cue("win" if victory else "loss", head_position())
	for e in enemies:
		if e.alive():
			if victory:
				_explode_enemy(e)
	_set_phase(Phase.RESULTS)


# --- spawning ---------------------------------------------------------------------------

func spawn(kind: String) -> Enemy:
	var e := Enemy.create(kind)
	e.battle = self
	add_child(e)
	enemies.append(e)
	match kind:
		"target":
			_place_target(e)
		"tank":
			var bay: Hangar = bays[_rng.randi() % bays.size()] if not bays.is_empty() else hangars[0]
			bay.request_open(2.2)
			var from := bay.inside_point()
			from.y = floor_y
			var to := bay.exit_point(0.3)
			to.y = floor_y
			e.hangar = bay
			e.emerge(from, to, bay.room_normal())
		"boss":
			_prepare_boss_bay()
			boss_bay.request_open(4.0)
			e.hangar = boss_bay
			e.emerge(boss_bay.global_transform * Vector3(0, 0, -0.45), boss_bay.exit_point(0.75), boss_bay.room_normal())
			cue("hangar_open", boss_bay.global_position, 4.0)
		_:
			var h: Hangar = hangars[_rng.randi() % hangars.size()]
			h.request_open(1.8)
			e.hangar = h
			e.emerge(h.inside_point(), h.exit_point(0.45), h.room_normal())
			cue("hangar_open", h.global_position)
	return e


func _place_target(e: Enemy) -> void:
	var walls := mounts.filter(func(m): return m.kind != "ceiling")
	var spot := Vector3.ZERO
	var normal := Vector3.BACK
	for attempt in range(16):
		var m: Dictionary = walls[_rng.randi() % walls.size()]
		var half := maxf(0.0, float(m.width) * 0.5 - 0.25)
		var p := _wall_point(m, _rng.randf_range(-half, half))
		p.y = floor_y + _rng.randf_range(0.95, minf(1.85, float(m.get("height", 2.4)) - 0.25))
		var clear := true
		for h in hangars + bays:
			if h.global_position.distance_to(p) < 0.5:
				clear = false
		for other in enemies:
			if other != e and other.kind == "target" and other.alive() and other.global_position.distance_to(p) < 0.35:
				clear = false
		spot = p
		normal = m.normal
		if clear:
			break
	e.global_position = spot
	e.look_at(spot - normal, Vector3.UP)
	e.wall_normal = normal
	e.state = Enemy.State.EMERGE
	e.age = 0.0
	cue("target_pop", spot, -4.0)


# --- shots and hits -------------------------------------------------------------------

func _step_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s := shots[i]
		if not is_instance_valid(s):
			shots.remove_at(i)
			continue
		if s.kind == "emissile":
			_lure(s)
		s.step(delta)
		if not s.dead:
			_resolve(s)
		if s.dead:
			if s.kind in ["missile", "bomb", "emissile"] and s.life >= s.max_life:
				Fx.explosion(self, s.global_position, 0.03)
			shots.remove_at(i)
			s.queue_free()


## Enemy missiles chase the nearest live flare that comes close.
func _lure(m: Shot) -> void:
	if m.target is Shot and is_instance_valid(m.target) and not (m.target as Shot).dead:
		return
	var best: Shot = null
	var best_d := CombatMath.FLARE_LURE
	for f in shots:
		if f.kind != "flare" or f.dead:
			continue
		var d := f.global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = f
	if best:
		m.target = best
	elif not is_instance_valid(m.target) or (m.target is Shot):
		m.target = jet


func _resolve(s: Shot) -> void:
	var a := s.prev
	var b := s.global_position
	if s.hostile:
		_resolve_enemy_shot(s, a, b)
		return
	match s.kind:
		"flare":
			return
		"bomb":
			var hit_floor := b.y <= floor_y + 0.005
			var hit_unit = null
			for e in enemies:
				if e.alive() and CombatMath.segment_sphere(a, b, e.hit_center(), e.radius) >= 0.0:
					hit_unit = e
			var w := {} if hit_floor or hit_unit else _wall_hit(a, b)
			if hit_floor or hit_unit or not w.is_empty():
				var at: Vector3 = Vector3(b.x, floor_y, b.z) if hit_floor else (b if hit_unit else w.position)
				_blast(at, CombatMath.BOMB_RADIUS, CombatMath.BOMB_DAMAGE, "bomb")
				Fx.explosion(self, at + Vector3(0, 0.03, 0), 0.09)
				Fx.scorch(self, at, Vector3.UP if hit_floor else (w.get("normal", Vector3.UP)), 0.3)
				cue("boom_big", at)
				s.dead = true
			return
	# Bullets and missiles: closest hit along the segment.
	var best_t := 2.0
	var best_e = null
	var best_shot: Shot = null
	var rad := 0.0 if s.kind == "bullet" else 0.03     # missile proximity fuse
	for e in enemies:
		if not e.alive():
			continue
		var t := CombatMath.segment_sphere(a, b, e.hit_center(), e.radius + rad)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_e = e
	if s.kind == "bullet":
		for o in shots:
			if o.dead or not o.can_be_shot():
				continue
			var t2 := CombatMath.segment_sphere(a, b, o.global_position, o.radius)
			if t2 >= 0.0 and t2 < best_t:
				best_t = t2
				best_e = null
				best_shot = o
	var w := _wall_hit(a, b)
	var wall_t := 2.0
	if not w.is_empty():
		wall_t = a.distance_to(w.position) / maxf(1e-6, a.distance_to(b))
	if best_t <= 1.0 and best_t < wall_t:
		var at := a.lerp(b, best_t)
		s.dead = true
		if best_shot:
			best_shot.dead = true
			Fx.explosion(self, best_shot.global_position, 0.035)
			cue("boom_small", at)
			_add_score(25, at, Color(1.0, 0.85, 0.3))
			return
		if s.kind == "missile":
			Fx.explosion(self, at, 0.045)
			cue("boom_small", at)
			_blast(at, 0.18, s.damage * 0.4, "missile", best_e)
			if best_e.alive() and best_e.damage(s.damage):
				_kill(best_e, "missile")
		else:
			Fx.sparks(self, at, (a - b).normalized(), Color(1.0, 0.85, 0.4), 3)
			cue("hit", at, -10.0)
			if best_e.damage(s.damage):
				_kill(best_e, "cannon")
		return
	if not w.is_empty():
		s.dead = true
		if s.kind == "missile":
			Fx.explosion(self, w.position, 0.04)
			Fx.scorch(self, w.position, w.normal, 0.12)
			cue("boom_small", w.position)
			_blast(w.position, 0.2, s.damage * 0.5, "missile")
		else:
			Fx.sparks(self, w.position, w.normal, Color(1.0, 0.75, 0.35), 4)
			Fx.scorch(self, w.position, w.normal, 0.018)
			if _rng.randf() < 0.3:
				cue("ricochet", w.position, -12.0)
		return
	if not CombatMath.inside(b, box, 3.0):
		s.dead = true


func _resolve_enemy_shot(s: Shot, a: Vector3, b: Vector3) -> void:
	var jp := jet.global_position
	if s.kind == "flak":
		var close := jp.distance_to(b) < 0.2
		if close or (s.fuse > 0.0 and s.life * s.speed >= s.fuse + 0.15):
			Fx.explosion(self, b, 0.035, Color(1.0, 0.7, 0.3))
			cue("flak_burst", b, -4.0)
			var dmg := CombatMath.blast_damage(jp.distance_to(b), 0.24, s.damage)
			if dmg > 0.0 and not jet.destroyed:
				jet.take_hit(dmg)
			s.dead = true
			return
	elif s.kind == "emissile" and s.target is Shot and is_instance_valid(s.target):
		# Chasing a flare: detonate on it.
		if b.distance_to((s.target as Shot).global_position) < 0.06:
			Fx.explosion(self, b, 0.04)
			cue("boom_small", b)
			(s.target as Shot).dead = true
			s.dead = true
			_add_score(30, b, Color(1.0, 0.7, 0.3))
			return
	if not jet.destroyed and CombatMath.segment_sphere(a, b, jp, CombatMath.JET_RADIUS + s.radius) >= 0.0:
		s.dead = true
		jet.take_hit(s.damage)
		Fx.explosion(self, b, 0.03 if s.kind != "emissile" else 0.05, Color(1.0, 0.4, 0.2))
		cue("player_hit", b)
		streak = 0
		hud.set_combo(1.0)
		return
	var w := _wall_hit(a, b)
	if not w.is_empty():
		s.dead = true
		Fx.sparks(self, w.position, w.normal, Color(1.0, 0.3, 0.2), 3)
		if s.kind == "emissile":
			Fx.explosion(self, w.position, 0.04)
			Fx.scorch(self, w.position, w.normal, 0.1)
		return
	if not CombatMath.inside(b, box, 3.0):
		s.dead = true


func _blast(at: Vector3, radius: float, damage: float, weapon: String, skip = null) -> void:
	for e in enemies.duplicate():
		if e == skip or not e.alive():
			continue
		var dmg := CombatMath.blast_damage(e.hit_center().distance_to(at), radius + e.radius, damage)
		if dmg > 0.0 and e.damage(dmg):
			_kill(e, weapon)


func _kill(e: Enemy, weapon: String) -> void:
	streak += 1
	_combo_timer = CombatMath.COMBO_WINDOW
	var mult := CombatMath.combo(streak)
	hud.set_combo(mult)
	var pts := CombatMath.points(e.kind, mult, weapon)
	_add_score(pts, e.hit_center(), Neon.AMBER if mult > 1.0 else Neon.WHITE, e.kind == "boss")
	if e.kind != "target" and e.kind != "boss" and _rng.randf() < 0.15:
		_drop_repair(e.hit_center())
	_explode_enemy(e)


func _explode_enemy(e: Enemy) -> void:
	e.state = Enemy.State.DYING
	var at := e.hit_center()
	match e.kind:
		"target":
			Fx.sparks(self, at, e.wall_normal, Color(1.0, 0.9, 0.5), 8)
			cue("target_hit", at)
		"boss":
			Fx.explosion(self, at, 0.3)
			for i in range(4):
				Fx.explosion(self, at + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.3, 0.3)), 0.12)
			cue("boom_big", at, 6.0)
		_:
			Fx.explosion(self, at, 0.07 if e.kind != "tank" else 0.09)
			cue("boom_big" if e.kind == "tank" else "boom_small", at)
			if e.kind == "tank":
				Fx.scorch(self, Vector3(at.x, floor_y, at.z), Vector3.UP, 0.32)
	jet.locks.erase(e)
	enemies.erase(e)
	e.queue_free()


func _add_score(points: int, at: Vector3, color: Color, big: bool = false) -> void:
	score += points
	hud.set_score(score)
	hud.popup(at, points, color, big)


# --- pickups --------------------------------------------------------------------------

func _drop_repair(at: Vector3) -> void:
	var p := Node3D.new()
	var core := Neon.make_orb(Color(0.3, 1.0, 0.45), 0.018, 10, 5)
	p.add_child(core)
	var cross_h := MeshInstance3D.new()
	cross_h.mesh = Models.box(Vector3(0.05, 0.012, 0.012))
	cross_h.material_override = Neon.emitter_material(Neon.WHITE)
	p.add_child(cross_h)
	var cross_v := MeshInstance3D.new()
	cross_v.mesh = Models.box(Vector3(0.012, 0.05, 0.012))
	cross_v.material_override = Neon.emitter_material(Neon.WHITE)
	p.add_child(cross_v)
	p.add_child(Neon.make_halo(Color(0.3, 1.0, 0.45), 0.16, 0.45))
	p.set_meta("life", 0.0)
	add_child(p)
	p.global_position = CombatMath.clamp_into(at, box, 0.3, 0.6)
	pickups.append(p)


func _step_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		var life: float = p.get_meta("life") + delta
		p.set_meta("life", life)
		p.rotate_y(delta * 2.0)
		p.global_position.y += sin(life * 3.0) * 0.02 * delta
		if phase == Phase.PLAYING and not jet.destroyed and p.global_position.distance_to(jet.global_position) < 0.15:
			jet.repair(25.0)
			cue("pickup", p.global_position)
			_add_score(20, p.global_position, Color(0.3, 1.0, 0.45))
			p.queue_free()
			pickups.remove_at(i)
		elif life > 14.0:
			p.queue_free()
			pickups.remove_at(i)


# --- lock marks -------------------------------------------------------------------------

func _make_lock_mark() -> Node3D:
	var root := Node3D.new()
	var pts := PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0)])
	for core in [true, false]:
		var mesh := ImmediateMesh.new()
		Neon.build_tube(mesh, pts, func(_t): return 0.035 if core else 0.11)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Neon.glow_material(Neon.RED, core)
		root.add_child(mi)
	return root


func _update_lock_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	for i in range(_lock_marks.size()):
		var mark := _lock_marks[i]
		if i < jet.locks.size() and is_instance_valid(jet.locks[i]):
			var e: Enemy = jet.locks[i]
			mark.visible = true
			mark.global_position = e.hit_center()
			if cam:
				mark.look_at(cam.global_position, Vector3.UP, true)
			var s := e.radius * 1.5
			mark.scale = Vector3.ONE * s
			mark.rotate_object_local(Vector3.FORWARD, Time.get_ticks_msec() * 0.003)
		else:
			mark.visible = false


# --- menu and results -----------------------------------------------------------------------

func _clear_ui() -> void:
	for r in [_menu_root, _results_root]:
		if r and is_instance_valid(r):
			r.queue_free()
	_menu_root = null
	_results_root = null
	_buttons.clear()


func _ui_anchor(distance: float) -> Transform3D:
	var hp := head_position()
	var fwd := -head.global_basis.z if head else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var origin := hp + fwd * distance
	origin.y = hp.y - 0.15
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), origin)


func _add_button(parent: Node3D, kind: String, color: Color, r: float, pos: Vector3, action: Callable) -> UI.Button3D:
	var b := UI.Button3D.new(kind, color, r)
	b.position = pos
	b.set_meta("action", action)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _build_menu() -> void:
	_menu_root = Node3D.new()
	add_child(_menu_root)
	_menu_root.global_transform = _ui_anchor(1.25)
	_add_button(_menu_root, "play", Neon.CYAN, 0.12, Vector3(0, 0.0, 0), start_match)
	var best := save.best("raid")
	if best > 0:
		var l := UI.digits(str(best), 120, Neon.WHITE)
		l.position = Vector3(0, 0.24, 0)
		_menu_root.add_child(l)
		var crown := UI.icon("crown", Neon.AMBER, 0.06)
		crown.position = Vector3(0, 0.34, 0)
		_menu_root.add_child(crown)
	var stars := save.stars("raid")
	for i in range(3):
		var st := UI.filled_star(Neon.AMBER if i < stars else Neon.AMBER_DIM, 0.05)
		st.position = Vector3(-0.07 + i * 0.07, -0.2, 0)
		_menu_root.add_child(st)


func _build_results() -> void:
	_results_root = Node3D.new()
	add_child(_results_root)
	_results_root.global_transform = _ui_anchor(1.25)
	var stars := CombatMath.stars(jet.armor / CombatMath.JET_ARMOR, won)
	var record := save.record("raid", score, stars)
	var l := UI.digits(str(score), 200, Neon.WHITE if not record else Neon.AMBER)
	l.position = Vector3(0, 0.22, 0)
	_results_root.add_child(l)
	if record:
		var crown := UI.icon("crown", Neon.AMBER, 0.08)
		crown.position = Vector3(0, 0.38, 0)
		_results_root.add_child(crown)
	for i in range(3):
		var st := UI.filled_star(Neon.AMBER if i < stars else Neon.AMBER_DIM, 0.06)
		st.position = Vector3(-0.09 + i * 0.09, 0.06, 0)
		_results_root.add_child(st)
	_add_button(_results_root, "retry", Neon.CYAN, 0.09, Vector3(-0.13, -0.14, 0), start_match)
	_add_button(_results_root, "home", Neon.VIOLET, 0.07, Vector3(0.13, -0.14, 0), func(): _set_phase(Phase.MENU))


func _clear_battlefield() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for s in shots:
		s.queue_free()
	shots.clear()
	for p in pickups:
		p.queue_free()
	pickups.clear()
	hud.clear_popups()
	Fx.clear_scorches()
	if boss_bay:
		boss_bay.queue_free()
		boss_bay = null
	for h in hangars + bays:
		h.open_target = 0.0
		h.hold = 0.0
