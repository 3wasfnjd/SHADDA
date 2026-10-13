class_name GameDirector
extends Node3D
## Runs SHADDA inside the real room with no rounds and no text.
## Flow: SCANNING (room anchors) → PLACING (the station hovers where you look;
## A drops it) → PLAYING (continuous pressure from the rifts) → ENDED (the
## station goes dark or the rifts seal; A plays again).

enum Phase { SCANNING, PLACING, PLAYING, ENDED }

const MAX_RIFTS := 3
const FALLBACK_RIFT_DISTANCE := 2.8
const FALLBACK_RIFT_ANGLES := [-70.0, 0.0, 70.0]
const START_DELAY := 3.0

var phase: int = Phase.SCANNING
var head: XRCamera3D
var gauntlets: Array[Gauntlet] = []
var station: Station
var rifts: Array[Rift] = []
var robots: Array = []
var spawner := SpawnDirector.new()
var audio: ShaddaAudio
var floor_offset: float = 0.0
var captures: int = 0
var rescues: int = 0
var survived: bool = false
var room_mounts: Array = []
var room_found: bool = false

var _scenes: Dictionary = {}
var _rift_cursor: int = 0
var _start_timer: float = 0.0
var _end_timer: float = 0.0
var _floor_body: StaticBody3D
var _gaze_point: Vector3 = Vector3(0, 0, -1.2)


func build(camera: XRCamera3D, hands: Array[Gauntlet]) -> void:
	head = camera
	gauntlets = hands
	_scenes = {
		"station": load("res://assets/models/runtime/shadda_battery_station.glb"),
		"cell": load("res://assets/models/runtime/shadda_power_cell.glb"),
		"rift": load("res://assets/models/runtime/shadda_rift.glb"),
		"A": load("res://assets/models/runtime/shadda_robot_A.glb"),
		"B": load("res://assets/models/runtime/shadda_robot_B.glb"),
		"C": load("res://assets/models/runtime/shadda_robot_C.glb"),
		"D": load("res://assets/models/runtime/shadda_robot_D.glb"),
	}
	audio = ShaddaAudio.new()
	add_child(audio)
	# Arena floor: a wide invisible slab at y = 0 so dropped cells land on it.
	_floor_body = StaticBody3D.new()
	_floor_body.collision_layer = 1
	_floor_body.collision_mask = 0
	var slab := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	slab.shape = box
	slab.position.y = -0.1
	_floor_body.add_child(slab)
	add_child(_floor_body)
	station = Station.create(_scenes["station"])
	add_child(station)
	station.install_cells(_scenes["cell"], self)
	station.begin_placement()
	for i in range(MAX_RIFTS):
		var rift := Rift.create(_scenes["rift"])
		add_child(rift)
		rift.hum = audio.attach_loop("hum", rift)
		rifts.append(rift)
	for g in gauntlets:
		g.director = self
	phase = Phase.SCANNING
	apply_fallback_layout()


## Called by RoomScan (or immediately in preview/fallback).
func on_room_ready(mounts: Array, floor_y: float, found: bool) -> void:
	room_mounts = mounts
	room_found = found and not mounts.is_empty()
	if found:
		floor_offset = floor_y
		position.y = floor_offset
	if room_found:
		_mount_rifts_on_room()
	else:
		apply_fallback_layout()
	phase = Phase.PLACING


func _mount_rifts_on_room() -> void:
	var used := 0
	for m in room_mounts:
		if used >= rifts.size():
			break
		var rift := rifts[used]
		# Keep rifts apart from each other.
		var too_close := false
		for j in range(used):
			if rifts[j].global_position.distance_to(m.origin) < 1.2:
				too_close = true
		if too_close:
			continue
		rift.mount(Vector3(m.origin.x, floor_offset, m.origin.z), m.normal)
		used += 1
	# Fewer than three usable surfaces: leave the rest unused.
	for i in range(used, rifts.size()):
		rifts[i].global_position = Vector3(0, -50, 0)


## No room data: rifts float where walls usually are, around the player.
func apply_fallback_layout() -> void:
	var forward := -head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var feet := feet_local()
	for i in range(rifts.size()):
		var direction := forward.rotated(Vector3.UP, deg_to_rad(FALLBACK_RIFT_ANGLES[i]))
		rifts[i].mount(to_global(feet + direction * FALLBACK_RIFT_DISTANCE), -direction)


func active_rifts() -> Array:
	var out: Array = []
	for r in rifts:
		if r.global_position.y > -10.0:
			out.append(r)
	return out


func feet_local() -> Vector3:
	var local := to_local(head.global_position)
	return Vector3(local.x, 0.0, local.z)


## Left stick before the match nudges the arena floor when the estimate is off.
func adjust_floor(axis: float, delta: float) -> float:
	if phase == Phase.PLAYING or absf(axis) < 0.25:
		return floor_offset
	floor_offset = clampf(floor_offset + axis * delta * 0.25, -1.2, 1.2)
	position.y = floor_offset
	return floor_offset


func cue(name: String, point: Vector3, volume_db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, point, volume_db)


func on_button(action: StringName, hand_index: int) -> void:
	if action == &"ax_button":
		match phase:
			Phase.PLACING:
				_place_station_and_start()
			Phase.ENDED:
				if _end_timer > 1.5:
					_reset_for_placement()
			Phase.PLAYING:
				if hand_index < gauntlets.size():
					gauntlets[hand_index].release_everything()
	elif action == &"by_button" and phase == Phase.PLACING and not room_found:
		apply_fallback_layout()


func _place_station_and_start() -> void:
	station.place()
	cue("dock", station.global_position)
	for g in gauntlets:
		g.release_everything()
	for i in range(station.cells.size()):
		station.cells[i].charge = 1.0
		station.dock(station.cells[i], i)
	station.set_powered(true)
	spawner.start()
	captures = 0
	rescues = 0
	survived = false
	_start_timer = 0.0
	phase = Phase.PLAYING


func _reset_for_placement() -> void:
	for robot in robots:
		if is_instance_valid(robot):
			robot.queue_free()
	robots.clear()
	for rift in rifts:
		rift.close()
	for cell in station.cells:
		cell.visible = true
	station.set_powered(true)
	station.begin_placement()
	phase = Phase.PLACING


func _process(delta: float) -> void:
	if head == null:
		return
	match phase:
		Phase.PLACING:
			_update_gaze_placement(delta)
		Phase.PLAYING:
			_start_timer += delta
			if _start_timer >= START_DELAY:
				var kind := spawner.tick(delta)
				if kind != "":
					_spawn(kind)
			_update_rift_moods()
			_check_end()
		Phase.ENDED:
			_end_timer += delta


## The station hovers on the floor where the player looks (1–3 m ahead).
func _update_gaze_placement(delta: float) -> void:
	var origin := head.global_position
	var dir := -head.global_basis.z
	var floor_plane := Plane(Vector3.UP, global_position.y)
	var hit = floor_plane.intersects_ray(origin, dir)
	var target: Vector3
	if hit != null:
		target = hit
	else:
		var forward := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.FORWARD
		target = Vector3(origin.x, global_position.y, origin.z) + forward * 2.0
	var feet := Vector3(origin.x, global_position.y, origin.z)
	var away := target - feet
	var d := away.length()
	if d < 0.9 or d > 3.0:
		away = away.normalized() * clampf(d, 0.9, 3.0)
	target = feet + away
	_gaze_point = _gaze_point.lerp(target, minf(1.0, delta * 6.0))
	station.global_position = _gaze_point
	station.look_at(Vector3(origin.x, _gaze_point.y, origin.z), Vector3.UP, true)
	station.rotation.x = 0.0
	station.rotation.z = 0.0


func _spawn(kind: String) -> void:
	var available := active_rifts()
	if available.is_empty():
		return
	var rift: Rift = available[_rift_cursor % available.size()]
	_rift_cursor += 1
	rift.open()
	var robot := Robot.create(kind, _scenes[kind])
	robot.director = self
	add_child(robot)
	robot.configure(rift, station, head)
	robot.defeated.connect(_on_robot_defeated)
	robot.escaped.connect(_on_robot_escaped)
	robot.cell_taken.connect(_on_cell_taken)
	robot.cell_dropped.connect(_on_cell_dropped)
	robots.append(robot)
	cue("spawn", rift.global_position)


func _update_rift_moods() -> void:
	# A rift stays lit while one of its raiders is out; closes when quiet.
	for rift in active_rifts():
		var busy := false
		for robot in robots:
			if is_instance_valid(robot) and robot.home_rift == rift and robot.state != Robot.State.DOWN:
				busy = true
		if not busy and rift.is_open() and rift.open_seconds() > 2.5:
			rift.close()
			cue("seal", rift.global_position, -6.0)
	# Warn from the next rift shortly before its raider comes.
	if spawner.alive < spawner.max_alive() and spawner.next_spawn - spawner.time < 2.0 and not spawner.finished:
		var available := active_rifts()
		if not available.is_empty():
			available[_rift_cursor % available.size()].warn()


func _on_robot_defeated(robot: Robot) -> void:
	captures += 1
	spawner.robot_gone()
	robots.erase(robot)


func _on_robot_escaped(robot: Robot, _with_cell: bool) -> void:
	spawner.robot_gone()
	robots.erase(robot)
	if _with_cell:
		cue("loss" if station.lost_count() >= station.cells.size() else "release", robot.global_position)


func _on_cell_taken(_robot: Robot) -> void:
	cue("alert", station.global_position)


func _on_cell_dropped(robot: Robot, cell: Node3D) -> void:
	var drop := cell.global_position + Vector3(0, 0.05, 0)
	(cell as PowerCell).drop_at(drop, robot.velocity * 0.5 + Vector3(0, 0.6, 0))
	cue("drop", drop)


func on_cell_docked(_cell: PowerCell) -> void:
	rescues += 1


func _check_end() -> void:
	if station.lost_count() >= station.cells.size():
		_end(false)
	elif spawner.finished and robots.is_empty():
		_end(true)


func _end(won: bool) -> void:
	phase = Phase.ENDED
	survived = won
	_end_timer = 0.0
	for rift in rifts:
		if rift.mode != Rift.Mode.CLOSED:
			cue("seal", rift.global_position)
		rift.close()
	for g in gauntlets:
		g.release_everything()
	station.set_powered(won)
	cue("win" if won else "loss", station.global_position)


func targets() -> Array:
	var out: Array = []
	out.append_array(robots)
	for cell in station.cells:
		if cell.state == PowerCell.State.LOOSE:
			out.append(cell)
	return out


func update_hands(delta: float, triggers: Array, grips: Array) -> void:
	var list := targets()
	for i in range(gauntlets.size()):
		gauntlets[i].update(delta, triggers[i], grips[i], list, station.cells, station, phase == Phase.PLAYING)
