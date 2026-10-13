class_name Spark
extends CharacterBody3D
## A critter from the cracks. Four families share one brain:
##  spark — weaves through the air, orbits the gem, dives at your face
##  snake — crawls on the floor with a long neon body; yanks tear segments off
##  drone — hovers high, banks into turns, hauls shards out of the room
##  ball  — rolls and bounces; rope it, stretch, release to fling it into walls
## All of them: rope drag by mass, yank → shard drop/stun, crush in a fist,
## punch with a fast hand, slam into a scanned wall.

signal died(spark: Spark)
signal escaped(spark: Spark, with_shard: bool)
signal shard_taken(spark: Spark)
signal shard_dropped(spark: Spark, at: Vector3)
signal split(spark: Spark, at: Vector3)
signal bit_player(spark: Spark)

enum State { EMERGE, APPROACH, DRAIN, FLEE, STUN, DIVE, DEAD }

const REACH := 0.5
const SLAM_SPEED := 2.3
const STUN_SECONDS := 1.3
const TRAIL_POINTS := 16

var kind: String = "ember"
var family: String = "spark"
var stats: Dictionary = {}
var state: int = State.EMERGE
var home: Node3D
var gem: Node3D
var player_head: Node3D
var director: Node
var has_shard: bool = false
var tethers: Array = []
var radius: float = 0.12
var speed: float = 1.5
var mass: float = 1.0
var color: Color = Neon.AMBER
var preview_only: bool = false
var segments_left: int = 0

var _timer: float = 0.0
var _life: float = 0.0
var _seed: float = 0.0
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0
var _tension: float = 0.0
var _hit_flash: float = 0.0
var _dive_timer: float = 0.0
var _dive_from: int = State.DRAIN
var _flung: float = 0.0
var _core: MeshInstance3D
var _inner: MeshInstance3D
var _body: Node3D
var _body_rot: Basis = Basis.IDENTITY
var _eyes: Node3D
var _eye_list: Array[Node3D] = []
var _licks: Array[MeshInstance3D] = []
var _fins: Array[MeshInstance3D] = []
var _plates: Array[MeshInstance3D] = []
var _motes: Array[MeshInstance3D] = []
var _rotors: Array[MeshInstance3D] = []
var _segments: Array[MeshInstance3D] = []
var _stripe: MeshInstance3D
var _seam: MeshInstance3D
var _blink: float = 0.0
var _next_blink: float = 2.0
var _stretch: float = 1.0
var _halo: MeshInstance3D
var _shadow: MeshInstance3D
var _shard: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_mat: ShaderMaterial
var _history: PackedVector3Array = PackedVector3Array()
var _history_timer: float = 0.0
var _burst: Array[MeshInstance3D] = []
var _shock: MeshInstance3D
var _roll_angle: float = 0.0
var _fur: Array[MeshInstance3D] = []
var _ears: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _ear_swing: Vector2 = Vector2.ZERO
var _ear_vel: Vector2 = Vector2.ZERO
var _prev_vel: Vector3 = Vector3.ZERO
var hp: int = 1
var is_boss: bool = false
var last_hit: String = "crush"
var _homing: Node3D = null
var _crown: Node3D = null


static func create(spark_kind: String) -> Spark:
	var s := Spark.new()
	s.kind = spark_kind
	s.stats = SparkMath.stats(spark_kind)
	return s


func _ready() -> void:
	family = stats.get("family", "spark")
	collision_layer = 2
	collision_mask = 1 | (2 if family == "ball" else 0)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	radius = stats.radius
	speed = stats.speed
	mass = stats.mass
	color = stats.color
	segments_left = stats.get("segments", 0)
	_seed = randf() * 100.0
	_orbit_dir = 1.0 if randf() > 0.5 else -1.0
	_dive_timer = randf_range(2.0, 5.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	_body = Node3D.new()
	add_child(_body)
	_core = Neon.make_living_orb(color, radius, 16, 8)
	_body.add_child(_core)
	_inner = Neon.make_orb(Neon.WHITE.lerp(color, 0.2), radius * 0.4, 8, 4)
	_body.add_child(_inner)
	_build_character()
	_halo = Neon.make_halo(color, radius * 6.0, 0.35)
	add_child(_halo)
	_shadow = Neon.make_contact_shadow(radius * 3.0, 0.3)
	_shadow.top_level = true
	add_child(_shadow)
	_shard = Neon.make_crystal(Neon.WHITE, radius * 0.3)
	_shard.visible = false
	add_child(_shard)
	_trail_mat = Neon.glow_material(color, false, true)
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.material_override = _trail_mat
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.extra_cull_margin = 16.0
	add_child(_trail)
	for i in range(8):
		var b := Neon.make_halo(color, radius * 2.0, 0.0)
		b.visible = false
		b.top_level = true
		add_child(b)
		_burst.append(b)
	_shock = Neon.make_ring_mesh(color, radius * 2.0, radius * 0.08)
	_shock.visible = false
	_shock.top_level = true
	add_child(_shock)
	if is_boss:
		_crown = UI.icon("crown", Neon.AMBER, radius * 1.1)
		_crown.position = Vector3(0, radius * 1.6, 0)
		add_child(_crown)


## Turns this critter into the wave-5 boss: twice the size, much heavier,
## takes several hits, wears a crown.
func make_boss() -> void:
	is_boss = true
	hp = SparkMath.BOSS_HP
	stats = stats.duplicate()
	stats.radius = stats.radius * 2.3
	stats.mass = maxf(stats.mass * 4.0, 5.0)
	stats.speed = stats.speed * 0.7
	stats.drain_time = stats.drain_time * 1.6
	stats.dive = 7.0


func configure(crack: Node3D, target_gem: Node3D, head: Node3D) -> void:
	home = crack
	gem = target_gem
	player_head = head
	global_position = crack.spawn_point()
	velocity = crack.outward() * 0.6
	if family == "snake" or family == "ball":
		# Floor crawlers drop to the floor right away.
		velocity.y = -1.0


# --- tether interface -------------------------------------------------------

func tether_anchor() -> Node3D:
	return self


func can_be_tethered() -> bool:
	return state != State.DEAD and state != State.EMERGE and not preview_only


func attach_tether(t: Node3D) -> void:
	if not tethers.has(t):
		tethers.append(t)
	_hit_flash = 1.0


func detach_tether(t: Node3D) -> void:
	tethers.erase(t)


func on_tether_snapped() -> void:
	_hit_flash = 1.0


func is_roped() -> bool:
	return not tethers.is_empty()


## Applies one hit. Bosses (and only bosses) survive until their hp runs out.
func hit(method: String) -> void:
	if state == State.DEAD:
		return
	last_hit = method
	_hit_flash = 1.0
	if is_boss and hp > 1:
		hp -= 1
		if director:
			director.call("on_boss_hurt", self)
		for t in tethers.duplicate():
			if is_instance_valid(t):
				t.release()
		state = State.STUN
		_timer = 0.0
		velocity = -velocity * 0.5 + Vector3(0, 1.0, 0)
		_homing = null
		return
	_die()


## Crushed in a gauntlet fist.
func crush() -> void:
	hit("crush")


## A hand jerked back on the rope: light critters fly at the hand (and get
## caught there); heavy ones and bosses just take a hit and stagger.
func yank(hand_point: Node3D, strength: float) -> bool:
	if state == State.DEAD:
		return false
	_hit_flash = 1.0
	if has_shard:
		has_shard = false
		_shard.visible = false
		shard_dropped.emit(self, global_position)
	if kind == "splitter":
		split.emit(self, global_position)
		last_hit = "yank"
		_die()
		return false
	if family == "snake" and segments_left > 3:
		segments_left = maxi(0, segments_left - 3)
		_rebuild_segments()
	if is_boss or mass >= 3.0:
		if is_boss:
			hit("yank")
		else:
			state = State.STUN
			_timer = 0.0
			velocity += (hand_point.global_position - global_position).normalized() * 1.4
			_flung = 0.4
		return false
	velocity = (hand_point.global_position - global_position).normalized() * (3.6 + strength * 2.2) + Vector3(0, 1.0, 0)
	_flung = 1.2
	_homing = hand_point
	state = State.STUN
	_timer = 0.0
	return true


func is_flying_to_hand() -> bool:
	return _homing != null and _flung > 0.0 and state != State.DEAD


## Hit by a fast-moving hand: balls fly, everything else bursts.
func punch(hand_velocity: Vector3) -> void:
	if state == State.DEAD:
		return
	if family == "ball" and not is_boss:
		fling(hand_velocity.normalized(), clampf(hand_velocity.length() / 3.0, 0.4, 1.0))
	else:
		hit("punch")


## Sling release: launched away; a fast ball bursts on walls or other balls.
func fling(direction: Vector3, strength: float) -> void:
	if state == State.DEAD:
		return
	velocity = direction.normalized() * (3.0 + strength * 5.5)
	_flung = 1.2
	state = State.STUN
	_timer = 0.0
	_hit_flash = 1.0
	if has_shard:
		has_shard = false
		_shard.visible = false
		shard_dropped.emit(self, global_position)


# --- behaviour ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_timer += delta
	_life += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	_flung = maxf(0.0, _flung - delta)
	if preview_only:
		_animate(delta)
		return
	if state == State.DEAD:
		_animate(delta)
		return
	var pull := Vector3.ZERO
	_tension = 0.0
	for t in tethers:
		if not is_instance_valid(t):
			continue
		pull += TetherMath.pull_velocity(t.hand_position(), global_position, t.rest_length, mass, delta)
		_tension = maxf(_tension, t.tension)
	var gem_center: Vector3 = gem.anchor_point()
	var ground := family == "snake" or family == "ball"
	match state:
		State.EMERGE:
			var out: Vector3 = home.spawn_point() + home.outward() * 0.7
			if ground:
				out.y = global_position.y - position.y + radius
			_fly_toward(out, delta, 1.0)
			if _timer > 0.5:
				state = State.APPROACH
				_timer = 0.0
		State.APPROACH:
			var goal := gem_center + SparkMath.weave_offset(_life, stats.weave, stats.weave_hz, _seed)
			if family == "drone":
				goal.y = maxf(goal.y, 1.3) + sin(_life * 1.3) * 0.2
			_fly_toward(_ground_goal(goal), delta, 1.0)
			if _flat_or_full_distance(gem_center) < 0.55 + radius:
				state = State.DRAIN
				_timer = 0.0
				_orbit_angle = atan2(global_position.z - gem_center.z, global_position.x - gem_center.x)
			_maybe_dive(delta)
		State.DRAIN:
			_orbit_angle += _orbit_dir * delta * (speed / 0.5)
			var h := sin(_life * 3.0) * 0.12
			if family == "drone":
				h = 0.5 + sin(_life * 2.0) * 0.1
			var goal := SparkMath.orbit_point(gem_center, _orbit_angle, 0.5 + radius, h)
			_fly_toward(_ground_goal(goal), delta, 1.3)
			if _timer >= stats.drain_time * (1.0 + _tension * 2.0):
				has_shard = true
				_shard.visible = true
				shard_taken.emit(self)
				state = State.FLEE
				_timer = 0.0
			_maybe_dive(delta)
		State.FLEE:
			var exit: Vector3 = home.spawn_point() + home.outward() * 0.3
			var goal := exit + SparkMath.weave_offset(_life, stats.weave * 0.6, stats.weave_hz, _seed)
			if ground and home.on_ceiling:
				goal = exit    # crawlers climb straight up the wall below a ceiling crack
			_fly_toward(goal if not ground or home.on_ceiling else _ground_goal(goal), delta, 1.15)
			if global_position.distance_to(exit) < 0.35 and _tension < 0.3:
				_escape()
				return
		State.DIVE:
			var target: Vector3 = player_head.global_position + Vector3(0, -0.1, 0)
			_fly_toward(target, delta, 1.8, true)
			if global_position.distance_to(target) < 0.3:
				bit_player.emit(self)
				_hit_flash = 1.0
				velocity = (global_position - target).normalized() * 2.5
				state = _dive_from
				_timer = 0.0
			elif _timer > 2.2:
				state = _dive_from
				_timer = 0.0
		State.STUN:
			if _homing and is_instance_valid(_homing) and _flung > 0.0:
				var want := (_homing.global_position - global_position).normalized() * maxf(velocity.length(), 4.0)
				velocity = velocity.lerp(want, minf(1.0, delta * 7.0))
			elif _homing and _flung <= 0.0:
				_homing = null
			if _flung <= 0.0:
				velocity *= 1.0 - minf(1.0, delta * 3.0)
				if not ground:
					velocity.y -= 2.0 * delta
			if _timer >= STUN_SECONDS and _flung <= 0.0:
				state = State.APPROACH
				_timer = 0.0
	# Rope drag.
	if pull != Vector3.ZERO:
		if ground:
			pull.y = minf(pull.y, 0.0) if family == "snake" else pull.y
		velocity += pull
		velocity *= 1.0 - minf(0.5, delta * 1.2)
	if _tension >= TetherMath.STUN_TENSION and state != State.STUN:
		_yanked(pull)
	var before := velocity
	move_and_slide()
	# Height rules per family.
	if ground:
		if position.y < radius + 0.01:
			position.y = radius + 0.01
			velocity.y = (absf(velocity.y) * 0.5) if family == "ball" else 0.0
		elif family == "snake" and not (state == State.FLEE and home.on_ceiling) and _flung <= 0.0:
			position.y = radius + 0.01
			velocity.y = 0.0
		if family == "ball" and position.y > radius + 0.02 and not is_roped():
			velocity.y -= 9.0 * delta
	else:
		if position.y < radius + 0.05:
			position.y = radius + 0.05
			velocity.y = absf(velocity.y) * 0.4
		if position.y > 2.3:
			position.y = 2.3
			velocity.y = -absf(velocity.y) * 0.4
	# Bounce off whatever we hit; slam into scanned walls while roped or flung.
	for i in range(get_slide_collision_count()):
		var hit := get_slide_collision(i)
		var collider := hit.get_collider()
		var impact := before.dot(-hit.get_normal())
		if collider is Spark and family == "ball" and (_flung > 0.0 or collider._flung > 0.0) and impact > 1.5:
			collider.call_deferred("hit", "slam")
			hit("slam")
			return
		if collider and collider.has_meta("labels") and (is_roped() or _flung > 0.0) and impact > SLAM_SPEED and _homing == null:
			if director:
				director.call("cue", "thud", global_position, 4.0)
			hit("slam")
			if state == State.DEAD:
				return
		if family == "ball" and impact > 0.3 and collider is StaticBody3D:
			velocity = before.bounce(hit.get_normal()) * 0.7
	_animate(delta)


func _ground_goal(goal: Vector3) -> Vector3:
	if family == "snake" or family == "ball":
		goal.y = global_position.y - position.y + radius
	return goal


func _flat_or_full_distance(point: Vector3) -> float:
	if family == "snake" or family == "ball":
		return Vector2(global_position.x, global_position.z).distance_to(Vector2(point.x, point.z))
	return global_position.distance_to(point)


func _maybe_dive(delta: float) -> void:
	var every: float = stats.get("dive", 0.0)
	if every <= 0.0 or player_head == null or is_roped():
		return
	_dive_timer -= delta
	if _dive_timer <= 0.0:
		_dive_timer = every * randf_range(0.8, 1.4)
		if global_position.distance_to(player_head.global_position) < 3.5:
			_dive_from = state
			state = State.DIVE
			_timer = 0.0
			if director:
				director.call("cue", "spark_spawn", global_position, -6.0)


func _fly_toward(goal: Vector3, delta: float, factor: float, ignore_player: bool = false) -> void:
	var to := goal - global_position
	var desired := Vector3.ZERO
	if to.length() > 0.02:
		desired = to.normalized() * speed * factor * (1.0 - _tension * 0.85)
	if player_head and not ignore_player:
		var away := global_position - player_head.global_position
		var d := away.length()
		if d < 0.45 and d > 0.001:
			desired += away.normalized() * (0.45 - d) * 6.0
	var accel := speed * (3.0 if family != "ball" else 1.6)
	if family == "ball":
		desired.y = velocity.y   # gravity and bounces own the vertical for balls
	var change := desired - velocity
	if change.length() > accel * delta:
		change = change.normalized() * accel * delta
	velocity += change


func _yanked(pull: Vector3) -> void:
	_hit_flash = 1.0
	if is_boss:
		state = State.STUN
		_timer = 0.0
		return
	if kind == "splitter" and state != State.STUN:
		split.emit(self, global_position)
		_die()
		return
	if family == "snake":
		segments_left = maxi(0, segments_left - 3)
		_rebuild_segments()
		if segments_left <= 2:
			_die()
			return
	if has_shard:
		has_shard = false
		_shard.visible = false
		shard_dropped.emit(self, global_position)
	state = State.STUN
	_timer = 0.0
	velocity += pull.normalized() * 1.5 if pull.length() > 0.001 else Vector3.ZERO


func _die() -> void:
	if state == State.DEAD:
		return
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.release()
	state = State.DEAD
	_timer = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	has_shard = false
	_shard.visible = false
	_body.visible = false
	for seg in _segments:
		seg.visible = false
	for i in range(_burst.size()):
		_burst[i].visible = true
		_burst[i].global_position = global_position
	_shock.visible = true
	_shock.global_position = global_position
	died.emit(self)


func _escape() -> void:
	var had := has_shard
	state = State.DEAD
	escaped.emit(self, had)
	queue_free()


# --- character ----------------------------------------------------------------

func _build_character() -> void:
	_eyes = Node3D.new()
	_body.add_child(_eyes)
	var eye_count := 1 if kind in ["mote", "pebble"] else 2
	var eye_r := radius * (0.22 if family != "ball" and kind != "brute" else 0.16)
	for i in range(eye_count):
		var eye := Neon.make_eye(eye_r)
		var x := 0.0 if eye_count == 1 else (-1.0 if i == 0 else 1.0) * radius * 0.42
		eye.position = Vector3(x, radius * 0.25, radius * 0.82)
		_eyes.add_child(eye)
		_eye_list.append(eye)
	match family:
		"snake":
			_core.scale = Vector3(0.9, 0.75, 1.1)
			_rebuild_segments()
		"drone":
			_core.scale = Vector3(1.15, 0.55, 1.15)
			for i in range(4):
				var rotor := Neon.make_ring_mesh(Neon.WHITE.lerp(color, 0.4), radius * 0.5, radius * 0.05)
				var ax := (-1.0 if i % 2 == 0 else 1.0) * radius * 1.05
				var az := (-1.0 if i < 2 else 1.0) * radius * 1.05
				rotor.position = Vector3(ax, radius * 0.35, az)
				_body.add_child(rotor)
				_rotors.append(rotor)
				var arm := Neon.make_orb(color.darkened(0.5), radius * 0.1, 6, 3)
				arm.position = Vector3(ax * 0.5, radius * 0.2, az * 0.5)
				arm.scale = Vector3(radius * 10.0, 1.0, 1.0) if absf(ax) > absf(az) else Vector3(1.0, 1.0, radius * 10.0)
				_body.add_child(arm)
		"ball":
			_stripe = Neon.make_ring_mesh(Neon.WHITE.lerp(color, 0.3), radius * 0.98, radius * 0.07)
			_body.add_child(_stripe)
			var stripe2 := Neon.make_ring_mesh(Neon.WHITE.lerp(color, 0.5), radius * 0.98, radius * 0.04)
			stripe2.rotation_degrees.x = 90.0
			_body.add_child(stripe2)
		_:
			if kind != "brute":
				_add_puff_parts()
			match kind:
				"ember":
					for i in range(4):
						var lick := Neon.make_lick(color, radius * 0.32, radius * 1.3)
						lick.position = Vector3(cos(i * 1.6) * radius * 0.45, radius * 0.75, sin(i * 1.6) * radius * 0.45)
						_body.add_child(lick)
						_licks.append(lick)
				"zip":
					for i in range(2):
						var fin := Neon.make_lick(color, radius * 0.25, radius * 1.4)
						fin.rotation_degrees = Vector3(90, 0, (28.0 if i == 0 else -28.0))
						fin.position = Vector3((-1.0 if i == 0 else 1.0) * radius * 0.55, 0.0, -radius * 0.9)
						_body.add_child(fin)
						_fins.append(fin)
					_core.scale = Vector3(0.85, 0.85, 1.25)
				"brute":
					for i in range(7):
						var plate := Neon.make_living_orb(color, radius * 0.55, 7, 4, true)
						var a := i * 2.4
						var dir := Vector3(cos(a) * cos(i * 0.9), sin(i * 0.9), sin(a) * cos(i * 0.9)).normalized()
						plate.position = dir * radius * 0.78
						plate.scale = Vector3(1.0, 0.55, 1.0)
						_body.add_child(plate)
						_plates.append(plate)
				"splitter":
					_seam = Neon.make_ring_mesh(Neon.WHITE.lerp(color, 0.3), radius * 0.95, radius * 0.05)
					_seam.rotation_degrees.z = 90.0
					_body.add_child(_seam)
			for i in range(2 if kind != "brute" else 3):
				var mote := Neon.make_orb(Neon.WHITE.lerp(color, 0.5), radius * 0.14, 6, 3)
				_body.add_child(mote)
				_motes.append(mote)


## Fuzzy puff body: fur shells, two springy ears and two little feet.
func _add_puff_parts() -> void:
	var fur_len := radius * 0.32
	_fur = Neon.add_fur(_body, color, radius, fur_len, 6, 30.0 if radius > 0.1 else 22.0)
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var ear_root := Node3D.new()
		ear_root.position = Vector3(side * radius * 0.5, radius * 0.75, -radius * 0.1)
		_body.add_child(ear_root)
		var ear := Neon.make_lick(color, radius * 0.22, radius * 0.9)
		ear.position = Vector3(0, radius * 0.4, 0)
		ear.material_override = Neon.orb_material(color.lerp(Neon.WHITE, 0.25), Color(1, 0.95, 0.85), 4.0)
		ear_root.add_child(ear)
		var tipball := Neon.make_orb(Neon.WHITE.lerp(color, 0.3), radius * 0.12, 6, 3)
		tipball.position = Vector3(0, radius * 0.9, 0)
		ear_root.add_child(tipball)
		ear_root.rotation_degrees.z = -side * 18.0
		_ears.append(ear_root)
		var foot := Neon.make_orb(color.darkened(0.35), radius * 0.26, 8, 4)
		foot.scale = Vector3(1.0, 0.6, 1.3)
		foot.position = Vector3(side * radius * 0.42, -radius * 0.95, radius * 0.1)
		_body.add_child(foot)
		_feet.append(foot)
	# The living orb becomes the skin under the fur.
	_core.scale = Vector3.ONE * 0.97


func _rebuild_segments() -> void:
	for seg in _segments:
		seg.queue_free()
	_segments.clear()
	for i in range(segments_left):
		var t := float(i) / maxf(1.0, segments_left - 1)
		var seg := Neon.make_living_orb(color, radius * (0.85 - 0.45 * t), 10, 5)
		seg.top_level = true
		add_child(seg)
		_segments.append(seg)


func _animate_character(delta: float) -> void:
	var flat_speed := velocity.length()
	if flat_speed > 0.15:
		var facing := velocity.normalized()
		if absf(facing.y) > 0.97:
			facing = (facing + _body_rot.z * 0.2).normalized()
			if absf(facing.y) > 0.97:
				facing = Vector3(0.01, 0, 1)
		var target := Basis.looking_at(facing, Vector3.UP, true)
		if family == "drone":
			# Bank into the motion.
			var local := _body_rot.inverse() * velocity
			target = target * Basis(Vector3.RIGHT, clampf(local.z * 0.15, -0.5, 0.5)) * Basis(Vector3.FORWARD, clampf(-local.x * 0.2, -0.6, 0.6))
		if family == "ball":
			_roll_angle += flat_speed * delta / maxf(radius, 0.02)
			target = Basis(Vector3.UP, atan2(velocity.x, velocity.z)) * Basis(Vector3.RIGHT, _roll_angle)
		_body_rot = _body_rot.slerp(target, minf(1.0, delta * (6.0 if family != "ball" else 12.0))).orthonormalized()
	var want_stretch := 1.0
	if family != "ball":
		want_stretch = 1.0 + clampf(flat_speed / maxf(speed, 0.1), 0.0, 1.5) * 0.3 - _hit_flash * 0.35
	_stretch = lerpf(_stretch, want_stretch, minf(1.0, delta * 10.0))
	var squash := 1.0 / sqrt(maxf(_stretch, 0.3))
	var breathe := 1.0 + sin(_life * 5.0) * (0.05 if family != "ball" else 0.0)
	_body.basis = _body_rot * Basis.from_scale(Vector3(squash, squash, _stretch) * breathe)
	if player_head and _eyes and family != "ball":
		var local := _body.global_basis.inverse() * (player_head.global_position - _eyes.global_position)
		var yaw := clampf(atan2(local.x, local.z), -0.7, 0.7)
		var pitch := clampf(-atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.5)
		_eyes.rotation = _eyes.rotation.lerp(Vector3(pitch, yaw, 0), minf(1.0, delta * 8.0))
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(1.6, 4.5)
	_blink = maxf(0.0, _blink - delta)
	var open := 1.0 if _blink <= 0.0 else 0.12
	var mood := 1.35 if is_roped() else (0.6 if state == State.DRAIN else (1.5 if state == State.DIVE else 1.0))
	for eye in _eye_list:
		eye.scale = Vector3(mood, open * mood, 1.0)
	for i in range(_licks.size()):
		var f := 0.75 + 0.35 * sin(_life * (9.0 + i * 1.7) + i)
		_licks[i].scale = Vector3(1.0, f, 1.0)
		_licks[i].rotation = Vector3(sin(_life * 7.0 + i) * 0.25, 0.0, cos(_life * 6.0 + i * 2.0) * 0.25)
	for i in range(_fins.size()):
		_fins[i].rotation_degrees.z = (28.0 if i == 0 else -28.0) + sin(_life * 14.0 + i) * 12.0
	for i in range(_plates.size()):
		_plates[i].position = _plates[i].position.normalized() * radius * (0.78 + 0.04 * sin(_life * 2.0 + i))
	if _seam:
		_seam.rotation.y += delta * 2.5
	for i in range(_rotors.size()):
		_rotors[i].rotation.y += delta * (28.0 + (6.0 if is_roped() else 0.0)) * (1.0 if i % 2 == 0 else -1.0)
	for i in range(_motes.size()):
		var a := _life * (3.0 + i * 0.7) + i * TAU / 3.0
		var tilt := i * 1.1
		_motes[i].position = Vector3(cos(a) * radius * 1.5, sin(a) * radius * 1.5 * sin(tilt), sin(a) * radius * 1.5 * cos(tilt))
	# Snake body follows the head's path.
	if family == "snake" and _history.size() >= 2:
		for i in range(_segments.size()):
			var back := (i + 1) * 1.4
			var idx := _history.size() - 1 - int(back)
			if idx < 0:
				idx = 0
			var frac: float = back - floor(back)
			var a_pos := _history[maxi(idx, 0)]
			var b_pos := _history[maxi(idx - 1, 0)]
			_segments[i].global_position = a_pos.lerp(b_pos, frac)
			_segments[i].scale = Vector3.ONE * (1.0 + sin(_life * 6.0 - i * 0.6) * 0.08)
			(_segments[i].material_override as ShaderMaterial).set_shader_parameter("heat", _hit_flash)
	(_core.material_override as ShaderMaterial).set_shader_parameter("heat", _hit_flash + (0.35 if state == State.STUN else 0.0))
	for f in _fur:
		(f.material_override as ShaderMaterial).set_shader_parameter("heat", _hit_flash)
	# Ears: a damped spring driven by acceleration (they flop when it turns or gets yanked).
	if not _ears.is_empty():
		var accel := (velocity - _prev_vel) / maxf(delta, 0.001)
		var local := _body_rot.inverse() * accel
		var force := Vector2(clampf(-local.z * 0.04, -1.5, 1.5), clampf(local.x * 0.04, -1.5, 1.5))
		_ear_vel += (force - _ear_swing * 60.0 - _ear_vel * 7.0) * delta
		_ear_swing += _ear_vel * delta * 10.0
		_ear_swing = _ear_swing.clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
		for i in range(_ears.size()):
			var side := -1.0 if i == 0 else 1.0
			_ears[i].rotation = Vector3(_ear_swing.x, 0.0, deg_to_rad(-side * 18.0) + _ear_swing.y + sin(_life * 3.0 + i) * 0.05)
	_prev_vel = velocity
	for i in range(_feet.size()):
		var paddle := sin(_life * 14.0 + i * PI) * clampf(velocity.length() / maxf(speed, 0.1), 0.0, 1.0)
		_feet[i].position.z = radius * 0.1 + paddle * radius * 0.25
		_feet[i].position.y = -radius * 0.95 + maxf(0.0, -paddle) * radius * 0.12


func _animate(delta: float) -> void:
	if state == State.DEAD:
		var t := clampf(_timer / 0.6, 0.0, 1.0)
		for i in range(_burst.size()):
			var a := TAU * i / _burst.size()
			var dir := Vector3(cos(a), sin(a * 2.0) * 0.6, sin(a))
			_burst[i].global_position = global_position + dir * t * radius * 8.0
			Neon.set_halo_color(_burst[i], color.lerp(Neon.WHITE, 0.4), (1.0 - t) * 0.9)
		_shock.scale = Vector3.ONE * (1.0 + t * 6.0)
		_shock.global_rotation = Vector3(PI * 0.5, 0, 0) if family != "ball" else Vector3.ZERO
		(_shock.material_override as StandardMaterial3D).albedo_color = color.lerp(Neon.WHITE, 0.5) * Color(1, 1, 1, 1.0 - t)
		_shock.visible = t < 1.0
		Neon.set_halo_color(_halo, Neon.WHITE.lerp(color, 0.3), (1.0 - t) * 1.2)
		_trail_mat.set_shader_parameter("alpha_scale", 1.0 - t)
		(_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.3 * (1.0 - t))
		if t >= 1.0:
			queue_free()
		return
	_animate_character(delta)
	_inner.scale = Vector3.ONE * (1.0 + sin(_life * 9.0) * 0.15)
	if _crown:
		_crown.position = Vector3(0, radius * 1.6 + sin(_life * 3.0) * 0.02, 0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			_crown.look_at(cam.global_position, Vector3.UP, true)
	var glow := color if not is_roped() else TetherMath.rope_color(_tension)
	Neon.set_halo_color(_halo, glow, 0.3 + _hit_flash * 0.5 + _tension * 0.3 + (0.2 if state == State.STUN else 0.0))
	_shard.position = Vector3(0, radius * 1.4, 0)
	_shard.rotation.y += delta * 4.0
	_history_timer += delta
	if _history_timer >= 0.025:
		_history_timer = 0.0
		_history.append(global_position)
		var keep := TRAIL_POINTS if family != "snake" else int(segments_left * 1.4) + 4
		while _history.size() > keep:
			_history.remove_at(0)
	if _history.size() >= 2 and family != "snake":
		var pts := PackedVector3Array()
		for i in range(_history.size() - 1, -1, -1):
			pts.append(_history[i])
		var r := radius * 0.5
		Neon.build_tube(_trail_mesh, pts, func(t): return r * (1.0 - t) + 0.004)
	_trail_mat.set_shader_parameter("tint", glow)
	_trail_mat.set_shader_parameter("alpha_scale", clampf(velocity.length() / speed, 0.15, 1.0) * (0.0 if family == "snake" else 1.0))
	var floor_y := global_position.y - position.y
	_shadow.global_position = Vector3(global_position.x, floor_y + 0.004, global_position.z)
	_shadow.global_rotation = Vector3.ZERO
	(_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, clampf(0.35 - position.y * 0.12, 0.08, 0.35))
