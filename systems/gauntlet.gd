class_name Gauntlet
extends Node3D
## One player hand: rigged gauntlet model, finger poses, neon light states,
## the rope, and power-cell handling.
## Trigger: fire/hold the rope (aimed along the controller's aim pose, with a
## faint guide while the trigger is half-pressed). Grip: reel the rope in,
## grab a loose cell within reach (or pull one in from up to half a metre),
## or crush a roped raider that is within arm's reach. A/X: let go.

enum Light { READY, CONNECTED, HIGH_TENSION, RELEASE }

const GRAB_RADIUS := 0.3
const MAGNET_RADIUS := 0.55
const DOCK_RADIUS := 0.16
const CRUSH_REACH := 0.55

var index: int = 0
var controller: XRController3D
var aim_node: Node3D                     # controller with the OpenXR "aim" pose
var model: Node3D
var anim: AnimationPlayer
var tether: Tether
var tether_origin: Node3D
var grip_anchor: Node3D
var held_cell: PowerCell = null
var director: Node = null
var trigger: float = 0.0
var grip: float = 0.0
var _pose: String = ""
var _emitters: Dictionary = {}
var _light: int = Light.READY
var _light_pulse: float = 0.0
var _halo: MeshInstance3D
var _guide: MeshInstance3D
var _guide_mesh := ImmediateMesh.new()
var _trigger_was_down: bool = false
var _grip_was_down: bool = false
var _haptic_cooldown: float = 0.0
var _creak_timer: float = 0.0
var _refire_timer: float = 0.0


static func create(hand_index: int, scene: PackedScene) -> Gauntlet:
	var g := Gauntlet.new()
	g.index = hand_index
	g.model = scene.instantiate() as Node3D
	return g


func _ready() -> void:
	add_child(model)
	model.rotation_degrees.x = -90.0
	model.position = Vector3(0, -0.025, 0.04)
	_emitters = Neon.restyle(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	tether_origin = model.find_child("TetherOrigin", true, false) as Node3D
	grip_anchor = model.find_child("GripAnchor", true, false) as Node3D
	if tether_origin == null:
		tether_origin = Node3D.new()
		tether_origin.position = Vector3(0, 0.078, 0.034)
		model.add_child(tether_origin)
	if grip_anchor == null:
		grip_anchor = tether_origin
	tether = Tether.new()
	add_child(tether)
	tether.setup(tether_origin, index)
	_halo = Neon.make_halo(Neon.CYAN, 0.1, 0.3)
	tether_origin.add_child(_halo)
	_guide = MeshInstance3D.new()
	_guide.mesh = _guide_mesh
	_guide.top_level = true
	_guide.material_override = Neon.halo_material(Neon.CYAN, 0.0)
	(_guide.material_override as StandardMaterial3D).albedo_texture = null
	(_guide.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	(_guide.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.extra_cull_margin = 16.0
	add_child(_guide)
	play_pose("Open")
	set_light(Light.READY)


## Direction the controller points (OpenXR aim pose, -Z), falling back to the fingers.
func aim_direction() -> Vector3:
	if aim_node:
		return -aim_node.global_basis.z.normalized()
	return -global_basis.z.normalized()


func aim_origin() -> Vector3:
	return aim_node.global_position if aim_node else tether_origin.global_position


func hand_position() -> Vector3:
	return grip_anchor.global_position


func update(delta: float, trigger_value: float, grip_value: float, targets: Array, cells: Array, station: Station, allow_play: bool) -> void:
	trigger = trigger_value
	grip = grip_value
	_haptic_cooldown = maxf(0.0, _haptic_cooldown - delta)
	var trigger_down := trigger > 0.55
	var grip_down := grip > 0.6
	if allow_play:
		_refire_timer = maxf(0.0, _refire_timer - delta)
		var want_fire := trigger_down and held_cell == null and not tether.is_busy() and (not _trigger_was_down or (tether.state == Tether.State.IDLE and _refire_timer <= 0.0))
		if want_fire:
			var hit := tether.fire(aim_direction(), targets, aim_origin())
			_haptic(0.35 if hit else 0.12, 0.05)
			_cue("fire")
			_refire_timer = 0.45
		if not trigger_down and tether.state == Tether.State.ATTACHED:
			tether.release()
			set_light(Light.RELEASE)
			_cue("release")
		_update_cell(delta, cells, station, grip_down)
		if grip_down and not _grip_was_down:
			_try_crush()
	elif tether.is_busy():
		tether.release()
	_trigger_was_down = trigger_down
	_grip_was_down = grip_down
	tether.update(delta, grip)
	_auto_grab_roped_cell()
	# Pose.
	var pose := "Open"
	if held_cell:
		pose = "Fist"
	elif tether.state == Tether.State.ATTACHED:
		pose = "Pull" if grip > 0.3 else "TetherGrip"
	elif trigger > 0.2:
		pose = "Aim"
	elif grip > 0.3:
		pose = "Fist"
	play_pose(pose)
	# Lights and haptics.
	if tether.state == Tether.State.ATTACHED:
		if _light == Light.READY or _light == Light.RELEASE:
			_cue("attach")
		set_light(Light.HIGH_TENSION if tether.tension > 0.55 else Light.CONNECTED)
		var amplitude := TetherMath.haptic_amplitude(tether.tension, grip > 0.3)
		if amplitude > 0.05 and _haptic_cooldown <= 0.0:
			_haptic(amplitude, 0.08)
			_haptic_cooldown = 0.08
		_creak_timer -= delta
		if tether.tension > 0.6 and _creak_timer <= 0.0:
			_creak_timer = randf_range(0.25, 0.5)
			_cue("creak")
	elif tether.state == Tether.State.SNAP:
		if _light != Light.RELEASE:
			_cue("snap")
			_haptic(0.9, 0.15)
		set_light(Light.RELEASE)
	elif _light != Light.READY and tether.state == Tether.State.IDLE:
		_light_pulse += delta
		if _light_pulse > 0.4:
			set_light(Light.READY)
	_apply_light(delta)
	_draw_guide(allow_play and held_cell == null and not tether.is_busy() and trigger > 0.08)


func _update_cell(delta: float, cells: Array, station: Station, grip_down: bool) -> void:
	if held_cell:
		held_cell.global_transform = grip_anchor.global_transform
		held_cell.global_rotation = global_rotation + Vector3(-PI * 0.5, 0, 0)
		var socket := station.nearest_free_socket(held_cell.global_position, DOCK_RADIUS) if not station.placing else -1
		if grip < 0.3 or socket >= 0:
			var cell := held_cell
			held_cell = null
			if socket >= 0:
				station.dock(cell, socket)
				_haptic(0.6, 0.12)
				if director:
					director.call("on_cell_docked", cell)
			else:
				var toss := Vector3.ZERO
				if controller and controller.has_method("get_pose"):
					var pose := controller.get_pose()
					if pose:
						toss = pose.linear_velocity
				cell.drop_at(cell.global_position, toss)
		return
	if not grip_down:
		return
	var hand := hand_position()
	var nearest: PowerCell = null
	var nearest_d := MAGNET_RADIUS
	for cell in cells:
		if not cell.is_available_for_grab():
			continue
		var d := minf(cell.grab_position().distance_to(hand), cell.global_position.distance_to(hand))
		if d < nearest_d:
			nearest_d = d
			nearest = cell
	if nearest == null:
		return
	if nearest_d <= GRAB_RADIUS:
		_take_cell(nearest)
	else:
		# Magnet: a loose cell within half a metre slides toward the closed fist.
		var to_hand := hand - nearest.global_position
		nearest.sleeping = false
		nearest.apply_central_impulse(to_hand.normalized() * delta * 4.5 * nearest.mass)


func _take_cell(cell: PowerCell) -> void:
	if tether.is_busy():
		tether.release()
	var parent: Node = cell.get_parent()
	if parent:
		parent.remove_child(cell)
	add_child(cell)
	cell.set_held(index)
	held_cell = cell
	_haptic(0.5, 0.08)
	_cue("grab")


## A cell reeled in by the rope lands in the hand automatically.
func _auto_grab_roped_cell() -> void:
	if tether.state != Tether.State.ATTACHED or held_cell != null:
		return
	var target := tether.target
	if target is PowerCell and target.is_available_for_grab() and target.global_position.distance_to(hand_position()) < GRAB_RADIUS:
		tether.release()
		_take_cell(target)


func _try_crush() -> void:
	if tether.state != Tether.State.ATTACHED:
		return
	var target := tether.target
	if target is Robot and target.tether_anchor().global_position.distance_to(hand_position()) < CRUSH_REACH:
		_haptic(1.0, 0.25)
		_cue("capture")
		target.crush()


func _draw_guide(show: bool) -> void:
	_guide.visible = show
	if not show:
		return
	var from := tether_origin.global_position
	var to := aim_origin() + aim_direction() * 3.0
	var strength := clampf((trigger - 0.08) / 0.4, 0.15, 1.0)
	_guide_mesh.clear_surfaces()
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_guide_mesh.surface_set_color(Color(Neon.CYAN.r, Neon.CYAN.g, Neon.CYAN.b, 0.35 * strength))
	_guide_mesh.surface_add_vertex(from)
	_guide_mesh.surface_set_color(Color(Neon.CYAN.r, Neon.CYAN.g, Neon.CYAN.b, 0.0))
	_guide_mesh.surface_add_vertex(to)
	_guide_mesh.surface_end()


func play_pose(pose_name: String) -> void:
	if anim == null or _pose == pose_name:
		return
	for clip in anim.get_animation_list():
		if clip == pose_name or clip.ends_with("/" + pose_name):
			anim.play(clip, 0.12)
			_pose = pose_name
			return


func set_light(light: int) -> void:
	if _light == light:
		return
	_light = light
	_light_pulse = 0.0


func _apply_light(delta: float) -> void:
	var cyan := Neon.CYAN
	var amber := Neon.AMBER_DIM
	var halo := 0.25
	match _light:
		Light.CONNECTED:
			cyan = Neon.WHITE.lerp(Neon.CYAN, 0.5)
			amber = Neon.AMBER
			halo = 0.5
		Light.HIGH_TENSION:
			cyan = Neon.WHITE
			amber = Neon.WHITE.lerp(Neon.AMBER, 0.4)
			halo = 0.8
		Light.RELEASE:
			cyan = Neon.CYAN_DIM
			amber = Neon.AMBER_DIM
			halo = 0.06
	if _emitters.has("M_Cyan_Emitter"):
		var m := _emitters["M_Cyan_Emitter"] as StandardMaterial3D
		m.albedo_color = m.albedo_color.lerp(cyan, delta * 10.0)
	if _emitters.has("M_Amber_Emitter"):
		var m := _emitters["M_Amber_Emitter"] as StandardMaterial3D
		m.albedo_color = m.albedo_color.lerp(amber, delta * 10.0)
	Neon.set_halo_color(_halo, cyan, halo)


func _cue(name: String) -> void:
	if director:
		director.call("cue", name, hand_position())


func _haptic(amplitude: float, seconds: float) -> void:
	if controller:
		controller.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


func release_everything() -> void:
	if tether.is_busy():
		tether.release()
	if held_cell:
		var cell := held_cell
		held_cell = null
		cell.drop_at(cell.global_position)
