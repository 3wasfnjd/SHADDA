class_name PlayerJet
extends Node3D
## The player's fighter. It flies a hand-length ahead of the right controller
## along its aim ray (a stiff spring, so it feels like flying but stays
## precise), rolls with the wrist and banks into turns.
##
## Right trigger  cannon (twin, alternating)      Right grip  hold = lock up to 4, release = salvo
## A              bomb (impact ring on the floor)   B           flares (decoy enemy missiles)
## Left trigger   laser (overheats)

var battle = null
var hand: XRController3D = null          # for haptics (null in tests)
var model: Dictionary = {}
var armor: float = CombatMath.JET_ARMOR
var velocity: Vector3 = Vector3.ZERO
var missiles: int = CombatMath.MISSILE_STOCK
var bombs: int = CombatMath.BOMB_STOCK
var flares: int = CombatMath.FLARE_STOCK
var heat: float = 0.0
var overheated: bool = false
var lasing: bool = false
var locks: Array = []                    # Enemy nodes, in lock order
var destroyed: bool = false
var hit_flash: float = 0.0
var weapons_live: bool = true            # false in menus: cannon only, no damage taken
var _cannon_cd: float = 0.0
var _barrel: int = 0
var _lock_timer: float = 0.0
var _grip_held: bool = false
var _grip_time: float = 0.0
var _salvo: Array = []
var _salvo_timer: float = 0.0
var _missile_reload: float = 0.0
var _bomb_reload: float = 0.0
var _flare_reload: float = 0.0
var _beam: MeshInstance3D
var _beam_mesh := ImmediateMesh.new()
var _beam_glow: MeshInstance3D
var _beam_glow_mesh := ImmediateMesh.new()
var _sight: MeshInstance3D
var _sight_mesh := ImmediateMesh.new()
var _pipper: MeshInstance3D
var _impact_ring: MeshInstance3D
var _muzzle_flash: MeshInstance3D
var _smoke_timer: float = 0.0
var _placed: bool = false
var aim_point: Vector3 = Vector3.ZERO     # where the nose is pointing (for UI buttons and tests)


func _ready() -> void:
	model = Models.jet(false)
	add_child(model.root)
	_beam = MeshInstance3D.new()
	_beam.mesh = _beam_mesh
	_beam.material_override = Neon.glow_material(Color(0.4, 0.9, 1.0), true)
	_beam.top_level = true
	_beam.extra_cull_margin = 8.0
	add_child(_beam)
	_beam_glow = MeshInstance3D.new()
	_beam_glow.mesh = _beam_glow_mesh
	_beam_glow.material_override = Neon.glow_material(Neon.CYAN, false)
	_beam_glow.top_level = true
	_beam_glow.extra_cull_margin = 8.0
	add_child(_beam_glow)
	# Gun sight: a hairline from the nose to whatever it points at, and a pipper there.
	_sight = MeshInstance3D.new()
	_sight.mesh = _sight_mesh
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.no_depth_test = false
	_sight.material_override = sm
	_sight.top_level = true
	_sight.extra_cull_margin = 8.0
	add_child(_sight)
	_pipper = Neon.make_ring_mesh(Color(0.5, 1.0, 0.6), 0.022, 0.0016)
	_pipper.top_level = true
	add_child(_pipper)
	_impact_ring = Neon.make_ring_mesh(Color(1.0, 0.85, 0.2), 0.06, 0.002)
	_impact_ring.top_level = true
	_impact_ring.visible = false
	add_child(_impact_ring)
	_muzzle_flash = Neon.make_halo(Color(1.0, 0.8, 0.4), 0.08, 0.0)
	_muzzle_flash.top_level = true
	add_child(_muzzle_flash)
	refresh_stores()


func reset() -> void:
	armor = CombatMath.JET_ARMOR
	missiles = CombatMath.MISSILE_STOCK
	bombs = CombatMath.BOMB_STOCK
	flares = CombatMath.FLARE_STOCK
	heat = 0.0
	overheated = false
	locks.clear()
	_salvo.clear()
	destroyed = false
	visible = true
	refresh_stores()


func forward() -> Vector3:
	return -global_basis.z


func nose() -> Vector3:
	return (model.nose as Node3D).global_position


## Follows the aim pose. `aim` is the controller's aim transform (world space).
func fly(delta: float, aim: Transform3D) -> void:
	var fwd := -aim.basis.z.normalized()
	var target := aim.origin + fwd * CombatMath.JET_LEAD
	if battle:
		target.y = maxf(target.y, battle.floor_y + 0.06)
	if not _placed:
		global_position = target
		velocity = Vector3.ZERO
		_placed = true
	var r: Array = CombatMath.spring(global_position, velocity, target, 22.0, delta)
	global_position = r[0]
	velocity = r[1]
	# Orientation: the controller's own frame (so the wrist rolls the jet),
	# plus a little bank into lateral motion and a nose lift when climbing.
	var up := aim.basis.y.normalized()
	var want := Basis.looking_at(fwd, up)
	var lateral := velocity.dot(want.x)
	want = want * Basis(Vector3.FORWARD, clampf(-lateral * 1.2, -0.7, 0.7))
	var q := global_basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), minf(1.0, delta * 26.0))
	global_basis = Basis(q)
	var burn := clampf(0.6 + velocity.length() * 0.8, 0.6, 1.6)
	(model.burner as Node3D).scale = Vector3(1, 1, burn + sin(Time.get_ticks_msec() * 0.06) * 0.08)


func control(delta: float, trigger_r: float, grip_r: float, trigger_l: float) -> void:
	if destroyed:
		_beam.visible = false
		_beam_glow.visible = false
		return
	hit_flash = maxf(0.0, hit_flash - delta * 4.0)
	_reload(delta)
	_update_sight()
	# Cannon.
	_cannon_cd -= delta
	if trigger_r > 0.55 and _cannon_cd <= 0.0:
		_cannon_cd = 1.0 / CombatMath.CANNON_RATE
		_fire_cannon()
	(_muzzle_flash.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, (_muzzle_flash.material_override as StandardMaterial3D).albedo_color.a - delta * 12.0)
	if not weapons_live:
		_beam.visible = false
		_beam_glow.visible = false
		_impact_ring.visible = false
		return
	# Missile lock: hold grip to sweep locks, release to fire.
	if grip_r > 0.55:
		_grip_time += delta
		_grip_held = true
		_lock_timer -= delta
		if _lock_timer <= 0.0 and locks.size() < mini(CombatMath.MISSILE_LOCKS, missiles):
			var e = _best_lock_candidate()
			if e:
				locks.append(e)
				_lock_timer = CombatMath.LOCK_TIME
				_haptic(0.35, 0.04)
				if battle:
					battle.cue("lock", global_position, -6.0 + locks.size() * 1.5)
	elif grip_r < 0.3 and _grip_held:
		_grip_held = false
		_release_salvo()
		_grip_time = 0.0
		_lock_timer = 0.0
	for i in range(locks.size() - 1, -1, -1):
		if not is_instance_valid(locks[i]) or not locks[i].alive():
			locks.remove_at(i)
	_salvo_timer -= delta
	if not _salvo.is_empty() and _salvo_timer <= 0.0:
		_salvo_timer = 0.09
		_launch_missile(_salvo.pop_front())
	# Laser.
	if overheated:
		heat = maxf(0.0, heat - CombatMath.LASER_COOL * 1.3 * delta)
		if heat <= 0.15:
			overheated = false
	lasing = trigger_l > 0.55 and not overheated
	if lasing:
		heat = minf(1.0, heat + CombatMath.LASER_HEAT * delta)
		if heat >= 1.0:
			overheated = true
			lasing = false
			_haptic(0.6, 0.15)
			if battle:
				battle.cue("overheat", global_position)
	else:
		heat = maxf(0.0, heat - CombatMath.LASER_COOL * delta)
	_update_laser(delta)
	# Bomb predictor ring on the floor while there are ground units.
	if battle and bombs > 0 and battle.has_ground_units():
		var p: Vector3 = CombatMath.bomb_impact(global_position + Vector3(0, -0.03, 0), velocity + forward() * 0.5, battle.floor_y)
		_impact_ring.visible = true
		_impact_ring.global_position = p + Vector3(0, 0.004, 0)
		_impact_ring.global_basis = Basis.IDENTITY
	else:
		_impact_ring.visible = false
	# Smoke when badly hurt.
	if armor < CombatMath.JET_ARMOR * 0.3 and battle:
		_smoke_timer -= delta
		if _smoke_timer <= 0.0:
			_smoke_timer = 0.1
			battle.smoke_puff(global_position + global_basis.z * 0.12, 0.02)


func drop_bomb() -> bool:
	if destroyed or not weapons_live or bombs <= 0 or battle == null:
		return false
	bombs -= 1
	_bomb_reload = CombatMath.BOMB_RELOAD
	refresh_stores()
	var from := global_position + global_basis.y * -0.035
	battle.player_fire("bomb", from, forward(), velocity, null)
	battle.cue("bomb_drop", from)
	_haptic(0.4, 0.06)
	return true


func pop_flares() -> bool:
	if destroyed or not weapons_live or flares <= 0 or battle == null:
		return false
	flares -= 1
	_flare_reload = CombatMath.FLARE_RELOAD
	for s: float in [-1.0, 0.0, 1.0]:
		var dir := (global_basis.z + global_basis.x * 0.9 * s + Vector3(0, -0.2, 0)).normalized()
		battle.player_fire("flare", global_position + global_basis.z * 0.1, dir, velocity, null)
	battle.cue("flare", global_position)
	_haptic(0.3, 0.05)
	return true


func take_hit(amount: float) -> void:
	if destroyed or not weapons_live:
		return
	armor = maxf(0.0, armor - amount)
	hit_flash = 1.0
	_haptic(0.9, 0.18)
	if armor <= 0.0:
		destroyed = true
		visible = false


func repair(amount: float) -> void:
	armor = minf(CombatMath.JET_ARMOR, armor + amount)


func refresh_stores() -> void:
	if model.is_empty():
		return
	for i in range(model.pylons.size()):
		(model.pylons[i] as Node3D).visible = i < missiles
	for i in range(model.bombs.size()):
		(model.bombs[i] as Node3D).visible = i < bombs


# --- internals -----------------------------------------------------------------

func _reload(delta: float) -> void:
	if missiles < CombatMath.MISSILE_STOCK:
		_missile_reload -= delta
		if _missile_reload <= 0.0:
			missiles += 1
			_missile_reload = CombatMath.MISSILE_RELOAD
			refresh_stores()
	else:
		_missile_reload = CombatMath.MISSILE_RELOAD
	if bombs < CombatMath.BOMB_STOCK:
		_bomb_reload -= delta
		if _bomb_reload <= 0.0:
			bombs += 1
			_bomb_reload = CombatMath.BOMB_RELOAD
			refresh_stores()
	if flares < CombatMath.FLARE_STOCK:
		_flare_reload -= delta
		if _flare_reload <= 0.0:
			flares += 1
			_flare_reload = CombatMath.FLARE_RELOAD


func _fire_cannon() -> void:
	if battle == null:
		return
	var muzzle: Node3D = model.muzzles[_barrel]
	_barrel = 1 - _barrel
	var spread := deg_to_rad(CombatMath.CANNON_SPREAD_DEG)
	var dir := forward().rotated(global_basis.x, randf_range(-spread, spread)).rotated(global_basis.y, randf_range(-spread, spread))
	# Converge both barrels on the pipper so the stream lands on the sight.
	if aim_point != Vector3.ZERO and aim_point.distance_to(muzzle.global_position) > 0.25:
		dir = (aim_point - muzzle.global_position).normalized().rotated(global_basis.x, randf_range(-spread, spread))
	battle.player_fire("bullet", muzzle.global_position, dir, velocity, null)
	battle.cue("cannon", muzzle.global_position, -4.0)
	_muzzle_flash.global_position = muzzle.global_position + dir * 0.012
	(_muzzle_flash.material_override as StandardMaterial3D).albedo_color.a = 0.9
	_haptic(0.12, 0.02)


func _best_lock_candidate():
	if battle == null:
		return null
	var best = null
	var best_angle := INF
	for e in battle.enemies:
		if not e.can_be_locked() or locks.has(e):
			continue
		var c: Vector3 = e.hit_center()
		if not CombatMath.in_lock_cone(nose(), forward(), c):
			continue
		var a := CombatMath.off_axis_deg(nose(), forward(), c)
		if a < best_angle:
			best_angle = a
			best = e
	return best


func _release_salvo() -> void:
	if missiles <= 0:
		locks.clear()
		return
	if locks.is_empty():
		_salvo.append(null)             # dumb-fire one straight ahead
	else:
		for e in locks:
			_salvo.append(e)
	locks.clear()


func _launch_missile(target) -> void:
	if missiles <= 0 or battle == null:
		return
	missiles -= 1
	_missile_reload = CombatMath.MISSILE_RELOAD
	# Fire from the outermost loaded pylon down to the innermost.
	var idx := clampi(missiles, 0, model.pylons.size() - 1)
	var from: Vector3 = (model.pylons[idx] as Node3D).global_position
	refresh_stores()
	battle.player_fire("missile", from, forward(), velocity, target)
	battle.cue("missile", from)
	_haptic(0.5, 0.07)


func _update_sight() -> void:
	var o := nose()
	var f := forward()
	var dist := 3.0
	var hit_enemy := false
	if battle:
		var r: Dictionary = battle.ray_scene(o, f, 6.0)
		dist = r.distance
		hit_enemy = r.enemy != null
	aim_point = o + f * dist
	_sight_mesh.clear_surfaces()
	_sight_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var segments := 14
	for i in range(segments):
		var t0 := float(i) / segments
		var t1 := t0 + 0.5 / segments
		var a := (1.0 - t0) * 0.55
		var col := Color(0.5, 1.0, 0.6, a) if not hit_enemy else Color(1.0, 0.35, 0.3, a)
		_sight_mesh.surface_set_color(col)
		_sight_mesh.surface_add_vertex(o + f * dist * t0)
		_sight_mesh.surface_set_color(col)
		_sight_mesh.surface_add_vertex(o + f * dist * t1)
	_sight_mesh.surface_end()
	_pipper.global_position = aim_point - f * 0.01
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to_cam := cam.global_position - _pipper.global_position
		if to_cam.length() > 0.01:
			_pipper.look_at(_pipper.global_position - to_cam, Vector3.UP)
			_pipper.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_pipper.scale = Vector3.ONE * clampf(to_cam.length() / 1.2, 0.5, 3.0)
	((_pipper.material_override) as StandardMaterial3D).albedo_color = Color(1.0, 0.35, 0.3) if hit_enemy else Color(0.5, 1.0, 0.6)


func _update_laser(delta: float) -> void:
	_beam_mesh.clear_surfaces()
	_beam_glow_mesh.clear_surfaces()
	_beam.visible = lasing
	_beam_glow.visible = lasing
	if not lasing or battle == null:
		return
	var o: Vector3 = (model.laser as Node3D).global_position
	var f := forward()
	var r: Dictionary = battle.ray_scene(o, f, CombatMath.LASER_RANGE)
	var end: Vector3 = o + f * float(r.distance)
	if r.enemy != null:
		battle.laser_hit(r.enemy, CombatMath.LASER_DPS * delta, end)
	elif r.wall:
		battle.laser_burn(end, r.normal, delta)
	var pts := PackedVector3Array([o, end])
	var flick := 0.85 + randf() * 0.3
	Neon.build_tube(_beam_mesh, pts, func(_t): return 0.0016 * flick)
	Neon.build_tube(_beam_glow_mesh, pts, func(_t): return 0.007 * flick)
	if Engine.get_physics_frames() % 6 == 0:
		_haptic(0.15, 0.03)


func _haptic(amplitude: float, duration: float) -> void:
	if hand and hand.get_is_active():
		hand.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)
