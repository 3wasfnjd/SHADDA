extends Node3D
## Boot sequence: OpenXR + passthrough, studio intro, room scan, then the
## battle. The right controller flies the jet; the left wrist wears the HUD.
## Desktop "--preview" fakes the headset so CI can render flat screenshots
## (which prove nothing about the Quest itself).

const IntroClock = preload("res://systems/intro_clock.gd")

var clock = IntroClock.new()
var xr: OpenXRInterface
var origin: XROrigin3D
var head: XRCamera3D
var studio: Sprite3D
var controllers: Array[XRController3D] = []
var aim_controllers: Array[XRController3D] = []
var jet: PlayerJet
var hud: WristHud
var director: BattleDirector
var room_scan: RoomScan
var foreground: bool = true
var positioned: bool = false
var rendered: bool = false
var failed: bool = false
var preview: bool = false
var preview_mode: String = ""
var preview_time: float = 0.0
var preview_shots: int = 0
var started: bool = false


func _ready() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	preview_mode = OS.get_environment("SAQR_PREVIEW")
	get_viewport().transparent_bg = true
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
	head.near = 0.02
	head.far = 60.0
	origin.add_child(head)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	# One soft key light so the models read as solid shapes (no shadows: cheap).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = false
	add_child(sun)
	studio = Sprite3D.new()
	studio.texture = load("res://assets/ui/studio.png")
	studio.pixel_size = 0.00085
	studio.modulate.a = 0.0
	add_child(studio)
	for i in range(2):
		var controller := XRController3D.new()
		controller.tracker = &"left_hand" if i == 0 else &"right_hand"
		controller.pose = &"grip"
		origin.add_child(controller)
		controllers.append(controller)
		controller.button_pressed.connect(_button.bind(i))
		var aim := XRController3D.new()
		aim.tracker = controller.tracker
		aim.pose = &"aim"
		origin.add_child(aim)
		aim_controllers.append(aim)
	hud = WristHud.new()
	controllers[0].add_child(hud)
	director = BattleDirector.new()
	add_child(director)
	jet = PlayerJet.new()
	jet.hand = controllers[1]
	director.add_child(jet)
	jet.visible = false
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		environment.background_color = Color(0.36, 0.38, 0.40, 1.0)
		get_viewport().transparent_bg = false
		head.position = Vector3(0, 1.6, 0)
		head.rotation_degrees.x = -8.0
		head.fov = 80.0
		controllers[0].position = Vector3(-0.2, 1.28, -0.36)
		controllers[0].rotation_degrees = Vector3(-10, 25, 0)
		controllers[1].position = Vector3(0.12, 1.36, -0.32)
		aim_controllers[1].position = controllers[1].position
		_add_preview_room()
	else:
		if xr == null or (not xr.is_initialized() and not xr.initialize()):
			_stop("تعذر تشغيل OpenXR. أعد تشغيل التطبيق من النظارة.")
			return
		get_viewport().use_xr = true
		if not xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			_stop("Passthrough غير متاح. اللعبة تتطلب رؤية الغرفة.")
			return
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr.pose_recentered.connect(_recenter)
		if xr.get_available_display_refresh_rates().has(72.0):
			xr.display_refresh_rate = 72.0
	RenderingServer.frame_post_draw.connect(_frame_drawn)


func _frame_drawn() -> void:
	rendered = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		foreground = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		foreground = true


func _tracking_ready() -> bool:
	if preview:
		return true
	if xr == null or xr.get_session_state() != OpenXRInterface.SESSION_STATE_FOCUSED:
		return false
	var tracker := XRServer.get_tracker("head") as XRPositionalTracker
	if tracker == null or not tracker.has_pose("default"):
		return false
	var pose := tracker.get_pose("default")
	if not pose.has_tracking_data or pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_NONE:
		return false
	if not Engine.has_singleton("OpenXRFbPassthroughExtension"):
		return false
	return bool(Engine.get_singleton("OpenXRFbPassthroughExtension").call("is_passthrough_started"))


func _process(delta: float) -> void:
	if failed:
		return
	if preview and preview_mode == "models":
		_models_lineup(delta)
		return
	var ready := foreground and _tracking_ready()
	if ready and not positioned:
		_recenter()
		positioned = true
		rendered = false
		return
	studio.modulate.a = clock.tick(delta, ready and positioned and rendered)
	studio.visible = not clock.finished and ready
	if preview and not clock.finished:
		clock.tick(10.0, true)
	if clock.finished and not started:
		started = true
		director.build(head, jet, hud)
		if preview:
			director.on_room_ready(_preview_mounts(), 0.0, true)
		else:
			room_scan = RoomScan.new()
			add_child(room_scan)
			room_scan.room_ready.connect(director.on_room_ready)
			room_scan.start(origin, head)
	if not started:
		return
	jet.visible = ready and not jet.destroyed and (preview or controllers[1].get_is_active())
	if not ready:
		return
	var triggers := [0.0, 0.0]
	var grips := [0.0, 0.0]
	if preview:
		_preview_input(delta, triggers, grips)
	else:
		for i in range(2):
			triggers[i] = controllers[i].get_float("trigger")
			grips[i] = controllers[i].get_float("grip")
	jet.fly(delta, aim_controllers[1].global_transform)
	director.update_controls(delta, triggers[1], grips[1], triggers[0])


func _button(action: StringName, hand_index: int) -> void:
	if not clock.finished or not foreground or director == null or not started:
		return
	director.on_button(action, hand_index)


func _recenter() -> void:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	studio.global_position = head.global_position + forward * 1.6
	studio.look_at(head.global_position, Vector3.UP, true)


func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "SAQR")
	get_tree().quit(1)


# --- desktop preview (CI screenshots; not a headset capture) ------------------------------

const PREVIEW_ROOM := [
	{"origin": Vector3(0.0, 0, -2.6), "normal": Vector3(0, 0, 1), "width": 4.2, "height": 2.6, "kind": "wall"},
	{"origin": Vector3(2.1, 0, -0.6), "normal": Vector3(-1, 0, 0), "width": 4.0, "height": 2.6, "kind": "wall"},
	{"origin": Vector3(-2.1, 0, -0.6), "normal": Vector3(1, 0, 0), "width": 4.0, "height": 2.6, "kind": "wall"},
	{"origin": Vector3(0.0, 0, 1.4), "normal": Vector3(0, 0, -1), "width": 4.2, "height": 2.6, "kind": "wall"},
	{"origin": Vector3(0.0, 2.6, -0.6), "normal": Vector3.DOWN, "width": 4.0, "height": 0.0, "kind": "ceiling"},
]


func _preview_mounts() -> Array:
	return PREVIEW_ROOM.duplicate(true)


## Grey stand-in walls and floor so the screenshots read like a room.
func _add_preview_room() -> void:
	var wall_m := StandardMaterial3D.new()
	wall_m.albedo_color = Color(0.78, 0.76, 0.72)
	wall_m.roughness = 0.95
	wall_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.52, 0.45, 0.38)
	floor_m.roughness = 0.9
	for m in PREVIEW_ROOM:
		var q := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		if m.kind == "ceiling":
			continue
		plane.size = Vector2(m.width, m.height)
		plane.orientation = PlaneMesh.FACE_Z
		q.mesh = plane
		q.material_override = wall_m
		add_child(q)
		q.position = m.origin + Vector3(0, m.height * 0.5, 0)
		q.look_at(q.position - m.normal, Vector3.UP)
		q.rotate_object_local(Vector3.UP, PI)
	var fl := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(4.2, 4.0)
	fl.mesh = fp
	fl.material_override = floor_m
	fl.position = Vector3(0, 0, -0.6)
	add_child(fl)


## Scripted demo for screenshots. Default: menu → wave 1 (targets, drones) →
## cannon → lock → salvo. SAQR_PREVIEW=armor: tanks, bombs, fighter missile and
## flares. SAQR_PREVIEW=boss: the gunship coming out of its bay.
func _preview_input(delta: float, triggers: Array, grips: Array) -> void:
	preview_time += delta
	var aim := aim_controllers[1]
	match director.phase:
		BattleDirector.Phase.MENU:
			_point(aim, director._menu_root.global_position if director._menu_root else Vector3(0, 1.4, -1.2))
			if preview_time > 0.9:
				director.auto_spawn = preview_mode == ""
				director.start_match()
				if preview_mode == "armor":
					director._queue.clear()
					director.wave = 1
					director.hud.set_wave(1, false)
					for k in ["tank", "tank", "fighter", "drone"]:
						director.spawn(k)
				elif preview_mode == "boss":
					director._queue.clear()
					director._begin_wave(4)
					director._queue.clear()
					director.spawn("boss")
				preview_time = 1.0
		BattleDirector.Phase.PLAYING:
			var target = _preview_target()
			if target:
				_point(aim, target.hit_center())
			if preview_mode == "":
				triggers[1] = 1.0 if preview_time > 2.6 and preview_time < 3.3 else 0.0
				grips[1] = 1.0 if preview_time > 3.5 and preview_time < 4.6 else 0.0
				triggers[0] = 1.0 if preview_time > 5.2 and preview_time < 5.9 else 0.0
			elif preview_mode == "armor":
				if preview_time > 3.6 and preview_time < 3.62:
					director.on_button(&"ax_button", 1)
				if preview_time > 4.4 and preview_time < 4.42:
					director.on_button(&"by_button", 1)
				triggers[1] = 1.0 if preview_time > 5.0 and preview_time < 5.6 else 0.0
			elif preview_mode == "boss":
				triggers[1] = 1.0 if preview_time > 5.0 and preview_time < 5.8 else 0.0
				grips[1] = 1.0 if preview_time > 6.0 and preview_time < 7.0 else 0.0
			if preview_time > 8.5 and director.phase == BattleDirector.Phase.PLAYING:
				director.won = true
				director._finish(true)
		BattleDirector.Phase.RESULTS:
			_point(aim, director._results_root.global_position if director._results_root else Vector3(0, 1.4, -1.2))
	var shots: Array = {
		"": [[0.6, "menu"], [1.9, "targets"], [3.0, "cannon"], [4.4, "lock"], [5.0, "salvo"], [5.6, "laser"], [9.4, "results"]],
		"armor": [[2.4, "bays"], [3.4, "tanks"], [3.9, "bomb"], [4.6, "flares"], [6.5, "fighter"]],
		"boss": [[2.0, "boss_bay"], [3.6, "boss_emerges"], [5.5, "boss_fight"], [7.2, "boss_lock"]],
	}[preview_mode]
	if preview_shots < shots.size() and preview_time >= shots[preview_shots][0]:
		var shot_name: String = shots[preview_shots][1]
		preview_shots += 1
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/previews")
		get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % shot_name)
		print("preview shot %s: phase=%d wave=%d score=%d enemies=%d shots=%d locks=%d armor=%d" % [shot_name, director.phase, director.wave, director.score, director.enemies.size(), director.shots.size(), jet.locks.size(), int(jet.armor)])
		if preview_shots >= shots.size():
			get_tree().quit()


func _preview_target():
	var best = null
	var best_d := INF
	for e in director.enemies:
		if not e.alive():
			continue
		var a := CombatMath.off_axis_deg(head.global_position, -head.global_basis.z, e.hit_center())
		if a < best_d:
			best_d = a
			best = e
	return best


func _point(aim: Node3D, at: Vector3) -> void:
	var from := controllers[1].global_position
	if at.distance_to(from) < 0.2:
		return
	var want := Basis.looking_at((at - from).normalized(), Vector3.UP)
	aim.global_transform = Transform3D(aim.global_basis.slerp(want, 0.25), from)
	controllers[1].global_basis = aim.global_basis


## SAQR_PREVIEW=models: the player's jet up close, then every enemy, for a
## design review (desktop render, not a headset capture).
var _lineup: Node3D
func _models_lineup(delta: float) -> void:
	preview_time += delta
	if _lineup == null:
		_lineup = Node3D.new()
		add_child(_lineup)
		hud.visible = false
		var j := Models.jet(false)
		_lineup.add_child(j.root)
		j.root.position = Vector3(0, 1.36, -0.46)
		j.root.rotation_degrees = Vector3(0, 135, -8)
		head.rotation_degrees = Vector3(-17, 0, 0)
		head.fov = 42.0
	var stages := [[0.4, "jet_closeup"], [1.2, "jet_top"], [2.0, "enemies"]]
	if preview_shots >= stages.size():
		get_tree().quit()
		return
	if preview_time < stages[preview_shots][0]:
		return
	var shot_name: String = stages[preview_shots][1]
	preview_shots += 1
	if shot_name == "jet_top":
		var jr: Node3D = _lineup.get_child(0)
		jr.position = Vector3(0, 1.1, -0.33)
		jr.rotation_degrees = Vector3(0, 180, 0)
		head.rotation_degrees = Vector3(-58, 0, 0)
	elif shot_name == "enemies":
		for c in _lineup.get_children():
			c.queue_free()
		var items := [["fighter", Models.jet(true), Vector3(-0.42, 1.52, -0.9), Vector3(10, 150, -8)],
			["drone", Models.drone(), Vector3(0.0, 1.55, -0.9), Vector3(15, 200, 0)],
			["tank", Models.tank(), Vector3(0.42, 1.38, -0.9), Vector3(20, 145, 0)],
			["boss", Models.gunship(), Vector3(-0.05, 1.13, -1.15), Vector3(14, 155, 0)],
			["target", Models.target(), Vector3(0.62, 1.12, -1.25), Vector3(0, -25, 0)]]
		for it in items:
			var r: Node3D = it[1].root
			_lineup.add_child(r)
			r.position = it[2]
			r.rotation_degrees = it[3]
			if it[0] == "boss":
				r.scale = Vector3.ONE * 0.75
		head.rotation_degrees = Vector3(-8, 0, 0)
		head.fov = 62.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % shot_name)
	print("preview shot %s: %d triangles" % [shot_name, Models.triangles(_lineup)])
