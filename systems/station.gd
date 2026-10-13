class_name Station
extends Node3D
## The three-socket battery station. Before the match it hovers where the
## player looks (placement preview); A drops it onto the real floor. Owns the
## cells' docking, the 7-segment counter, slot lights and the alarm glow.

signal cells_changed(docked: int)

const SEGMENTS := {
	0: ["a", "b", "c", "d", "e", "f"],
	1: ["b", "c"],
	2: ["a", "b", "g", "e", "d"],
	3: ["a", "b", "g", "c", "d"],
}

var model: Node3D
var sockets: Array[Node3D] = []
var cells: Array[PowerCell] = []
var placing: bool = true
var powered: bool = true
var _segments: Dictionary = {}
var _slot_levels: Array[MeshInstance3D] = []
var _emitters: Dictionary = {}
var _halo: MeshInstance3D
var _alarm: float = 0.0
var _time: float = 0.0
var _drop: float = 0.0
var _body: StaticBody3D


static func create(scene: PackedScene) -> Station:
	var station := Station.new()
	station.model = scene.instantiate() as Node3D
	return station


func _ready() -> void:
	add_child(model)
	_emitters = Neon.restyle(model)
	Neon.rest_on_floor(model)
	for i in range(1, 4):
		var socket := model.find_child("BatterySocket_0%d" % i, true, false) as Node3D
		if socket:
			sockets.append(socket)
		var level := model.find_child("DISPLAY_Slot_0%d_Level" % i, true, false) as MeshInstance3D
		if level:
			_slot_levels.append(level)
	for seg in ["a", "b", "c", "d", "e", "f", "g"]:
		var mi := model.find_child("DISPLAY_Count_seg_" + seg, true, false) as MeshInstance3D
		if mi:
			_segments[seg] = mi
	var bounds := Neon.merged_aabb(model)
	_halo = Neon.make_halo(Neon.CYAN, 0.8, 0.0)
	_halo.position = Vector3(0, bounds.size.y * 0.5, 0)
	add_child(_halo)
	add_child(Neon.make_contact_shadow(maxf(bounds.size.x, bounds.size.z) * 1.25, 0.45))
	# Solid body so dropped cells and raiders bump into it.
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	shape.position = Vector3(0, bounds.size.y * 0.5, 0)
	_body.add_child(shape)
	add_child(_body)


func install_cells(cell_scene: PackedScene, world: Node3D) -> void:
	for i in range(sockets.size()):
		var cell := PowerCell.create(cell_scene)
		cell.world = world
		add_child(cell)
		cells.append(cell)
		dock(cell, i)
	_refresh_display()


func dock(cell: PowerCell, index: int) -> void:
	if cell.get_parent() != self:
		cell.get_parent().remove_child(cell)
		add_child(cell)
	cell.global_transform = sockets[index].global_transform
	cell.set_docked(index)
	_refresh_display()
	cells_changed.emit(docked_count())


func socket_free(index: int) -> bool:
	for cell in cells:
		if cell.state == PowerCell.State.DOCKED and cell.socket_index == index:
			return false
	return true


func nearest_free_socket(point: Vector3, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance
	for i in range(sockets.size()):
		if not socket_free(i):
			continue
		var d := sockets[i].global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


func docked_count() -> int:
	var n := 0
	for cell in cells:
		if cell.state == PowerCell.State.DOCKED:
			n += 1
	return n


func lost_count() -> int:
	var n := 0
	for cell in cells:
		if cell.state == PowerCell.State.LOST:
			n += 1
	return n


## A raider asks for a cell. Returns the cell (reparented to the robot) or null.
func take_cell(robot: Node3D) -> PowerCell:
	var pick: PowerCell = null
	for cell in cells:
		if cell.state == PowerCell.State.DOCKED:
			pick = cell
			break
	if pick == null:
		return null
	remove_child(pick)
	robot.add_child(pick)
	pick.set_carried()
	_alarm = 1.0
	_refresh_display()
	cells_changed.emit(docked_count())
	return pick


## Where a ground raider should stand to reach the sockets.
func approach_point(from: Vector3) -> Vector3:
	var to := from - global_position
	to.y = 0.0
	if to.length() < 0.01:
		to = Vector3.FORWARD
	return global_position + to.normalized() * 0.42


func begin_placement() -> void:
	placing = true
	_body.collision_layer = 0


## Lands the station where it currently hovers.
func place() -> void:
	placing = false
	_drop = 1.0
	_body.collision_layer = 1
	if get_parent() and get_parent().has_method("cue"):
		get_parent().call("cue", "thud", global_position)


func set_powered(on: bool) -> void:
	powered = on


func _refresh_display() -> void:
	var count := docked_count()
	var lit: Array = SEGMENTS.get(count, SEGMENTS[0])
	for seg in _segments.keys():
		(_segments[seg] as MeshInstance3D).visible = lit.has(seg)
	for i in range(_slot_levels.size()):
		_slot_levels[i].visible = not socket_free(i)


func _process(delta: float) -> void:
	_time += delta
	_alarm = maxf(0.0, _alarm - delta * 0.35)
	_drop = maxf(0.0, _drop - delta * 4.0)
	# Placement hover and landing thud.
	if placing:
		model.position.y = 0.05 + sin(_time * 3.0) * 0.015
	else:
		model.position.y = _drop * _drop * 0.08
	var count := docked_count()
	var base := Neon.CYAN if count > 1 else (Neon.AMBER if count == 1 else Neon.RED)
	if not powered:
		base = Neon.CYAN_DIM
	var color := base.lerp(Neon.AMBER, _alarm)
	var pulse := 0.5 + 0.5 * sin(_time * (2.0 + _alarm * 10.0 + (4.0 if placing else 0.0)))
	Neon.set_halo_color(_halo, color, (0.05 + 0.05 * pulse + _alarm * 0.25) if powered else 0.0)
	if _emitters.has("M_Cyan_Emitter"):
		(_emitters["M_Cyan_Emitter"] as StandardMaterial3D).albedo_color = color
	for name in ["M_DisplayCount_a", "M_DisplayCount_g", "M_DisplaySlot_01"]:
		if _emitters.has(name):
			(_emitters[name] as StandardMaterial3D).albedo_color = color.lightened(0.2) if (powered and (not placing or pulse > 0.5)) else Color(0.02, 0.03, 0.04)
