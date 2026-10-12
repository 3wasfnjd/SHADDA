extends Node3D

const IntroClock = preload("res://systems/intro_clock.gd")
enum Flow { INTRO, MENU, PLACEMENT, CONFIRM, PLAY, PAUSE, CALIBRATE, RESULT }
var flow: Flow = Flow.INTRO
var before_calibration: Flow = Flow.MENU
var clock = IntroClock.new()
var cfg: Dictionary
var xr: OpenXRInterface
var origin := XROrigin3D.new()
var head := XRCamera3D.new()
var controllers: Array[XRController3D] = []
var models: Array[Node3D] = []
var alignments: Array[Node3D] = []
var emitters: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var previous_pose: Array[String] = ["", ""]
var trigger_down: Array[bool] = [false,false]
var hand_hits: Array[Dictionary] = [{},{}]
var aim_meshes: Array[ImmediateMesh] = []
var aim_dots: Array[MeshInstance3D] = []
var hint_labels: Array[Label3D] = []
var angles: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var offsets: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var offset_mode: Array[bool] = [false,false]
var haptic_timer: float = 0.0
var studio := Sprite3D.new()
var menu: Label3D
var room := ShaddaRoomSetup.new()
var arena: ShaddaArena
var foreground: bool = true
var positioned: bool = false
var rendered: bool = false
var was_ready: bool = false
var failed: bool = false
var preview: bool = false
var preview_time: float = 0.0
var preview_stage: int = 0
var pending_start: bool = false
var head_guard := AnimatableBody3D.new()
var aim_material := ShaddaVisuals.material(Color(0.02,0.6,0.8),0.5)
var peak_draw_calls: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/playtest.json"))
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	get_viewport().transparent_bg = true
	add_child(origin)
	head.near = 0.03
	origin.add_child(head)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85,0.9,1)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-25,0)
	light.light_energy = 1.1
	add_child(light)
	studio.texture = load("res://assets/ui/studio.png")
	studio.pixel_size = 0.00085
	studio.modulate.a = 0.0
	add_child(studio)
	menu = ShaddaVisuals.label("",36)
	menu.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	menu.hide()
	add_child(menu)
	_load_alignment()
	for i in range(2):
		var controller := XRController3D.new()
		controller.tracker = &"left_hand" if i == 0 else &"right_hand"
		# Aim's -Z points forward. Grip has a controller-dependent holding pitch.
		controller.pose = &"aim"
		origin.add_child(controller)
		controllers.append(controller)
		controller.button_pressed.connect(_button.bind(i))
		var alignment := Node3D.new()
		controller.add_child(alignment)
		alignments.append(alignment)
		var side := "left" if i == 0 else "right"
		var model: Node3D = load("res://assets/models/runtime/shadda_gauntlet_%s.glb" % side).instantiate()
		alignment.add_child(model)
		model.rotation_degrees.x = float(cfg["glove_pitch_degrees"])
		model.hide()
		models.append(model)
		var emitter := model.find_child("TetherOrigin",true,false) as Node3D
		assert(emitter != null, "Original TetherOrigin must be retained")
		emitters.append(emitter)
		var found := model.find_children("*","AnimationPlayer",true,false)
		players.append(found[0] as AnimationPlayer if not found.is_empty() else null)
		var aim := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		aim.mesh = mesh
		add_child(aim)
		aim_meshes.append(mesh)
		var dot := ShaddaVisuals.sphere(0.012,Color(0.02,0.75,1))
		add_child(dot)
		dot.hide()
		aim_dots.append(dot)
		var hint := ShaddaVisuals.label("",22)
		add_child(hint)
		hint_labels.append(hint)
	_apply_alignment()
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		head.position = Vector3(0,1.45,1.65)
		head.look_at(Vector3(0,0.60,-0.30))
		for i in range(2):
			controllers[i].position = Vector3(-0.23 if i == 0 else 0.23,1.00,1.10)
			controllers[i].rotation_degrees.x = -22.0
	else:
		if xr == null or (not xr.is_initialized() and not xr.initialize()):
			_stop("تعذر تشغيل OpenXR. أعد تشغيل التطبيق من النظارة.")
			return
		get_viewport().use_xr = true
		if not xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			_stop("Passthrough غير متاح. اللعبة تتطلب رؤية الغرفة.")
			return
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr.pose_recentered.connect(_system_recentered)
		if xr.get_available_display_refresh_rates().has(72.0):
			xr.display_refresh_rate = 72.0
	add_child(room)
	room.setup(origin,cfg,preview)
	head_guard.collision_layer = 8
	head_guard.collision_mask = 6
	var guard_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.34
	guard_shape.shape = sphere
	head_guard.add_child(guard_shape)
	add_child(head_guard)
	RenderingServer.frame_post_draw.connect(_frame_drawn)

func _frame_drawn() -> void:
	rendered = true
	peak_draw_calls = maxi(peak_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

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
	return Engine.has_singleton("OpenXRFbPassthroughExtension") and bool(Engine.get_singleton("OpenXRFbPassthroughExtension").call("is_passthrough_started"))

func _hands_ready() -> bool:
	return preview or (controllers[0].get_is_active() and controllers[1].get_is_active())

func _process(delta: float) -> void:
	if failed:
		return
	var ready := foreground and _tracking_ready()
	if ready and not positioned:
		_recenter_menu()
		positioned = true
		rendered = false
		was_ready = true
		return
	if flow == Flow.PLAY and (not ready or not _hands_ready()):
		_pause()
	if ready and not was_ready:
		_recenter_menu()
	if flow == Flow.INTRO:
		studio.modulate.a = clock.tick(delta,ready and was_ready and positioned and rendered)
		if clock.finished:
			flow = Flow.MENU
			_update_menu()
	was_ready = ready
	studio.visible = flow == Flow.INTRO and ready
	menu.visible = flow not in [Flow.INTRO,Flow.PLAY] and ready
	for i in range(2):
		models[i].visible = flow != Flow.INTRO and ready and (preview or controllers[i].get_is_active())
		if models[i].visible:
			var pose := "Open"
			if flow == Flow.PLAY and arena.tethers[i].active:
				pose = "Pull" if controllers[i].get_float("grip") > 0.15 else "TetherGrip"
			elif controllers[i].get_float("grip") > 0.15:
				pose = "Fist"
			_play_pose(i,pose)
		if flow != Flow.PLAY or not ready:
			aim_meshes[i].clear_surfaces()
			aim_dots[i].hide()
			hint_labels[i].hide()
	if flow == Flow.CALIBRATE and ready:
		for i in range(2):
			var stick := controllers[i].get_vector2("thumbstick")
			if stick.length() < 0.2:
				continue
			if offset_mode[i]:
				if controllers[i].get_float("grip") > 0.5:
					offsets[i].z = clampf(offsets[i].z+stick.y*delta*0.03,-0.15,0.15)
				else:
					offsets[i].x = clampf(offsets[i].x+stick.x*delta*0.03,-0.1,0.1)
					offsets[i].y = clampf(offsets[i].y+stick.y*delta*0.03,-0.1,0.1)
			elif controllers[i].get_float("grip") > 0.5:
				angles[i].z += stick.x*delta*35.0
			else:
				angles[i].x += stick.y*delta*35.0
				angles[i].y -= stick.x*delta*35.0
		_apply_alignment()
	if preview:
		_preview(delta)

func _physics_process(delta: float) -> void:
	if failed or not foreground or not _tracking_ready():
		return
	head_guard.global_position = head.global_position
	if pending_start:
		pending_start = false
		_begin_game()
	if flow == Flow.PLACEMENT:
		room.update_placement(head,controllers[1],controllers[0].get_vector2("thumbstick").y,delta)
		menu.text = "ضع محطة الطاقة\n"+room.info+"\nY ضبط القفازات"
	if flow != Flow.PLAY:
		return
	haptic_timer += delta
	for i in range(2):
		var ray_start := controllers[i].global_position
		var ray_end := ray_start-controllers[i].global_basis.z*float(cfg["rope_range"])
		var query := PhysicsRayQueryParameters3D.create(ray_start,ray_end,31,[head_guard.get_rid()])
		query.collide_with_areas = true
		if not arena.tethers[i].active:
			query.collision_mask = 15
		hand_hits[i] = get_world_3d().direct_space_state.intersect_ray(query)
		var hit := hand_hits[i]
		var point: Vector3 = ray_end if hit.is_empty() else hit.position
		ShaddaVisuals.line(aim_meshes[i],PackedVector3Array([emitters[i].global_position,point]),aim_material)
		aim_dots[i].visible = not hit.is_empty()
		aim_dots[i].global_position = point
		hint_labels[i].global_position = point+Vector3.UP*0.06
		hint_labels[i].visible = not hit.is_empty()
		var text := ""
		if not hit.is_empty():
			if hit.collider is ShaddaBattery:
				text = "بطارية"
			elif hit.collider is ShaddaThief:
				text = "لص"
			elif bool(hit.collider.get_meta("station",false)) and arena.tethers[i].active and arena.tethers[i].body is ShaddaBattery:
				text = "Trigger: إعادة للمنفذ"
			elif arena.tethers[i].active and arena.tethers[i].body is ShaddaThief and hit.collider.collision_layer & 1:
				text = "Trigger: تثبيت"
			else:
				text = "مسار محجوب"
		hint_labels[i].text = text
		arena.tethers[i].reel = controllers[i].get_float("grip")
		var pressed := controllers[i].get_float("trigger") > 0.65
		if pressed and not trigger_down[i]:
			_trigger(i)
		trigger_down[i] = pressed
		if haptic_timer >= 0.24 and arena.tethers[i].active:
			var strength := clampf(arena.tethers[i].tension/65.0,0.0,1.0)
			if strength > 0.03:
				controllers[i].trigger_haptic_pulse("haptic",0,0.04+strength*0.18,0.035,0)
	if haptic_timer >= 0.24:
		haptic_timer = 0.0

func _trigger(i: int) -> void:
	var hit := hand_hits[i]
	if hit.is_empty():
		return
	if arena.tethers[i].active:
		if bool(hit.collider.get_meta("station",false)):
			arena.return_to_station(i)
		elif hit.collider.collision_layer & 1:
			arena.bind_to_surface(i,hit.position+hit.normal*0.02)
	elif hit.collider is RigidBody3D:
		if arena.grab(i,hit.collider,hit.position,emitters[i]):
			controllers[i].trigger_haptic_pulse("haptic",0,0.18,0.07,0)

func _button(action: StringName, hand: int) -> void:
	if flow == Flow.INTRO or not foreground or not _tracking_ready():
		return
	var a := hand == 1 and action == &"ax_button"
	var b := hand == 1 and action == &"by_button"
	var x := hand == 0 and action == &"ax_button"
	var y := hand == 0 and action == &"by_button"
	match flow:
		Flow.MENU:
			if a:
				flow = Flow.PLACEMENT
				room.start()
			elif y:
				_calibrate()
		Flow.PLACEMENT:
			if a and room.clear:
				room.frozen_selection = true
				if room.has_real_floor:
					pending_start = true
				else:
					flow = Flow.CONFIRM
			elif b:
				room.scan()
			elif y:
				_calibrate()
		Flow.CONFIRM:
			if a:
				room.confirm_manual()
				pending_start = true
			elif b:
				flow = Flow.PLACEMENT
				room.frozen_selection = false
		Flow.PLAY:
			if b:
				arena.release_hand(1)
			elif x:
				arena.release_hand(0)
			elif y:
				_pause()
		Flow.PAUSE:
			if a and _hands_ready():
				arena.safe_resume()
				get_tree().paused = false
				flow = Flow.PLAY
			elif x:
				_calibrate()
			elif b:
				_clear_arena()
				get_tree().paused = false
				flow = Flow.PLACEMENT
				room.start()
		Flow.CALIBRATE:
			if action == &"thumbstick_click":
				offset_mode[hand] = not offset_mode[hand]
			elif a or y:
				if a:
					_save_alignment()
				else:
					_load_alignment()
				_apply_alignment()
				flow = before_calibration
			elif b:
				angles = [Vector3.ZERO,Vector3.ZERO]
				offsets = [Vector3.ZERO,Vector3.ZERO]
				_apply_alignment()
		Flow.RESULT:
			if a:
				pending_start = true
			elif y:
				_calibrate()
	_update_menu()

func _begin_game() -> void:
	_clear_arena()
	get_tree().paused = false
	arena = ShaddaArena.new()
	add_child(arena)
	arena.setup(cfg,room.selected)
	arena.player_position = head.global_position
	arena.result_changed.connect(_result)
	arena.docked_feedback.connect(_docked)
	flow = Flow.PLAY
	menu.hide()
	for i in range(2):
		trigger_down[i] = controllers[i].get_float("trigger") > 0.65

func _clear_arena() -> void:
	if is_instance_valid(arena):
		arena.process_mode = Node.PROCESS_MODE_DISABLED
		for b in arena.batteries+[arena.enemy]:
			b.collision_layer = 0
			b.collision_mask = 0
		arena.queue_free()
		arena = null

func _pause() -> void:
	if flow != Flow.PLAY:
		return
	arena.release_hand(0)
	arena.release_hand(1)
	arena.safe_resume()
	get_tree().paused = true
	flow = Flow.PAUSE
	_recenter_menu()
	_update_menu()

func _calibrate() -> void:
	before_calibration = flow
	flow = Flow.CALIBRATE
	_recenter_menu()
	_update_menu()

func _update_menu() -> void:
	match flow:
		Flow.MENU:
			menu.text = "شدّة  /  SHADDA\nA ابدأ    •    Y ضبط القفازات\nTrigger إمساك • Grip شدّ • X / B تحرير\nأشر للمحطة واضغط Trigger لإرجاع البطارية"
		Flow.CONFIRM:
			menu.text = "تأكد أن الإطار على أرض مستوية وخالية من الأثاث\nلا يلزم لمس الأرض أو الجدار\nA ابدأ التجربة    •    B تعديل"
		Flow.PAUSE:
			menu.text = "متوقف\nتأكد أن المحطة ما زالت في موضعها\nA استئناف • X ضبط القفازات • B إعادة الوضع"
		Flow.CALIBRATE:
			menu.text = "ضبط القفازين\nعصا كل يد: الميل والاتجاه • Grip + العصا: اللف\nاضغط العصا للتبديل إلى الإزاحة\nA حفظ • B افتراضي • Y إلغاء"
		Flow.RESULT:
			menu.text = ("حميت الطاقة!" if arena.won else "فُقدت البطاريات")+"\nA العب مجددًا • Y ضبط القفازات"

func _result(_won: bool) -> void:
	flow = Flow.RESULT
	_recenter_menu()
	_update_menu()

func _docked(_hand: int) -> void:
	for controller in controllers:
		controller.trigger_haptic_pulse("haptic",0,0.16,0.07,0)

func _play_pose(i: int, pose_name: String) -> void:
	if players[i] == null or previous_pose[i] == pose_name:
		return
	for clip in players[i].get_animation_list():
		if clip == pose_name or clip.ends_with("/"+pose_name):
			players[i].play(clip,0.15)
			previous_pose[i] = pose_name
			return

func _apply_alignment() -> void:
	for i in range(alignments.size()):
		alignments[i].rotation_degrees = angles[i]
		var v: Array = cfg["glove_offset"]
		alignments[i].position = Vector3(float(v[0]),float(v[1]),float(v[2]))+offsets[i]

func _save_alignment() -> void:
	var file := ConfigFile.new()
	for i in range(2):
		file.set_value("hand_%d"%i,"angles",angles[i])
		file.set_value("hand_%d"%i,"offset",offsets[i])
	file.save("user://gauntlet_alignment.cfg")

func _load_alignment() -> void:
	var file := ConfigFile.new()
	angles = [Vector3.ZERO,Vector3.ZERO]
	offsets = [Vector3.ZERO,Vector3.ZERO]
	if file.load("user://gauntlet_alignment.cfg") == OK:
		for i in range(2):
			angles[i] = file.get_value("hand_%d"%i,"angles",Vector3.ZERO)
			offsets[i] = file.get_value("hand_%d"%i,"offset",Vector3.ZERO)

func _system_recentered() -> void:
	if flow == Flow.PLAY:
		_pause()
	_recenter_menu()

func _recenter_menu() -> void:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	studio.global_position = head.global_position+forward*1.6
	studio.look_at(head.global_position,Vector3.UP,true)
	menu.global_position = studio.global_position-Vector3.UP*0.08
	menu.look_at(head.global_position,Vector3.UP,true)

func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message,"SHADDA")
	get_tree().quit(1)

func _preview(delta: float) -> void:
	preview_time += delta
	if preview_stage == 0 and preview_time > 2.0:
		preview_stage = 1
		_capture("stage-c-intro.png")
	elif preview_stage == 1 and clock.finished:
		preview_stage = 2
		room.selected = Transform3D.IDENTITY
		room.clear = true
		room.draw_outline()
		room.outline.show()
		room.confirm_manual()
		pending_start = true
	elif preview_stage == 2 and preview_time > 7.0:
		preview_stage = 3
		_capture("stage-c-play.png")
		arena.grab(0,arena.enemy,arena.enemy.global_position,emitters[0])
		arena.tethers[0].rest_length *= 0.65
	elif preview_stage == 3 and preview_time > 8.5:
		preview_stage = 4
		_capture("stage-c-tether.png")
	elif preview_stage == 4 and preview_time > 9.0:
		preview_stage = 5
		var file := FileAccess.open("res://build/render-report.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"peak_draw_calls":peak_draw_calls,"budget":400,"quest_tested":false,"renderer":"desktop GL preview","scene":"two gloves, three cells, station, robot B, tether"},"\t"))
		file.close()
		get_tree().quit(0 if peak_draw_calls <= 400 else 1)

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/"+filename)
