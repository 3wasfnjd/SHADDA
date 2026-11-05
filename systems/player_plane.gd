class_name PlayerPlane
extends Node3D
## The player's plane, flown by hand like a radio-controlled model — nothing
## is automatic. It sits on the real floor; you open the throttle, roll down
## the "runway", pull back to lift off, bank to turn, and can land again
## anywhere flat (floor or table top). Too slow and it stalls; touch down too
## hard and it crashes. Parked on the ground it repairs and rearms.
##
## Left stick   ↑↓ throttle (stays where you leave it)   ←→ rudder / ground steering
## Right stick  ↑↓ pitch (pull back = nose up)            ←→ roll
## Right trigger guns   Right grip hold = lock, release = rockets
## A bomb   B barrel roll   Left trigger boost   Left grip brakes

enum State { PARKED, FLYING, CRASHING, WRECKED }

var battle = null
var hand: XRController3D = null
var model: Dictionary = {}
var state: State = State.PARKED
var flight: Dictionary = {"pos": Vector3.ZERO, "basis": Basis.IDENTITY, "speed": 0.0, "sink": 0.0, "ground": true}
var hp: float = WarMath.PLANE_HP
var rockets: int = WarMath.ROCKETS
var bombs: int = WarMath.BOMBS
var boost: float = 1.0
var boosting: bool = false
var throttle: float = 0.0
var stalling: bool = false
var locks: Array = []
var hit_flash: float = 0.0
var velocity: Vector3 = Vector3.ZERO
var gear_height: float = WarMath.GEAR_HEIGHT
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
var _smoke_t: float = 0.0
var _crash_spin: float = 0.0
var _crash_fwd: Vector3 = Vector3.FORWARD
var _crash_speed: float = 0.0
var _stall_beep: float = 0.0
var _shadow: MeshInstance3D
var _engine: AudioStreamPlayer3D
var _sight: MeshInstance3D


func _ready() -> void:
	model = Models.player_plane(0.0018) if Models.has_player_model() else Models.fighter(Models.PLAYER, 0.0022)
	(model.root as Node3D).scale = Vector3.ONE * WarMath.PLANE_SCALE
	gear_height = float(model.get("gear_height", WarMath.GEAR_HEIGHT)) * WarMath.PLANE_SCALE
	add_child(model.root)
	_shadow = Toon.shadow_blob(0.22)
	add_child(_shadow)
	# Gun sight: a small ring 0.9 m ahead of the nose.
	_sight = Toon.add(self, Toon.torus(0.02, 0.0016, 24), Toon.flat(Color(1.0, 0.95, 0.5, 0.9)))
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

func park(at: Vector3, heading: Vector3, surface_y: float) -> void:
	var h := heading
	h.y = 0.0
	h = h.normalized() if h.length() > 0.01 else Vector3.FORWARD
	state = State.PARKED
	hp = WarMath.PLANE_HP
	rockets = WarMath.ROCKETS
	bombs = WarMath.BOMBS
	boost = 1.0
	throttle = 0.0
	locks.clear()
	_salvo.clear()
	_roll_t = -1.0
	_rpm = 0.0
	visible = true
	flight = {"pos": Vector3(at.x, surface_y + gear_height, at.z), "basis": Basis.looking_at(h, Vector3.UP), "speed": 0.0, "sink": 0.0, "ground": true}
	_apply_pose()
	refresh_stores()
	if _engine.playing:
		_engine.stop()


func start_engine() -> void:
	if state != State.PARKED:
		return
	state = State.FLYING
	throttle = 0.0
	if _engine.stream:
		_engine.play()


func alive() -> bool:
	return state == State.FLYING


func airborne() -> bool:
	return state == State.FLYING and not flight.ground


func on_ground() -> bool:
	return state == State.FLYING and flight.ground


func forward() -> Vector3:
	return -(flight.basis as Basis).z


func hit_center() -> Vector3:
	return global_position


func nose() -> Vector3:
	return (model.nose as Node3D).global_position


# --- per frame --------------------------------------------------------------------------

## inp: {pitch, roll, yaw, throttle_delta, boost, brake} from the sticks.
func tick(delta: float, inp: Dictionary, trigger: float, grip: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta * 4.0)
	var prev: Vector3 = flight.pos
	match state:
		State.PARKED:
			_rpm = move_toward(_rpm, 0.0, delta * 2.0)
		State.FLYING:
			_fly(delta, inp)
			if state == State.FLYING:
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


func _fly(delta: float, inp: Dictionary) -> void:
	throttle = clampf(throttle + float(inp.get("throttle_delta", 0.0)) * delta * 0.8, 0.0, 1.0)
	if inp.has("throttle"):
		throttle = float(inp.throttle)
	boosting = bool(inp.get("boost", false)) and boost > 0.02 and not flight.ground
	if boosting:
		boost = maxf(0.0, boost - delta / WarMath.BOOST_SECONDS)
	else:
		boost = minf(1.0, boost + WarMath.BOOST_RECHARGE * delta)
	_rpm = move_toward(_rpm, 0.25 + throttle * 0.75 + (0.3 if boosting else 0.0), delta * 2.0)
	var under: float = battle.surface_below(flight.pos + Vector3(0, 0.05, 0)) if battle else 0.0
	var before: Vector3 = flight.pos
	var step := {"pitch": inp.get("pitch", 0.0), "roll": inp.get("roll", 0.0), "yaw": inp.get("yaw", 0.0), "throttle": throttle, "boost": boosting, "brake": inp.get("brake", false)}
	if _roll_t >= 0.0:
		step.roll = 0.0
	var was_ground: bool = flight.ground
	var r := WarMath.rc_fly(flight, step, delta, under, gear_height)
	# Rolling off a table edge: start falling instead of floating.
	if was_ground and r.ground:
		var under_now: float = battle.surface_below(r.pos + Vector3(0, 0.05, 0)) if battle else 0.0
		if under_now < under - 0.05:
			r.ground = false
			r.pos.y = under + gear_height
		elif under_now > under + 0.05:
			_scrape(-forward(), r.pos)
			r.pos = before
			r.speed = 0.0
	flight = {"pos": r.pos, "basis": r.basis, "speed": r.speed, "sink": r.sink, "ground": r.ground}
	match r.event:
		"liftoff":
			if battle:
				battle.on_airborne()
		"landed":
			if battle:
				battle.cue("thud", flight.pos, -4.0)
				Fx.smoke(battle, flight.pos - Vector3(0, gear_height * 0.8, 0), 0.02)
		"crash":
			_scrape(Vector3.UP, flight.pos - Vector3(0, gear_height, 0))
			take_hit(WarMath.CRASH_DAMAGE * 2.0, true)
	stalling = not flight.ground and flight.speed < WarMath.STALL
	if stalling and battle:
		_stall_beep -= delta
		if _stall_beep <= 0.0:
			_stall_beep = 0.35
			battle.cue("warning", global_position, -8.0)
	_hit_walls(before)
	if _roll_t >= 0.0:
		_roll_t += delta
		if _roll_t >= WarMath.ROLL_TIME:
			_roll_t = -1.0
	_roll_cd = maxf(0.0, _roll_cd - delta)
	# Parked on the ground with the engine idling: patch up and rearm.
	if flight.ground and flight.speed < 0.05:
		repair(6.0 * delta)
		_rocket_reload -= delta
		_bomb_reload -= delta * 2.0


## Real walls (physics) or the room box: bounce off with damage.
func _hit_walls(before: Vector3) -> void:
	if battle == null:
		return
	var w: Dictionary = battle.wall_hit(before + Vector3(0, 0.02, 0), (flight.pos as Vector3) + forward() * 0.09 + Vector3(0, 0.02, 0))
	if w.is_empty() or (w.normal as Vector3).y > 0.7:
		return
	_scrape(w.normal, w.position)
	var n: Vector3 = w.normal
	flight.pos = (w.position as Vector3) + n * 0.14 - Vector3(0, 0.02, 0)
	var r: Vector3 = forward().bounce(n)
	if flight.ground:
		r.y = 0.0
	r = r.normalized()
	flight.basis = Basis.looking_at(r, Vector3.UP)
	flight.speed *= 0.4


func _scrape(normal: Vector3, at: Vector3) -> void:
	take_hit(WarMath.CRASH_DAMAGE, true)
	if battle:
		Fx.sparks(battle, at, normal, 10)
		Fx.mark(battle, at, normal, 0.05)
		battle.cue("crash", at)
		battle.shake(0.5)


func _crash(delta: float) -> void:
	_crash_spin += delta * 7.0
	_crash_fwd = (_crash_fwd + Vector3(0, -1.6 * delta, 0)).normalized()
	_crash_speed = minf(2.2, _crash_speed + delta * 1.5)
	flight.pos += _crash_fwd * _crash_speed * delta
	_smoke_t -= delta
	if _smoke_t <= 0.0 and battle:
		_smoke_t = 0.04
		Fx.smoke(battle, global_position, 0.02, true)
	var ground: float = battle.surface_below(flight.pos) if battle else 0.0
	var w: Dictionary = battle.wall_hit((flight.pos as Vector3) - _crash_fwd * _crash_speed * delta, flight.pos) if battle else {}
	if (flight.pos as Vector3).y <= ground + 0.02 or not w.is_empty():
		flight.pos.y = maxf(flight.pos.y, ground + 0.02)
		state = State.WRECKED
		_rpm = 0.0
		_engine.stop()
		if battle:
			Fx.explosion(battle, flight.pos, 0.1)
			Fx.mark(battle, Vector3(flight.pos.x, ground, flight.pos.z), Vector3.UP, 0.25)
			battle.cue("boom_big", flight.pos)
			battle.shake(1.0)
			battle.on_plane_destroyed()


func _apply_pose() -> void:
	global_position = flight.pos
	if state == State.CRASHING:
		global_basis = Basis.looking_at(_crash_fwd, Vector3.UP if absf(_crash_fwd.y) < 0.98 else Vector3.BACK) * Basis(Vector3.FORWARD, _crash_spin)
		return
	var b: Basis = flight.basis
	if _roll_t >= 0.0:
		var u := _roll_t / WarMath.ROLL_TIME
		b = b * Basis(Vector3.FORWARD, TAU * u * u * (3.0 - 2.0 * u) * _roll_dir)
	global_basis = b


func _animate(delta: float) -> void:
	_apply_pose()
	(model.prop as Node3D).rotate_object_local(Vector3.FORWARD, delta * (4.0 + 70.0 * _rpm) * (1.0 if state == State.FLYING else 0.2))
	var blur := model.blur as MeshInstance3D
	(blur.material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.25, 0.25, 0.28, clampf((_rpm - 0.35) * 0.5, 0.0, 0.3)))
	var under: float = battle.surface_below(global_position + Vector3(0, 0.02, 0)) if battle else 0.0
	var h := maxf(0.0, global_position.y - under)
	_shadow.visible = state != State.WRECKED
	_shadow.global_position = Vector3(global_position.x, under + 0.003, global_position.z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - h * 0.25, 0.45, 1.0)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.55 - h * 0.18, 0.12, 0.55)
	_sight.visible = airborne()
	if _sight.visible:
		var at := nose() + forward() * 0.9
		_sight.global_position = at
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_position - at
			if to_cam.length() > 0.05:
				_sight.look_at(at - to_cam, Vector3.UP if absf(to_cam.normalized().y) < 0.98 else Vector3.RIGHT)
				_sight.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	if _engine.playing:
		_engine.pitch_scale = clampf(0.5 + _rpm * 0.45 + float(flight.speed) * 0.25, 0.4, 2.0)
		_engine.volume_db = -16.0 + _rpm * 4.0 + (2.0 if boosting else 0.0)
	if alive() and hp < WarMath.PLANE_HP * 0.5 and battle:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.07 if hp < WarMath.PLANE_HP * 0.25 else 0.14
			var ex: Node3D = model.exhaust[randi() % 2]
			Fx.smoke(battle, ex.global_position, 0.012, hp < WarMath.PLANE_HP * 0.25)


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
	var converge := nose() + forward() * 0.9
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
	_roll_dir = -1.0 if WarMath.bank_of(flight.basis) > 0.0 else 1.0
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
		_crash_fwd = forward()
		_crash_speed = maxf(0.6, float(flight.speed))
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
