class_name Enemy
extends Node3D
## Every enemy in the room war. The battle creates them at a real door or
## window (planes, tanks), on a real surface (balloons) or where a supply
## crate lands (flak guns), and ticks them each physics frame.

enum State { ENTER, ACTIVE, ESCAPED, DEAD }

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
	add_child(parts.root)
	if kind in ["fighter", "transport", "bomber", "balloon"]:
		_shadow = Toon.shadow_blob(radius * 2.6)
		add_child(_shadow)
	if kind in ["fighter", "transport", "bomber", "tank"]:
		_engine = AudioStreamPlayer3D.new()
		var s = load("res://assets/audio/" + ("tank_engine" if kind == "tank" else "enemy_engine") + ".wav")
		if s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).data.size() / 2
		_engine.stream = s
		_engine.unit_size = 0.7 if kind != "bomber" else 1.4
		_engine.max_distance = 7.0
		_engine.volume_db = -20.0 if kind != "bomber" else -12.0
		_engine.pitch_scale = {"fighter": 1.15, "transport": 0.8, "bomber": 0.6, "tank": 1.0}[kind]
		_engine.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
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
	return global_position


func alive() -> bool:
	return state == State.ENTER or state == State.ACTIVE


func can_be_locked() -> bool:
	return alive() and (state == State.ACTIVE or kind == "bomber" or kind == "transport")


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
	if kind == "bomber" and at != Vector3.INF:
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
	if hp <= 0.0 or (kind == "bomber" and _dead_engines() >= 3):
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
	match kind:
		"fighter":
			_tick_fighter(delta)
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
	var jet: Vector3 = battle.player_position()
	var to: Vector3 = jet - (flight.pos as Vector3)
	_mode_t -= delta
	if _mode == "attack":
		_goal = jet + battle.player_velocity() * 0.35
		if to.length() < 0.45 or _mode_t < -6.0:
			_mode = "extend"
			_mode_t = _rng.randf_range(1.4, 2.4)
			_goal = WarMath.clamp_into(flight.pos + flight.fwd * 1.6 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.4), _rng.randf_range(-1, 1)), battle.box, 0.5, 0.6)
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
			var dir: Vector3 = (jet + battle.player_velocity() * (to.length() / WarMath.ENEMY_BULLET_SPEED) - m.global_position).normalized()
			dir = (dir + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))).normalized()
			battle.enemy_fire("ebullet", m.global_position, dir, velocity)
			Fx.muzzle(battle, m.global_position, dir, 0.014)
	elif _fire_t <= 0.0 and _mode == "attack" and flight.fwd.dot(to.normalized()) > 0.94 and to.length() < 2.4:
		_burst = 6
		_fire_t = _rng.randf_range(1.6, 2.6)
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
	var rx := maxf(0.55, (hi.x - lo.x) * 0.5 - 0.6)
	var rz := maxf(0.55, (hi.z - lo.z) * 0.5 - 0.6)
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


func _tick_tank(delta: float) -> void:
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
