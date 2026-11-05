extends Node3D
## Boot: OpenXR + passthrough, a fresh room scan, then the war. The studio
## logo appears exactly once: as the Meta system splash while the app loads
## (assets/ui/studio.png → vr_splash.png). There is no second in-game logo.
## The plane is flown entirely by hand (see PlayerPlane for the sticks);
## the right controller also points at the menu buttons.
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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.92)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
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
	add_child(battle)
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
		if xr.get_available_display_refresh_rates().has(72.0):
			xr.display_refresh_rate = 72.0
	RenderingServer.frame_post_draw.connect(func(): rendered = true)


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
		positioned = true
		rendered = false
		return
	if positioned and (rendered or preview) and not started:
		started = true
		battle.build(head, plane, hud)
		battle.hands = controllers
		plane.visible = true
		if preview:
			battle.on_room_ready(PREVIEW_ROOM.duplicate(true))
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
	if preview:
		var input := _preview_input(delta)
		tr = input[0]
		gr = input[1]
		inp = input[2]
	else:
		tr = controllers[1].get_float("trigger")
		gr = controllers[1].get_float("grip")
		var ls := controllers[0].get_vector2("thumbstick")
		var rs := controllers[1].get_vector2("thumbstick")
		inp = {
			"throttle_delta": _dead(ls.y),
			"yaw": _dead(ls.x),
			"pitch": -_dead(rs.y),          # pull back = nose up
			"roll": _dead(rs.x),
			"boost": controllers[0].get_float("trigger") > 0.5,
			"brake": controllers[0].get_float("grip") > 0.5,
		}
	var aim := aims[1].global_transform
	battle.update_controls(delta, aim.origin, -aim.basis.z, inp, tr, gr)


static func _dead(v: float) -> float:
	return 0.0 if absf(v) < 0.12 else signf(v) * (absf(v) - 0.12) / 0.88


func _button(action: StringName, hand_index: int) -> void:
	if not started or not foreground:
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


func _preview_room_visuals() -> void:
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


func _capture(name: String, last: bool) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % name)
	print("preview %s: phase=%d wave=%d score=%d enemies=%d crates=%d shots=%d hp=%d state=%d" % [name, battle.phase, battle.wave, battle.score, battle.enemies.size(), battle.crates.size(), battle.shots.size(), int(plane.hp), plane.state])
	if last:
		get_tree().quit()
