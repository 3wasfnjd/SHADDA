class_name ShaddaThief
extends RigidBody3D

enum Mode { APPROACH, WARNING, ESCAPE, RESIST, RECOVER, DISABLED }
var mode: Mode = Mode.APPROACH
var arena: Node3D
var cfg: Dictionary
var visual: Node3D
var hand: Node3D
var wheels: Array[Node3D] = []
var carried: ShaddaBattery
var target: ShaddaBattery
var warning: float = 0.0
var rethink: float = 0.0
var cooldown: float = 3.0
var recovery: float = 0.0
var steal_count: int = 0
var status_label: Label3D

func setup(game: Node3D, settings: Dictionary) -> void:
	arena = game
	cfg = settings
	mass = float(cfg["enemy_mass"])
	collision_layer = 2
	collision_mask = 15
	continuous_cd = true
	linear_damp = 1.0
	angular_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 4
	physics_material_override = PhysicsMaterial.new()
	# The single collider represents wheels: use rolling resistance, not boot friction.
	physics_material_override.friction = 0.04
	physics_material_override.bounce = 0.04
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = float(cfg["enemy_height"])
	capsule.radius = 0.21
	collision.shape = capsule
	add_child(collision)
	visual = load("res://assets/models/runtime/shadda_robot_B.glb").instantiate()
	visual.position.y = -float(cfg["enemy_height"]) * 0.5
	add_child(visual)
	hand = visual.find_child("GrabPoint_Hand_R", true, false)
	assert(hand != null, "Robot B must retain its original grab point")
	for side in ["L", "R"]:
		var wheel := visual.find_child("RIG_Wheel_" + side, true, false) as Node3D
		if wheel != null:
			wheels.append(wheel)
	status_label = ShaddaVisuals.label("", 26)
	status_label.position.y = 0.56
	add_child(status_label)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(float(cfg.get("enemy_max_speed", 2.2)))
	state.angular_velocity = state.angular_velocity.limit_length(4.0)

func reset_at(p: Vector3) -> void:
	freeze = true
	global_transform = Transform3D(Basis.IDENTITY, p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	carried = null
	target = null
	mode = Mode.APPROACH
	cooldown = 3.0
	warning = 0.0
	freeze = false
	show()

func _physics_process(delta: float) -> void:
	if arena == null or mode == Mode.DISABLED or arena.finished:
		return
	cooldown = maxf(0.0, cooldown - delta)
	arena.contain(self)
	var up_error := global_basis.y.cross(Vector3.UP)
	apply_torque((up_error * 16.0 - Vector3(angular_velocity.x, 0, angular_velocity.z) * 4.0).limit_length(18.0))
	var rolling := linear_velocity.dot(global_basis.z) / 0.083
	for wheel in wheels:
		wheel.rotate_x(rolling * delta)
	if is_instance_valid(carried) and carried.state.state != ShaddaBatteryState.State.ROBOT:
		carried = null
		mode = Mode.RECOVER
		cooldown = 2.5
	if is_instance_valid(carried):
		var point := carried.grab_point.global_position
		var error := hand.global_position - point
		if error.length() > 0.65:
			carried.state.transition(ShaddaBatteryState.State.GROUND)
			carried = null
			cooldown = 2.0
		else:
			var force := (error * 48.0 - (carried.linear_velocity - linear_velocity) * 4.0 + Vector3.UP * carried.mass * 9.81).limit_length(12.0)
			carried.apply_force(force, point - carried.global_position)
	if arena.body_tethered(self) or global_basis.y.dot(Vector3.UP) < 0.65:
		mode = Mode.RESIST
		status_label.text = "مقيّد"
		cooldown = maxf(cooldown, 1.5)
		return
	if cooldown > 0.0:
		status_label.text = ""
		return
	var goal := global_position
	if is_instance_valid(carried):
		mode = Mode.ESCAPE
		status_label.text = "يهرب بالبطارية!"
		goal = arena.escape_point.global_position
		var flat := goal - global_position
		flat.y = 0.0
		if flat.length() < 0.2:
			if carried.lost():
				arena.sound("alert", global_position)
			carried = null
			target = null
			cooldown = 3.0
			return
	else:
		rethink -= delta
		if rethink <= 0.0 or not is_instance_valid(target) or target.state.state not in [ShaddaBatteryState.State.DOCKED, ShaddaBatteryState.State.GROUND]:
			target = arena.choose_battery(global_position)
			rethink = 0.35
		if not is_instance_valid(target):
			status_label.text = "يبحث"
			return
		goal = target.global_position
		var reach := hand.global_position.distance_to(target.grab_point.global_position)
		var query := PhysicsRayQueryParameters3D.create(hand.global_position, target.global_position, 1, [get_rid()])
		if reach < 0.43 and get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			if mode != Mode.WARNING:
				warning = float(cfg["steal_warning_seconds"])
				arena.sound("alert", global_position)
			mode = Mode.WARNING
			status_label.text = "يحاول السرقة!"
			warning -= delta
			if warning <= 0.0 and target.stolen():
				carried = target
				steal_count += 1
				mode = Mode.ESCAPE
			return
		mode = Mode.APPROACH
		status_label.text = ""
	var waypoint: Vector3 = arena.next_waypoint(global_position, goal)
	var direction := waypoint - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		return
	direction = direction.normalized()
	var desired := direction * float(cfg["enemy_speed"])
	var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	apply_central_force(((desired - velocity) * mass * 12.0).limit_length(mass * float(cfg["enemy_acceleration"])))
	var yaw_error := atan2(global_basis.z.cross(direction).y, global_basis.z.dot(direction))
	apply_torque(Vector3.UP * clampf(yaw_error * 7.0 - angular_velocity.y * 2.0, -8.0, 8.0))
