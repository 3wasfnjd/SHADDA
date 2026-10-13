class_name PowerCell
extends RigidBody3D
## One removable SHADDA power cell. Docked it charges; carried by a raider it
## drains; dropped it is a real rigid body on the real floor that the player
## can grab by hand or rope and reel in; carried through a rift it is lost.

enum State { DOCKED, CARRIED, HELD, LOOSE, LOST }

signal state_changed(cell: PowerCell)

const DRAIN_PER_SECOND := 0.03
const CHARGE_PER_SECOND := 0.08

var state: int = State.DOCKED
var socket_index: int = -1
var charge: float = 1.0
var holder_hand: int = -1
var world: Node3D = null
var model: Node3D
var grab_point: Node3D
var tethers: Array = []
var _levels: Array[MeshInstance3D] = []
var _helix: Array[MeshInstance3D] = []
var _emitters: Dictionary = {}
var _halo: MeshInstance3D
var _time: float = 0.0
var _shown_levels: int = -1


static func create(scene: PackedScene) -> PowerCell:
	var cell := PowerCell.new()
	cell.model = scene.instantiate() as Node3D
	return cell


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 0.35
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	can_sleep = true
	linear_damp = 0.4
	angular_damp = 1.5
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.15
	physics_material_override.friction = 0.9
	add_child(model)
	_emitters = Neon.restyle(model)
	var bounds := Neon.merged_aabb(model)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(bounds.size.x, bounds.size.z) * 0.5
	cylinder.height = bounds.size.y
	shape.shape = cylinder
	shape.position = bounds.get_center()
	add_child(shape)
	grab_point = model.find_child("GrabPoint", true, false) as Node3D
	for i in range(1, 5):
		var level := model.find_child("CORE_Level_0%d" % i, true, false) as MeshInstance3D
		if level:
			_levels.append(level)
	for node in model.find_children("CORE_Helix_*", "MeshInstance3D", true, false):
		_helix.append(node as MeshInstance3D)
	_halo = Neon.make_halo(Neon.CYAN, 0.3, 0.0)
	_halo.position = bounds.get_center()
	add_child(_halo)
	_apply_visuals(true)


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.DOCKED:
			charge = minf(1.0, charge + CHARGE_PER_SECOND * delta)
		State.CARRIED:
			charge = maxf(0.0, charge - DRAIN_PER_SECOND * delta)
	_apply_visuals(false)


func _physics_process(delta: float) -> void:
	if state != State.LOOSE:
		return
	# Rope pull: reel the cell toward the hand.
	for t in tethers:
		if is_instance_valid(t):
			var pull := TetherMath.pull_velocity(t.hand_position(), tether_anchor().global_position, t.rest_length, mass * 2.0, delta)
			if pull != Vector3.ZERO:
				apply_central_impulse(pull * mass * 3.0)
	# Fell too far (through a missing floor): put it back on the arena floor.
	if position.y < -1.5:
		position.y = 0.3
		linear_velocity = Vector3.ZERO


func _apply_visuals(force: bool) -> void:
	var levels := int(ceil(charge * 4.0 - 0.001))
	var color := Neon.CYAN
	if levels <= 0:
		color = Neon.RED
	elif levels == 1:
		color = Neon.AMBER
	if force or levels != _shown_levels:
		_shown_levels = levels
		for i in range(_levels.size()):
			_levels[i].visible = i < levels
		for h in _helix:
			h.visible = levels > 0
		if _emitters.has("M_Cyan_Emitter"):
			(_emitters["M_Cyan_Emitter"] as StandardMaterial3D).albedo_color = color
	var pulse := 0.5 + 0.5 * sin(_time * (5.0 if state == State.LOOSE else 1.8))
	var halo_alpha := 0.0
	if state == State.LOOSE:
		halo_alpha = 0.3 + 0.3 * pulse
	elif state == State.HELD or not tethers.is_empty():
		halo_alpha = 0.25
	Neon.set_halo_color(_halo, color, halo_alpha)


func _set_state(new_state: int) -> void:
	state = new_state
	freeze = new_state != State.LOOSE
	if freeze:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	state_changed.emit(self)


func set_docked(index: int) -> void:
	socket_index = index
	holder_hand = -1
	visible = true
	_release_tethers()
	_set_state(State.DOCKED)


func set_carried() -> void:
	socket_index = -1
	holder_hand = -1
	_release_tethers()
	_set_state(State.CARRIED)


func set_held(hand: int) -> void:
	socket_index = -1
	holder_hand = hand
	_release_tethers()
	_set_state(State.HELD)


func _reparent_to_world() -> void:
	if world == null or get_parent() == world:
		return
	var keep := global_transform
	get_parent().remove_child(self)
	world.add_child(self)
	global_transform = keep


func drop_at(point: Vector3, toss: Vector3 = Vector3.ZERO) -> void:
	_reparent_to_world()
	socket_index = -1
	holder_hand = -1
	global_position = point
	position.y = maxf(position.y, 0.12)
	_set_state(State.LOOSE)
	linear_velocity = toss
	angular_velocity = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))


func mark_lost() -> void:
	_reparent_to_world()
	socket_index = -1
	holder_hand = -1
	visible = false
	_release_tethers()
	_set_state(State.LOST)


func is_available_for_grab() -> bool:
	return state == State.LOOSE


func grab_position() -> Vector3:
	return grab_point.global_position if grab_point else global_position + Vector3(0, 0.09, 0)


# --- tether interface (the rope can fish a loose cell back) -----------------

func tether_anchor() -> Node3D:
	return grab_point if grab_point else self


func can_be_tethered() -> bool:
	return state == State.LOOSE


func attach_tether(t: Node3D) -> void:
	if not tethers.has(t):
		tethers.append(t)
	sleeping = false


func detach_tether(t: Node3D) -> void:
	tethers.erase(t)


func on_tether_snapped() -> void:
	pass


func _release_tethers() -> void:
	for t in tethers.duplicate():
		if is_instance_valid(t):
			t.release()
	tethers.clear()
