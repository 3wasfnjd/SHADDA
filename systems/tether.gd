class_name Tether
extends Node3D
## One neon energy rope fired from a gauntlet. Visual = hot core tube + wide
## glow tube rebuilt every frame from TetherMath.rope_points.
## Logic = idle / flying / attached / miss / snap, with reel-in and tension.
## Targets implement: tether_anchor(), can_be_tethered(), attach_tether(t),
## detach_tether(t), on_tether_snapped().

enum State { IDLE, FLYING, ATTACHED, MISS, SNAP }

const SEGMENTS := 18
const RANGE := 7.0
const FLY_TIME := 0.1
const MISS_TIME := 0.28
const SNAP_TIME := 0.22

var state: int = State.IDLE
var target: Node3D = null
var anchor_node: Node3D = null
var rest_length: float = 1.0
var tension: float = 0.0
var reeling: float = 0.0
var hand_index: int = 0
var snap_timer: float = 0.0
var _timer: float = 0.0
var _fly_from: Vector3
var _fly_to: Vector3
var _time: float = 0.0
var _origin: Node3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _core_mesh := ImmediateMesh.new()
var _glow_mesh := ImmediateMesh.new()
var _core_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _tip: MeshInstance3D


func _ready() -> void:
	_core_mat = Neon.glow_material(Neon.CYAN, true)
	_glow_mat = Neon.glow_material(Neon.CYAN, false)
	_core = MeshInstance3D.new()
	_core.mesh = _core_mesh
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.extra_cull_margin = 16.0
	_glow = MeshInstance3D.new()
	_glow.mesh = _glow_mesh
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.extra_cull_margin = 16.0
	add_child(_core)
	add_child(_glow)
	_tip = Neon.make_halo(Neon.CYAN, 0.16, 0.9)
	_tip.visible = false
	add_child(_tip)
	top_level = true
	visible = false


func setup(origin: Node3D, index: int) -> void:
	_origin = origin
	hand_index = index


func is_busy() -> bool:
	return state == State.FLYING or state == State.ATTACHED


## Fires along `direction` from `aim_from` (the controller's aim pose); the
## rope itself is drawn from the gauntlet emitter. Returns what was hit.
func fire(direction: Vector3, targets: Array, aim_from: Vector3 = Vector3.INF) -> Node3D:
	if _origin == null or is_busy():
		return null
	var from := _origin.global_position
	var ray_from := aim_from if aim_from != Vector3.INF else from
	var hit := _find_target(ray_from, direction.normalized(), targets)
	_fly_from = from
	_timer = 0.0
	if hit == null:
		state = State.MISS
		_fly_to = from + direction.normalized() * 2.6
		visible = true
		return null
	target = hit
	anchor_node = hit.tether_anchor()
	_fly_to = anchor_node.global_position
	state = State.FLYING
	visible = true
	return hit


## What a shot fired now would hit (for the lock-on reticle).
func peek_target(aim_from: Vector3, direction: Vector3, targets: Array) -> Node3D:
	return _find_target(aim_from, direction.normalized(), targets)


func _find_target(from: Vector3, direction: Vector3, targets: Array) -> Node3D:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE, 2)
	var result := space.intersect_ray(query)
	if not result.is_empty() and result.collider != null and result.collider.has_method("tether_anchor") and result.collider.can_be_tethered():
		return result.collider
	var best: Node3D = null
	var best_score := 0.972   # cos(~13.5°) aim assist
	for t in targets:
		if not is_instance_valid(t) or not t.can_be_tethered():
			continue
		var to: Vector3 = t.tether_anchor().global_position - from
		var distance: float = to.length()
		if distance > RANGE or distance < 0.05:
			continue
		var score := direction.dot(to / distance)
		if score > best_score:
			best_score = score
			best = t
	return best


func release() -> void:
	if state == State.ATTACHED and is_instance_valid(target):
		target.detach_tether(self)
	target = null
	anchor_node = null
	state = State.IDLE
	tension = 0.0
	snap_timer = 0.0
	visible = false
	_tip.visible = false


func snap() -> void:
	if state == State.ATTACHED and is_instance_valid(target):
		target.detach_tether(self)
		if target.has_method("on_tether_snapped"):
			target.on_tether_snapped()
	target = null
	anchor_node = null
	state = State.SNAP
	_timer = 0.0
	_tip.visible = false


func update(delta: float, grip: float) -> void:
	_time += delta
	if _origin == null:
		return
	var from := _origin.global_position
	reeling = grip
	match state:
		State.IDLE:
			return
		State.MISS:
			_timer += delta
			var t := _timer / MISS_TIME
			if t >= 1.0:
				release()
				return
			var reach := 1.0 - absf(t * 2.0 - 1.0)
			var tip := from.lerp(_fly_to, reach)
			_draw(from, tip, from.distance_to(tip) + 0.2, 0.012 * reach, Neon.CYAN, 0.45 * (1.0 - t))
			_tip.visible = true
			_tip.global_position = tip
		State.SNAP:
			_timer += delta
			var t := _timer / SNAP_TIME
			if t >= 1.0:
				release()
				return
			_draw(from, from.lerp(_fly_to, 1.0 - t), rest_length, 0.05 * t, Neon.WHITE, 1.0 - t)
		State.FLYING:
			_timer += delta
			var t := clampf(_timer / FLY_TIME, 0.0, 1.0)
			if not is_instance_valid(target) or not target.can_be_tethered():
				release()
				return
			_fly_to = anchor_node.global_position
			var tip := _fly_from.lerp(_fly_to, t)
			_draw(from, tip, from.distance_to(tip) + 0.1, 0.0, Neon.CYAN, 0.9)
			_tip.visible = true
			_tip.global_position = tip
			if t >= 1.0:
				state = State.ATTACHED
				rest_length = maxf(TetherMath.MIN_REST, from.distance_to(_fly_to))
				snap_timer = 0.0
				target.attach_tether(self)
		State.ATTACHED:
			if not is_instance_valid(target) or not target.can_be_tethered():
				release()
				return
			var anchor := anchor_node.global_position
			# Winch clutch: reeling slows as tension climbs instead of snapping.
			rest_length = TetherMath.reel(rest_length, grip * clampf(1.0 - tension * 1.1, 0.0, 1.0), delta)
			var distance := from.distance_to(anchor)
			tension = TetherMath.tension(distance, rest_length)
			snap_timer = TetherMath.snap_timer(snap_timer, tension, delta)
			if TetherMath.should_snap(snap_timer):
				_fly_to = anchor
				snap()
				return
			var color := TetherMath.rope_color(tension)
			_draw(from, anchor, rest_length, 0.004 + tension * 0.01, color, 0.8 + tension * 0.2)
			_tip.visible = true
			_tip.global_position = anchor
			Neon.set_halo_color(_tip, color, 0.7)


func hand_position() -> Vector3:
	return _origin.global_position if _origin else global_position


func _draw(from: Vector3, to: Vector3, rest: float, wobble: float, color: Color, alpha: float) -> void:
	var points := TetherMath.rope_points(from, to, rest, SEGMENTS, wobble, _time)
	_core_mat.set_shader_parameter("tint", color)
	_glow_mat.set_shader_parameter("tint", color)
	_core_mat.set_shader_parameter("alpha_scale", alpha)
	_glow_mat.set_shader_parameter("alpha_scale", alpha)
	var core_r := 0.007 + tension * 0.003
	var glow_r := 0.036 + tension * 0.015
	Neon.build_tube(_core_mesh, points, func(_t): return core_r)
	Neon.build_tube(_glow_mesh, points, func(_t): return glow_r)
