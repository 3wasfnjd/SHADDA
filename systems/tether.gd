class_name Tether
extends Node3D
## One neon energy rope fired from a gauntlet. Visual = two camera-facing
## ribbons (hot core + wide glow) rebuilt every frame from TetherMath.rope_points.
## Logic = idle / flying / attached / snapping, with reel-in and tension.

enum State { IDLE, FLYING, ATTACHED, MISS, SNAP }

const SEGMENTS := 18
const RANGE := 6.5
const FLY_TIME := 0.11
const MISS_TIME := 0.28
const SNAP_TIME := 0.22

var state: int = State.IDLE
var target: Node3D = null            # Robot (CharacterBody3D) when attached
var anchor_node: Node3D = null       # TetherPoint on the robot
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

const ROPE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.12, 0.82, 1.0, 1.0);
uniform float alpha_scale = 1.0;
uniform float pulse_speed = 2.2;
uniform float core = 0.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float pulse = 0.78 + 0.22 * sin(UV.x * 22.0 - TIME * pulse_speed * 6.283);
	float a;
	vec3 rgb;
	if (core > 0.5) {
		a = (0.75 + 0.25 * facing) * pulse * alpha_scale * COLOR.a;
		rgb = mix(tint.rgb, vec3(1.0), 0.45) * a;
	} else {
		a = pow(facing, 1.7) * pulse * alpha_scale * COLOR.a * 0.55;
		rgb = tint.rgb * a;
	}
	ALBEDO = rgb;
	ALPHA = a;
}
"""

func _ready() -> void:
	var shader := Shader.new()
	shader.code = ROPE_SHADER
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = shader
	_core_mat.set_shader_parameter("core", 1.0)
	_core_mat.render_priority = 3
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = shader
	_glow_mat.set_shader_parameter("core", 0.0)
	_glow_mat.render_priority = 2
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


## Fires along `direction` from the gauntlet. Returns the robot that was hit, or null.
func fire(direction: Vector3, robots: Array) -> Node3D:
	if _origin == null or is_busy():
		return null
	var from := _origin.global_position
	var hit := _find_target(from, direction.normalized(), robots)
	_fly_from = from
	_timer = 0.0
	if hit == null:
		state = State.MISS
		_fly_to = from + direction.normalized() * 2.4
		visible = true
		return null
	target = hit
	anchor_node = hit.tether_anchor()
	_fly_to = anchor_node.global_position
	state = State.FLYING
	visible = true
	return hit


func _find_target(from: Vector3, direction: Vector3, robots: Array) -> Node3D:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RANGE, 2)
	var result := space.intersect_ray(query)
	if not result.is_empty() and result.collider != null and result.collider.has_method("tether_anchor"):
		return result.collider
	# Aim assist: nearest robot inside a narrow cone.
	var best: Node3D = null
	var best_score := 0.985   # cos(~10°)
	for robot in robots:
		if not is_instance_valid(robot) or not robot.can_be_tethered():
			continue
		var to: Vector3 = robot.tether_anchor().global_position - from
		var distance: float = to.length()
		if distance > RANGE or distance < 0.05:
			continue
		var score := direction.dot(to / distance)
		if score > best_score:
			best_score = score
			best = robot
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


## Called by the gauntlet every frame.
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
			var tip := _fly_to
			_draw(from, from.lerp(tip, 1.0 - t), rest_length, 0.05 * t, Neon.WHITE, 1.0 - t)
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
			rest_length = TetherMath.reel(rest_length, grip, delta)
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
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else from + Vector3.UP
	_core_mat.set_shader_parameter("tint", color)
	_glow_mat.set_shader_parameter("tint", color)
	_core_mat.set_shader_parameter("alpha_scale", alpha)
	_glow_mat.set_shader_parameter("alpha_scale", alpha)
	_build_ribbon(_core_mesh, points, eye, 0.011 + tension * 0.005)
	_build_ribbon(_glow_mesh, points, eye, 0.065 + tension * 0.03)


func _build_ribbon(mesh: ImmediateMesh, points: PackedVector3Array, _eye: Vector3, radius: float) -> void:
	# A 6-sided tube; unlike a camera-facing ribbon it stays visible when the
	# player looks straight down the rope.
	const SIDES := 6
	mesh.clear_surfaces()
	var count := points.size()
	if count < 2:
		return
	var frames_u: Array[Vector3] = []
	var frames_v: Array[Vector3] = []
	var u_axis := Vector3.ZERO
	for i in range(count):
		var direction: Vector3
		if i < count - 1:
			direction = points[i + 1] - points[i]
		else:
			direction = points[i] - points[i - 1]
		if direction.length_squared() < 1e-10:
			direction = Vector3.FORWARD
		direction = direction.normalized()
		if i == 0:
			var helper := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
			u_axis = direction.cross(helper).normalized()
		else:
			u_axis = (u_axis - direction * u_axis.dot(direction))
			if u_axis.length_squared() < 1e-8:
				u_axis = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
			u_axis = u_axis.normalized()
		frames_u.append(u_axis)
		frames_v.append(direction.cross(u_axis).normalized())
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count - 1):
		var u0 := float(i) / float(count - 1)
		var u1 := float(i + 1) / float(count - 1)
		for k in range(SIDES):
			var a0 := TAU * float(k) / SIDES
			var a1 := TAU * float(k + 1) / SIDES
			var n00 := frames_u[i] * cos(a0) + frames_v[i] * sin(a0)
			var n01 := frames_u[i] * cos(a1) + frames_v[i] * sin(a1)
			var n10 := frames_u[i + 1] * cos(a0) + frames_v[i + 1] * sin(a0)
			var n11 := frames_u[i + 1] * cos(a1) + frames_v[i + 1] * sin(a1)
			var p00 := points[i] + n00 * radius
			var p01 := points[i] + n01 * radius
			var p10 := points[i + 1] + n10 * radius
			var p11 := points[i + 1] + n11 * radius
			_vertex(mesh, p00, n00, u0)
			_vertex(mesh, p10, n10, u1)
			_vertex(mesh, p01, n01, u0)
			_vertex(mesh, p01, n01, u0)
			_vertex(mesh, p10, n10, u1)
			_vertex(mesh, p11, n11, u1)
	mesh.surface_end()


func _vertex(mesh: ImmediateMesh, p: Vector3, n: Vector3, u: float) -> void:
	mesh.surface_set_color(Color(1, 1, 1, 1))
	mesh.surface_set_normal(n)
	mesh.surface_set_uv(Vector2(u, 0.0))
	mesh.surface_add_vertex(p)
