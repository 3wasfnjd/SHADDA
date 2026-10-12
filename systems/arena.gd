class_name ShaddaArena
extends Node3D

signal result_changed(won: bool)
signal docked_feedback(hand: int)
var cfg: Dictionary
var batteries: Array[ShaddaBattery] = []
var enemy: ShaddaThief
var station: Node3D
var docks: Array[Node3D] = []
var dock_targets: Array[Node3D] = []
var tethers: Array[ShaddaTether] = []
var links: Array[ShaddaTether] = []
var escape_point := Node3D.new()
var navigation := NavigationRegion3D.new()
var nav_ready: bool = false
var rebuild_after: float = 0.2
var elapsed: float = 0.0
var rescues: int = 0
var finished: bool = false
var won: bool = false
var player_position := Vector3.ZERO
var status: Label3D
var audio := ShaddaAudio.new()
var peak_draw_calls: int = 0

func setup(settings: Dictionary, pose: Transform3D) -> void:
	cfg = settings
	process_mode = Node.PROCESS_MODE_PAUSABLE
	global_transform = pose
	add_child(audio)
	station = load("res://assets/models/runtime/shadda_battery_station.glb").instantiate()
	station.position = Vector3(0, 0, 0.27)
	add_child(station)
	var base := StaticBody3D.new()
	base.collision_layer = 8
	base.collision_mask = 6
	base.set_meta("station", true)
	station.add_child(base)
	var box := BoxShape3D.new()
	box.size = Vector3(0.38, 0.046, 0.18)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = 0.023
	base.add_child(shape)
	# A generous selectable region around the genuine station, with no physical wall.
	var selector := Area3D.new()
	selector.collision_layer = 16
	selector.collision_mask = 0
	selector.set_meta("station", true)
	station.add_child(selector)
	var select_shape := CollisionShape3D.new()
	var select_box := BoxShape3D.new()
	select_box.size = Vector3(0.46, 0.45, 0.3)
	select_shape.shape = select_box
	select_shape.position.y = 0.2
	selector.add_child(select_shape)
	for i in range(3):
		var socket := station.find_child("BatterySocket_%02d" % (i+1), true, false) as Node3D
		assert(socket != null, "All three original battery sockets must exist")
		docks.append(socket)
		var dock_target := Node3D.new()
		socket.add_child(dock_target)
		dock_target.position.y = float(cfg["battery_half_height"])
		dock_targets.append(dock_target)
		var battery := ShaddaBattery.new()
		add_child(battery)
		battery.setup(i, self, cfg)
		batteries.append(battery)
		battery.reset_at(i, dock_pose(i))
	for i in range(2):
		var tether := ShaddaTether.new()
		add_child(tether)
		tethers.append(tether)
		tether.released.connect(_hand_released.bind(i))
	for i in range(3):
		var link := ShaddaTether.new()
		add_child(link)
		links.append(link)
	enemy = ShaddaThief.new()
	add_child(enemy)
	enemy.setup(self, cfg)
	enemy.reset_at(to_global(Vector3(-0.65, float(cfg["enemy_height"]) * 0.5 + 0.02, -0.55)))
	add_child(escape_point)
	escape_point.position = Vector3(0.65, 0.12, -0.58)
	var escape_marker := ShaddaVisuals.label("هروب", 24)
	escape_point.add_child(escape_marker)
	status = ShaddaVisuals.label("", 34)
	status.position = Vector3(0, 0.61, 0.26)
	add_child(status)
	add_child(navigation)
	navigation.navigation_mesh = NavigationMesh.new()
	update_status()

func dock_pose(slot: int) -> Transform3D:
	return dock_targets[slot].global_transform

func slot_available(slot: int, except: ShaddaBattery = null) -> bool:
	for b in batteries:
		if b != except and ((b.state.state == ShaddaBatteryState.State.DOCKED and b.state.dock_id == slot) or b.magnet_slot == slot):
			return false
	return true

func next_slot(battery: ShaddaBattery) -> int:
	if slot_available(battery.identity, battery):
		return battery.identity
	for i in range(3):
		if slot_available(i, battery):
			return i
	return -1

func counts() -> Vector2i:
	var docked := 0
	var lost := 0
	for b in batteries:
		docked += int(b.state.state == ShaddaBatteryState.State.DOCKED)
		lost += int(b.state.state == ShaddaBatteryState.State.LOST)
	return Vector2i(docked, lost)

func choose_battery(from: Vector3) -> ShaddaBattery:
	var result: ShaddaBattery
	var best := INF
	for b in batteries:
		if b.state.state in [ShaddaBatteryState.State.DOCKED, ShaddaBatteryState.State.GROUND]:
			var distance := from.distance_squared_to(b.global_position)
			if distance < best:
				best = distance
				result = b
	return result

func grab(hand: int, body: RigidBody3D, point: Vector3, anchor: Node3D) -> bool:
	if finished or tethers[hand].active or body_tethered(body):
		return false
	if body is ShaddaBattery and not body.grab(hand):
		return false
	if not (body is ShaddaBattery or body is ShaddaThief):
		return false
	tethers[hand].attach(body, point, anchor, cfg)
	sound("grab", point)
	return true

func release_hand(hand: int) -> void:
	var body: RigidBody3D = tethers[hand].body
	tethers[hand].release()
	if body is ShaddaBattery:
		body.drop()

func _hand_released(reason: String, hand: int) -> void:
	for b in batteries:
		if b.state.state == ShaddaBatteryState.State.PLAYER and b.state.owner_id == hand and not body_tethered(b):
			b.drop()
	if reason in ["break", "blocked", "tracking_jump"]:
		sound("release", station.global_position)

func body_tethered(body: RigidBody3D) -> bool:
	for rope in tethers + links:
		if rope.active and rope.body == body:
			return true
	return false

func detach_body(body: RigidBody3D, drop: bool = true) -> void:
	for rope in tethers + links:
		if rope.active and rope.body == body:
			rope.release("dock" if not drop else "manual")
	if drop and body is ShaddaBattery:
		body.drop()

func return_to_station(hand: int) -> bool:
	var body: RigidBody3D = tethers[hand].body
	if not body is ShaddaBattery or body.state.state == ShaddaBatteryState.State.ROBOT:
		return false
	var slot := next_slot(body)
	if slot < 0:
		return false
	var target := dock_targets[slot]
	var query := PhysicsRayQueryParameters3D.create(body.global_position, target.global_position, 1, [body.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	var link := _free_link()
	if link == null:
		return false
	# A visible new tether is anchored at the station. The battery stays dynamic;
	# only the last 12 cm use the short magnetic docking capture.
	var battery: ShaddaBattery = body
	tethers[hand].release("station_link")
	battery.drop()
	link.attach(body, body.global_position, target, cfg, true)
	sound("grab", target.global_position)
	return true

func bind_to_surface(hand: int, point: Vector3) -> bool:
	var rope := tethers[hand]
	if not rope.active or not rope.body is ShaddaThief:
		return false
	var link := _free_link()
	if link == null:
		return false
	var fixed := Node3D.new()
	add_child(fixed)
	fixed.global_position = point
	var target := rope.body
	var attach_point := target.to_global(rope.local_point)
	rope.release("bound")
	link.attach(target, attach_point, fixed, cfg)
	link.rest_length = maxf(0.25, point.distance_to(attach_point) * 0.75)
	get_tree().create_timer(7.0, false).timeout.connect(func():
		if is_instance_valid(link) and link.anchor == fixed:
			link.release("timeout")
		fixed.queue_free())
	sound("grab", point)
	return true

func _free_link() -> ShaddaTether:
	for link in links:
		if not link.active:
			return link
	return null

func battery_docked(battery: ShaddaBattery) -> void:
	if battery.stolen_before and not battery.rescued_counted:
		rescues += 1
		battery.rescued_counted = true
	sound("dock", battery.global_position)
	docked_feedback.emit(-1)
	update_status()

func sound(cue: String, point: Vector3) -> void:
	audio.play_cue(cue, point)

func update_status() -> void:
	var c := counts()
	status.text = "البطاريات %d / 3   •   الاسترجاع %d\n%d:%02d" % [c.x, rescues, int(maxf(0.0,float(cfg["round_seconds"])-elapsed))/60, int(maxf(0.0,float(cfg["round_seconds"])-elapsed))%60]

func _physics_process(delta: float) -> void:
	if cfg.is_empty() or finished:
		return
	elapsed += delta
	if not nav_ready:
		rebuild_after -= delta
		if rebuild_after <= 0.0:
			_build_navigation()
	for i in range(2):
		var rope := tethers[i]
		if rope.active and rope.body is ShaddaBattery:
			var b: ShaddaBattery = rope.body
			if b.state.state == ShaddaBatteryState.State.ROBOT:
				# Integrate excess pulling impulse. A short strong tug and a sustained
				# weaker pull both work independently of render rate.
				b.contested_time = maxf(0.0, b.contested_time + (rope.tension - float(cfg["gripper_break_force"])) * delta)
				if b.contested_time >= 1.8:
					b.state.transition(ShaddaBatteryState.State.PLAYER, i)
					b.contested_time = 0.0
					sound("release", b.global_position)
	update_status()
	if counts().y == 3:
		finish(false)
	elif rescues >= int(cfg["rescues_to_win"]) or elapsed >= float(cfg["round_seconds"]):
		finish(true)

func finish(success: bool) -> void:
	if finished:
		return
	finished = true
	won = success
	for rope in tethers + links:
		rope.release("finished")
	enemy.mode = ShaddaThief.Mode.DISABLED
	safe_resume()
	enemy.freeze = true
	for b in batteries:
		b.freeze = true
	sound("win" if won else "loss", station.global_position)
	result_changed.emit(won)

func safe_resume() -> void:
	for body in batteries + [enemy]:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	for rope in tethers + links:
		rope.resample()

func contain(body: RigidBody3D) -> void:
	# The cyan test perimeter is a virtual play boundary, never a claimed wall.
	var p := to_local(body.global_position)
	var edge_x := float(cfg["arena_width"]) * 0.5 - 0.16
	var edge_z := float(cfg["arena_depth"]) * 0.5 - 0.16
	var force := Vector3.ZERO
	if absf(p.x) > edge_x:
		force.x = -signf(p.x) * (absf(p.x)-edge_x) * 45.0
	if absf(p.z) > edge_z:
		force.z = -signf(p.z) * (absf(p.z)-edge_z) * 45.0
	body.apply_central_force((global_basis * force * body.mass).limit_length(35.0))

func _build_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 0.82
	var step := 0.2
	var nx := int(float(cfg["arena_width"]) / step)
	var nz := int(float(cfg["arena_depth"]) / step)
	for x in range(nx):
		for z in range(nz):
			var p := Vector3((x+0.5)*step-float(cfg["arena_width"])*0.5,0,(z+0.5)*step-float(cfg["arena_depth"])*0.5)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(global_basis,to_global(p+Vector3.UP*0.44))
			query.collision_mask = 9
			if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
				continue
			var base := vertices.size()
			for offset in [Vector3(-0.5,0,-0.5),Vector3(-0.5,0,0.5),Vector3(0.5,0,0.5),Vector3(0.5,0,-0.5)]:
				vertices.append(p+offset*step)
			polygons.append(PackedInt32Array([base,base+1,base+2,base+3]))
	nav_mesh.vertices = vertices
	for polygon in polygons:
		nav_mesh.add_polygon(polygon)
	navigation.navigation_mesh = nav_mesh
	nav_ready = true

func next_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(goal.x,from.y,goal.z), 1)
	if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return goal
	if nav_ready:
		var map := navigation.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var path := NavigationServer3D.map_get_path(map,from,goal,true)
			if path.size() > 1:
				return path[1]
	return from
