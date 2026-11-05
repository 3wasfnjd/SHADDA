class_name PlayerPlane
extends Node3D
## The player's cartoon fighter. It really flies: it sits on the floor, rolls
## and takes off, always moves forward, turns toward the spot the right
## controller points at, banks, loses speed in climbs, bounces off real walls,
## and spirals down in smoke when shot to pieces.
##
## Right trigger  guns              Right grip  hold = lock (up to 4), release = rockets
## A              bomb              B           barrel roll (dodges fire)
## Left trigger   boost

enum State { PARKED, TAKEOFF, FLYING, CRASHING, WRECKED }

var battle = null
var hand: XRController3D = null
var model: Dictionary = {}
var state: State = State.PARKED
var flight: Dictionary = {"pos": Vector3.ZERO, "fwd": Vector3.FORWARD, "speed": 0.0, "bank": 0.0}
var hp: float = WarMath.PLANE_HP
var rockets: int = WarMath.ROCKETS
var bombs: int = WarMath.BOMBS
var boost: float = 1.0
var boosting: bool = false
var locks: Array = []
var hit_flash: float = 0.0
var ground_y: float = 0.0
var velocity: Vector3 = Vector3.ZERO
var steer_target: Vector3 = Vector3.ZERO
var gear_height: float = WarMath.GEAR_HEIGHT
var parked_pitch: float = 11.0
var _rpm: float = 0.0
var _gun_cd: float = 0.0
var _barrel: int = 0
var _lock_timer: float = 0.0
var _grip_held: bool = false
var _salvo: Array = []
var _salvo_timer: float = 0.0
var _rocket_reload: float = 0.0
var _bomb_reload: float = 0.0
var _roll_t: float = -1.0
var _roll_cd: float = 0.0
var _roll_dir: float = 1.0
var _gear: float = 1.0
var _air_time: float = 0.0
var _smoke_t: float = 0.0
var _crash_spin: float = 0.0
var _shadow: MeshInstance3D
var _engine: AudioStreamPlayer3D
var _sight: MeshInstance3D


func _ready() -> void:
	model = Models.player_plane(0.0018) if Models.has_player_model() else Models.fighter(Models.PLAYER, 0.0022)
	gear_height = model.get("gear_height", WarMath.GEAR_HEIGHT)
	parked_pitch = model.get("parked_pitch", 11.0)
	add_child(model.root)
	_shadow = Toon.shadow_blob(0.3)
	add_child(_shadow)
	# Gun sight: a small ring 1.2 m ahead of the nose.
	_sight = Toon.add(self, Toon.torus(0.025, 0.0018, 24), Toon.flat(Color(1.0, 0.95, 0.5, 0.9)))
	_sight.top_level = true
	_engine = AudioStreamPlayer3D.new()
	var stream = load("res://assets/audio/engine.wav")
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	_engine.stream = stream
	_engine.unit_size = 0.9
	_engine.max_distance = 8.0
	_engine.volume_db = -14.0
	_engine.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_engine)


# --- life cycle -------------------------------------------------------------------

## Parks the plane on a surface, nose along `heading`, tail resting on its wheel.
func park(at: Vector3, heading: Vector3, surface_y: float) -> void:
	var h := heading
	h.y = 0.0
	h = h.normalized() if h.length() > 0.01 else Vector3.FORWARD
	ground_y = surface_y
	state = State.PARKED
	hp = WarMath.PLANE_HP
	rockets = WarMath.ROCKETS
	bombs = WarMath.BOMBS
	boost = 1.0
	locks.clear()
	_salvo.clear()
	_roll_t = -1.0
	_gear = 1.0
	_rpm = 0.0
	_air_time = 0.0
	visible = true
	flight = {"pos": Vector3(at.x, surface_y + gear_height, at.z), "fwd": h, "speed": 0.0, "bank": 0.0}
	_apply_pose(0.0)
	refresh_stores()
	if _engine.playing:
		_engine.stop()


func start_engine() -> void:
	if state != State.PARKED:
		return
	state = State.TAKEOFF
	if _engine.stream:
		_engine.play()


func alive() -> bool:
	return state == State.FLYING or state == State.TAKEOFF


func airborne() -> bool:
	return state == State.FLYING


func forward() -> Vector3:
	return flight.fwd


func hit_center() -> Vector3:
	return global_position


func nose() -> Vector3:
	return (model.nose as Node3D).global_position


# --- per frame --------------------------------------------------------------------------

func tick(delta: float, aim_point: Vector3, trigger: float, grip: float, boost_in: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta * 4.0)
	steer_target = aim_point
	var prev: Vector3 = flight.pos
	match state:
		State.PARKED:
			_rpm = move_toward(_rpm, 0.0, delta * 2.0)
		State.TAKEOFF:
			_takeoff(delta)
		State.FLYING:
			_fly(delta, aim_point, boost_in)
			_weapons(delta, trigger, grip)
		State.CRASHING:
			_crash(delta)
		State.WRECKED:
			_rpm = 0.0
			_smoke_t -= delta
			if _smoke_t <= 0.0 and battle:
				_smoke_t = 0.15
				Fx.smoke(battle, global_position + Vector3(0, 0.03, 0), 0.02, true)
	velocity = (flight.pos - prev) / maxf(delta, 1e-4)
	_animate(delta)


func _takeoff(delta: float) -> void:
	_rpm = move_toward(_rpm, 1.0, delta * 1.5)
	if _rpm < 0.6:
		return
	flight.speed = minf(WarMath.CRUISE, flight.speed + delta * 1.1)
	var fwd: Vector3 = flight.fwd
	fwd.y = 0.0
	fwd = fwd.normalized()
	if flight.speed >= WarMath.TAKEOFF_SPEED:
		_air_time += delta
		fwd = (fwd + Vector3(0, 0.55, 0)).normalized()
	flight.fwd = fwd
	flight.pos += fwd * flight.speed * delta
	flight.pos.y = maxf(flight.pos.y, ground_y + gear_height)
	if flight.pos.y > ground_y + 0.3:
		state = State.FLYING
		if battle:
			battle.on_airborne()
	_hit_walls(flight.pos - fwd * flight.speed * delta)


func _fly(delta: float, aim_point: Vector3, boost_in: float) -> void:
	_air_time += delta
	_rpm = move_toward(_rpm, 1.0 + (0.3 if boosting else 0.0), delta * 2.0)
	boosting = boost_in > 0.5 and boost > 0.02
	if boosting:
		boost = maxf(0.0, boost - delta / WarMath.BOOST_SECONDS)
	else:
		boost = minf(1.0, boost + WarMath.BOOST_RECHARGE * delta)
	var want := WarMath.BOOST if boosting else WarMath.CRUISE
	var before: Vector3 = flight.pos
	var box: Dictionary = battle.box if battle else {"min": Vector3(-2, 0, -2), "max": Vector3(2, 2.5, 2)}
	flight = WarMath.fly(flight, aim_point, want, delta, box)
	# Keep clear of the floor and furniture tops under the plane.
	var floor_here: float = battle.surface_below(flight.pos) if battle else 0.0
	if flight.pos.y < floor_here + 0.09:
		if flight.fwd.y < -0.35 and _air_time > 0.5:
			_scrape(Vector3.UP, flight.pos)
		flight.pos.y = floor_here + 0.09
		flight.fwd = (flight.fwd + Vector3(0, 0.6, 0)).normalized()
	_hit_walls(before)
	if _roll_t >= 0.0:
		_roll_t += delta
		if _roll_t >= WarMath.ROLL_TIME:
			_roll_t = -1.0
	_roll_cd = maxf(0.0, _roll_cd - delta)
	_gear = move_toward(_gear, 0.0, delta * 2.5) if _air_time > 0.6 else _gear


## Real walls (physics) or the room box: bounce off with damage.
func _hit_walls(before: Vector3) -> void:
	if battle == null:
		return
	var w: Dictionary = battle.wall_hit(before, flight.pos + flight.fwd * 0.12)
	if w.is_empty():
		return
	_scrape(w.normal, w.position)
	var n: Vector3 = w.normal
	flight.pos = w.position + n * 0.18 - flight.fwd * 0.05
	var r: Vector3 = flight.fwd.bounce(n)
	r.y = clampf(r.y, -0.3, 0.4)
	flight.fwd = r.normalized()
	flight.speed *= 0.6


func _scrape(normal: Vector3, at: Vector3) -> void:
	take_hit(WarMath.CRASH_DAMAGE, true)
	if battle:
		Fx.sparks(battle, at, normal, 10)
		Fx.mark(battle, at, normal, 0.05)
		battle.cue("crash", at)
		battle.shake(0.5)


func _crash(delta: float) -> void:
	_crash_spin += delta * 7.0
	var fwd: Vector3 = flight.fwd
	fwd = (fwd + Vector3(0, -1.6 * delta, 0)).normalized()
	flight.fwd = fwd
	flight.speed = minf(2.4, flight.speed + delta * 1.5)
	flight.pos += fwd * flight.speed * delta
	_smoke_t -= delta
	if _smoke_t <= 0.0 and battle:
		_smoke_t = 0.04
		Fx.smoke(battle, global_position, 0.025, true)
	var ground: float = battle.surface_below(flight.pos) if battle else 0.0
	var w: Dictionary = battle.wall_hit(flight.pos - fwd * flight.speed * delta, flight.pos) if battle else {}
	if flight.pos.y <= ground + 0.03 or not w.is_empty():
		flight.pos.y = maxf(flight.pos.y, ground + 0.03)
		state = State.WRECKED
		_rpm = 0.0
		_engine.stop()
		if battle:
			Fx.explosion(battle, flight.pos, 0.12)
			Fx.mark(battle, Vector3(flight.pos.x, ground, flight.pos.z), Vector3.UP, 0.3)
			battle.cue("boom_big", flight.pos)
			battle.shake(1.0)
			battle.on_plane_destroyed()


func _apply_pose(delta: float) -> void:
	global_position = flight.pos
	var roll := 0.0
	if _roll_t >= 0.0:
		var u := _roll_t / WarMath.ROLL_TIME
		roll = TAU * u * u * (3.0 - 2.0 * u) * _roll_dir
	if state == State.CRASHING:
		roll = _crash_spin
	if state == State.PARKED or (state == State.TAKEOFF and flight.speed < WarMath.TAKEOFF_SPEED):
		# Taildragger: nose up ~11° on its wheels.
		var b := Basis.looking_at(flight.fwd, Vector3.UP)
		global_basis = b * Basis(Vector3.RIGHT, deg_to_rad(parked_pitch))
	else:
		global_basis = WarMath.plane_basis(flight.fwd, flight.bank, roll)


func _animate(delta: float) -> void:
	_apply_pose(delta)
	(model.prop as Node3D).rotate_object_local(Vector3.FORWARD, delta * (6.0 + 70.0 * _rpm))
	var blur := model.blur as MeshInstance3D
	(blur.material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.25, 0.25, 0.28, clampf((_rpm - 0.4) * 0.5, 0.0, 0.3)))
	for g in model.gear:
		(g as Node3D).rotation.x = lerpf(-1.45, 0.0, _gear)
	# Shadow on whatever is underneath.
	var under: float = battle.surface_below(global_position) if battle else 0.0
	var h := maxf(0.0, global_position.y - under)
	_shadow.visible = state != State.WRECKED
	_shadow.global_position = Vector3(global_position.x, under + 0.003, global_position.z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - h * 0.25, 0.45, 1.0)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.55 - h * 0.18, 0.12, 0.55)
	_sight.visible = state == State.FLYING
	if _sight.visible:
		var at := nose() + forward() * 1.2
		_sight.global_position = at
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_position - at
			if to_cam.length() > 0.05:
				_sight.look_at(at - to_cam, Vector3.UP if absf(to_cam.normalized().y) < 0.98 else Vector3.RIGHT)
				_sight.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Engine note follows speed.
	if _engine.playing:
		_engine.pitch_scale = clampf(0.55 + _rpm * 0.35 + float(flight.speed) * 0.22, 0.4, 2.0)
		_engine.volume_db = -14.0 + (3.0 if boosting else 0.0)
	# Damage smoke.
	if alive() and hp < WarMath.PLANE_HP * 0.5 and battle:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.07 if hp < WarMath.PLANE_HP * 0.25 else 0.14
			var ex: Node3D = model.exhaust[randi() % 2]
			Fx.smoke(battle, ex.global_position, 0.014, hp < WarMath.PLANE_HP * 0.25)


# --- weapons ------------------------------------------------------------------------------------

func _weapons(delta: float, trigger: float, grip: float) -> void:
	_reload(delta)
	_gun_cd -= delta
	if trigger > 0.55 and _gun_cd <= 0.0 and battle:
		_gun_cd = 1.0 / WarMath.GUN_RATE
		_fire_guns()
	if grip > 0.55:
		_grip_held = true
		_lock_timer -= delta
		if _lock_timer <= 0.0 and locks.size() < mini(WarMath.LOCKS, rockets):
			var e = _best_lock()
			if e:
				locks.append(e)
				_lock_timer = WarMath.LOCK_TIME
				_haptic(0.3, 0.04)
				battle.cue("lock", global_position, -4.0 + locks.size() * 1.5)
	elif grip < 0.3 and _grip_held:
		_grip_held = false
		_release()
	for i in range(locks.size() - 1, -1, -1):
		if not is_instance_valid(locks[i]) or not locks[i].alive():
			locks.remove_at(i)
	_salvo_timer -= delta
	if not _salvo.is_empty() and _salvo_timer <= 0.0:
		_salvo_timer = 0.1
		_launch(_salvo.pop_front())


func _reload(delta: float) -> void:
	if rockets < WarMath.ROCKETS:
		_rocket_reload -= delta
		if _rocket_reload <= 0.0:
			rockets += 1
			_rocket_reload = WarMath.ROCKET_RELOAD
			refresh_stores()
	else:
		_rocket_reload = WarMath.ROCKET_RELOAD
	if bombs < WarMath.BOMBS:
		_bomb_reload -= delta
		if _bomb_reload <= 0.0:
			bombs += 1
			_bomb_reload = WarMath.BOMB_RELOAD
			refresh_stores()


func _fire_guns() -> void:
	# Two guns per burst, alternating inner/outer pairs; converge 1.2 m ahead.
	var pair := [_barrel, _barrel + 2]
	_barrel = 1 - _barrel
	var converge := nose() + forward() * 1.2
	for i in pair:
		var m: Node3D = model.muzzles[i]
		var dir := (converge - m.global_position).normalized()
		dir = dir.rotated(global_basis.y, randf_range(-0.006, 0.006)).rotated(global_basis.x, randf_range(-0.006, 0.006))
		battle.player_fire("bullet", m.global_position, dir, velocity, null)
		if randf() < 0.5:
			Fx.muzzle(battle, m.global_position, dir)
	battle.cue("gun", global_position, -5.0)
	_haptic(0.12, 0.02)


func _best_lock():
	var best = null
	var best_a := INF
	for e in battle.enemies:
		if not e.can_be_locked() or locks.has(e):
			continue
		var c: Vector3 = e.hit_center()
		if not WarMath.in_cone(nose(), forward(), c):
			continue
		var a := WarMath.off_axis_deg(nose(), forward(), c)
		if a < best_a:
			best_a = a
			best = e
	return best


func _release() -> void:
	if rockets <= 0:
		locks.clear()
		return
	if locks.is_empty():
		_salvo.append(null)
	else:
		_salvo.append_array(locks)
	locks.clear()


func _launch(target) -> void:
	if rockets <= 0 or battle == null:
		return
	rockets -= 1
	_rocket_reload = WarMath.ROCKET_RELOAD
	var idx := clampi(rockets % model.rockets.size(), 0, model.rockets.size() - 1)
	var from: Vector3 = (model.rockets[idx] as Node3D).global_position
	refresh_stores()
	battle.player_fire("rocket", from, forward(), velocity, target)
	battle.cue("rocket", from)
	_haptic(0.45, 0.06)


func drop_bomb() -> bool:
	if not airborne() or bombs <= 0 or battle == null:
		return false
	bombs -= 1
	_bomb_reload = WarMath.BOMB_RELOAD
	var rack: Node3D = model.bombs[bombs % model.bombs.size()]
	var from := rack.global_position
	refresh_stores()
	battle.player_fire("bomb", from, Vector3.DOWN, velocity, null)
	battle.cue("bomb_drop", from)
	_haptic(0.35, 0.05)
	return true


func barrel_roll() -> bool:
	if not airborne() or _roll_t >= 0.0 or _roll_cd > 0.0:
		return false
	_roll_t = 0.0
	_roll_cd = WarMath.ROLL_COOLDOWN
	_roll_dir = -1.0 if flight.bank > 0.0 else 1.0
	if battle:
		battle.cue("whoosh", global_position)
	_haptic(0.3, 0.1)
	return true


func rolling() -> bool:
	return _roll_t >= 0.0


func take_hit(amount: float, crash: bool = false) -> void:
	if not alive():
		return
	if rolling() and not crash:
		amount *= 0.2
	hp = maxf(0.0, hp - amount)
	hit_flash = 1.0
	_haptic(0.8 if amount > 5.0 else 0.4, 0.12)
	if hp <= 0.0:
		state = State.CRASHING
		_crash_spin = 0.0
		locks.clear()
		_salvo.clear()
		if battle:
			battle.cue("engine_die", global_position)


func repair(amount: float) -> void:
	hp = minf(WarMath.PLANE_HP, hp + amount)


func refresh_stores() -> void:
	if model.is_empty():
		return
	for i in range(model.rockets.size()):
		(model.rockets[i] as Node3D).visible = i < rockets
	for i in range(model.bombs.size()):
		(model.bombs[i] as Node3D).visible = i < bombs


func _haptic(amplitude: float, duration: float) -> void:
	if hand and hand.get_is_active():
		hand.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)
