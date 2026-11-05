extends Node3D
## Boot: OpenXR + passthrough, a fresh room scan, then the war. The studio
## logo appears exactly once: as the Meta system splash while the app loads
## (assets/ui/studio.png → vr_splash.png). There is no second in-game logo.
## The plane is flown entirely by hand (see PlayerPlane for the sticks);
## the flight-stick hand also points at the menu boards.
## Store behaviour: the game pauses when the Meta menu opens or the headset
## loses focus, and on the left menu button; boards re-centre on recenter.
## Settings (quality, refresh rate, audio, handedness…) come from Profile.
## Desktop "--preview" fakes a headset in a grey room so CI can render
## screenshots (which prove nothing about the Quest itself).

var xr: OpenXRInterface
var origin: XROrigin3D
var head: XRCamera3D
var controllers: Array[XRController3D] = []
var aims: Array[XRController3D] = []
var plane: PlayerPlane
var hud: Hud
var battle: Battle
var room_scan: RoomScan
var menus: Menus
var sun: DirectionalLight3D
var env: Environment

## Free flight for tuning takeoff and handling: no room scan, no enemies,
## a flat floor and a large open box around the player. Set true to bring
## back the mandatory Space Setup scan and the room war.
const ROOM_SCAN := false
var foreground := true
var positioned := false
var rendered := false
var failed := false
var started := false
var preview := false
var preview_mode := ""
var preview_t := 0.0
var preview_shots := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Profile.ensure()
	_setup_buses()
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	preview_mode = OS.get_environment("SAQR_PREVIEW")
	get_viewport().transparent_bg = true
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
	head.near = 0.02
	head.far = 50.0
	head.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	origin.add_child(head)
	var env_node := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.92)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	add_child(env_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.9)
	add_child(sun)
	for i in range(2):
		var c := XRController3D.new()
		c.tracker = &"left_hand" if i == 0 else &"right_hand"
		c.pose = &"grip"
		origin.add_child(c)
		controllers.append(c)
		c.button_pressed.connect(_button.bind(i))
		var a := XRController3D.new()
		a.tracker = c.tracker
		a.pose = &"aim"
		origin.add_child(a)
		aims.append(a)
	hud = Hud.new()
	controllers[0].add_child(hud)
	battle = Battle.new()
	battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(battle)
	menus = Menus.new()
	add_child(menus)
	menus.head = head
	menus.battle = battle
	battle.menus = menus
	menus.settings_changed.connect(apply_settings)
	battle.dusk_changed.connect(_on_dusk)
	plane = PlayerPlane.new()
	plane.hand = controllers[1]
	battle.add_child(plane)
	plane.visible = false
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		env.background_color = Color(0.62, 0.78, 0.92, 1.0)
		get_viewport().transparent_bg = false
		head.position = Vector3(0, 1.6, 0.6)
		head.fov = 78.0
		controllers[0].position = Vector3(-0.22, 1.25, 0.25)
		controllers[0].rotation_degrees = Vector3(-10, 25, 0)
		controllers[1].position = Vector3(0.18, 1.3, 0.3)
		aims[1].position = controllers[1].position
		_preview_room_visuals()
	else:
		if xr == null or (not xr.is_initialized() and not xr.initialize()):
			_stop("تعذر تشغيل OpenXR. أعد تشغيل التطبيق من النظارة.")
			return
		get_viewport().use_xr = true
		if not xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			_stop("Passthrough غير متاح. اللعبة تتطلب رؤية الغرفة.")
			return
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr.session_visible.connect(_on_focus_lost)
		xr.session_stopping.connect(_on_focus_lost)
		xr.pose_recentered.connect(_on_recentered)
	RenderingServer.frame_post_draw.connect(func(): rendered = true)
	apply_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		foreground = false
		_on_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		foreground = true


## The Meta menu opened or the headset came off: freeze the game behind a
## pause board (a store requirement — nothing runs while you're away).
func _on_focus_lost() -> void:
	if started and battle and battle.phase == Battle.Phase.PLAYING:
		battle.pause_game()


func _on_recentered() -> void:
	if menus:
		menus.recenter()


# --- settings -----------------------------------------------------------------------------

func _setup_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


static func _db(v: float) -> float:
	return -80.0 if v <= 0.01 else linear_to_db(v)


## Applies Profile settings: volumes, render quality, refresh rate, the
## language of open boards and the plane's assists.
func apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _db(float(Profile.get_s("music"))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _db(float(Profile.get_s("sfx"))))
	var q := str(Profile.get_s("quality"))
	var vp := get_viewport()
	# Kept conservative for the headset: 4× MSAA only on Ultra, native resolution.
	vp.msaa_3d = Viewport.MSAA_4X if q == "ultra" else Viewport.MSAA_2X
	vp.scaling_3d_scale = 1.0
	Debris.effects_high = str(Profile.get_s("effects")) == "high"
	Fx.budget = 60 if Debris.effects_high else 35
	if plane:
		plane.aim_assist = bool(Profile.get_s("aim_assist"))
		plane.leveler = bool(Profile.get_s("leveler"))
		plane.haptics = bool(Profile.get_s("haptics"))
	if xr and xr.is_initialized() and not preview:
		var want := float(int(Profile.get_s("refresh")))
		var rates := xr.get_available_display_refresh_rates()
		if not rates.has(want):
			want = 90.0 if rates.has(90.0) else (72.0 if rates.has(72.0) else 0.0)
		if want > 0.0:
			xr.display_refresh_rate = want
		# Fixed foveation: stronger on Balanced, gentle on Ultra; dynamic on all.
		if "foveation_level" in xr:
			xr.foveation_level = {"balanced": 3, "high": 2, "ultra": 1}.get(q, 2)
		if xr.has_method("set_cpu_level"):
			var lvl := OpenXRInterface.PERF_SETTINGS_LEVEL_SUSTAINED_HIGH if q != "balanced" else OpenXRInterface.PERF_SETTINGS_LEVEL_SUSTAINED_LOW
			xr.set_cpu_level(lvl)
			xr.set_gpu_level(lvl)
	if menus and menus.is_open() and menus.panel.rtl != (Lang.code() == "ar"):
		menus.refresh()


## Dusk mission: the real room dims and warms, the sun goes low and orange.
func _on_dusk(on: bool) -> void:
	if sun:
		sun.light_color = Color(1.0, 0.62, 0.38) if on else Color(1.0, 0.97, 0.9)
		sun.light_energy = 0.95 if on else 1.15
		sun.rotation_degrees = Vector3(-18, -60, 0) if on else Vector3(-55, -35, 0)
	if env:
		env.ambient_light_color = Color(0.62, 0.55, 0.7) if on else Color(0.82, 0.84, 0.92)
	if preview or not Engine.has_singleton("OpenXRFbPassthroughExtension"):
		return
	var pt = Engine.get_singleton("OpenXRFbPassthroughExtension")
	if pt.has_method("set_brightness_contrast_saturation"):
		if on:
			pt.call("set_brightness_contrast_saturation", -38.0, 1.15, 0.65)
		else:
			pt.call("set_brightness_contrast_saturation", 0.0, 1.0, 1.0)


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
	# Focus comes back with the XR session even if Android never says so.
	if not foreground and xr and not preview and xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED:
		foreground = true
	var ready := foreground and _tracking_ready()
	if ready and not positioned:
		positioned = true
		rendered = false
		return
	if positioned and (rendered or preview) and not started:
		started = true
		battle.build(head, plane, hud)
		battle.hands = controllers
		menus.hand = controllers[_stick()]
		plane.visible = true
		if preview:
			battle.on_room_ready(_free_flight_room() if _open_preview() else PREVIEW_ROOM.duplicate(true))
		else:
			if ROOM_SCAN:
				room_scan = RoomScan.new()
				add_child(room_scan)
				room_scan.room_ready.connect(battle.on_room_ready)
				room_scan.start(origin, head)
			else:
				battle.on_room_ready(_free_flight_room())
	if not started or not ready or battle.phase == Battle.Phase.SCANNING:
		return
	var tr := 0.0
	var gr := 0.0
	var inp := {}
	var stick := _stick()
	var other := 1 - stick
	if preview:
		var input := _preview_input(delta)
		tr = input[0]
		gr = input[1]
		inp = input[2]
	else:
		tr = controllers[stick].get_float("trigger")
		gr = controllers[stick].get_float("grip")
		var ls := controllers[other].get_vector2("thumbstick")
		var rs := controllers[stick].get_vector2("thumbstick")
		var sens := float(Profile.get_s("sensitivity"))
		var inv := -1.0 if bool(Profile.get_s("invert")) else 1.0
		inp = {
			"throttle_delta": _dead(ls.y),
			"yaw": _dead(ls.x),
			"pitch": clampf(_dead(rs.y) * inv * sens, -1.0, 1.0),     # stick up = climb / take off, down = descend / land
			"roll": clampf(_dead(rs.x) * sens, -1.0, 1.0),
			"boost": controllers[other].get_float("trigger") > 0.5,
			"brake": controllers[other].get_float("grip") > 0.5,
		}
	var aim := aims[stick].global_transform
	menus.hand = controllers[stick]
	if menus.is_open():
		menus.update(delta, aim.origin, -aim.basis.z, tr)
		tr = 0.0
		gr = 0.0
	elif battle.phase == Battle.Phase.PLAYING and not battle.paused:
		menus.update(delta, aim.origin, -aim.basis.z, 0.0)
	battle.update_controls(delta, aim.origin, -aim.basis.z, inp, tr, gr)


func _stick() -> int:
	return 0 if str(Profile.get_s("hand")) == "left" else 1


static func _dead(v: float) -> float:
	return 0.0 if absf(v) < 0.12 else signf(v) * (absf(v) - 0.12) / 0.88


func _button(action: StringName, hand_index: int) -> void:
	if not started or not foreground:
		return
	if menus.is_open() and action != &"menu_button":
		return
	battle.on_button(action, hand_index)



func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "SAQR")
	get_tree().quit(1)


## Floor from the tracking space (stage origin = floor); if the runtime gave a
## local space instead, assume the player stands 1.6 m tall.
func _free_flight_room() -> Dictionary:
	var floor_y := 0.0
	if head.global_position.y < 0.6:
		floor_y = head.global_position.y - 1.6
	return {"floor_y": floor_y, "ceiling_y": floor_y + 5.0, "walls": [], "openings": [], "surfaces": [], "blocks": [], "found": false, "free": true}


# --- desktop preview -------------------------------------------------------------------------

## A 4.4 × 4 m grey room with a window (front wall), a door (left wall) and a table.
static var PREVIEW_ROOM := {
	"floor_y": 0.0, "ceiling_y": 2.6, "found": true, "preview": true,
	"walls": [
		{"origin": Vector3(0, 0, -2.4), "normal": Vector3(0, 0, 1), "width": 4.4, "height": 2.6},
		{"origin": Vector3(2.2, 0, -0.4), "normal": Vector3(-1, 0, 0), "width": 4.0, "height": 2.6},
		{"origin": Vector3(-2.2, 0, -0.4), "normal": Vector3(1, 0, 0), "width": 4.0, "height": 2.6},
		{"origin": Vector3(0, 0, 1.6), "normal": Vector3(0, 0, -1), "width": 4.4, "height": 2.6},
	],
	"openings": [
		{"kind": "window", "center": Vector3(0.6, 1.45, -2.4), "base": Vector3(0.6, 1.0, -2.4), "normal": Vector3(0, 0, 1), "width": 1.1, "height": 0.9},
		{"kind": "door", "center": Vector3(-2.2, 1.0, -1.2), "base": Vector3(-2.2, 0.0, -1.2), "normal": Vector3(1, 0, 0), "width": 0.9, "height": 2.0},
	],
	"surfaces": [{"center": Vector3(1.2, 0.74, -1.3), "axis_x": Vector3(1, 0, 0), "axis_z": Vector3(0, 0, 1), "half": Vector2(0.45, 0.3), "label": "TABLE"}],
	"blocks": [{"xform": Transform3D(Basis.IDENTITY, Vector3(1.2, 0.37, -1.3)), "box": AABB(Vector3(-0.45, -0.37, -0.3), Vector3(0.9, 0.74, 0.6))}],
}


func _open_preview() -> bool:
	return preview_mode.begins_with("m") or preview_mode == "crash" or preview_mode == "soak"


func _preview_room_visuals() -> void:
	if _open_preview():
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.6, 0.5, 0.38)
		var fl0 := MeshInstance3D.new()
		var fp0 := PlaneMesh.new()
		fp0.size = Vector2(20, 20)
		fl0.mesh = fp0
		fl0.material_override = fm
		add_child(fl0)
		return
	var wall_m := StandardMaterial3D.new()
	wall_m.albedo_color = Color(0.86, 0.84, 0.8)
	wall_m.roughness = 0.95
	wall_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for w in PREVIEW_ROOM.walls:
		var n: Vector3 = w.normal
		var x := Vector3(n.z, 0, -n.x)
		var t := Transform3D(Basis(x, Vector3.UP, n), w.origin)
		var holes: Array = []
		for o in PREVIEW_ROOM.openings:
			var l: Vector3 = t.affine_inverse() * (o.base as Vector3)
			if absf(l.z) < 0.1:
				holes.append(Rect2(l.x - o.width * 0.5, l.y, o.width, o.height))
		for cell in WarMath.rect_minus_holes(Rect2(-w.width * 0.5, 0, w.width, w.height), holes):
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = (cell as Rect2).size
			q.mesh = qm
			q.material_override = wall_m
			add_child(q)
			q.transform = t * Transform3D(Basis.IDENTITY, Vector3((cell as Rect2).get_center().x, (cell as Rect2).get_center().y, 0.0))
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.62, 0.5, 0.38)
	var fl := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(4.4, 4.0)
	fl.mesh = fp
	fl.material_override = floor_m
	fl.position = Vector3(0, 0, -0.4)
	add_child(fl)
	var table := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.9, 0.74, 0.6)
	table.mesh = tb
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.55, 0.4, 0.28)
	table.material_override = tm
	table.position = Vector3(1.2, 0.37, -1.3)
	add_child(table)


## Scripted flights for the screenshots. Returns [trigger_r, grip_r, trigger_l].
func _preview_input(delta: float) -> Array:
	preview_t += delta
	if preview_mode == "menus":
		return _preview_menus(delta)
	if preview_mode == "soak":
		return _preview_soak(delta)
	if _open_preview():
		return _preview_campaign(delta)
	var out: Array = [0.0, 0.0, {}]
	var aim := aims[1]
	var point := Vector3(0, 1.2, -1.0)
	match battle.phase:
		Battle.Phase.MENU:
			point = battle._ui_root.global_position if battle._ui_root else point
			if preview_t > 1.0:
				battle.start_match()
				battle.auto_spawn = false
				preview_t = 1.0
		Battle.Phase.PLAYING:
			if preview_mode == "" and preview_t > 3.0 and preview_t < 3.05 and battle.enemies.is_empty():
				for k in ["balloon", "balloon", "balloon", "fighter", "fighter"]:
					battle.spawn(k)
			elif preview_mode == "ground" and preview_t > 3.0 and preview_t < 3.05 and battle.enemies.is_empty():
				battle.spawn("transport")
				battle.spawn("tank")
				battle.spawn("tank")
			elif preview_mode == "boss" and preview_t > 3.0 and preview_t < 3.05 and battle.enemies.is_empty():
				battle.spawn("bomber")
				battle.spawn("fighter")
			var target = null
			var best := INF
			for e in battle.enemies:
				if e.alive() and e.state == Enemy.State.ACTIVE:
					var d: float = e.hit_center().distance_to(plane.global_position)
					if d < best:
						best = d
						target = e
			if target and preview_t > 4.0:
				point = target.hit_center()
				if preview_mode == "ground" and target.kind in ["tank", "aa"]:
					point += Vector3(0, 0.8, 0)
			else:
				point = Vector3(sin(preview_t * 0.6) * 1.2, 1.3, -1.0 + cos(preview_t * 0.6) * 0.8)
			if preview_t > 4.5:
				out[0] = 1.0 if fmod(preview_t, 1.6) < 0.9 else 0.0
			if preview_t > 6.0 and preview_t < 7.0:
				out[1] = 1.0
			if preview_mode == "ground" and absf(preview_t - 8.0) < 0.02:
				plane.drop_bomb()
			if preview_t > 12.5:
				battle._finish(true)
	aim.global_transform = Transform3D(Basis.looking_at((point - controllers[1].global_position).normalized(), Vector3.UP), controllers[1].global_position)
	if battle.phase == Battle.Phase.PLAYING:
		var goal := point
		if plane.flight.ground and preview_t < 2.6:
			goal = plane.global_position + plane.forward() * 2.0
		out[2] = WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6))
	# Camera follows the action a little so the shots frame the plane.
	if battle.phase == Battle.Phase.PLAYING and plane.visible:
		var want := Basis.looking_at((plane.global_position - head.global_position).normalized(), Vector3.UP)
		head.global_basis = head.global_basis.slerp(want, minf(1.0, delta * 3.0))
	var shots: Array = {
		"": [[0.8, "menu"], [2.0, "takeoff"], [3.4, "climb"], [5.0, "enemies_in"], [6.6, "dogfight"], [7.6, "rockets"], [9.5, "fight"], [13.5, "results"]],
		"ground": [[4.5, "transport"], [6.5, "crate_drop"], [8.2, "bomb"], [10.0, "flak"], [12.0, "tanks"]],
		"boss": [[4.0, "bomber_in"], [6.0, "bomber"], [8.0, "bomber_fight"], [10.0, "bomber_engine"]],
	}[preview_mode]
	if preview_shots < shots.size() and preview_t >= shots[preview_shots][0]:
		var name: String = shots[preview_shots][1]
		preview_shots += 1
		_capture(name, preview_shots >= shots.size())
	return out


## SAQR_PREVIEW=menus: every board, one screenshot each.
var _boards := [["main", {}], ["missions", {}], ["brief", {"index": 2}], ["hangar", {"tab": "upgrades"}], ["hangar", {"tab": "weapons"}],
	["settings", {"tab": "game"}], ["settings", {"tab": "graphics"}], ["controls", {}], ["pause", {}],
	["debrief", {"index": 3, "stars": 2, "score": 4250, "time": 83.0, "kills": 7, "accuracy": 41, "hull": 72, "coins": 285, "record": true}],
	["failed", {"index": 4, "reason": "plane_lost"}], ["main_en", {}], ["brief_en", {"index": 2}], ["hangar_en", {"tab": "upgrades"}]]
var _board_open := -1
func _preview_menus(_delta: float) -> Array:
	head.fov = 56.0
	head.position = Vector3(0, 1.48, 0.6)
	var k := int(preview_t / 0.9)
	if k < _boards.size() and k != _board_open and battle.phase == Battle.Phase.MENU:
		_board_open = k
		var b: Array = _boards[k]
		var name: String = b[0]
		if name.ends_with("_en"):
			Profile.settings.lang = "en"
			name = name.trim_suffix("_en")
		if k == 0:
			Profile.progress.coins = 1240
			for id in ["training", "patrol", "convoy"]:
				Profile.progress.missions[id] = {"done": true, "stars": 3 if id != "convoy" else 2, "best": 3000}
			Profile.progress.owned.append("quad")
			Profile.progress.levels.engine = 2
			Profile.progress.levels.guns = 1
		menus.open(name, b[1])
	if preview_shots < _boards.size() and preview_t >= 0.9 * preview_shots + 0.55:
		preview_shots += 1
		_capture("board_%02d_%s" % [preview_shots, menus.screen], preview_shots >= _boards.size())
	var aim := aims[1]
	if menus.is_open():
		var target := menus.panel.global_transform * Vector3(0.0, -0.02, 0.0)
		aim.global_transform = Transform3D(Basis.looking_at((target - controllers[1].global_position).normalized(), Vector3.UP), controllers[1].global_position)
	return [0.0, 0.0, {}]


## SAQR_PREVIEW=soak: a long real sortie seen from a fixed standing head,
## for checking that nothing vanishes over minutes of play.
var _soak_shot := 0.0
var _soak_stall := 0.0
var _soak_idx := -1
func _preview_soak(delta: float) -> Array:
	var out: Array = [0.0, 0.0, {}]
	if battle.phase == Battle.Phase.MENU:
		if preview_t > 0.6:
			Profile.progress.seen_controls = true
			Profile.settings.difficulty = "easy"
			battle.start_mission(0)
		return out
	var c: Campaign = battle.campaign
	if c == null:
		return out
	if c.index != _soak_idx:
		_soak_idx = c.index
		_soak_stall = 0.0
	_soak_stall += delta
	var goal := c.center + Vector3(0, 1.3, 0)
	if plane.flight.ground:
		goal = plane.global_position + plane.forward() * 3.0 + Vector3(0, 1.0, 0)
	elif c._ring_i < c._rings.size():
		goal = c._rings[c._ring_i].pos
	else:
		var best := INF
		for e in battle.enemies:
			if e.alive() and e.state == Enemy.State.ACTIVE:
				var d: float = e.hit_center().distance_to(plane.global_position)
				if d < best:
					best = d
					goal = e.hit_center() + (Vector3(0, 0.7, 0) if e.kind in ["tank", "truck", "sam", "soldier", "fuel", "radar", "aa"] else Vector3.ZERO)
	# Keep the flow moving: after 25 s on one mission, help it along.
	if _soak_stall > 25.0 and c.mode == "play":
		if c._ring_i < c._rings.size():
			c._ring_i = c._rings.size() - 1
		for e in battle.enemies.duplicate():
			if e.alive() and e.state == Enemy.State.ACTIVE and randf() < 0.05:
				battle._kill(e, "gun")
		if c.id == "escort":
			c.t = maxf(c.t, Campaign.ESCORT_TIME)
	out[0] = 1.0 if fmod(preview_t, 1.4) < 0.8 else 0.0
	out[2] = WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6), 0.75)
	if plane.airborne() and fmod(preview_t, 5.0) < delta:
		plane.use_special()
	# A standing player looking ahead over the battle area.
	head.global_basis = Basis.looking_at((battle.arena_center + Vector3(0, 1.0, 0) - head.global_position).normalized(), Vector3.UP)
	_soak_shot += delta
	if _soak_shot >= 10.0:
		_soak_shot = 0.0
		preview_shots += 1
		var p := plane.global_position
		var finite := is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
		var visible_enemies := 0
		for e in battle.enemies:
			if e.is_visible_in_tree():
				visible_enemies += 1
		var deb := 0
		var shells := 0
		for n in battle.get_children():
			if n is Debris:
				deb += 1
		print("  breakdown: fx=%d debris=%d marks=%d enemies=%d" % [Fx.live, deb, Fx._marks.size(), battle.enemies.size()])
		print("SOAK t=%d mission=%d mode=%s plane=%s finite=%s state=%d visible=%s enemies=%d/%d friends=%d shots=%d nodes=%d objects_drawn=%d fps=%d" % [int(Time.get_ticks_msec() / 1000), c.index, c.mode, p, finite, plane.state, plane.visible and plane.model.root.visible, visible_enemies, battle.enemies.size(), battle.friends.size(), battle.shots.size(), get_tree().get_node_count(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), Engine.get_frames_per_second()])
		_capture("soak_%02d" % preview_shots, preview_shots >= 36 or battle.phase == Battle.Phase.RESULTS)
	return out


## SAQR_PREVIEW=m1..m8: jump into a mission over a plain floor and fly the
## autopilot at its objectives for screenshots. "crash": shot down.
var _jumped := false
func _preview_campaign(delta: float) -> Array:
	var out: Array = [0.0, 0.0, {}]
	var n := 3 if preview_mode == "crash" else int(preview_mode.substr(1)) - 1
	if battle.phase == Battle.Phase.MENU:
		if preview_t > 0.6:
			Profile.progress.seen_controls = true
			battle.start_mission(n)
		return out
	var c: Campaign = battle.campaign
	if c == null:
		return out
	if not _jumped:
		_jumped = true
		var f := -head.global_basis.z
		f.y = 0
		plane.flight = {"pos": head.global_position + f.normalized() * 1.2 + Vector3(0, -0.3, 0), "basis": Basis.looking_at(f.normalized(), Vector3.UP), "speed": 1.2, "sink": 0.0, "ground": false}
		c._intro_t = 2.0
		preview_t = 0.0
	if c.mode == "play" and c.t < 0.1:
		c.t = 6.0 if preview_mode != "m1" else 0.0
	var goal := c.center + Vector3(0, 1.3, 0)
	if c._ring_i < c._rings.size():
		goal = c._rings[c._ring_i].pos
	else:
		var best := INF
		for e in battle.enemies:
			if e.alive() and e.state == Enemy.State.ACTIVE:
				var d: float = e.hit_center().distance_to(plane.global_position)
				if d < best:
					best = d
					goal = e.hit_center() + (Vector3(0, 0.7, 0) if e.kind in ["tank", "truck", "sam", "soldier", "fuel", "radar", "aa"] else Vector3.ZERO)
	out[0] = 1.0 if preview_t > 3.0 and fmod(preview_t, 1.4) < 0.8 else 0.0
	out[2] = WarMath.autopilot(plane.flight, WarMath.clamp_into(goal, battle.box, 0.6, 0.6), 0.75)
	if plane.airborne() and preview_mode in ["m3", "m6"]:
		if fmod(preview_t, 4.0) < delta:
			plane.use_special()
	if preview_mode == "crash" and preview_t > 3.0 and plane.alive():
		plane.invincible = false
		plane.take_hit(999.0)
	var look_at_p := plane.global_position.lerp(goal, 0.3)
	if preview_mode == "crash" and not plane.alive():
		look_at_p = plane.global_position + Vector3(0, -0.3, 0)
	var want := Basis.looking_at((look_at_p - head.global_position).normalized(), Vector3.UP)
	head.global_basis = head.global_basis.slerp(want, minf(1.0, delta * 2.5))
	aims[1].global_transform = Transform3D(head.global_basis, controllers[1].global_position)
	var times := [0.4, 2.5, 5.0, 7.5, 10.0, 12.5] if preview_mode != "crash" else [3.05, 3.3, 3.8, 4.6, 6.0, 8.0]
	if preview_shots < times.size() and preview_t >= times[preview_shots]:
		preview_shots += 1
		_capture("%s_%d" % [preview_mode, preview_shots], preview_shots >= times.size())
	return out


func _capture(name: String, last: bool) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % name)
	print("preview %s: phase=%d wave=%d score=%d enemies=%d crates=%d shots=%d hp=%d state=%d" % [name, battle.phase, battle.wave, battle.score, battle.enemies.size(), battle.crates.size(), battle.shots.size(), int(plane.hp), plane.state])
	if last:
		get_tree().quit()
