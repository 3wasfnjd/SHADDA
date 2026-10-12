class_name ShaddaBattery
extends RigidBody3D

var identity: int = 0
var state := ShaddaBatteryState.new()
var arena: Node3D
var cfg: Dictionary
var magnet_slot: int = -1
var stolen_before: bool = false
var rescued_counted: bool = false
var contested_time: float = 0.0
var dock_cooldown: float = 0.0
var visual: Node3D
var grab_point: Node3D

func setup(id: int, game: Node3D, settings: Dictionary) -> void:
	identity = id
	arena = game
	cfg = settings
	mass = float(cfg["battery_mass"])
	continuous_cd = true
	linear_damp = 0.6
	angular_damp = 2.5
	collision_layer = 4
	collision_mask = 15
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.height = 0.18
	cylinder.radius = 0.034
	shape.shape = cylinder
	add_child(shape)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.7
	physics_material_override.bounce = 0.06
	visual = load("res://assets/models/runtime/shadda_power_cell.glb").instantiate()
	visual.position.y = -0.09
	add_child(visual)
	grab_point = visual.find_child("GrabPoint", true, false)
	assert(grab_point != null, "The original cell GrabPoint is required")

func reset_at(slot: int, pose: Transform3D) -> void:
	freeze = true
	global_transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	state.reset(slot)
	magnet_slot = -1
	stolen_before = false
	rescued_counted = false
	show()
	collision_layer = 4

func grab(hand: int) -> bool:
	if state.state == ShaddaBatteryState.State.ROBOT:
		return true # The player's spring must overcome the robot gripper first.
	if not state.transition(ShaddaBatteryState.State.PLAYER, hand):
		return false
	magnet_slot = -1
	freeze = false
	dock_cooldown = 0.8
	sleeping = false
	return true

func drop() -> void:
	if state.state == ShaddaBatteryState.State.PLAYER:
		state.transition(ShaddaBatteryState.State.GROUND)
	freeze = false

func stolen() -> bool:
	if not state.transition(ShaddaBatteryState.State.ROBOT, 0):
		return false
	stolen_before = true
	add_collision_exception_with(arena.enemy)
	rescued_counted = false
	magnet_slot = -1
	freeze = false
	sleeping = false
	return true

func lost() -> bool:
	if not state.transition(ShaddaBatteryState.State.LOST):
		return false
	freeze = true
	collision_layer = 0
	hide()
	return true

func _integrate_forces(body_state: PhysicsDirectBodyState3D) -> void:
	body_state.linear_velocity = body_state.linear_velocity.limit_length(float(cfg.get("battery_max_speed", 3.0)))
	body_state.angular_velocity = body_state.angular_velocity.limit_length(8.0)

func _physics_process(delta: float) -> void:
	dock_cooldown = maxf(0.0, dock_cooldown - delta)
	if arena == null or freeze:
		return
	arena.contain(self)
	if state.state == ShaddaBatteryState.State.ROBOT:
		return
	if get_collision_exceptions().has(arena.enemy):
		remove_collision_exception_with(arena.enemy)
	# A held cell must be allowed to leave its socket. Docking starts only
	# after release or an explicit hand-off to the station return tether.
	if dock_cooldown > 0.0 or state.state == ShaddaBatteryState.State.PLAYER:
		return
	if magnet_slot < 0:
		for i in range(3):
			if arena.slot_available(i, self) and global_position.distance_to(arena.dock_pose(i).origin) < float(cfg["dock_capture_radius"]) and linear_velocity.length() < 1.2:
				magnet_slot = i
				arena.detach_body(self, false)
				break
	if magnet_slot < 0:
		return
	if not arena.slot_available(magnet_slot, self):
		magnet_slot = -1
		return
	var pose: Transform3D = arena.dock_pose(magnet_slot)
	var error := pose.origin - global_position
	if error.length() > 0.18:
		magnet_slot = -1
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, pose.origin, 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		magnet_slot = -1
		return
	apply_central_force((error * 45.0 - linear_velocity * 6.0 + Vector3.UP * mass * 9.81).limit_length(12.0))
	apply_torque(global_basis.y.cross(pose.basis.y) * 0.8 - angular_velocity * 0.1)
	if error.length() < 0.014 and linear_velocity.length() < 0.25:
		if state.transition(ShaddaBatteryState.State.DOCKED, -1, magnet_slot):
			freeze = true
			global_transform = pose
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			magnet_slot = -1
			arena.battery_docked(self)
