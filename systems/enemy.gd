class_name Enemy
extends Node3D
## Every enemy in the room war. The battle creates them at a real door or
## window (planes, tanks), on a real surface (balloons) or where a supply
## crate lands (flak guns), and ticks them each physics frame.

enum State { ENTER, ACTIVE, ESCAPED, DEAD, FALLING }

var kind: String = "fighter"
var hp: float = 1.0
var max_hp: float = 1.0
var radius: float = 0.1
var state: State = State.ENTER
var battle = null
var parts: Dictionary = {}
var flight: Dictionary = {"pos": Vector3.ZERO, "fwd": Vector3.FORWARD, "speed": 1.0, "bank": 0.0}
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var hit_flash: float = 0.0
var entry: Dictionary = {}          # the opening it came through {center, normal, ...}
var anchor: Vector3 = Vector3.ZERO  # balloons: cable anchor on a surface
var drops: Array = []               # transport: points to drop crates over
var practice: bool = false          # free-flight sparring partner: evades when chased
var path: Array = []                # convoy route on the floor (trucks, tanks)
var path_speed: float = 0.2
var target_marked: bool = false     # a mission objective (shows a marker)
var sam_phase: String = "idle"      # SAM team: idle → prep (2 s, telegraphed) → fire
var sam_t: float = 0.0
var reload_mult: float = 1.0
var crew: Array = []                # soldiers around a SAM launcher
var friendly: bool = false          # the player's side (escort plane, hangars)
var prey: Node3D = null             # what a fighter/diver attacks instead of the player
var burn_t: float = 0.0             # set on fire by incendiary rounds
var _rocket_t: float = 4.0          # raider / heli / fortress missiles
var _station: Vector3 = Vector3.ZERO  # helicopter hover point
var _flak_t: float = 2.0
var _warn: Label3D
var _aim_line: MeshInstance3D
var _aim_mesh := ImmediateMesh.new()
var _fall_spin: float = 0.0
var _walk: float = 0.0
var run_to: Vector3 = Vector3.INF
var _mode: String = "attack"
var _mode_t: float = 0.0
var _goal: Vector3 = Vector3.ZERO
var _fire_t: float = 0.0
var _burst: int = 0
var _burst_t: float = 0.0
var _bomb_t: float = 0.0
var _smoke_t: float = 0.0
var _shadow: MeshInstance3D
var _flash_mats: Array = []
var _engine: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


static func create(enemy_kind: String) -> Enemy:
	var e := Enemy.new()
	e.kind = enemy_kind
	var spec: Dictionary = WarMath.ENEMIES[enemy_kind]
	e.hp = spec.hp
	e.max_hp = spec.hp
	e.radius = spec.radius
	e.name = enemy_kind.capitalize()
	return e


func _ready() -> void:
	_rng.randomize()
	match kind:
		"fighter":
			parts = Models.fighter(Models.ENEMY, 0.002)
			parts.root.scale = Vector3.ONE * 0.92
			for g in parts.gear:
				(g as Node3D).rotation.x = -1.45
		"transport":
			parts = Models.transport()
		"bomber":
			parts = Models.bomber()
		"tank":
			parts = Models.tank()
		"aa":
			parts = Models.aa_gun()
		"balloon":
			parts = Models.balloon()
		"ace":
			parts = Models.fighter(Models.ACE, 0.002)
			parts.root.scale = Vector3.ONE * 0.95
			for g in parts.gear:
				(g as Node3D).rotation.x = -1.45
			practice = true
		"soldier":
			parts = Models.soldier("rifle")
		"sam":
			parts = Models.launcher()
			for i in range(2):
				var c := Models.soldier("crew")
				c.root.position = Vector3(-0.035 + i * 0.07, 0, 0.045)
				c.root.rotation.y = PI * (0.15 if i == 0 else -0.15)
				parts.root.add_child(c.root)
				crew.append(c)
			_warn = UI.number("!", 150, Color(1.0, 0.2, 0.1))
			_warn.position = Vector3(0, 0.16, 0)
			_warn.visible = false
			parts.root.add_child(_warn)
			_aim_line = MeshInstance3D.new()
			_aim_line.mesh = _aim_mesh
			_aim_line.material_override = Toon.flat(Color(1.0, 0.15, 0.1, 0.8))
			_aim_line.top_level = true
			_aim_line.extra_cull_margin = 10.0
			parts.root.add_child(_aim_line)
			(parts.tube as Node3D).rotation.x = -0.15
			sam_t = _rng.randf_range(1.5, 3.0)
		"truck":
			parts = Models.truck()
		"diver":
			parts = Models.fighter(Models.DIVER, 0.002)
			parts.root.scale = Vector3.ONE * 0.95
			for g in parts.gear:
				(g as Node3D).rotation.x = -1.45
			var bomb := Models.bomb()
			bomb.position = Vector3(0, -0.05, 0.0)
			bomb.scale = Vector3.ONE * 1.3
			parts.root.add_child(bomb)
			parts["belly_bomb"] = bomb
		"cargo":
			parts = Models.transport(Models.FRIEND)
		"heli":
			parts = Models.heli()
		"wingman":
			parts = Models.fighter(Models.PLAYER, 0.002)
			parts.root.scale = Vector3.ONE * 0.85
			for g in parts.gear:
				(g as Node3D).rotation.x = -1.45
		"raider":
			parts = Models.raider()
			for g in parts.gear:
				(g as Node3D).rotation.x = -1.45
		"gunship":
			parts = Models.fortress()
		"hangar":
			parts = Models.hangar()
		"radar":
			parts = Models.radar()
		"fuel":
			parts = Models.fuel_tank()
	add_child(parts.root)
	if kind in ["fighter", "ace", "transport", "bomber", "balloon", "diver", "cargo", "heli", "raider", "gunship", "wingman"]:
		_shadow = Toon.shadow_blob(radius * 2.6)
		add_child(_shadow)
	if kind in ["fighter", "ace", "transport", "bomber", "tank", "truck", "diver", "cargo", "heli", "raider", "gunship", "wingman"]:
		_engine = AudioStreamPlayer3D.new()
		var s = load("res://assets/audio/" + ("tank_engine" if kind in ["tank", "truck"] else "enemy_engine") + ".wav")
		if s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
		_engine.stream = s
		_engine.unit_size = 0.7 if not kind in ["bomber", "gunship"] else 1.4
		_engine.max_distance = 7.0
		_engine.volume_db = -20.0 if not kind in ["bomber", "gunship"] else -12.0
		_engine.pitch_scale = {"fighter": 1.15, "ace": 1.35, "transport": 0.8, "bomber": 0.6, "tank": 1.0, "truck": 1.25, "diver": 1.05, "cargo": 0.75, "heli": 1.7, "raider": 0.95, "gunship": 0.5, "wingman": 1.25}[kind]
		_engine.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		_engine.bus = &"SFX"
		add_child(_engine)
		if s:
			_engine.play()
	_fire_t = _rng.randf_range(1.5, 2.5)
	_bomb_t = 4.0


func hit_center() -> Vector3:
	match kind:
		"tank":
			return global_position + Vector3(0, 0.05, 0)
		"aa":
			return global_position + Vector3(0, 0.05, 0)
		"balloon":
			return (parts.body as Node3D).global_position
		"soldier":
			return global_position + Vector3(0, 0.035, 0)
		"sam":
			return global_position + Vector3(0, 0.045, 0)
		"truck":
			return global_position + Vector3(0, 0.045, 0)
		"radar":
			return global_position + Vector3(0, 0.2, 0)
		"fuel":
			return global_position + Vector3(0, 0.07, 0)
		"hangar":
			return global_position + Vector3(0, 0.05, 0)
	return global_position


func alive() -> bool:
	return state == State.ENTER or state == State.ACTIVE


func can_be_locked() -> bool:
	return alive() and (state == State.ACTIVE or kind in ["bomber", "gunship", "transport", "heli"])


## Armoured enemies take less from plain bullets.
func gun_armor() -> float:
	return float(WarMath.GUN_ARMOR.get(kind, 1.0))


## Planes: start behind the opening and fly in along its normal.
func enter_through(opening: Dictionary) -> void:
	entry = opening
	var n: Vector3 = opening.normal
	var start: Vector3 = opening.center - n * 0.55
	if kind == "tank":
		start = opening.base - n * 0.35
	flight = {"pos": start, "fwd": n, "speed": 0.0 if kind == "tank" else 1.0, "bank": 0.0}
	global_position = start
	_face(n)
	state = State.ENTER
	age = 0.0


## Balloons grow out of a surface and rise on their cable.
func rise_from(point: Vector3) -> void:
	anchor = point
	global_position = point
	state = State.ENTER
	age = 0.0


## Flak guns appear where their crate landed.
func land_at(point: Vector3, facing: Vector3) -> void:
	global_position = point
	_face(facing)
	state = State.ACTIVE


func _face(dir: Vector3) -> void:
	var d := dir
	if kind in ["tank", "aa"]:
		d.y = 0.0
	if d.length_squared() < 1e-6:
		return
	look_at(global_position + d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.BACK)


func damage(amount: float, at: Vector3 = Vector3.INF) -> bool:
	if not alive():
		return false
	if kind in ["bomber", "gunship"] and at != Vector3.INF:
		var best = null
		var best_d := 0.085
		for eng in parts.engines:
			if eng.hp <= 0.0:
				continue
			var d := (eng.node as Node3D).global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = eng
		if best:
			best.hp -= amount * 1.5
			if best.hp <= 0.0:
				_kill_engine(best)
			amount *= 0.4
		else:
			amount *= 0.5
	hp -= amount
	hit_flash = 1.0
	if hp <= 0.0 or (kind in ["bomber", "gunship"] and _dead_engines() >= 3):
		state = State.DEAD
		return true
	return false


func _dead_engines() -> int:
	var n := 0
	for eng in parts.get("engines", []):
		if eng.hp <= 0.0:
			n += 1
	return n


func _kill_engine(eng: Dictionary) -> void:
	(eng.blur as Node3D).visible = false
	if battle:
		Fx.explosion(battle, (eng.node as Node3D).global_position, 0.06)
		battle.cue("boom_small", (eng.node as Node3D).global_position)


# --- ticking -------------------------------------------------------------------------

func tick(delta: float) -> void:
	age += delta
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	_flash()
	var before := global_position
	if state == State.FALLING:
		_tick_falling(delta)
		velocity = (global_position - before) / maxf(delta, 1e-4)
		_animate(delta)
		return
	match kind:
		"fighter", "ace", "raider":
			_tick_fighter(delta)
			if kind == "raider" and state == State.ACTIVE:
				_raider_rockets(delta)
		"heli":
			_tick_heli(delta)
		"wingman":
			_tick_wingman(delta)
		"gunship":
			_tick_bomber(delta)
			if state == State.ACTIVE:
				_fortress_guns(delta)
		"soldier":
			_tick_soldier(delta)
		"sam":
			_tick_sam(delta)
		"truck":
			_tick_convoy(delta)
		"radar":
			(parts.dish as Node3D).rotate_y(delta * 1.8)
		"fuel", "hangar":
			pass
		"diver":
			_tick_diver(delta)
		"cargo":
			_tick_cargo(delta)
		"transport":
			_tick_transport(delta)
		"bomber":
			_tick_bomber(delta)
		"tank":
			_tick_tank(delta)
		"aa":
			_tick_aa(delta)
		"balloon":
			_tick_balloon(delta)
	velocity = (global_position - before) / maxf(delta, 1e-4)
	_animate(delta)


func _animate(delta: float) -> void:
	if parts.has("prop"):
		(parts.prop as Node3D).rotate_object_local(Vector3.FORWARD, delta * 60.0)
		var bm := (parts.blur as MeshInstance3D).material_override as ShaderMaterial
		bm.set_shader_parameter("albedo", Color(0.25, 0.25, 0.28, 0.25))
	for key in ["props"]:
		for p in parts.get(key, []):
			(p.prop as Node3D).rotate_object_local(Vector3.FORWARD, delta * 50.0)
			((p.blur as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.25, 0.25, 0.28, 0.25))
	for eng in parts.get("engines", []):
		if eng.hp > 0.0:
			(eng.prop as Node3D).rotate_object_local(Vector3.FORWARD, delta * 45.0)
			((eng.blur as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.25, 0.25, 0.28, 0.25))
		else:
			_smoke_t -= delta
			if _smoke_t <= 0.0 and battle:
				_smoke_t = 0.06
				Fx.smoke(battle, (eng.node as Node3D).global_position, 0.03, true)
	if _shadow and battle:
		var under: float = battle.surface_below(global_position)
		var h := maxf(0.0, global_position.y - under)
		_shadow.global_position = Vector3(global_position.x, under + 0.003, global_position.z)
		_shadow.scale = Vector3.ONE * clampf(1.0 - h * 0.25, 0.45, 1.0)
		(_shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.5 - h * 0.17, 0.1, 0.5)
		_shadow.visible = state != State.ENTER or WarMath.inside(global_position, battle.box, 0.0)
	if hp < max_hp * 0.4 and kind != "balloon" and battle:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.1
			Fx.smoke(battle, hit_center(), radius * 0.25, true)


func _flash() -> void:
	if hit_flash <= 0.0 and _flash_mats.is_empty():
		return
	if _flash_mats.is_empty():
		for mi in parts.root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.material_override is ShaderMaterial and (m.material_override as ShaderMaterial).shader == Toon._shader("toon", Toon.TOON_SHADER):
				var u := Toon.unique(m.material_override as ShaderMaterial)
				m.set_meta("orig", m.material_override)
				m.material_override = u
				_flash_mats.append(m)
	for m in _flash_mats:
		if is_instance_valid(m):
			((m as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("flash", hit_flash * 0.8)
	if hit_flash <= 0.0:
		for m in _flash_mats:
			if is_instance_valid(m):
				(m as MeshInstance3D).material_override = m.get_meta("orig")
		_flash_mats.clear()


func _pose_from_flight() -> void:
	global_position = flight.pos
	global_basis = WarMath.plane_basis(flight.fwd, flight.bank)


## Straight in through the opening until well inside the room.
func _entering(delta: float, speed: float) -> bool:
	var n: Vector3 = entry.normal
	flight.speed = move_toward(flight.speed, speed, delta * 2.0)
	flight.pos += flight.fwd * flight.speed * delta
	_pose_from_flight()
	var depth: float = (flight.pos - (entry.center as Vector3)).dot(n)
	if depth > 0.55:
		state = State.ACTIVE
		return true
	return false


func _tick_fighter(delta: float) -> void:
	if state == State.ENTER:
		_entering(delta, 1.3)
		return
	if _hold_formation(delta):
		return
	var hunting: bool = prey != null and is_instance_valid(prey) and prey.alive()
	if practice and not hunting:
		_tick_sparring(delta)
		return
	var jet: Vector3 = (prey as Enemy).hit_center() if hunting else battle.player_position()
	var jet_v: Vector3 = (prey as Enemy).velocity if hunting else battle.player_velocity()
	var to: Vector3 = jet - (flight.pos as Vector3)
	_mode_t -= delta
	if _mode == "attack":
		_goal = jet + jet_v * 0.35
		if to.length() < 0.45 or _mode_t < -6.0:
			_mode = "extend"
			_mode_t = _rng.randf_range(1.4, 2.4)
			_goal = battle.clamp_front(flight.pos + flight.fwd * 1.6 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.4), _rng.randf_range(-1, 1)))
	elif _mode_t <= 0.0:
		_mode = "attack"
		_mode_t = 0.0
	flight = WarMath.fly(flight, _goal, 1.2, delta, battle.box, 2.2)
	_pose_from_flight()
	# Bursts when the nose is on the player.
	_fire_t -= delta
	if _burst > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = 0.09
			_burst -= 1
			var m: Node3D = parts.muzzles[_burst % parts.muzzles.size()]
			var dir: Vector3 = (jet + jet_v * (to.length() / WarMath.ENEMY_BULLET_SPEED) - m.global_position).normalized()
			dir = (dir + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))).normalized()
			battle.enemy_fire("ebullet", m.global_position, dir, velocity)
			Fx.muzzle(battle, m.global_position, dir, 0.014)
	elif _fire_t <= 0.0 and _mode == "attack" and flight.fwd.dot(to.normalized()) > 0.94 and to.length() < 2.4:
		_burst = 6
		_fire_t = _rng.randf_range(1.6, 2.6) * (1.5 if hunting else 1.0)
		battle.cue("enemy_gun", global_position, -6.0)


## Sparring fighter: wanders near the player, breaks hard left/right/up/down
## when the player gets on its tail, and now and then turns to joust.
func _tick_sparring(delta: float) -> void:
	var me: Vector3 = flight.pos
	var you: Vector3 = battle.player_position()
	var to_you := you - me
	var fwd: Vector3 = flight.fwd
	var chased := to_you.length() < 3.0 and fwd.dot(to_you.normalized()) < -0.3
	var head: Vector3 = battle.head_position()
	_mode_t -= delta
	if chased and _mode != "evade":
		_mode = "evade"
		_mode_t = _rng.randf_range(1.0, 1.6)
		var side := fwd.cross(Vector3.UP).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
		_goal = me + side * 2.0 + fwd * 1.0 + Vector3(0, _rng.randf_range(-0.6, 0.8), 0)
	elif _mode_t <= 0.0:
		if _rng.randf() < 0.35:
			_mode = "attack"
			_mode_t = _rng.randf_range(2.0, 3.0)
		else:
			_mode = "wander"
			_mode_t = _rng.randf_range(2.0, 3.5)
			_goal = battle.arena_random()
	if _mode == "attack":
		_goal = you + battle.player_velocity() * 0.4
	# Stay in the battle area in front of the player (never behind the headset).
	if _mode != "attack":
		_goal = battle.clamp_front(_goal)
	_goal.y = clampf(_goal.y, battle.floor_y + 0.7, battle.floor_y + 2.6)
	var ace := kind == "ace"
	var spd := (1.55 if ace else 1.4) if _mode == "evade" else (1.3 if ace else 1.15)
	flight = WarMath.fly(flight, _goal, spd, delta, battle.box, (3.0 if ace else 2.4) if _mode == "evade" else (2.4 if ace else 1.9))
	_pose_from_flight()
	_fire_t -= delta
	if _burst > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = 0.09
			_burst -= 1
			var m: Node3D = parts.muzzles[_burst % parts.muzzles.size()]
			battle.enemy_fire("ebullet", m.global_position, -global_basis.z, velocity)
			Fx.muzzle(battle, m.global_position, -global_basis.z, 0.014)
	elif _fire_t <= 0.0 and _mode == "attack" and fwd.dot(to_you.normalized()) > 0.95 and to_you.length() < 2.5:
		_burst = 5
		_fire_t = _rng.randf_range(2.0, 3.0)
		battle.cue("enemy_gun", global_position, -6.0)


func _tick_transport(delta: float) -> void:
	if state == State.ENTER:
		_entering(delta, 0.8)
		return
	var huge := {"min": Vector3(-99, -99, -99), "max": Vector3(99, 99, 99)}
	if _mode == "attack":
		_mode = "drop"
	if _mode == "drop":
		if drops.is_empty():
			_mode = "exit"
			entry = battle.exit_opening(flight.pos)
		else:
			var p: Vector3 = drops[0]
			var over := Vector3(p.x, maxf(p.y + 0.75, battle.floor_y + 1.2), p.z)
			_goal = over
			var flat := Vector2(flight.pos.x - p.x, flight.pos.z - p.z).length()
			if flat < 0.18:
				battle.drop_crate((parts.hatch as Node3D).global_position, p)
				drops.pop_front()
				battle.cue("hatch", global_position)
			elif flat < 0.6:
				flight.speed = move_toward(flight.speed, 0.6, delta)
	if _mode == "exit":
		var n: Vector3 = entry.normal
		var c: Vector3 = entry.center
		var depth: float = ((flight.pos as Vector3) - c).dot(n)
		_goal = c + n * 0.7 if depth > 0.45 and flight.fwd.dot(-n) < 0.8 else c - n * 1.2
		if depth < -0.4:
			state = State.ESCAPED
			return
		flight = WarMath.fly(flight, _goal, 0.85, delta, huge, 1.6)
	else:
		flight = WarMath.fly(flight, _goal, 0.85, delta, battle.box, 1.4)
	_pose_from_flight()


func _tick_bomber(delta: float) -> void:
	if state == State.ENTER:
		_entering(delta, 0.6)
		return
	# Wide laps high in the room.
	var c: Vector3 = battle.box_center()
	var lo: Vector3 = battle.box.min
	var hi: Vector3 = battle.box.max
	if battle.free_flight:
		# Laps across the front: wide side to side, shallow in depth.
		var cc: Vector3 = battle.arena_center + battle.arena_fwd * 0.4
		var d: Vector3 = flight.pos - cc
		var ang2 := atan2(d.dot(battle.arena_fwd) / 1.1, d.dot(battle.arena_side) / 2.0) + 0.5
		_goal = cc + battle.arena_side * cos(ang2) * 2.0 + battle.arena_fwd * sin(ang2) * 1.1
		_goal.y = battle.floor_y + 1.9
	else:
		var rx := minf(2.4, maxf(0.55, (hi.x - lo.x) * 0.5 - 0.6))
		var rz := minf(2.4, maxf(0.55, (hi.z - lo.z) * 0.5 - 0.6))
		var ang := atan2(flight.pos.z - c.z, flight.pos.x - c.x) + 0.6
		_goal = Vector3(c.x + cos(ang) * rx, minf(hi.y - 0.45, battle.floor_y + 1.9), c.z + sin(ang) * rz)
	flight = WarMath.fly(flight, _goal, 0.55, delta, battle.box, 0.9)
	flight.bank *= 0.6
	_pose_from_flight()
	# Turrets track and fire.
	var jet: Vector3 = battle.player_position()
	for t in [["top", "top_guns"], ["tail", "tail_guns"]]:
		var tur: Node3D = parts[t[0]]
		var local := tur.global_transform.affine_inverse() * jet
		tur.rotate_object_local(Vector3.UP, clampf(atan2(-local.x, -local.z), -delta * 3.0, delta * 3.0))
	_fire_t -= delta
	if _fire_t <= 0.0 and _burst <= 0:
		_burst = 6
		_fire_t = _rng.randf_range(1.6, 2.4)
	if _burst > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = 0.11
			_burst -= 1
			var guns: Array = parts.top_guns + parts.tail_guns
			var best: Node3D = guns[0]
			for g in guns:
				if (g as Node3D).global_position.distance_to(jet) < best.global_position.distance_to(jet):
					best = g
			var dir := (jet - best.global_position).normalized()
			dir = (dir + Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06))).normalized()
			battle.enemy_fire("ebullet", best.global_position, dir, velocity)
	# Carpet bombs on the floor (dangerous if you fly low under it).
	_bomb_t -= delta
	if _bomb_t <= 0.0:
		_bomb_t = _rng.randf_range(4.0, 6.0)
		battle.enemy_fire("ebomb", (parts.bay as Node3D).global_position, Vector3.DOWN, velocity)


## Enemy squadrons arrive in a V behind their leader and hold it for a few
## seconds (until the leader falls or they're hit), then break to attack.
func _hold_formation(delta: float) -> bool:
	if not has_meta("form_lead"):
		return false
	var lead = get_meta("form_lead")
	if lead == self or not is_instance_valid(lead) or not lead.alive() or age > float(get_meta("form_until", 7.0)) or hp < max_hp:
		remove_meta("form_lead")
		return false
	var lb := Basis.looking_at(lead.flight.fwd, Vector3.UP)
	var off: Vector3 = get_meta("form_off")
	var slot: Vector3 = (lead.flight.pos as Vector3) + lb * off
	var gap := slot - (flight.pos as Vector3)
	flight = WarMath.fly(flight, slot + (lead.flight.fwd as Vector3) * 0.4, clampf(float(lead.flight.speed) + gap.length() * 1.5, 0.6, 2.2), delta, battle.box, 3.0)
	_pose_from_flight()
	return true


## Your squadron: a wingman holds a slot beside your plane and breaks off to
## chase enemy planes that come near you, then comes back to formation.
var _wing_shot_t: float = 0.0
func _tick_wingman(delta: float) -> void:
	var lead: PlayerPlane = battle.plane
	var slot: Vector3 = get_meta("slot", Vector3(0.32, 0.02, 0.3))
	var lpos: Vector3 = lead.global_position
	var lfwd: Vector3 = lead.forward()
	lfwd.y = clampf(lfwd.y, -0.5, 0.5)
	lfwd = lfwd.normalized()
	_mode_t -= delta
	if _mode_t <= 0.0:
		_mode_t = 1.5
		prey = null
		var best := 2.6
		for e in battle.enemies:
			if e.alive() and e.state == State.ACTIVE and e.kind in ["fighter", "ace", "diver", "raider", "heli", "transport"]:
				var d: float = e.hit_center().distance_to(lpos)
				if d < best:
					best = d
					prey = e
	var spd := 1.2
	# Leash: never stray far from you.
	if (flight.pos as Vector3).distance_to(lpos) > 2.4:
		prey = null
		_mode_t = 1.0
	var hunting: bool = prey != null and is_instance_valid(prey) and (prey as Enemy).alive()
	if hunting:
		var tgt: Vector3 = (prey as Enemy).hit_center()
		_goal = tgt + (prey as Enemy).velocity * 0.3
		spd = 1.6
		var to := tgt - (flight.pos as Vector3)
		_wing_shot_t -= delta
		if to.length() < 2.2 and (flight.fwd as Vector3).dot(to.normalized()) > 0.985 and _wing_shot_t <= 0.0:
			_wing_shot_t = 0.11
			var side := (flight.fwd as Vector3).cross(Vector3.UP).normalized()
			for sgn: float in [-1.0, 1.0]:
				var from: Vector3 = (flight.pos as Vector3) + (flight.fwd as Vector3) * 0.08 + side * 0.05 * sgn
				battle.player_fire("bullet", from, (tgt - from).normalized(), velocity * 0.5, null, {"damage": 0.45, "ally": true})
			battle.cue("enemy_gun", global_position, -10.0)
	elif lead.airborne():
		var lb := Basis.looking_at(lfwd, Vector3.UP)
		_goal = lpos + lb * slot
		var gap := _goal - (flight.pos as Vector3)
		spd = clampf(float(lead.flight.speed) + gap.length() * 1.6, 0.6, 2.4)
		_goal += lfwd * 0.5
	else:
		# Plane on the ground: circle overhead and wait.
		var a := age * 0.5 + (0.0 if slot.x > 0.0 else PI)
		_goal = lpos + Vector3(cos(a) * 0.9, 1.2, sin(a) * 0.9)
		spd = 0.9
	_goal.y = maxf(_goal.y, battle.floor_y + 0.35)
	flight = WarMath.fly(flight, _goal, spd, delta, battle.box, 3.2)
	_pose_from_flight()


## Raider: a homing rocket whenever the player is ahead of its nose.
func _raider_rockets(delta: float) -> void:
	_rocket_t -= delta
	if _rocket_t > 0.0:
		return
	var jet: Vector3 = battle.player_position()
	var to: Vector3 = jet - global_position
	if to.length() < 3.2 and (flight.fwd as Vector3).dot(to.normalized()) > 0.55:
		_rocket_t = _rng.randf_range(7.0, 9.0)
		var s = battle.enemy_fire("sam", global_position + (flight.fwd as Vector3) * 0.12 - Vector3(0, 0.02, 0), to.normalized(), velocity)
		if s:
			s.target = battle.plane
	else:
		_rocket_t = 0.5


## The fortress: side cannon turrets throw flak bursts at the player and the
## tail launches a homing missile now and then.
func _fortress_guns(delta: float) -> void:
	var jet: Vector3 = battle.player_position()
	for g in parts.get("side_guns", []):
		var piv: Node3D = g.pivot
		var local := piv.global_transform.affine_inverse() * jet
		piv.rotate_object_local(Vector3.UP, clampf(atan2(-local.x, -local.z), -delta * 2.0, delta * 2.0))
	_flak_t -= delta
	if _flak_t <= 0.0:
		_flak_t = _rng.randf_range(2.2, 3.2)
		for g in parts.get("side_guns", []):
			var mz: Node3D = g.muzzle
			var d: Vector3 = (jet + battle.player_velocity() * 0.4 - mz.global_position).normalized()
			battle.enemy_fire("flak", mz.global_position, d, velocity)
	_rocket_t -= delta
	if _rocket_t <= 0.0:
		_rocket_t = _rng.randf_range(9.0, 12.0)
		var tail: Node3D = parts.tail
		var s = battle.enemy_fire("sam", tail.global_position, (jet - tail.global_position).normalized(), velocity)
		if s:
			s.target = battle.plane


## Attack helicopter: pops up from the floor, hovers at a station in front
## of the player, turns to face the plane, sidesteps every few seconds,
## chin-gun bursts and a pair of homing rockets now and then.
func _tick_heli(delta: float) -> void:
	(parts.rotor as Node3D).rotate_y(delta * 26.0)
	(parts.tail_rotor as Node3D).rotate_x(delta * 34.0)
	var me: Vector3 = flight.pos
	if state == State.ENTER:
		me.y = move_toward(me.y, _station.y, delta * 0.55)
		flight.pos = me
		global_position = me
		if absf(me.y - _station.y) < 0.02:
			state = State.ACTIVE
			_mode_t = _rng.randf_range(4.0, 6.0)
		return
	_mode_t -= delta
	if _mode_t <= 0.0:
		_mode_t = _rng.randf_range(5.0, 8.0)
		_station = battle.clamp_front(me + battle.arena_side * _rng.randf_range(-1.2, 1.2) + battle.arena_fwd * _rng.randf_range(-0.5, 0.5) + Vector3(0, _rng.randf_range(-0.3, 0.3), 0))
		_station.y = clampf(_station.y, battle.floor_y + 0.8, battle.floor_y + 1.9)
	var bob := Vector3(0, sin(age * 1.7) * 0.03, 0)
	var to := _station + bob - me
	var v: Vector3 = flight.get("vel", Vector3.ZERO)
	v = v.lerp(to.limit_length(0.5) * 1.2, minf(1.0, delta * 1.5))
	flight["vel"] = v
	me += v * delta
	flight.pos = me
	var jet: Vector3 = battle.player_position()
	var face := jet - me
	face.y = 0.0
	if face.length() > 0.01:
		flight.fwd = WarMath.steer(flight.fwd, face.normalized(), 1.6, delta)
	flight.speed = v.length()
	global_position = me
	var tilt_f: float = clampf(v.dot(flight.fwd) * 0.6, -0.25, 0.25)
	var right: Vector3 = (flight.fwd as Vector3).cross(Vector3.UP).normalized()
	var tilt_s: float = clampf(v.dot(right) * 0.6, -0.25, 0.25)
	global_basis = Basis.looking_at(flight.fwd, Vector3.UP) * Basis(Vector3.RIGHT, -tilt_f) * Basis(Vector3.FORWARD, -tilt_s)
	# Chin gun follows the plane.
	var gun: Node3D = parts.gun
	var lg := gun.global_transform.affine_inverse() * jet
	gun.rotate_object_local(Vector3.UP, clampf(atan2(-lg.x, -lg.z), -delta * 3.0, delta * 3.0))
	_fire_t -= delta
	if _fire_t <= 0.0 and _burst <= 0:
		_burst = 5
		_fire_t = _rng.randf_range(2.4, 3.4)
	if _burst > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = 0.12
			_burst -= 1
			var mz: Node3D = parts.muzzle
			var dir: Vector3 = (jet + battle.player_velocity() * 0.3 - mz.global_position).normalized()
			dir = (dir + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))).normalized()
			battle.enemy_fire("ebullet", mz.global_position, dir, velocity)
	_rocket_t -= delta
	if _rocket_t <= 0.0:
		_rocket_t = _rng.randf_range(9.0, 12.0)
		var pod: Node3D = parts.pods[_rng.randi() % 2]
		var s = battle.enemy_fire("sam", pod.global_position, (jet - pod.global_position).normalized(), velocity)
		if s:
			s.target = battle.plane


func _tick_tank(delta: float) -> void:
	if not path.is_empty():
		_tick_convoy(delta)
		_aim_and_fire(delta, parts.turret, parts.barrel, parts.muzzle, "shell", 3.2)
		return
	if state == State.ENTER:
		var n: Vector3 = entry.normal
		flight.pos += n * 0.22 * delta
		flight.pos.y = battle.floor_y
		global_position = flight.pos
		_face(n)
		if (flight.pos - (entry.base as Vector3)).dot(n) > 0.45:
			state = State.ACTIVE
			_goal = battle.ground_goal(global_position, n)
		return
	var to := _goal - global_position
	to.y = 0.0
	if to.length() > 0.04:
		var dir := to.normalized()
		var f := -global_basis.z
		f.y = 0.0
		var nf := WarMath.steer(f.normalized(), dir, 1.5, delta)
		global_position += nf * 0.2 * delta
		global_position.y = battle.floor_y
		_face(nf)
	elif _rng.randf() < delta * 0.15:
		_goal = battle.ground_goal(global_position, -global_basis.z)
	_aim_and_fire(delta, parts.turret, parts.barrel, parts.muzzle, "shell", 2.6)


func _tick_aa(delta: float) -> void:
	_aim_and_fire(delta, parts.mount, parts.guns, parts.muzzles[0], "flak", 1.7)


func _aim_and_fire(delta: float, yaw_node: Node3D, pitch_node: Node3D, muzzle: Node3D, shot: String, period: float) -> void:
	var jet: Vector3 = battle.player_position()
	var lead: Vector3 = jet + battle.player_velocity() * (jet.distance_to(muzzle.global_position) / (WarMath.FLAK_SPEED if shot == "flak" else WarMath.SHELL_SPEED))
	var local: Vector3 = (yaw_node.get_parent() as Node3D).global_transform.affine_inverse() * lead
	var yaw := atan2(-(local.x - yaw_node.position.x), -(local.z - yaw_node.position.z))
	yaw_node.rotation.y = lerp_angle(yaw_node.rotation.y, yaw, minf(1.0, delta * 3.0))
	var flat := Vector2(local.x - yaw_node.position.x, local.z - yaw_node.position.z).length()
	var pitch := atan2(local.y - yaw_node.position.y, flat)
	if shot == "shell":
		var d := WarMath.ballistic_dir(muzzle.global_position, lead, WarMath.SHELL_SPEED, WarMath.SHELL_GRAVITY)
		pitch = asin(clampf(d.y, -1.0, 1.0))
	pitch_node.rotation.x = lerpf(pitch_node.rotation.x, clampf(pitch, -0.1, 1.4), minf(1.0, delta * 3.0))
	_fire_t -= delta
	if _fire_t <= 0.0 and battle.player_airborne():
		_fire_t = _rng.randf_range(period * 0.8, period * 1.2)
		var dir := -muzzle.global_basis.z
		if shot == "flak":
			dir = (lead - muzzle.global_position).normalized()
		var s: Shot = battle.enemy_fire(shot, muzzle.global_position, dir, Vector3.ZERO)
		if s and shot == "flak":
			s.fuse = muzzle.global_position.distance_to(lead) + _rng.randf_range(-0.1, 0.12)
		Fx.muzzle(battle, muzzle.global_position, dir, 0.022)
		Fx.smoke(battle, muzzle.global_position, 0.015)


func _tick_balloon(delta: float) -> void:
	var body: Node3D = parts.body
	var cable: MeshInstance3D = parts.cable
	var top: float = 0.0
	if state == State.ENTER:
		var u := clampf(age / 2.2, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		body.scale = Vector3.ONE * maxf(0.05, e)
		top = lerpf(0.05, get_meta("height", 1.0), e)
		if u >= 1.0:
			state = State.ACTIVE
	else:
		top = get_meta("height", 1.0)
	var sway := Vector3(sin(age * 0.7) * 0.06, sin(age * 1.1) * 0.02, cos(age * 0.6) * 0.06)
	body.position = Vector3(0, top, 0) + sway * minf(1.0, age)
	body.rotation.y = sin(age * 0.4) * 0.5
	cable.position = body.position * 0.5
	cable.basis = Basis(Quaternion(Vector3.UP, body.position.normalized())) * Basis.from_scale(Vector3(1, maxf(0.001, body.position.length()), 1))



# --- campaign units --------------------------------------------------------------------------

## Dive bomber: climbs over its hangar, tips over into a screaming dive,
## lets the bomb go low and pulls out — then picks another hangar.
func _tick_diver(delta: float) -> void:
	if state == State.ENTER:
		_entering(delta, 1.3)
		return
	var hunting: bool = prey != null and is_instance_valid(prey) and (prey as Enemy).alive()
	if not hunting:
		prey = battle.campaign.live_hangar() if battle.campaign and battle.campaign.has_method("live_hangar") else null
		if prey == null:
			_tick_sparring(delta)
			return
	var tgt: Vector3 = (prey as Enemy).hit_center()
	var me: Vector3 = flight.pos
	var flat := Vector2(me.x - tgt.x, me.z - tgt.z).length()
	_mode_t -= delta
	var spd := 1.15
	var turn := 2.0
	match _mode:
		"dive":
			_goal = tgt
			spd = 1.75
			turn = 2.8
			if me.y - tgt.y < 0.55 or flat < 0.12:
				battle.enemy_fire("ebomb", me + Vector3(0, -0.04, 0), Vector3.DOWN, velocity * 0.85)
				(parts.belly_bomb as Node3D).visible = false
				_mode = "pull"
				_mode_t = 1.8
		"pull":
			_goal = me + flight.fwd * 1.2 + Vector3(0, 1.4, 0)
			spd = 1.3
			turn = 2.6
			if _mode_t <= 0.0:
				_mode = "climb"
				(parts.belly_bomb as Node3D).visible = true
				if randf() < 0.5 and battle.campaign and battle.campaign.has_method("live_hangar"):
					prey = battle.campaign.live_hangar()
		_:
			# Climb and line up over the target, then tip over.
			var away := Vector3(me.x - tgt.x, 0, me.z - tgt.z)
			away = away.normalized() if away.length() > 0.01 else Vector3.BACK
			_goal = tgt + away * 0.9 + Vector3(0, 1.8, 0)
			if me.y > tgt.y + 1.45 and flat < 1.25 and flight.fwd.dot((tgt - me).normalized()) > 0.35:
				_mode = "dive"
				battle.cue("dive", me, 2.0)
				battle.callout(Lang.t("dive_warn"), Color(1.0, 0.45, 0.25), 1.0)
	if _mode != "dive":
		_goal = battle.clamp_front(_goal)
	_goal.y = clampf(_goal.y, battle.floor_y + 0.1, battle.floor_y + 2.6)
	flight = WarMath.fly(flight, _goal, spd, delta, battle.box, turn)
	_pose_from_flight()


## The friendly supply plane: follows its route at the pace the mission sets
## (path_speed = progress 0…1 along the route).
var _route_len: float = -1.0
func _tick_cargo(delta: float) -> void:
	if path.size() < 2:
		return
	if _route_len < 0.0:
		_route_len = 0.0
		var prev: Vector3 = flight.pos
		for p in path:
			_route_len += prev.distance_to(p)
			prev = p
	var want := _route_point(clampf(path_speed + 0.02, 0.0, 1.0))
	var me: Vector3 = flight.pos
	var to := want - me
	var step := minf(to.length(), delta * 1.2)
	if to.length() > 0.001:
		var nf := WarMath.steer(flight.fwd, to.normalized(), 1.6, delta)
		var turn: float = (flight.fwd as Vector3).cross(nf).y
		flight.bank = lerpf(flight.bank, clampf(turn / maxf(delta, 1e-4) * 0.35, -0.6, 0.6), minf(1.0, delta * 3.0))
		flight.fwd = nf
		flight.pos = me + nf * step
	_pose_from_flight()


func _route_point(u: float) -> Vector3:
	var goal_len := u * _route_len
	var prev: Vector3 = path[0]
	var acc := 0.0
	for i in range(1, path.size()):
		var p: Vector3 = path[i]
		var seg := prev.distance_to(p)
		if acc + seg >= goal_len:
			return prev.lerp(p, (goal_len - acc) / maxf(seg, 1e-5))
		acc += seg
		prev = p
	return path[path.size() - 1]


## A destroyed hangar stays as a burnt shell.
func ruin() -> void:
	state = State.DEAD
	var root: Node3D = parts.root
	root.scale = Vector3(1.0, 0.35, 1.0)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = Toon.mat(Color(0.18, 0.16, 0.15), 0.1, 0.0015)
	if battle:
		Fx.smoke(battle, global_position + Vector3(0, 0.05, 0), 0.06, true)

## Shot-down planes spiral down trailing smoke and blow up on the floor.
func start_fall() -> void:
	state = State.FALLING
	_fall_spin = 0.0
	if _engine:
		_engine.pitch_scale *= 0.7


func _tick_falling(delta: float) -> void:
	_fall_spin += delta * 6.0
	var fwd: Vector3 = flight.fwd
	fwd = (fwd + Vector3(0, -1.4 * delta, 0)).normalized()
	flight.fwd = fwd
	flight.speed = minf(2.0, float(flight.speed) + delta * 1.2)
	flight.pos += fwd * flight.speed * delta
	global_position = flight.pos
	global_basis = Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.BACK) * Basis(Vector3.FORWARD, _fall_spin)
	_smoke_t -= delta
	if _smoke_t <= 0.0 and battle:
		_smoke_t = 0.04
		Fx.smoke(battle, global_position, radius * 0.25, true)
		if randf() < 0.3:
			Fx.sparks(battle, global_position, Vector3.UP, 2, Color(1.0, 0.6, 0.2))
	if global_position.y <= battle.surface_below(global_position) + 0.03 or age > 12.0:
		battle.on_wreck_landed(self)


## Follows its convoy route along the floor; leaving the end = escaped.
func _tick_convoy(delta: float) -> void:
	if path.is_empty():
		return
	var goal: Vector3 = path[0]
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 0.05:
		path.pop_front()
		if path.is_empty():
			state = State.ESCAPED
		return
	var f := -global_basis.z
	f.y = 0.0
	var nf := WarMath.steer(f.normalized() if f.length() > 0.01 else to.normalized(), to.normalized(), 2.0, delta)
	global_position += nf * path_speed * delta
	global_position.y = battle.surface_below(global_position + Vector3(0, 0.05, 0))
	_face(nf)
	if parts.has("wheels"):
		for w in parts.wheels:
			(w as Node3D).rotate_object_local(Vector3.RIGHT, -path_speed * delta / 0.015)
	state = State.ACTIVE


## Rifle soldier: runs to a spot, then stands and takes pot-shots at the plane.
func _tick_soldier(delta: float) -> void:
	state = State.ACTIVE
	var legs: Array = parts.legs
	if run_to != Vector3.INF:
		var to := run_to - global_position
		to.y = 0.0
		if to.length() < 0.03:
			run_to = Vector3.INF
		else:
			global_position += to.normalized() * 0.18 * delta
			global_position.y = battle.surface_below(global_position + Vector3(0, 0.05, 0))
			_face(to)
			_walk += delta * 14.0
			for i in range(legs.size()):
				(legs[i] as Node3D).rotation.x = sin(_walk + PI * i) * 0.7
			return
	for l in legs:
		(l as Node3D).rotation.x = 0.0
	var to_p: Vector3 = battle.player_position() - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	if flat.length() > 0.01:
		var want := Basis.looking_at(flat.normalized(), Vector3.UP)
		global_basis = global_basis.orthonormalized().slerp(want, minf(1.0, delta * 4.0)).orthonormalized()
	(parts.arms as Node3D).rotation.x = lerpf((parts.arms as Node3D).rotation.x, clampf(atan2(to_p.y, flat.length()), 0.0, 1.2), minf(1.0, delta * 4.0))
	_fire_t -= delta
	if _fire_t <= 0.0 and battle.player_airborne() and to_p.length() < 3.5:
		_fire_t = _rng.randf_range(1.8, 3.2)
		var dir := (to_p + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.1, 0.2), _rng.randf_range(-0.2, 0.2))).normalized()
		var from := global_position + Vector3(0, 0.045, 0) + dir * 0.03
		battle.enemy_fire("ebullet", from, dir, Vector3.ZERO)
		Fx.muzzle(battle, from, dir, 0.01)


## Anti-air team: idle (reloading) → PREP for 2 s — the crew raises the tube,
## a red "!" blinks overhead, a red aim line locks on and a beep speeds up —
## → FIRE a homing missile you can outturn, barrel-roll past or shoot down.
func _tick_sam(delta: float) -> void:
	state = State.ACTIVE
	var tube: Node3D = parts.tube
	var mount: Node3D = parts.mount
	var lamp := parts.lamp as MeshInstance3D
	var you: Vector3 = battle.player_position()
	var to := you - (parts.muzzle as Node3D).global_position
	sam_t -= delta
	match sam_phase:
		"idle":
			tube.rotation.x = lerpf(tube.rotation.x, -0.1, minf(1.0, delta * 3.0))
			_warn.visible = false
			_aim_line.visible = false
			(lamp.material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.35, 0.06, 0.06))
			for c in crew:
				(c.arms as Node3D).rotation.x = lerpf((c.arms as Node3D).rotation.x, 0.0, minf(1.0, delta * 3.0))
			if sam_t <= 0.0 and battle.player_airborne() and to.length() < 5.0:
				sam_phase = "prep"
				sam_t = WarMath.SAM_PREP
				battle.cue("alarm", global_position, -2.0)
		"prep":
			var u := 1.0 - sam_t / WarMath.SAM_PREP
			# Crew heaves the tube up and swings it onto the plane.
			var local: Vector3 = global_transform.affine_inverse() * you
			var yaw := atan2(-local.x, -local.z)
			mount.rotation.y = lerp_angle(mount.rotation.y, yaw, minf(1.0, delta * 5.0))
			var pitch := clampf(atan2(local.y - 0.04, Vector2(local.x, local.z).length()), 0.15, 1.4)
			tube.rotation.x = lerpf(tube.rotation.x, pitch, minf(1.0, delta * 4.0))
			for c in crew:
				(c.arms as Node3D).rotation.x = 1.1
			var period := lerpf(0.4, 0.1, u)
			var on := fmod(age, period) < period * 0.5
			_warn.visible = on
			_warn.scale = Vector3.ONE * (1.0 + u * 0.6)
			(lamp.material_override as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.15, 0.1) if on else Color(0.35, 0.06, 0.06))
			_aim_line.visible = true
			_aim_mesh.clear_surfaces()
			_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			var a: Vector3 = (parts.muzzle as Node3D).global_position
			for k in range(10):
				var t0 := k / 10.0
				_aim_mesh.surface_add_vertex(a.lerp(you, t0))
				_aim_mesh.surface_add_vertex(a.lerp(you, t0 + 0.05))
			_aim_mesh.surface_end()
			_beep_t -= delta
			if _beep_t <= 0.0:
				_beep_t = period
				battle.cue("lock", global_position, -6.0)
			if sam_t <= 0.0:
				sam_phase = "idle"
				sam_t = _rng.randf_range(4.0, 6.0) * reload_mult
				_warn.visible = false
				_aim_line.visible = false
				var m: Node3D = parts.muzzle
				var s: Shot = battle.enemy_fire("sam", m.global_position, -m.global_basis.z, Vector3.ZERO)
				if s:
					s.target = battle.plane
				Fx.muzzle(battle, m.global_position, -m.global_basis.z, 0.03)
				Fx.smoke(battle, m.global_position + m.global_basis.z * 0.08, 0.03)
				battle.cue("rocket", m.global_position)
var _beep_t: float = 0.0
