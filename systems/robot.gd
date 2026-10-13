class_name Robot
extends CharacterBody3D
## A SHADDA raider with physically plausible motion: inertia-limited steering,
## a procedural gait driven on the model's real mechanical joints (hips, knees,
## ankles, wheels, rotors, arms, neck), rope tug-of-war by mass, tumbling when
## yanked, and shutdown when crushed by a gauntlet or slammed into a wall.

signal defeated(robot: Robot)
signal escaped(robot: Robot, with_cell: bool)
signal cell_taken(robot: Robot)
signal cell_dropped(robot: Robot, cell: Node3D)

enum State { EMERGE, SEEK, STEAL, FLEE, TUMBLE, DOWN, GONE }

const REACH := 0.55            # metres: a roped raider this close can be crushed
const SLAM_SPEED := 2.1        # m/s into a wall while roped = shutdown
const TUMBLE_SECONDS := 2.4

var kind: String = "A"
var stats: Dictionary = {}
var state: int = State.EMERGE
var model: Node3D
var home_rift: Node3D
var station: Node3D
var cell: Node3D = null
var carry_point: Node3D
var crown: Node3D
var eyes: Array[MeshInstance3D] = []
var tethers: Array = []
var hover: float = 0.0
var mass: float = 1.0
var speed: float = 0.6
var accel: float = 1.4
var turn_rate: float = 2.8
var gait: String = "biped"
var player_head: Node3D

var _timer: float = 0.0
var _phase: float = 0.0
var _hit_flash: float = 0.0
var _emitters: Dictionary = {}
var _halo: MeshInstance3D
var _expression: String = ""
var _tension: float = 0.0
var _tumble_dir: Vector3 = Vector3.FORWARD
var _joints: Dictionary = {}       # name -> Node3D
var _rest: Dictionary = {}         # name -> Vector3 rotation
var _body: Node3D
var _body_rest: Vector3
var _prev_velocity: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO  # pitch, roll
var _leg_length: float = 0.25
var _wheel_spin: float = 0.0


static func create(robot_kind: String, scene: PackedScene) -> Robot:
	var robot := Robot.new()
	robot.kind = robot_kind
	robot.stats = SpawnDirector.robot_stats(robot_kind)
	robot.model = scene.instantiate() as Node3D
	return robot


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1               # real walls from the room scan
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	mass = stats.get("mass", 1.0)
	speed = stats.get("speed", 0.6)
	accel = stats.get("accel", 1.4)
	turn_rate = stats.get("turn", 2.8)
	hover = stats.get("hover", 0.0)
	gait = stats.get("gait", "biped")
	add_child(model)
	_emitters = Neon.restyle(model)
	Neon.rest_on_floor(model)
	var bounds := Neon.merged_aabb(model)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.12, minf(bounds.size.x, bounds.size.z) * 0.42)
	capsule.height = maxf(bounds.size.y, capsule.radius * 2.0 + 0.01)
	shape.shape = capsule
	shape.position = Vector3(0, bounds.size.y * 0.5, 0)
	add_child(shape)
	crown = model.find_child("TetherPoint_Crown", true, false) as Node3D
	carry_point = _find_first(["GrabPoint_Backpack_R", "GrabPoint_R", "GrabPoint_Hand_R", "GrabPoint_Arm_R", "GrabPoint_L"])
	if crown == null:
		crown = Node3D.new()
		crown.position = Vector3(0, bounds.size.y, 0)
		model.add_child(crown)
	if carry_point == null:
		carry_point = crown
	for node in model.find_children("FACE_Eye_*", "MeshInstance3D", true, false):
		eyes.append(node as MeshInstance3D)
	for node in model.find_children("RIG_*", "Node3D", true, false):
		_joints[String(node.name)] = node
		_rest[String(node.name)] = (node as Node3D).rotation
	_body = _joints.get("RIG_Body", model)
	_body_rest = _body.rotation
	if _joints.has("RIG_Hip_L") and _joints.has("RIG_Ankle_L"):
		_leg_length = (_joints["RIG_Ankle_L"] as Node3D).global_position.distance_to((_joints["RIG_Hip_L"] as Node3D).global_position)
	_halo = Neon.make_halo(Neon.CYAN, 0.6, 0.0)
	_halo.position = Vector3(0, bounds.size.y * 0.55, 0)
	add_child(_halo)
	set_expression("Happy")
	scale = Vector3.ONE * 0.05


func _find_first(names: Array) -> Node3D:
	for n in names:
		var found := model.find_child(n, true, false)
		if found:
			return found as Node3D
	return null


func configure(rift: Node3D, target_station: Node3D, head: Node3D) -> void:
	home_rift = rift
	station = target_station
	player_head = head
	global_position = rift.spawn_inside()
	position.y = 0.0
	look_toward(rift.spawn_outside())


func look_toward(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_squared_to(global_position) > 1e-4:
		look_at(flat, Vector3.UP, true)


# --- tether interface -------------------------------------------------------

func tether_anchor() -> Node3D:
	return crown


func can_be_tethered() -> bool:
	return state != State.DOWN and state != State.GONE and state != State.EMERGE


func attach_tether(t: Node3D) -> void:
	if not tethers.has(t):
		tethers.append(t)
	set_expression("Surprised")
	_hit_flash = 1.0


func detach_tether(t: Node3D) -> void:
	tethers.erase(t)
	if tethers.is_empty() and state != State.TUMBLE and state != State.DOWN:
		set_expression("Happy" if cell else "Angry")


func on_tether_snapped() -> void:
	_hit_flash = 1.0


## A gauntlet closed its fist on a roped raider within reach.
func crush() -> void:
	if state == State.DOWN or state == State.GONE:
		return
	_shutdown()


func is_roped() -> bool:
	return not tethers.is_empty()


# --- behaviour ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_timer += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.5)
	var pull := Vector3.ZERO
	_tension = 0.0
	for t in tethers:
		if not is_instance_valid(t):
			continue
		pull += TetherMath.pull_velocity(t.hand_position(), crown.global_position, t.rest_length, mass, delta)
		_tension = maxf(_tension, t.tension)
	match state:
		State.EMERGE:
			var t := clampf(_timer / 1.4, 0.0, 1.0)
			scale = Vector3.ONE * maxf(0.05, smoothstep(0.0, 1.0, t))
			var exit: Vector3 = home_rift.spawn_outside()
			exit.y = global_position.y - position.y + hover
			global_position = global_position.lerp(exit, delta * 2.0)
			Neon.set_halo_color(_halo, Neon.CYAN, (1.0 - t) * 0.7)
			_animate(delta, true)
			if t >= 1.0:
				scale = Vector3.ONE
				state = State.SEEK
				set_expression("Angry")
			return
		State.SEEK:
			var goal: Vector3 = station.approach_point(global_position)
			_steer(goal, delta, 1.0)
			if _flat_distance(goal) < 0.14:
				state = State.STEAL
				_timer = 0.0
				set_expression("Happy")
		State.STEAL:
			_steer(global_position, delta, 0.0)
			look_toward(station.global_position)
			var steal_time: float = stats.get("steal_time", 2.0)
			if _timer >= steal_time * (1.0 + _tension):
				var taken: Node3D = station.take_cell(self)
				if taken:
					cell = taken
					cell_taken.emit(self)
				state = State.FLEE
				_timer = 0.0
		State.FLEE:
			var exit: Vector3 = home_rift.spawn_outside()
			_steer(exit, delta, 1.1)
			if _flat_distance(exit) < 0.2 and _tension < 0.25:
				_escape()
				return
		State.TUMBLE:
			_steer(global_position, delta, 0.0)
			velocity *= 1.0 - minf(1.0, delta * 4.0)
			if _timer >= TUMBLE_SECONDS:
				state = State.FLEE if cell else State.SEEK
				set_expression("Angry")
		State.DOWN:
			velocity *= 1.0 - minf(1.0, delta * 5.0)
			var t := clampf((_timer - 2.4) / 0.8, 0.0, 1.0)
			if t > 0.0:
				scale = Vector3.ONE * maxf(0.02, 1.0 - t)
			Neon.set_halo_color(_halo, Neon.CYAN, 0.4 * (1.0 - t))
			if t >= 1.0:
				state = State.GONE
				queue_free()
				return
		State.GONE:
			return
	# Rope: the raider is dragged by its crown; ground units can't be lifted.
	if pull != Vector3.ZERO and state != State.DOWN:
		if hover <= 0.0:
			pull.y = 0.0
		velocity += pull
		velocity *= 1.0 - minf(0.5, delta * 1.5)   # rope friction against the floor
	if _tension >= TetherMath.STUN_TENSION and state != State.TUMBLE and state != State.DOWN:
		_tumble(pull)
	var before := velocity
	move_and_slide()
	# Slammed into a real wall while roped.
	if state != State.DOWN and is_roped() and get_slide_collision_count() > 0 and before.length() > SLAM_SPEED:
		_shutdown()
	if hover <= 0.0:
		position.y = 0.0
	else:
		position.y = lerpf(position.y, hover + sin(_timer * 2.1) * 0.05, delta * 3.0)
	_animate(delta, false)


func _steer(goal: Vector3, delta: float, factor: float) -> void:
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var desired := Vector3.ZERO
	if factor > 0.0 and to_goal.length() > 0.02:
		desired = to_goal.normalized() * speed * factor * (1.0 - _tension * 0.85)
		# Walk around the player instead of through them.
		if hover <= 0.0 and player_head:
			var away := global_position - player_head.global_position
			away.y = 0.0
			var d := away.length()
			if d < 0.9 and d > 0.001:
				desired += away.normalized() * (0.9 - d) * speed * 1.6
	var flat := Vector3(velocity.x, 0, velocity.z)
	var change := desired - flat
	var max_change := accel * delta
	if change.length() > max_change:
		change = change.normalized() * max_change
	flat += change
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0
	if flat.length() > 0.05 and state != State.TUMBLE:
		var target_yaw := atan2(flat.x, flat.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, turn_rate * delta))


func _flat_distance(point: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(point.x, point.z))


func _tumble(pull: Vector3) -> void:
	_drop_cell()
	state = State.TUMBLE
	_timer = 0.0
	_hit_flash = 1.0
	_tumble_dir = pull.normalized() if pull.length() > 0.001 else -global_basis.z
	set_expression("Surprised")


func _shutdown() -> void:
	_drop_cell()
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.release()
	state = State.DOWN
	_timer = 0.0
	_hit_flash = 1.0
	set_expression("")
	if _emitters.has("M_Amber_Emitter"):
		(_emitters["M_Amber_Emitter"] as StandardMaterial3D).albedo_color = Color(0.12, 0.05, 0.02)
	if _emitters.has("M_Cyan_Emitter"):
		(_emitters["M_Cyan_Emitter"] as StandardMaterial3D).albedo_color = Neon.CYAN_DIM
	defeated.emit(self)


func _drop_cell() -> void:
	if cell == null:
		return
	var dropped := cell
	cell = null
	cell_dropped.emit(self, dropped)


func _escape() -> void:
	var had_cell := cell != null
	if cell:
		cell.call("mark_lost")
		cell = null
	state = State.GONE
	escaped.emit(self, had_cell)
	queue_free()


# --- procedural animation ----------------------------------------------------

func _animate(delta: float, _emerging: bool) -> void:
	var flat := Vector3(velocity.x, 0, velocity.z)
	var ground_speed := flat.length()
	var accel_vec := (velocity - _prev_velocity) / maxf(delta, 1e-4)
	_prev_velocity = velocity
	var local_accel := global_basis.inverse() * accel_vec
	# Body lean: pitch forward under acceleration, roll into turns.
	var target_lean := Vector2(clampf(-local_accel.z * 0.12, -0.25, 0.25), clampf(local_accel.x * 0.1, -0.2, 0.2))
	_lean = _lean.lerp(target_lean, minf(1.0, delta * 6.0))
	var body_rot := _body_rest + Vector3(_lean.x, 0.0, _lean.y)
	var body_offset := Vector3.ZERO
	match gait:
		"biped":
			var stride := _leg_length * 1.5
			_phase += ground_speed * delta / maxf(stride, 0.05) * TAU
			var amp := clampf(ground_speed / maxf(speed, 0.1), 0.0, 1.0)
			_biped_legs(amp)
			body_offset.y = absf(sin(_phase)) * 0.018 * amp
			body_rot.z += sin(_phase) * 0.03 * amp
			_arms(sin(_phase) * 0.45 * amp)
		"wheels":
			var radius := 0.06
			_wheel_spin -= ground_speed * delta / radius
			for side in ["L", "R"]:
				_set_joint("RIG_Wheel_" + side, Vector3(_wheel_spin, 0, 0))
				_set_joint("RIG_Knee_" + side, Vector3(sin(_timer * 11.0 + (0.0 if side == "L" else 1.7)) * 0.03 * clampf(ground_speed, 0.0, 1.0), 0, 0))
			body_rot.x += clampf(ground_speed * 0.12, 0.0, 0.14)
			_arms(sin(_timer * 7.0) * 0.12 * clampf(ground_speed, 0.0, 1.0))
		"flyer":
			var spin := _timer * 38.0
			for name in ["RIG_Rotor_L_0", "RIG_Rotor_L_1", "RIG_Rotor_R_0", "RIG_Rotor_R_1"]:
				_set_joint(name, Vector3(0, spin, 0))
			body_rot.x += _lean.x * 1.5
			body_offset.y = sin(_timer * 2.3) * 0.02
			for side in ["L", "R"]:
				_set_joint("RIG_Arm_%s_Elbow" % side, Vector3(-0.35 + sin(_timer * 1.7) * 0.12, 0, 0))
				_set_joint("RIG_Leg_%s_Elbow" % side, Vector3(-0.3 + cos(_timer * 1.9) * 0.12, 0, 0))
	if state == State.TUMBLE:
		var k := clampf(_timer / 0.3, 0.0, 1.0) * clampf((TUMBLE_SECONDS - _timer) / 0.5, 0.0, 1.0)
		var local_dir := global_basis.inverse() * _tumble_dir
		body_rot += Vector3(local_dir.z * 1.25 * k, 0.0, -local_dir.x * 1.25 * k)
		body_offset.y -= 0.12 * k
	elif state == State.DOWN:
		var k := clampf(_timer / 0.5, 0.0, 1.0)
		body_rot += Vector3(0.0, 0.0, 1.4 * k)
		body_offset.y -= 0.16 * k
	_body.rotation = body_rot
	_body.position.y = _body_rest_y() + body_offset.y
	_head_tracking(delta)
	# Lights.
	var glow := Neon.AMBER if tethers.is_empty() else TetherMath.rope_color(_tension)
	if state != State.DOWN:
		Neon.set_halo_color(_halo, glow, clampf(_hit_flash * 0.7 + _tension * 0.35, 0.0, 1.0))
		if _emitters.has("M_Amber_Emitter"):
			(_emitters["M_Amber_Emitter"] as StandardMaterial3D).albedo_color = Neon.AMBER.lerp(glow, 0.6 if not tethers.is_empty() else 0.0)
	if cell:
		cell.global_transform = carry_point.global_transform
		cell.global_rotation = Vector3(0, rotation.y, 0)


var _body_rest_y_cache: float = NAN
func _body_rest_y() -> float:
	if is_nan(_body_rest_y_cache):
		_body_rest_y_cache = _body.position.y
	return _body_rest_y_cache


func _biped_legs(amp: float) -> void:
	for side in ["L", "R"]:
		var phase := _phase + (0.0 if side == "L" else PI)
		var hip := -sin(phase) * 0.55 * amp
		var knee := maxf(0.0, sin(phase - 0.9)) * 0.9 * amp
		var ankle := -(hip + knee) * 0.55
		_set_joint("RIG_Hip_" + side, Vector3(hip, 0, 0))
		_set_joint("RIG_Knee_" + side, Vector3(knee, 0, 0))
		_set_joint("RIG_Ankle_" + side, Vector3(ankle, 0, 0))


func _arms(swing: float) -> void:
	_set_joint("RIG_Shoulder_L", Vector3(swing, 0, 0))
	_set_joint("RIG_Shoulder_R", Vector3(-swing, 0, 0))
	_set_joint("RIG_Elbow_L", Vector3(-0.25 - absf(swing) * 0.3, 0, 0))
	_set_joint("RIG_Elbow_R", Vector3(-0.25 - absf(swing) * 0.3, 0, 0))


func _head_tracking(delta: float) -> void:
	var head_joint: Node3D = _joints.get("RIG_Head", null)
	if head_joint == null or player_head == null:
		return
	var local := _body.global_basis.inverse() * (player_head.global_position - head_joint.global_position)
	var yaw := clampf(atan2(local.x, local.z), -1.0, 1.0)
	var pitch := clampf(-atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.4)
	var rest: Vector3 = _rest.get("RIG_Head", Vector3.ZERO)
	head_joint.rotation = head_joint.rotation.lerp(rest + Vector3(pitch, yaw, 0), minf(1.0, delta * 5.0))


func _set_joint(name: String, offset: Vector3) -> void:
	var joint: Node3D = _joints.get(name, null)
	if joint:
		joint.rotation = (_rest[name] as Vector3) + offset


func set_expression(name: String) -> void:
	if _expression == name:
		return
	_expression = name
	for eye in eyes:
		for i in range(eye.mesh.get_blend_shape_count()):
			var shape := String(eye.mesh.get_blend_shape_name(i))
			eye.set_blend_shape_value(i, 1.0 if shape == name else 0.0)
