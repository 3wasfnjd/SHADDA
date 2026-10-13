extends Node3D
## Boot sequence: OpenXR + passthrough, studio intro, then hands the frame
## loop to GameDirector. Desktop "--preview" mode fakes the headset so CI can
## render a flat screenshot of the arena (that preview proves nothing about
## the Quest; only the headset does).

const IntroClock = preload("res://systems/intro_clock.gd")

var clock = IntroClock.new()
var xr: OpenXRInterface
var origin: XROrigin3D
var head: XRCamera3D
var studio: Sprite3D
var controllers: Array[XRController3D] = []
var aim_controllers: Array[XRController3D] = []
var gauntlets: Array[Gauntlet] = []
var director: GameDirector
var room_scan: RoomScan
var foreground: bool = true
var positioned: bool = false
var rendered: bool = false
var failed: bool = false
var preview: bool = false
var preview_time: float = 0.0
var preview_shots: int = 0
var started: bool = false
var font: Font


func _ready() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	get_viewport().transparent_bg = true
	font = load("res://assets/ui/DejaVuSans.ttf")
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
	head.near = 0.03
	head.far = 60.0
	origin.add_child(head)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.82, 1.0)
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -30, 0)
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.96, 0.9)
	light.shadow_enabled = false
	add_child(light)
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
		var side := "left" if i == 0 else "right"
		var packed: PackedScene = load("res://assets/models/runtime/shadda_gauntlet_%s.glb" % side)
		if packed == null:
			_stop("تعذر تحميل القفاز")
			return
		var aim := XRController3D.new()
		aim.tracker = controller.tracker
		aim.pose = &"aim"
		origin.add_child(aim)
		aim_controllers.append(aim)
		var gauntlet := Gauntlet.create(i, packed)
		gauntlet.controller = controller
		gauntlet.aim_node = aim
		controller.add_child(gauntlet)
		gauntlet.visible = false
		gauntlets.append(gauntlet)
	director = GameDirector.new()
	add_child(director)
	director.visible = false
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		# Flat desktop stand-in for the room: dark backdrop so the neon reads.
		environment.background_color = Color(0.05, 0.06, 0.09, 1.0)
		get_viewport().transparent_bg = false
		head.position = Vector3(0, 1.6, 0)
		head.rotation_degrees.x = -36.0
		controllers[0].position = Vector3(-0.26, 1.18, -0.38)
		controllers[0].rotation_degrees = Vector3(-30, 8, 0)
		controllers[1].position = Vector3(0.26, 1.22, -0.38)
		controllers[1].rotation_degrees = Vector3(-12, -8, 0)
		for i in range(2):
			aim_controllers[i].position = controllers[i].position
			aim_controllers[i].rotation = controllers[i].rotation
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
	studio.visible = not clock.finished and ready
	if clock.finished and not started:
		started = true
		director.build(head, gauntlets)
		director.visible = true
		if preview:
			director.on_room_ready([], 0.0, false)
			director._rift_cursor = 1
		else:
			room_scan = RoomScan.new()
			add_child(room_scan)
			room_scan.room_ready.connect(director.on_room_ready)
			room_scan.start(origin, head)
	if not started:
		return
	for g in gauntlets:
		g.visible = ready and (preview or g.controller.get_is_active())
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
		director.adjust_floor(controllers[0].get_vector2("thumbstick").y, delta)
	director.update_hands(delta, triggers, grips)


func _button(action: StringName, hand_index: int) -> void:
	if not clock.finished or not foreground or director == null:
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


## Scripted desktop demo: place the station, let a raider emerge, rope it
## with the right hand and reel; screenshots land in build/previews/.
func _preview_input(delta: float, triggers: Array, grips: Array) -> void:
	preview_time += delta
	if preview_time > 0.6 and director.phase == GameDirector.Phase.PLACING:
		director.on_button(&"ax_button", 1)
		director.spawner.next_spawn = 0.0
	# Keep the right controller aimed at the first raider's crown.
	if not director.robots.is_empty() and is_instance_valid(director.robots[0]):
		var crown: Vector3 = director.robots[0].tether_anchor().global_position
		if crown.distance_to(controllers[1].global_position) > 0.2:
			controllers[1].look_at(crown, Vector3.UP)
			aim_controllers[1].global_transform = controllers[1].global_transform
	if preview_time > 9.4:
		triggers[1] = 1.0
	if preview_time > 11.2:
		grips[1] = 1.0
	var shots := [[0.4, "placing"], [5.6, "emerge"], [8.6, "walk"], [11.0, "rope"], [12.4, "pull"]]
	if preview_shots < shots.size() and preview_time >= shots[preview_shots][0]:
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/previews")
		get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % shots[preview_shots][1])
		var right := gauntlets[1]
		print("preview shot %s: phase=%d tether=%d tension=%0.2f robots=%d" % [shots[preview_shots][1], director.phase, right.tether.state, right.tether.tension, director.robots.size()])
		preview_shots += 1
		if preview_shots >= shots.size():
			get_tree().quit()


func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "SHADDA")
	get_tree().quit(1)
