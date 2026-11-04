class_name Enemy
extends Node3D
## Every hostile thing in the room. The battle director creates them at a
## hangar (or a wall spot for targets) and calls `tick()` each physics frame.
##
## target  — practice target that swings out of a real wall
## drone   — quadcopter: hovers around you and fires slow red pellets
## fighter — enemy jet: laps the room, launches heat-seeking missiles
## tank    — rolls out of a floor-level bay, fires flak shells upward
## boss    — gunship from the big bay: strafes, bursts, missile pairs

enum State { EMERGE, ACTIVE, DYING }

var kind: String = "drone"
var hp: float = 1.0
var max_hp: float = 1.0
var radius: float = 0.1
var speed: float = 1.0
var state: State = State.EMERGE
var battle = null                      # BattleDirector
var hangar = null                      # Hangar it came out of (or null)
var wall_normal: Vector3 = Vector3.BACK
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var hit_flash: float = 0.0
var parts: Dictionary = {}
var _goal: Vector3
var _goal_timer: float = 0.0
var _fire_timer: float = 0.0
var _missile_timer: float = 0.0
var _burst_left: int = 0
var _burst_timer: float = 0.0
var _emerge_from: Vector3
var _emerge_to: Vector3
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0
var _hit_mats: Array = []
var _rng := RandomNumberGenerator.new()
var _smoke_timer: float = 0.0


static func create(enemy_kind: String) -> Enemy:
	var e := Enemy.new()
	e.kind = enemy_kind
	var spec: Dictionary = CombatMath.ENEMIES[enemy_kind]
	e.hp = spec.hp
	e.max_hp = spec.hp
	e.radius = spec.radius
	e.speed = spec.speed
	e.name = enemy_kind.capitalize()
	return e


func _ready() -> void:
	_rng.randomize()
	match kind:
		"target":
			parts = Models.target()
		"drone":
			parts = Models.drone()
		"fighter":
			parts = Models.jet(true)
			parts.root.scale = Vector3.ONE * 0.85
		"tank":
			parts = Models.tank()
		"boss":
			parts = Models.gunship()
	add_child(parts.root)
	_fire_timer = _rng.randf_range(1.2, 2.4)
	_missile_timer = _rng.randf_range(3.0, 5.0)
	_orbit_dir = 1.0 if _rng.randf() < 0.5 else -1.0


## Centre of the hit sphere in world space.
func hit_center() -> Vector3:
	match kind:
		"target":
			return (parts.face as Node3D).global_position
		"tank":
			return global_position + Vector3(0, 0.045, 0)
	return global_position


func alive() -> bool:
	return state != State.DYING and is_inside_tree()


func can_be_locked() -> bool:
	return alive() and (state == State.ACTIVE or kind == "boss")


## Starts the emerge animation: from inside the wall bay to just in front of it.
func emerge(from: Vector3, to: Vector3, normal: Vector3) -> void:
	_emerge_from = from
	_emerge_to = to
	wall_normal = normal
	global_position = from
	_face(normal)
	state = State.EMERGE
	age = 0.0


func _face(dir: Vector3) -> void:
	var d := dir
	if kind == "tank" or kind == "target":
		d.y = 0.0
	if d.length_squared() < 1e-6:
		return
	look_at(global_position + d.normalized(), Vector3.UP)


func damage(amount: float) -> bool:
	if not alive():
		return false
	hp -= amount
	hit_flash = 1.0
	if hp <= 0.0:
		state = State.DYING
		return true
	return false


func tick(delta: float) -> void:
	age += delta
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	_flash_paint()
	if state == State.EMERGE:
		var dur: float = {"target": 0.45, "drone": 1.0, "fighter": 0.7, "tank": 1.4, "boss": 3.0}[kind]
		var u := clampf(age / dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		if kind == "target":
			(parts.hinge as Node3D).rotation_degrees.x = lerpf(-88.0, 0.0, e)
		else:
			global_position = _emerge_from.lerp(_emerge_to, e if kind != "tank" else u)
		_animate(delta)
		if u >= 1.0:
			state = State.ACTIVE
			_goal = global_position
			velocity = wall_normal * speed * 0.6
		return
	if state != State.ACTIVE:
		return
	match kind:
		"drone":
			_tick_drone(delta)
		"fighter":
			_tick_fighter(delta)
		"tank":
			_tick_tank(delta)
		"boss":
			_tick_boss(delta)
		"target":
			(parts.face as Node3D).rotation_degrees.z = sin(age * 1.7) * 6.0
	_animate(delta)
	if hp < max_hp * 0.4 and kind != "target":
		_smoke_timer -= delta
		if _smoke_timer <= 0.0:
			_smoke_timer = 0.12
			battle.smoke_puff(global_position, radius * 0.5)


func _animate(delta: float) -> void:
	if kind == "drone":
		for r in parts.rotors:
			(r as Node3D).rotate_y(delta * 40.0)
	elif kind == "boss":
		for g in parts.engines:
			(g as Node3D).scale = Vector3(1, 1, 0.35 + 0.08 * sin(age * 31.0 + g.position.x * 40.0))


func _flash_paint() -> void:
	if hit_flash <= 0.0 and _hit_mats.is_empty():
		return
	if _hit_mats.is_empty() and hit_flash > 0.0:
		for mi in parts.root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.material_override is StandardMaterial3D and not (m.material_override as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				m.material_overlay = _overlay()
				_hit_mats.append(m)
	if hit_flash <= 0.0:
		for m in _hit_mats:
			if is_instance_valid(m):
				(m as MeshInstance3D).material_overlay = null
		_hit_mats.clear()
	elif not _hit_mats.is_empty():
		var ov := (_hit_mats[0] as MeshInstance3D).material_overlay as StandardMaterial3D
		if ov:
			ov.albedo_color = Color(1, 1, 1, 0.75 * hit_flash)


var _ov_mat: StandardMaterial3D
func _overlay() -> StandardMaterial3D:
	if _ov_mat == null:
		_ov_mat = StandardMaterial3D.new()
		_ov_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ov_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ov_mat.albedo_color = Color(1, 1, 1, 0.75)
	return _ov_mat


# --- behaviours -------------------------------------------------------------------

func _pick_air_goal(min_d: float, max_d: float, low: float, high: float) -> Vector3:
	var head: Vector3 = battle.head_position()
	var center: Vector3 = battle.box_center()
	for i in range(12):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(min_d, max_d)
		var p := head.lerp(center, 0.4) + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = battle.floor_y + _rng.randf_range(low, high)
		p = CombatMath.clamp_into(p, battle.box, 0.35, low)
		var flat := Vector2(p.x - head.x, p.z - head.z).length()
		if flat >= min_d * 0.8:
			return p
	return CombatMath.clamp_into(head + Vector3(0, 0, -1.4), battle.box, 0.35, low)


func _tick_drone(delta: float) -> void:
	_goal_timer -= delta
	if _goal_timer <= 0.0 or global_position.distance_to(_goal) < 0.12:
		_goal = _pick_air_goal(0.8, 2.0, 0.9, 1.9)
		_goal_timer = _rng.randf_range(2.0, 3.5)
	var to := _goal - global_position
	var want := to.normalized() * minf(speed, to.length() * 2.0)
	velocity = velocity.lerp(want, minf(1.0, delta * 2.2))
	global_position += velocity * delta
	global_position.y += sin(age * 3.1) * 0.03 * delta
	var aim: Vector3 = battle.jet_position() - global_position
	_face(aim)
	rotate_object_local(Vector3.RIGHT, clampf(-velocity.length() * 0.25, -0.35, 0.0))
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = _rng.randf_range(2.0, 3.2)
		var dir: Vector3 = (battle.jet_position() - global_position).normalized()
		dir = (dir + Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06))).normalized()
		battle.enemy_fire("pellet", global_position + dir * 0.06, dir, null)


func _tick_fighter(delta: float) -> void:
	# Laps the room on a tilted ellipse that drifts; banks into the turn.
	var c: Vector3 = battle.box_center()
	var lo: Vector3 = battle.box.min
	var hi: Vector3 = battle.box.max
	var rx := maxf(0.6, (hi.x - lo.x) * 0.5 - 0.45)
	var rz := maxf(0.6, (hi.z - lo.z) * 0.5 - 0.45)
	_orbit_angle += _orbit_dir * speed / maxf(rx, rz) * delta
	var goal := Vector3(c.x + cos(_orbit_angle) * rx, battle.floor_y + 1.55 + sin(_orbit_angle * 2.0 + age * 0.3) * 0.35, c.z + sin(_orbit_angle) * rz)
	var to := goal - global_position
	var want := to.normalized() * speed if to.length() > 0.05 else velocity
	var prev_v := velocity
	velocity = velocity.lerp(want, minf(1.0, delta * 3.0))
	global_position += velocity * delta
	if velocity.length() > 0.05:
		look_at(global_position + velocity, Vector3.UP)
		var turn_rate := prev_v.normalized().cross(velocity.normalized()).y / maxf(delta, 1e-3)
		rotate_object_local(Vector3.FORWARD, clampf(turn_rate * 0.35, -1.0, 1.0))
	_missile_timer -= delta
	var to_jet: Vector3 = battle.jet_position() - global_position
	if _missile_timer <= 0.0 and to_jet.length() < 4.0:
		_missile_timer = _rng.randf_range(5.0, 7.0)
		battle.enemy_fire("emissile", global_position - global_basis.y * 0.03, (-global_basis.z + to_jet.normalized()).normalized(), battle.jet)
	_fire_timer -= delta
	if _fire_timer <= 0.0 and (-global_basis.z).dot(to_jet.normalized()) > 0.85:
		_fire_timer = 1.6
		battle.enemy_fire("pellet", global_position - global_basis.z * 0.12, to_jet.normalized(), null)


func _tick_tank(delta: float) -> void:
	if _goal_timer <= 0.0:
		var into := _rng.randf_range(0.6, 1.3)
		_goal = global_position + wall_normal * into
		_goal = CombatMath.clamp_into(_goal, battle.box, 0.3, 0.0)
		_goal.y = battle.floor_y
		_goal_timer = 99.0
	var to := _goal - global_position
	to.y = 0.0
	if to.length() > 0.03:
		velocity = to.normalized() * speed
		global_position += velocity * delta
		_face(velocity)
	else:
		velocity = Vector3.ZERO
	# Turret and barrels track the jet.
	var turret: Node3D = parts.turret
	var jet_p: Vector3 = battle.jet_position()
	var local := global_transform.affine_inverse() * jet_p
	var yaw := atan2(-local.x, -local.z)
	turret.rotation.y = lerp_angle(turret.rotation.y, yaw, minf(1.0, delta * 3.0))
	var flat := Vector2(local.x, local.z).length()
	var pitch := atan2(local.y - 0.08, flat)
	(parts.barrels as Node3D).rotation.x = lerpf((parts.barrels as Node3D).rotation.x, clampf(pitch, 0.1, 1.45), minf(1.0, delta * 3.0))
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = _rng.randf_range(2.2, 3.0)
		var muzzle: Node3D = parts.muzzle
		var lead: Vector3 = jet_p + battle.jet_velocity() * (jet_p.distance_to(muzzle.global_position) / CombatMath.FLAK_SPEED)
		var dir := (lead - muzzle.global_position).normalized()
		var s: Shot = battle.enemy_fire("flak", muzzle.global_position, dir, null)
		if s:
			s.fuse = muzzle.global_position.distance_to(lead)


func _tick_boss(delta: float) -> void:
	# Strafes across the room in front of the player, always facing them.
	var head: Vector3 = battle.head_position()
	var center: Vector3 = battle.box_center()
	var fwd := (center - head)
	fwd.y = 0.0
	if fwd.length() < 0.3:
		fwd = wall_normal * -1.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var hover := head + fwd * 1.7 + side * sin(age * 0.45) * 0.9
	hover.y = battle.floor_y + 1.65 + sin(age * 0.9) * 0.12
	hover = CombatMath.clamp_into(hover, battle.box, 0.45, 1.2)
	var to := hover - global_position
	velocity = velocity.lerp(to * 1.2, minf(1.0, delta * 1.5))
	global_position += velocity * delta
	var jet_p: Vector3 = battle.jet_position()
	var look := jet_p - global_position
	look.y *= 0.3
	if look.length() > 0.1:
		var target_basis := Basis.looking_at(look.normalized(), Vector3.UP)
		var roll := clampf(-velocity.dot(target_basis.x) * 0.4, -0.3, 0.3)
		target_basis = target_basis * Basis(Vector3.FORWARD, roll)
		global_basis = global_basis.orthonormalized().slerp(target_basis.orthonormalized(), minf(1.0, delta * 1.5)).orthonormalized()
	var turret: Node3D = parts.turret
	var local := turret.global_transform.affine_inverse() * jet_p
	turret.rotate_object_local(Vector3.UP, clampf(atan2(-local.x, -local.z), -delta * 2.0, delta * 2.0))
	# Bursts of five.
	_fire_timer -= delta
	if _fire_timer <= 0.0 and _burst_left <= 0:
		_burst_left = 5
		_fire_timer = _rng.randf_range(2.6, 3.4) * (0.75 if hp < max_hp * 0.5 else 1.0)
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = 0.13
			_burst_left -= 1
			var muzzle: Node3D = parts.muzzles[_burst_left % 2]
			var dir := (jet_p - muzzle.global_position).normalized()
			battle.enemy_fire("pellet", muzzle.global_position, dir, null)
	_missile_timer -= delta
	if _missile_timer <= 0.0:
		_missile_timer = _rng.randf_range(6.0, 8.0)
		for s: float in [-1.0, 1.0]:
			var from := global_position + global_basis.x * 0.2 * s
			battle.enemy_fire("emissile", from, (-global_basis.z + global_basis.x * 0.5 * s + Vector3.UP * 0.3).normalized(), battle.jet)
