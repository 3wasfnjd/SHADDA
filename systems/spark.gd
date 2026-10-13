class_name Spark
extends CharacterBody3D
## A spark: a living blob of energy that flies out of a wall crack, weaves to
## the gem, orbits it to drain a shard, and races back home. Pure procedural
## geometry: neon orb, inner core, orbiting motes, halo and a glowing trail.
## Ropes drag it by mass; a yank makes it drop its shard; crush it in your
## fist, or slam it into a real wall.

signal died(spark: Spark)
signal escaped(spark: Spark, with_shard: bool)
signal shard_taken(spark: Spark)
signal shard_dropped(spark: Spark, at: Vector3)
signal split(spark: Spark, at: Vector3)

enum State { EMERGE, APPROACH, DRAIN, FLEE, STUN, DEAD }

const REACH := 0.5
const SLAM_SPEED := 2.3
const STUN_SECONDS := 1.3
const TRAIL_POINTS := 16

var kind: String = "ember"
var stats: Dictionary = {}
var state: int = State.EMERGE
var home: Node3D                 # crack
var gem: Node3D
var player_head: Node3D
var director: Node
var has_shard: bool = false
var tethers: Array = []
var radius: float = 0.12
var speed: float = 1.5
var mass: float = 1.0
var color: Color = Neon.AMBER

var _timer: float = 0.0
var _life: float = 0.0
var _seed: float = 0.0
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0
var _tension: float = 0.0
var _hit_flash: float = 0.0
var _core: MeshInstance3D
var _inner: MeshInstance3D
var _motes: Array[MeshInstance3D] = []
var _body: Node3D
var _eyes: Node3D
var _eye_list: Array[Node3D] = []
var _licks: Array[MeshInstance3D] = []
var _fins: Array[MeshInstance3D] = []
var _plates: Array[MeshInstance3D] = []
var _seam: MeshInstance3D
var _blink: float = 0.0
var _next_blink: float = 2.0
var _stretch: float = 1.0
var _body_rot: Basis = Basis.IDENTITY
var _halo: MeshInstance3D
var _shadow: MeshInstance3D
var _shard: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_mat: ShaderMaterial
var _history: PackedVector3Array = PackedVector3Array()
var _history_timer: float = 0.0
var _burst: Array[MeshInstance3D] = []


static func create(spark_kind: String) -> Spark:
	var s := Spark.new()
	s.kind = spark_kind
	s.stats = SparkMath.stats(spark_kind)
	return s


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	radius = stats.radius
	speed = stats.speed
	mass = stats.mass
	color = stats.color
	_seed = randf() * 100.0
	_orbit_dir = 1.0 if randf() > 0.5 else -1.0
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
	for i in range(6):
		var b := Neon.make_halo(color, radius * 2.0, 0.0)
		b.visible = false
		b.top_level = true
		add_child(b)
		_burst.append(b)


func configure(crack: Node3D, target_gem: Node3D, head: Node3D) -> void:
	home = crack
	gem = target_gem
	player_head = head
	global_position = crack.spawn_point()
	velocity = crack.outward() * 0.6


# --- tether interface -------------------------------------------------------

func tether_anchor() -> Node3D:
	return self


func can_be_tethered() -> bool:
	return state != State.DEAD and state != State.EMERGE


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


## Crushed in a gauntlet fist.
func crush() -> void:
	if state != State.DEAD:
		_die()


# --- behaviour ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_timer += delta
	_life += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
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
	match state:
		State.EMERGE:
			_fly_toward(home.spawn_point() + home.outward() * 0.7, delta, 1.0)
			if _timer > 0.5:
				state = State.APPROACH
				_timer = 0.0
		State.APPROACH:
			var goal := gem_center + SparkMath.weave_offset(_life, stats.weave, stats.weave_hz, _seed)
			_fly_toward(goal, delta, 1.0)
			if global_position.distance_to(gem_center) < 0.55 + radius:
				state = State.DRAIN
				_timer = 0.0
				_orbit_angle = atan2(global_position.z - gem_center.z, global_position.x - gem_center.x)
		State.DRAIN:
			_orbit_angle += _orbit_dir * delta * (speed / 0.5)
			var goal := SparkMath.orbit_point(gem_center, _orbit_angle, 0.5 + radius, sin(_life * 3.0) * 0.12)
			_fly_toward(goal, delta, 1.3)
			if _timer >= stats.drain_time * (1.0 + _tension * 2.0):
				has_shard = true
				_shard.visible = true
				shard_taken.emit(self)
				state = State.FLEE
				_timer = 0.0
		State.FLEE:
			var exit: Vector3 = home.spawn_point() + home.outward() * 0.3
			_fly_toward(exit + SparkMath.weave_offset(_life, stats.weave * 0.6, stats.weave_hz, _seed), delta, 1.15)
			if global_position.distance_to(exit) < 0.35 and _tension < 0.3:
				_escape()
				return
		State.STUN:
			velocity *= 1.0 - minf(1.0, delta * 3.0)
			velocity.y -= 2.0 * delta
			if _timer >= STUN_SECONDS:
				state = State.APPROACH
				_timer = 0.0
	# Rope drag.
	if pull != Vector3.ZERO:
		velocity += pull
		velocity *= 1.0 - minf(0.5, delta * 1.2)
	if _tension >= TetherMath.STUN_TENSION and state != State.STUN:
		_yanked(pull)
	var before := velocity
	move_and_slide()
	# Keep above the floor and below head height + a bit.
	var floor_y := global_position.y - position.y
	if position.y < radius + 0.05:
		position.y = radius + 0.05
		velocity.y = absf(velocity.y) * 0.4
	if position.y > 2.2:
		position.y = 2.2
		velocity.y = -absf(velocity.y) * 0.4
	# Slam into a scanned surface while roped.
	if is_roped():
		for i in range(get_slide_collision_count()):
			var hit := get_slide_collision(i)
			var collider := hit.get_collider()
			if collider and collider.has_meta("labels") and before.dot(-hit.get_normal()) > SLAM_SPEED:
				if director:
					director.call("cue", "thud", global_position, 4.0)
				_die()
				return
	_animate(delta)


func _fly_toward(goal: Vector3, delta: float, factor: float) -> void:
	var to := goal - global_position
	var desired := Vector3.ZERO
	if to.length() > 0.02:
		desired = to.normalized() * speed * factor * (1.0 - _tension * 0.85)
	# Keep a respectful distance from the player's face.
	if player_head:
		var away := global_position - player_head.global_position
		var d := away.length()
		if d < 0.45 and d > 0.001:
			desired += away.normalized() * (0.45 - d) * 6.0
	var accel := speed * 3.0
	var change := desired - velocity
	if change.length() > accel * delta:
		change = change.normalized() * accel * delta
	velocity += change


func _yanked(pull: Vector3) -> void:
	_hit_flash = 1.0
	if kind == "splitter" and state != State.STUN:
		split.emit(self, global_position)
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
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.release()
	state = State.DEAD
	_timer = 0.0
	velocity = Vector3.ZERO
	has_shard = false
	_shard.visible = false
	_body.visible = false
	for i in range(_burst.size()):
		_burst[i].visible = true
		_burst[i].global_position = global_position
	died.emit(self)


func _escape() -> void:
	var had := has_shard
	state = State.DEAD
	escaped.emit(self, had)
	queue_free()


## Per-kind silhouette: flame licks, fins, rock plates, a glowing seam — and
## cartoon eyes on every spark so they read as creatures, not bullets.
func _build_character() -> void:
	_eyes = Node3D.new()
	_body.add_child(_eyes)
	var eye_count := 1 if kind == "mote" else 2
	var eye_r := radius * (0.22 if kind != "brute" else 0.16)
	for i in range(eye_count):
		var eye := Neon.make_eye(eye_r)
		var x := 0.0 if eye_count == 1 else (-1.0 if i == 0 else 1.0) * radius * 0.42
		eye.position = Vector3(x, radius * 0.25, radius * 0.82)
		_eyes.add_child(eye)
		_eye_list.append(eye)
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
				plate.look_at_from_position(plate.position, plate.position + dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
				plate.rotate_object_local(Vector3.RIGHT, PI * 0.5)
				_body.add_child(plate)
				_plates.append(plate)
			for i in range(3):
				var mote := Neon.make_orb(Neon.WHITE.lerp(color, 0.5), radius * 0.12, 6, 3)
				_body.add_child(mote)
				_motes.append(mote)
		"splitter":
			_seam = Neon.make_ring_mesh(Neon.WHITE.lerp(color, 0.3), radius * 0.95, radius * 0.05)
			_seam.rotation_degrees.z = 90.0
			_body.add_child(_seam)
			for i in range(2):
				var mote := Neon.make_orb(Neon.WHITE.lerp(color, 0.5), radius * 0.14, 6, 3)
				_body.add_child(mote)
				_motes.append(mote)
		_:
			for i in range(2):
				var mote := Neon.make_orb(Neon.WHITE.lerp(color, 0.5), radius * 0.16, 6, 3)
				_body.add_child(mote)
				_motes.append(mote)


func _animate_character(delta: float) -> void:
	# Face the way we fly, with squash & stretch by speed and a hit squash.
	var flat_speed := velocity.length()
	if flat_speed > 0.15:
		var target := Basis.looking_at(velocity.normalized(), Vector3.UP, true)
		_body_rot = _body_rot.slerp(target, minf(1.0, delta * 6.0)).orthonormalized()
	var want_stretch := 1.0 + clampf(flat_speed / maxf(speed, 0.1), 0.0, 1.5) * 0.3 - _hit_flash * 0.35
	_stretch = lerpf(_stretch, want_stretch, minf(1.0, delta * 10.0))
	var squash := 1.0 / sqrt(maxf(_stretch, 0.3))
	var breathe := 1.0 + sin(_life * 5.0) * 0.05
	_body.basis = _body_rot * Basis.from_scale(Vector3(squash, squash, _stretch) * breathe)
	# Eyes track the player; blink now and then; wide when roped, narrow when draining.
	if player_head and _eyes:
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
	var mood := 1.35 if is_roped() else (0.6 if state == State.DRAIN else 1.0)
	for eye in _eye_list:
		eye.scale = Vector3(mood, open * mood, 1.0)
	# Decorations.
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
	for i in range(_motes.size()):
		var a := _life * (3.0 + i * 0.7) + i * TAU / 3.0
		var tilt := i * 1.1
		_motes[i].position = Vector3(cos(a) * radius * 1.5, sin(a) * radius * 1.5 * sin(tilt), sin(a) * radius * 1.5 * cos(tilt))
	(_core.material_override as ShaderMaterial).set_shader_parameter("heat", _hit_flash + (0.35 if state == State.STUN else 0.0))


func _animate(delta: float) -> void:
	if state == State.DEAD:
		var t := clampf(_timer / 0.55, 0.0, 1.0)
		for i in range(_burst.size()):
			var a := TAU * i / _burst.size()
			var dir := Vector3(cos(a), sin(a * 2.0) * 0.6, sin(a))
			_burst[i].global_position = global_position + dir * t * radius * 7.0
			Neon.set_halo_color(_burst[i], color.lerp(Neon.WHITE, 0.4), (1.0 - t) * 0.9)
		Neon.set_halo_color(_halo, Neon.WHITE.lerp(color, 0.3), (1.0 - t) * 1.2)
		_trail_mat.set_shader_parameter("alpha_scale", 1.0 - t)
		(_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.3 * (1.0 - t))
		if t >= 1.0:
			queue_free()
		return
	_animate_character(delta)
	_inner.scale = Vector3.ONE * (1.0 + sin(_life * 9.0) * 0.15)
	var glow := color if not is_roped() else TetherMath.rope_color(_tension)
	Neon.set_halo_color(_halo, glow, 0.3 + _hit_flash * 0.5 + _tension * 0.3 + (0.2 if state == State.STUN else 0.0))
	_shard.position = Vector3(0, radius * 1.4, 0)
	_shard.rotation.y += delta * 4.0
	# Trail.
	_history_timer += delta
	if _history_timer >= 0.025:
		_history_timer = 0.0
		_history.append(global_position)
		if _history.size() > TRAIL_POINTS:
			_history.remove_at(0)
	if _history.size() >= 2:
		var pts := PackedVector3Array()
		for i in range(_history.size() - 1, -1, -1):
			pts.append(_history[i])
		var r := radius * 0.5
		Neon.build_tube(_trail_mesh, pts, func(t): return r * (1.0 - t) + 0.004)
	_trail_mat.set_shader_parameter("tint", glow)
	_trail_mat.set_shader_parameter("alpha_scale", clampf(velocity.length() / speed, 0.15, 1.0))
	# Shadow.
	var floor_y := global_position.y - position.y
	_shadow.global_position = Vector3(global_position.x, floor_y + 0.004, global_position.z)
	_shadow.global_rotation = Vector3.ZERO
	(_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, clampf(0.35 - position.y * 0.12, 0.08, 0.35))
