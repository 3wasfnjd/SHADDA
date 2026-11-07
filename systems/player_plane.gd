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
## Right trigger = right-wing guns, left trigger = left-wing guns (both = all)
## Right grip hold = lock, release = rockets
## A special weapon (bombs, cluster, air mines, Thunderbolt)   B barrel roll
## Left grip: boost in the air, brakes on the ground
## X = U-turn (tight half circle), Y = loop (full vertical loop)
## Shot down, it comes apart in pieces and the pilot bails out on a chute.

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
var invincible: bool = false       # can't be lost: damage stops at 15 % (stars still count it)
# Upgrades picked between campaign stages.
var power: float = 1.0
var gun_rate: float = 1.0
var gun_damage: float = 1.0
var rocket_max: int = WarMath.ROCKETS
var lock_mult: float = 1.0
var armor: float = 1.0
var cluster: bool = false
var upgrades: Array = []
var gun_kind: String = "twin"
var special: String = "bombs"
var special_max: int = WarMath.BOMBS
var has_flares: bool = false
var aim_assist: bool = true
var leveler: bool = true
var haptics: bool = true
var easy_flight: bool = true      # Easy (attitude) or Pro (rates) flight
var hand_l: XRController3D = null  # left controller (left-gun haptics)
var _trig_l: float = 0.0
var _man: Dictionary = {}          # running manoeuvre: loop / uturn
var damage_taken: float = 0.0
var _trails: Array = []
var _dust_t: float = 0.0
var _sm := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
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
	# Wingtip vapour trails (show in fast or tight flying).
	for tip in model.get("tips", []):
		var mesh := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.vertex_color_use_as_albedo = true
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = tm
		mi.top_level = true
		mi.extra_cull_margin = 10.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_trails.append({"tip": tip, "mesh": mesh, "pts": []})
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
	_engine.bus = &"SFX"
	add_child(_engine)


# --- life cycle -------------------------------------------------------------------

func park(at: Vector3, heading: Vector3, surface_y: float) -> void:
	var h := heading
	h.y = 0.0
	h = h.normalized() if h.length() > 0.01 else Vector3.FORWARD
	state = State.PARKED
	hp = WarMath.PLANE_HP
	rockets = rocket_max
	bombs = special_max
	boost = 1.0
	(model.root as Node3D).visible = true
	throttle = 0.0
	locks.clear()
	_salvo.clear()
	_man = {}
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
	_trig_l = float(inp.get("trigger_l", 0.0))
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
	velocity = (flight.pos - prev) / maxf(delta, 1e-4)
	_animate(delta)


func _fly(delta: float, inp: Dictionary) -> void:
	throttle = clampf(throttle + float(inp.get("throttle_delta", 0.0)) * delta * 0.8, 0.0, 1.0)
	if inp.has("throttle"):
		throttle = float(inp.throttle)
	if not _man.is_empty():
		_step_manoeuvre(delta)
		return
	boosting = bool(inp.get("boost", false)) and boost > 0.02 and not flight.ground
	if boosting:
		boost = maxf(0.0, boost - delta / WarMath.BOOST_SECONDS)
	else:
		boost = minf(1.0, boost + WarMath.BOOST_RECHARGE * delta)
	_rpm = move_toward(_rpm, 0.25 + throttle * 0.75 + (0.3 if boosting else 0.0), delta * 2.0)
	var under: float = battle.surface_below(flight.pos + Vector3(0, 0.05, 0)) if battle else 0.0
	var before: Vector3 = flight.pos
	# Smooth, progressive sticks: a soft curve near the centre for fine
	# corrections and a short ease so the plane never jerks.
	for k in ["pitch", "roll", "yaw"]:
		var raw := clampf(float(inp.get(k, 0.0)), -1.0, 1.0)
		var curved := raw if easy_flight else raw * (0.35 + 0.65 * absf(raw))
		_sm[k] = move_toward(_sm[k], curved, delta * (7.0 if easy_flight else 5.0))
	var step := {"pitch": _sm.pitch, "roll": _sm.roll, "yaw": _sm.yaw, "throttle": throttle, "boost": boosting, "brake": inp.get("brake", false), "power": power, "level": leveler}
	if _roll_t >= 0.0:
		step.roll = 0.0
	var was_ground: bool = flight.ground
	var r := WarMath.easy_fly(flight, step, delta, under, gear_height) if easy_flight else WarMath.rc_fly(flight, step, delta, under, gear_height)
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


## Nav lights blink, exhaust flames flicker with throttle and boost, and a
## badly damaged plane burns at the engine.
var _detail_t: float = 0.0
func _animate_details(delta: float) -> void:
	_detail_t += delta
	var lights: Array = model.get("lights", [])
	for i in range(lights.size()):
		var on := fmod(_detail_t + i * 0.15, 1.2) < 0.75 if i < 2 else fmod(_detail_t, 0.9) < 0.12
		(lights[i] as Node3D).visible = on and state != State.WRECKED
	var flames: Array = model.get("flames", [])
	var fire := state == State.FLYING and (throttle > 0.55 or boosting)
	for f in flames:
		var n := f as Node3D
		n.visible = fire
		if fire:
			var k := (1.6 if boosting else 0.6 + throttle * 0.5) * randf_range(0.8, 1.2)
			n.scale = Vector3(1.0, k, 1.0)
	if alive() and hp < WarMath.PLANE_HP * 0.25 and battle and randf() < delta * 14.0:
		var ex: Node3D = model.exhaust[randi() % 2]
		Fx.flame(battle, ex.global_position, 0.012)


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
		var hot := aim_assist and battle != null and _assist_point() != Vector3.INF
		(_sight.material_override as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.35, 0.2, 0.95) if hot else Color(1.0, 0.95, 0.5, 0.9))
		var at := nose() + forward() * 0.9
		_sight.global_position = at
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_position - at
			if to_cam.length() > 0.05:
				_sight.look_at(at - to_cam, Vector3.UP if absf(to_cam.normalized().y) < 0.98 else Vector3.RIGHT)
				_sight.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_update_trails(delta)
	# Prop wash kicks up dust on the take-off roll.
	if on_ground() and float(flight.speed) > 0.3 and battle:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.08
			Fx.smoke(battle, global_position - forward() * 0.1 - Vector3(0, gear_height * 0.8, 0), 0.012)
	if _engine.playing:
		_engine.pitch_scale = clampf(0.5 + _rpm * 0.45 + float(flight.speed) * 0.25, 0.4, 2.0)
		_engine.volume_db = -16.0 + _rpm * 4.0 + (2.0 if boosting else 0.0)
	_animate_details(delta)
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
	var right := trigger > 0.55
	var left := _trig_l > 0.55
	if (right or left) and _gun_cd <= 0.0 and battle:
		var spec: Dictionary = WarMath.GUN_SPECS.get(gun_kind, WarMath.GUN_SPECS.twin)
		_gun_cd = 1.0 / (WarMath.GUN_RATE * gun_rate * float(spec.rate))
		_fire_guns(left, right)
	if grip > 0.55:
		_grip_held = true
		_lock_timer -= delta
		if _lock_timer <= 0.0 and locks.size() < mini(WarMath.LOCKS, rockets):
			var e = _best_lock()
			if e:
				locks.append(e)
				_lock_timer = WarMath.LOCK_TIME * lock_mult
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
	if rockets < rocket_max:
		_rocket_reload -= delta
		if _rocket_reload <= 0.0:
			rockets += 1
			_rocket_reload = WarMath.ROCKET_RELOAD
			refresh_stores()
	else:
		_rocket_reload = WarMath.ROCKET_RELOAD
	if bombs < special_max:
		_bomb_reload -= delta
		if _bomb_reload <= 0.0:
			bombs += 1
			_bomb_reload = float(WarMath.SPECIAL_RELOAD.get(special, WarMath.BOMB_RELOAD))
			refresh_stores()


## Guns fire from the wing whose trigger is held: muzzles 0,1 are under the
## left wing, 2,3 under the right.
func _fire_guns(left: bool = true, right: bool = true) -> void:
	var spec: Dictionary = WarMath.GUN_SPECS.get(gun_kind, WarMath.GUN_SPECS.twin)
	var muzzles: Array = model.muzzles
	var pair: Array = []
	match int(spec.per):
		4:
			if left:
				pair += [0, 1]
			if right:
				pair += [2, 3]
		1:
			var side_r := right if not (left and right) else _barrel == 1
			pair = [(2 if side_r else 0) + (_barrel if not (left and right) else 0)]
		_:
			if left:
				pair.append(_barrel)
			if right:
				pair.append(_barrel + 2)
	_barrel = 1 - _barrel
	var converge := nose() + forward() * 0.9
	var assist := _assist_point() if aim_assist else Vector3.INF
	var shot_spec := {"damage": spec.damage, "incendiary": gun_kind == "quad", "explosive": WarMath.CANNON_BLAST if gun_kind == "cannon" else 0.0}
	var spread: float = spec.spread
	for i in pair:
		var m: Node3D = muzzles[i % muzzles.size()]
		var dir := (converge - m.global_position).normalized()
		if assist != Vector3.INF:
			dir = dir.slerp((assist - m.global_position).normalized(), 0.65)
		dir = dir.rotated(global_basis.y, randf_range(-spread, spread)).rotated(global_basis.x, randf_range(-spread, spread))
		battle.player_fire("bullet", m.global_position, dir, velocity, null, shot_spec)
		if randf() < (0.5 if gun_kind != "cannon" else 1.0):
			Fx.muzzle(battle, m.global_position, dir, 0.018 if gun_kind != "cannon" else 0.03)
	battle.cue("cannon20" if gun_kind == "cannon" else "gun", global_position, -5.0 if gun_kind != "quad" else -3.0)
	if left and hand_l and hand_l.get_is_active() and haptics:
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.12 if gun_kind != "cannon" else 0.35, 0.02, 0.0)
	if gun_kind == "minigun":
		Fx.muzzle(battle, nose() + forward() * 0.02, forward(), 0.022)
	if right:
		_haptic(0.12 if gun_kind != "cannon" else 0.35, 0.02 if gun_kind != "cannon" else 0.05)


## Aim assist: where to send rounds when an enemy sits near the sight.
func _assist_point() -> Vector3:
	var best := Vector3.INF
	var best_a := 7.0
	for e in battle.enemies:
		if not e.alive():
			continue
		var c: Vector3 = e.hit_center()
		var d := c.distance_to(nose())
		if d > 3.5:
			continue
		var lead: Vector3 = c + (e.velocity - velocity * 0.5) * (d / WarMath.BULLET_SPEED)
		var a := WarMath.off_axis_deg(nose(), forward(), lead)
		if a < best_a:
			best_a = a
			best = lead
	return best


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


## A button: whatever special weapon is fitted.
func use_special() -> bool:
	match special:
		"mines":
			return drop_mine()
		"lightning":
			return fire_lightning()
		"swarm":
			return fire_swarm()
	return drop_bomb()


func fire_swarm() -> bool:
	if not airborne() or bombs <= 0 or battle == null:
		return false
	bombs -= 1
	_bomb_reload = float(WarMath.SPECIAL_RELOAD.swarm)
	refresh_stores()
	battle.swarm(nose(), forward(), velocity)
	_haptic(0.7, 0.2)
	return true


func drop_mine() -> bool:
	if not airborne() or bombs <= 0 or battle == null:
		return false
	bombs -= 1
	_bomb_reload = float(WarMath.SPECIAL_RELOAD.mines)
	refresh_stores()
	var from := global_position - forward() * 0.12 - global_basis.y * 0.03
	battle.player_fire("mine", from, -forward(), velocity, null)
	battle.cue("bomb_drop", from, -4.0)
	_haptic(0.3, 0.05)
	return true


func fire_lightning() -> bool:
	if not airborne() or bombs <= 0 or battle == null:
		return false
	bombs -= 1
	_bomb_reload = float(WarMath.SPECIAL_RELOAD.lightning)
	refresh_stores()
	battle.lightning(nose(), forward())
	_haptic(0.9, 0.15)
	return true


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
		if has_flares:
			battle.flares(global_position - forward() * 0.1)
	_haptic(0.3, 0.1)
	return true


func rolling() -> bool:
	return _roll_t >= 0.0 or not _man.is_empty()


## Y: a full vertical loop. Shakes off missiles like a roll.
func loop() -> bool:
	return _start_manoeuvre("loop", 1.8)


## X: a tight half-circle U-turn toward the side the stick leans (right by default).
func u_turn() -> bool:
	return _start_manoeuvre("uturn", 1.3)


func _start_manoeuvre(kind: String, dur: float) -> bool:
	if not airborne() or _roll_t >= 0.0 or not _man.is_empty() or _roll_cd > 0.0:
		return false
	var f: Vector3 = -(flight.basis as Basis).z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
	var lean := WarMath.bank_of(flight.basis)
	_man = {"kind": kind, "t": 0.0, "dur": dur, "p0": flight.pos, "f0": f, "side": -1.0 if (lean < -0.1 or _sm.roll < -0.2) else 1.0}
	_roll_cd = WarMath.ROLL_COOLDOWN
	if battle:
		battle.cue("whoosh", global_position, 2.0)
		if has_flares:
			battle.flares(global_position - forward() * 0.1)
	_haptic(0.4, 0.15)
	return true


func _step_manoeuvre(delta: float) -> void:
	_man.t += delta
	var u: float = clampf(_man.t / _man.dur, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var p0: Vector3 = _man.p0
	var f0: Vector3 = _man.f0
	var right0 := f0.cross(Vector3.UP).normalized()
	var r := 0.38
	var speed: float = maxf(float(flight.speed), 1.0)
	var pos: Vector3
	var b: Basis
	if _man.kind == "loop":
		var th := TAU * e
		pos = p0 + f0 * (r * sin(th) + speed * 0.25 * u * float(_man.dur)) + Vector3.UP * (r * (1.0 - cos(th)))
		b = Basis.looking_at(f0, Vector3.UP) * Basis(Vector3.RIGHT, th)
	else:
		var s: float = _man.side
		var th2 := PI * e
		pos = p0 + f0 * (r * sin(th2)) + right0 * s * (r * (1.0 - cos(th2))) + Vector3.UP * 0.12 * sin(th2)
		var fwd := (f0 * cos(th2) + right0 * s * sin(th2)).normalized()
		b = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.FORWARD, s * 1.15 * sin(PI * u))
	var floor_y: float = battle.surface_below(pos + Vector3(0, 0.05, 0)) if battle else 0.0
	pos.y = maxf(pos.y, floor_y + gear_height + 0.05)
	flight.pos = pos
	flight.basis = b.orthonormalized()
	flight.ground = false
	if u >= 1.0:
		var fin: Vector3 = -(flight.basis as Basis).z
		fin.y = 0.0
		flight.basis = Basis.looking_at(fin.normalized() if fin.length() > 0.05 else f0, Vector3.UP)
		_man = {}


func take_hit(amount: float, crash: bool = false) -> void:
	if not alive():
		return
	if rolling() and not crash:
		amount *= 0.2
	amount *= armor
	damage_taken += amount
	hp = maxf(WarMath.PLANE_HP * WarMath.MIN_HP_FRACTION if invincible else 0.0, hp - amount)
	hit_flash = 1.0
	_haptic(0.8 if amount > 5.0 else 0.4, 0.12)
	if hp <= 0.0:
		_break_apart()


## Shot down: a fireball, the plane comes apart into its pieces, and the
## pilot bails out under a parachute.
func _break_apart() -> void:
	state = State.WRECKED
	_man = {}
	locks.clear()
	_salvo.clear()
	_rpm = 0.0
	if _engine.playing:
		_engine.stop()
	_haptic(1.0, 0.4)
	if battle == null:
		return
	var at := global_position
	Fx.explosion(battle, at, 0.14)
	battle.cue("boom_big", at, 4.0)
	battle.cue("crash", at, 0.0)
	battle.shake(1.0)
	Debris.from_model(battle, model.root, velocity * 0.6, at, "player")
	(model.root as Node3D).visible = false
	_shadow.visible = false
	Debris.eject(battle, (model.pilot.root as Node3D).global_position, velocity * 0.3)
	battle.on_plane_destroyed()


## Hangar loadout and settings from the profile.
func apply_loadout() -> void:
	reset_upgrades()
	var lv: Dictionary = Profile.progress.get("levels", {})
	var e := int(lv.get("engine", 0))
	var a := int(lv.get("armor", 0))
	var g := int(lv.get("guns", 0))
	var r := int(lv.get("rockets", 0))
	power = 1.0 + 0.12 * e
	armor = pow(0.82, a)
	gun_rate = 1.0 + 0.15 * g
	gun_damage = 1.0 + 0.2 * g
	rocket_max = WarMath.ROCKETS + r
	lock_mult = pow(0.8, r)
	gun_kind = str(Profile.progress.get("gun", "twin"))
	special = str(Profile.progress.get("special", "bombs"))
	cluster = special == "cluster"
	special_max = int(WarMath.SPECIAL_CHARGES.get(special, WarMath.BOMBS))
	has_flares = Profile.owns("flares")
	aim_assist = bool(Profile.get_s("aim_assist"))
	leveler = bool(Profile.get_s("leveler"))
	haptics = bool(Profile.get_s("haptics"))
	easy_flight = str(Profile.get_s("flight")) != "pro"
	rockets = rocket_max
	bombs = special_max
	refresh_stores()


## Hangar changes during a sortie (from the pause menu) or between missions:
## re-equip without repairing or resetting the hull record.
func refresh_loadout() -> void:
	var keep_hp := hp
	var keep_taken := damage_taken
	var keep_r := rockets
	var keep_b := bombs
	var keep_sp := special
	apply_loadout()
	hp = keep_hp
	damage_taken = keep_taken
	rockets = mini(keep_r, rocket_max)
	bombs = mini(keep_b, special_max) if keep_sp == special else special_max
	refresh_stores()


func rearm() -> void:
	rockets = rocket_max
	bombs = special_max
	refresh_stores()


func reset_upgrades() -> void:
	gun_kind = "twin"
	special = "bombs"
	special_max = WarMath.BOMBS
	has_flares = false
	power = 1.0
	gun_rate = 1.0
	gun_damage = 1.0
	rocket_max = WarMath.ROCKETS
	lock_mult = 1.0
	armor = 1.0
	cluster = false
	upgrades.clear()
	damage_taken = 0.0


## kind: engine, guns, rockets, armor, cluster.
func apply_upgrade(kind: String) -> void:
	upgrades.append(kind)
	match kind:
		"engine":
			power += 0.22
		"guns":
			gun_rate *= 1.4
			gun_damage *= 1.5
		"rockets":
			rocket_max += 2
			rockets = rocket_max
			lock_mult *= 0.55
		"armor":
			armor *= 0.6
			hp = WarMath.PLANE_HP
		"cluster":
			cluster = true
	refresh_stores()


func repair(amount: float) -> void:
	hp = minf(WarMath.PLANE_HP, hp + amount)


func refresh_stores() -> void:
	if model.is_empty():
		return
	for i in range(model.rockets.size()):
		(model.rockets[i] as Node3D).visible = i < rockets
	for i in range(model.bombs.size()):
		(model.bombs[i] as Node3D).visible = i < bombs and not special in ["lightning", "swarm"]


func _haptic(amplitude: float, duration: float) -> void:
	if haptics and hand and hand.get_is_active():
		hand.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)



func _update_trails(_delta: float) -> void:
	var bank := absf(WarMath.bank_of(flight.basis)) if state == State.FLYING else 0.0
	var on := airborne() and (float(flight.speed) > 1.35 or bank > 0.55 or boosting)
	var up := global_basis.y
	for t in _trails:
		var pts: Array = t.pts
		if on:
			pts.append((t.tip as Node3D).global_position)
			if pts.size() > 26:
				pts.pop_front()
		elif not pts.is_empty():
			pts.pop_front()
			if not pts.is_empty():
				pts.pop_front()
		var mesh: ImmediateMesh = t.mesh
		mesh.clear_surfaces()
		if pts.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(pts.size()):
			var a := float(i) / float(pts.size() - 1)
			var w := 0.0035 * a
			var c := Color(1, 1, 1, 0.55 * a)
			mesh.surface_set_color(c)
			mesh.surface_add_vertex(pts[i] + up * w)
			mesh.surface_set_color(c)
			mesh.surface_add_vertex(pts[i] - up * w)
		mesh.surface_end()
