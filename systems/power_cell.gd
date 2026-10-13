class_name PowerCell
extends Node3D
## One removable SHADDA power cell. Docked in the station it charges; carried
## by a raider it drains; dropped it falls to the floor and waits for the
## player's gauntlet; carried through a rift it is lost for the match.

enum State { DOCKED, CARRIED, HELD, LOOSE, LOST }

signal state_changed(cell: PowerCell)

const DRAIN_PER_SECOND := 0.035
const CHARGE_PER_SECOND := 0.08

var state: int = State.DOCKED
var socket_index: int = -1
var charge: float = 1.0
var holder_hand: int = -1
var world: Node3D = null
var model: Node3D
var grab_point: Node3D
var _levels: Array[MeshInstance3D] = []
var _helix: Array[MeshInstance3D] = []
var _symbol: MeshInstance3D
var _emitters: Dictionary = {}
var _halo: MeshInstance3D
var _ring: MeshInstance3D
var _fall_velocity: float = 0.0
var _bob: float = 0.0
var _shown_levels: int = -1


static func create(scene: PackedScene) -> PowerCell:
	var cell := PowerCell.new()
	cell.model = scene.instantiate() as Node3D
	return cell


func _ready() -> void:
	add_child(model)
	_emitters = Neon.restyle(model)
	grab_point = model.find_child("GrabPoint", true, false) as Node3D
	for i in range(1, 5):
		var level := model.find_child("CORE_Level_0%d" % i, true, false) as MeshInstance3D
		if level:
			_levels.append(level)
	for node in model.find_children("CORE_Helix_*", "MeshInstance3D", true, false):
		_helix.append(node as MeshInstance3D)
	_symbol = model.find_child("CORE_EnergySymbol", true, false) as MeshInstance3D
	_halo = Neon.make_halo(Neon.CYAN, 0.34, 0.35)
	_halo.position = Vector3(0, 0.09, 0)
	add_child(_halo)
	_ring = Neon.make_floor_ring(Neon.CYAN, 0.26, 0.0)
	_ring.position.y = 0.006
	add_child(_ring)
	_apply_visuals(true)


func _process(delta: float) -> void:
	_bob += delta
	match state:
		State.DOCKED:
			charge = minf(1.0, charge + CHARGE_PER_SECOND * delta)
		State.CARRIED:
			charge = maxf(0.0, charge - DRAIN_PER_SECOND * delta)
		State.LOOSE:
			_fall_velocity -= 9.8 * delta
			position.y += _fall_velocity * delta
			if position.y <= 0.0:
				position.y = 0.0
				_fall_velocity = -_fall_velocity * 0.25
				if absf(_fall_velocity) < 0.3:
					_fall_velocity = 0.0
			rotation = rotation.lerp(Vector3(0, rotation.y, 0), delta * 5.0)
		State.HELD:
			pass
	_apply_visuals(false)


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
		if _symbol:
			_symbol.visible = true
		if _emitters.has("M_Cyan_Emitter"):
			(_emitters["M_Cyan_Emitter"] as StandardMaterial3D).albedo_color = color
	var pulse := 0.5 + 0.5 * sin(_bob * (6.0 if state == State.LOOSE else 2.0))
	var halo_alpha := 0.25 + 0.2 * pulse
	if state == State.LOOSE:
		halo_alpha = 0.45 + 0.4 * pulse
	elif state == State.LOST:
		halo_alpha = 0.0
	Neon.set_halo_color(_halo, color, halo_alpha)
	Neon.set_halo_color(_ring, color, (0.4 + 0.4 * pulse) if state == State.LOOSE else 0.0)


func set_docked(index: int) -> void:
	state = State.DOCKED
	socket_index = index
	holder_hand = -1
	_fall_velocity = 0.0
	visible = true
	state_changed.emit(self)


func set_carried() -> void:
	state = State.CARRIED
	socket_index = -1
	holder_hand = -1
	state_changed.emit(self)


func set_held(hand: int) -> void:
	state = State.HELD
	socket_index = -1
	holder_hand = hand
	state_changed.emit(self)


func _reparent_to_world() -> void:
	if world == null or get_parent() == world:
		return
	var keep := global_transform
	get_parent().remove_child(self)
	world.add_child(self)
	global_transform = keep


func drop_at(point: Vector3) -> void:
	_reparent_to_world()
	state = State.LOOSE
	socket_index = -1
	holder_hand = -1
	global_position = point
	global_position.y = maxf(point.y, 0.05)
	_fall_velocity = 0.6
	state_changed.emit(self)


func mark_lost() -> void:
	_reparent_to_world()
	state = State.LOST
	socket_index = -1
	holder_hand = -1
	visible = false
	state_changed.emit(self)


func is_available_for_grab() -> bool:
	return state == State.LOOSE


func grab_position() -> Vector3:
	return grab_point.global_position if grab_point else global_position + Vector3(0, 0.12, 0)
