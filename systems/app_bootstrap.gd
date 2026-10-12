extends Node3D

const IntroClock = preload("res://systems/intro_clock.gd")
var clock = IntroClock.new()
var xr: OpenXRInterface
var origin: XROrigin3D
var head: XRCamera3D
var studio: Sprite3D
var menu: Label3D
var controllers: Array[XRController3D] = []
var models: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var previous_pose: Array[String] = ["", ""]
var foreground: bool = true
var positioned: bool = false
var rendered: bool = false
var failed: bool = false
var preview: bool = false

func _ready() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	get_viewport().transparent_bg = true
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
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
	studio = Sprite3D.new()
	studio.texture = load("res://assets/ui/studio.png")
	studio.pixel_size = 0.00085
	studio.modulate.a = 0.0
	studio.no_depth_test = false
	add_child(studio)
	menu = Label3D.new()
	menu.font = load("res://assets/ui/DejaVuSans.ttf")
	menu.text = "شدّة  /  SHADDA\nاختبار القفازات\nTrigger: تصويب     Grip: قبضة\nA/X: فتح     B/Y: إعادة تمركز"
	menu.font_size = 42
	menu.pixel_size = 0.001
	menu.outline_size = 4
	menu.visible = false
	add_child(menu)
	for i in range(2):
		var controller := XRController3D.new()
		controller.tracker = &"left_hand" if i == 0 else &"right_hand"
		controller.pose = &"grip"
		origin.add_child(controller)
		controllers.append(controller)
		controller.button_pressed.connect(_button.bind(i))
		var side := "left" if i == 0 else "right"
		var packed: PackedScene = load("res://assets/models/runtime/shadda_gauntlet_%s.glb" % side)
		if packed == null:
			_stop("تعذر تحميل القفاز")
			return
		var model := packed.instantiate() as Node3D
		controller.add_child(model)
		model.rotation_degrees.x = -90.0
		model.position = Vector3(0,-0.02,0.05)
		model.hide()
		models.append(model)
		var found := model.find_children("*", "AnimationPlayer", true, false)
		players.append(found[0] as AnimationPlayer if not found.is_empty() else null)
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		head.position.y = 1.6
		controllers[0].position = Vector3(-0.23,1.28,-0.42)
		controllers[1].position = Vector3(0.23,1.28,-0.42)
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
	var ready := foreground and _tracking_ready()
	if ready and not positioned:
		_recenter()
		positioned = true
		rendered = false
		return
	studio.modulate.a = clock.tick(delta, ready and positioned and rendered)
	menu.visible = clock.finished and ready
	studio.visible = not clock.finished and ready
	for i in range(models.size()):
		models[i].visible = clock.finished and ready and (preview or controllers[i].get_is_active())
		if not models[i].visible:
			continue
		var grip := controllers[i].get_float("grip")
		var trigger := controllers[i].get_float("trigger")
		var pose_name := "Fist" if grip > 0.15 else ("Aim" if trigger > 0.15 else "Open")
		_play_pose(i, pose_name)
	if preview and clock.finished:
		if not FileAccess.file_exists("res://build/previews/stage-a.png"):
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/previews")
			get_viewport().get_texture().get_image().save_png("res://build/previews/stage-a.png")
			get_tree().quit()

func _play_pose(i: int, pose_name: String) -> void:
	if players[i] == null or previous_pose[i] == pose_name:
		return
	for clip in players[i].get_animation_list():
		if clip == pose_name or clip.ends_with("/" + pose_name):
			players[i].play(clip, 0.15)
			previous_pose[i] = pose_name
			return

func _button(action: StringName, hand_index: int) -> void:
	if not clock.finished or not foreground:
		return
	if action == &"by_button":
		_recenter()
	elif action == &"ax_button":
		_play_pose(hand_index, "Open")
		controllers[hand_index].trigger_haptic_pulse("haptic",0,0.18,0.06,0)

func _recenter() -> void:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	studio.global_position = head.global_position + forward * 1.6
	studio.look_at(head.global_position, Vector3.UP, true)
	menu.global_position = studio.global_position
	menu.look_at(head.global_position, Vector3.UP, true)

func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "SHADDA")
	get_tree().quit(1)
