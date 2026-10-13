class_name Gauntlet
extends Node3D
## One player hand: the rigged gauntlet model, its finger poses, neon light
## states, the tether it fires and the power cell it can carry.
## Controls — Trigger: fire/hold rope. Grip: reel the rope in, or grab/hold a
## loose cell. A/X: let go. B/Y: re-centre (handled by the director).

enum Light { READY, CONNECTED, HIGH_TENSION, RELEASE }

const GRAB_RADIUS := 0.2
const DOCK_RADIUS := 0.14

var index: int = 0
var controller: XRController3D
var model: Node3D
var anim: AnimationPlayer
var tether: Tether
var tether_origin: Node3D
var aim_axis: Node3D
var grip_anchor: Node3D
var held_cell: PowerCell = null
var director: Node = null
var _pose: String = ""
var _emitters: Dictionary = {}
var _light: int = Light.READY
var _light_pulse: float = 0.0
var _halo: MeshInstance3D
var _trigger_was_down: bool = false
var _haptic_cooldown: float = 0.0
var trigger: float = 0.0
var grip: float = 0.0


static func create(hand_index: int, scene: PackedScene) -> Gauntlet:
	var g := Gauntlet.new()
	g.index = hand_index
	g.model = scene.instantiate() as Node3D
	return g


func _ready() -> void:
	add_child(model)
	model.rotation_degrees.x = -90.0
	model.position = Vector3(0, -0.02, 0.05)
	_emitters = Neon.restyle(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	tether_origin = model.find_child("TetherOrigin", true, false) as Node3D
	aim_axis = model.find_child("AimAxis", true, false) as Node3D
	grip_anchor = model.find_child("GripAnchor", true, false) as Node3D
	if tether_origin == null:
		tether_origin = Node3D.new()
		tether_origin.position = Vector3(0, 0.078, 0.034)
		model.add_child(tether_origin)
	if aim_axis == null:
		aim_axis = tether_origin
	if grip_anchor == null:
		grip_anchor = tether_origin
	tether = Tether.new()
	add_child(tether)
	tether.setup(tether_origin, index)
	_halo = Neon.make_halo(Neon.CYAN, 0.12, 0.35)
	tether_origin.add_child(_halo)
	play_pose("Open")
	set_light(Light.READY)


## Fingers pointing direction in world space (GLB fingers are +Y).
func aim_direction() -> Vector3:
	return aim_axis.global_basis.y.normalized()


func hand_position() -> Vector3:
	return grip_anchor.global_position


func update(delta: float, trigger_value: float, grip_value: float, robots: Array, cells: Array, station: Station, allow_play: bool) -> void:
	trigger = trigger_value
	grip = grip_value
	_haptic_cooldown = maxf(0.0, _haptic_cooldown - delta)
	var trigger_down := trigger > 0.55
	if allow_play:
		if trigger_down and not _trigger_was_down and held_cell == null and not tether.is_busy():
			var hit := tether.fire(aim_direction(), robots)
			_haptic(0.35 if hit else 0.12, 0.05)
		if not trigger_down and tether.state == Tether.State.ATTACHED:
			tether.release()
			set_light(Light.RELEASE)
		_update_cell(delta, cells, station)
	elif tether.is_busy():
		tether.release()
	_trigger_was_down = trigger_down
	tether.update(delta, grip)
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
		set_light(Light.HIGH_TENSION if tether.tension > 0.55 else Light.CONNECTED)
		var amplitude := TetherMath.haptic_amplitude(tether.tension, grip > 0.3)
		if amplitude > 0.05 and _haptic_cooldown <= 0.0:
			_haptic(amplitude, 0.08)
			_haptic_cooldown = 0.08
	elif tether.state == Tether.State.SNAP:
		set_light(Light.RELEASE)
	elif _light != Light.READY and tether.state == Tether.State.IDLE:
		_light_pulse += delta
		if _light_pulse > 0.4:
			set_light(Light.READY)
	_apply_light(delta)


func _update_cell(delta: float, cells: Array, station: Station) -> void:
	if held_cell:
		held_cell.global_transform = grip_anchor.global_transform
		held_cell.global_rotation = global_rotation + Vector3(-PI * 0.5, 0, 0)
		var socket := station.nearest_free_socket(held_cell.global_position, DOCK_RADIUS)
		if grip < 0.3 or socket >= 0:
			var cell := held_cell
			held_cell = null
			if socket >= 0:
				station.dock(cell, socket)
				_haptic(0.6, 0.12)
				if director:
					director.call("on_cell_docked", cell)
			else:
				cell.drop_at(cell.global_position)
		return
	if grip > 0.6:
		var hand := hand_position()
		for cell in cells:
			if cell.is_available_for_grab() and cell.grab_position().distance_to(hand) < GRAB_RADIUS:
				if tether.is_busy():
					tether.release()
				var parent: Node = cell.get_parent()
				if parent:
					parent.remove_child(cell)
				add_child(cell)
				cell.set_held(index)
				held_cell = cell
				_haptic(0.5, 0.08)
				break


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
	var halo := 0.3
	match _light:
		Light.CONNECTED:
			cyan = Neon.WHITE.lerp(Neon.CYAN, 0.5)
			amber = Neon.AMBER
			halo = 0.6
		Light.HIGH_TENSION:
			cyan = Neon.WHITE
			amber = Neon.WHITE.lerp(Neon.AMBER, 0.4)
			halo = 0.9
		Light.RELEASE:
			cyan = Neon.CYAN_DIM
			amber = Neon.AMBER_DIM
			halo = 0.08
	if _emitters.has("M_Cyan_Emitter"):
		var m := _emitters["M_Cyan_Emitter"] as StandardMaterial3D
		m.albedo_color = m.albedo_color.lerp(cyan, delta * 10.0)
	if _emitters.has("M_Amber_Emitter"):
		var m := _emitters["M_Amber_Emitter"] as StandardMaterial3D
		m.albedo_color = m.albedo_color.lerp(amber, delta * 10.0)
	Neon.set_halo_color(_halo, cyan, halo)


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
