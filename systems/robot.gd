class_name Robot
extends CharacterBody3D
## A SHADDA raider. Emerges from a rift, walks (or flies) to the battery
## station, steals a power cell and runs back. Tethers pull it around; enough
## tension makes it drop the cell, and dragging it into the player's capture
## ring defeats it.

signal defeated(robot: Robot)
signal escaped(robot: Robot, with_cell: bool)
signal cell_taken(robot: Robot)
signal cell_dropped(robot: Robot, cell: Node3D)

enum State { EMERGE, SEEK, STEAL, FLEE, STUN, DEFEAT, GONE }

const CAPTURE_RADIUS := 0.75    # metres from the player's capture ring centre
const STUN_SECONDS := 2.2

var kind: String = "A"
var stats: Dictionary = {}
var state: int = State.EMERGE
var model: Node3D
var home_rift: Node3D
var station: Node3D
var cell: Node3D = null
var carry_point: Node3D
var crown: Node3D
var back_point: Node3D
var eyes: Array[MeshInstance3D] = []
var anim: AnimationPlayer
var tethers: Array = []
var hover: float = 0.0
var mass: float = 1.0
var speed: float = 0.7
var _timer: float = 0.0
var _bob: float = 0.0
var _hit_flash: float = 0.0
var _emitters: Dictionary = {}
var _halo: MeshInstance3D
var _ring: MeshInstance3D
var _expression: String = ""
var _capture_center_fn: Callable
var _stun_count: int = 0
var _current_tension: float = 0.0
var _stun_seconds: float = STUN_SECONDS


static func create(robot_kind: String, scene: PackedScene) -> Robot:
	var robot := Robot.new()
	robot.kind = robot_kind
	robot.stats = RoundPlan.robot_stats(robot_kind)
	robot.model = scene.instantiate() as Node3D
	return robot


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	mass = stats.get("mass", 1.0)
	speed = stats.get("speed", 0.7)
	hover = stats.get("hover", 0.0)
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
	back_point = model.find_child("TetherPoint_Back", true, false) as Node3D
	carry_point = _find_first(["GrabPoint_Backpack_R", "GrabPoint_R", "GrabPoint_Hand_R", "GrabPoint_Arm_R", "GrabPoint_L"])
	if crown == null:
		crown = Node3D.new()
		crown.position = Vector3(0, bounds.size.y, 0)
		model.add_child(crown)
	if carry_point == null:
		carry_point = crown
	for node in model.find_children("FACE_Eye_*", "MeshInstance3D", true, false):
		eyes.append(node as MeshInstance3D)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
		for clip in anim.get_animation_list():
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_halo = Neon.make_halo(Neon.AMBER, 0.55, 0.0)
	_halo.position = Vector3(0, bounds.size.y * 0.55, 0)
	add_child(_halo)
	_ring = Neon.make_floor_ring(Neon.AMBER, 0.6 + bounds.size.x * 0.4, 0.5)
	_ring.position.y = 0.012
	add_child(_ring)
	set_expression("Happy")
	scale = Vector3.ONE * 0.05
	_timer = 0.0


func _find_first(names: Array) -> Node3D:
	for n in names:
		var found := model.find_child(n, true, false)
		if found:
			return found as Node3D
	return null


func configure(rift: Node3D, target_station: Node3D, capture_center: Callable) -> void:
	home_rift = rift
	station = target_station
	_capture_center_fn = capture_center
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
	return state != State.DEFEAT and state != State.GONE and state != State.EMERGE


func attach_tether(t: Node3D) -> void:
	if not tethers.has(t):
		tethers.append(t)
	set_expression("Surprised")
	_hit_flash = 1.0


func detach_tether(t: Node3D) -> void:
	tethers.erase(t)
	if tethers.is_empty() and state != State.STUN:
		set_expression("Happy" if cell else "Angry")


# --- behaviour ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_timer += delta
	_bob += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.5)
	var pulled := Vector3.ZERO
	var max_tension := 0.0
	for t in tethers:
		if not is_instance_valid(t):
			continue
		pulled += TetherMath.pull_velocity(t.hand_position(), crown.global_position, t.rest_length, mass, delta)
		max_tension = maxf(max_tension, t.tension)
	_current_tension = max_tension
	match state:
		State.EMERGE:
			var t := clampf(_timer / 1.1, 0.0, 1.0)
			scale = Vector3.ONE * maxf(0.05, t)
			var exit: Vector3 = home_rift.spawn_outside()
			exit.y = global_position.y - position.y + hover
			global_position = global_position.lerp(exit, delta * 2.4)
			Neon.set_halo_color(_halo, Neon.CYAN, (1.0 - t) * 0.9)
			if t >= 1.0:
				scale = Vector3.ONE
				state = State.SEEK
				set_expression("Angry")
		State.SEEK:
			var goal: Vector3 = station.approach_point(global_position)
			_steer(goal, delta, 1.0)
			if _flat_distance(goal) < 0.12:
				state = State.STEAL
				_timer = 0.0
				set_expression("Happy")
		State.STEAL:
			_steer(global_position, delta, 0.0)
			look_toward(station.global_position)
			var steal_time: float = stats.get("steal_time", 1.5)
			if _timer >= steal_time * (1.0 + max_tension):
				var taken: Node3D = station.take_cell(self)
				if taken:
					cell = taken
					cell_taken.emit(self)
					state = State.FLEE
					_timer = 0.0
				else:
					state = State.FLEE
		State.FLEE:
			var exit: Vector3 = home_rift.spawn_outside()
			_steer(exit, delta, 1.15)
			if _flat_distance(exit) < 0.18 and max_tension < 0.3:
				_escape()
				return
		State.STUN:
			_steer(global_position, delta, 0.0)
			var wobble := sin(_timer * 30.0) * 0.08 * maxf(0.0, 1.0 - _timer / _stun_seconds)
			rotation.z = wobble
			if _timer >= _stun_seconds:
				rotation.z = 0.0
				state = State.FLEE if cell else State.SEEK
				set_expression("Angry")
		State.DEFEAT:
			var t := clampf(_timer / 0.6, 0.0, 1.0)
			scale = Vector3.ONE * maxf(0.02, 1.0 - t)
			rotation.y += delta * 14.0
			Neon.set_halo_color(_halo, Neon.CYAN, 1.0 - t)
			if t >= 1.0:
				state = State.GONE
				queue_free()
			return
		State.GONE:
			return
	# Rope pull.
	if pulled != Vector3.ZERO:
		if hover <= 0.0:
			pulled.y = 0.0
		velocity += pulled
	if max_tension >= TetherMath.STUN_TENSION and cell and state != State.STUN:
		_drop_cell()
		_stun(STUN_SECONDS)
	move_and_slide()
	# Keep ground robots on the arena floor (parent-local y = 0), flyers at their altitude.
	if hover <= 0.0:
		position.y = 0.0
	else:
		position.y = lerpf(position.y, hover + sin(_bob * 2.1) * 0.06, delta * 3.0)
	# Capture check: dragged into the player's ring.
	if state != State.DEFEAT and _capture_center_fn.is_valid() and not tethers.is_empty():
		var center: Vector3 = _capture_center_fn.call()
		if Vector3(global_position.x, 0, global_position.z).distance_to(Vector3(center.x, 0, center.z)) < CAPTURE_RADIUS:
			_defeat()
			return
	_animate(delta, max_tension)


func _steer(goal: Vector3, delta: float, factor: float) -> void:
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var desired := Vector3.ZERO
	if factor > 0.0 and to_goal.length() > 0.02:
		desired = to_goal.normalized() * speed * factor * (1.0 - _current_tension * 0.9)
		# Flyers climb over, walkers skirt around the player.
		if hover <= 0.0 and _capture_center_fn.is_valid():
			var center: Vector3 = _capture_center_fn.call()
			var away := global_position - center
			away.y = 0.0
			var d := away.length()
			if d < 1.0 and d > 0.001:
				desired += away.normalized() * (1.0 - d) * speed * 1.4
	velocity.x = lerpf(velocity.x, desired.x, delta * 6.0)
	velocity.z = lerpf(velocity.z, desired.z, delta * 6.0)
	velocity.y = 0.0
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.08:
		var target_yaw := atan2(flat.x, flat.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 7.0)


func _flat_distance(point: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(point.x, point.z))


func _animate(delta: float, max_tension: float) -> void:
	var moving := Vector3(velocity.x, 0, velocity.z).length() > 0.05
	if anim:
		if moving and not anim.is_playing():
			anim.play(anim.get_animation_list()[0], 0.2, 1.4)
		elif not moving and anim.is_playing() and state != State.STEAL:
			anim.pause()
	if moving and hover <= 0.0:
		model.position.y = absf(sin(_bob * 9.0)) * 0.012
		model.rotation.z = sin(_bob * 9.0) * 0.03
	# Neon state: amber idle, cyan when roped, white-hot near snapping.
	var glow := Neon.AMBER if tethers.is_empty() else TetherMath.rope_color(max_tension)
	if cell:
		glow = glow.lerp(Neon.RED, 0.35)
	var ring_alpha := 0.35 + 0.25 * sin(_bob * 4.0) + _hit_flash * 0.5
	Neon.set_halo_color(_ring, glow, clampf(ring_alpha, 0.0, 1.0))
	Neon.set_halo_color(_halo, glow, clampf(_hit_flash * 0.8 + max_tension * 0.4, 0.0, 1.0))
	if _emitters.has("M_Amber_Emitter"):
		(_emitters["M_Amber_Emitter"] as StandardMaterial3D).albedo_color = Neon.AMBER.lerp(glow, 0.6 if not tethers.is_empty() else 0.0)
	if cell:
		cell.global_transform = carry_point.global_transform
		cell.global_rotation = Vector3(0, rotation.y, 0)


func _drop_cell() -> void:
	if cell == null:
		return
	var dropped := cell
	cell = null
	cell_dropped.emit(self, dropped)


## Called by a tether when it snaps: the raider staggers for a moment.
func on_tether_snapped() -> void:
	if state == State.SEEK or state == State.FLEE:
		_stun(0.6)


func _stun(seconds: float) -> void:
	state = State.STUN
	_stun_seconds = seconds
	_timer = 0.0
	_stun_count += 1
	_hit_flash = 1.0
	set_expression("Surprised")
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.snap()


func _defeat() -> void:
	_drop_cell()
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.release()
	state = State.DEFEAT
	_timer = 0.0
	set_expression("Surprised")
	defeated.emit(self)


func _escape() -> void:
	var had_cell := cell != null
	if cell:
		cell.call("mark_lost")
		cell = null
	state = State.GONE
	escaped.emit(self, had_cell)
	queue_free()


func set_expression(name: String) -> void:
	if _expression == name:
		return
	_expression = name
	for eye in eyes:
		for i in range(eye.mesh.get_blend_shape_count()):
			var shape := String(eye.mesh.get_blend_shape_name(i))
			eye.set_blend_shape_value(i, 1.0 if shape == name else 0.0)
