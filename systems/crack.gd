class_name Crack
extends Node3D
## A glowing fracture on a real wall (or floating where a wall should be when
## the room is unknown). Procedural: a jagged neon ring, a dark core disc and
## a violet bloom. +Z points into the room; the ring lies in the local XY plane
## at ~1.1 m above the mount point.

enum Mode { CLOSED, OPENING, OPEN, CLOSING }

const OPEN_SECONDS := 0.9
const CLOSE_SECONDS := 0.6
const HEIGHT := 1.1

var mode: int = Mode.CLOSED
var on_ceiling: bool = false
var hum: AudioStreamPlayer3D = null
var _time: float = 0.0
var _phase_time: float = 0.0
var _opened_at: float = 0.0
var _ring: MeshInstance3D
var _ring_mesh := ImmediateMesh.new()
var _ring_mat: ShaderMaterial
var _ring_glow: MeshInstance3D
var _ring_glow_mesh := ImmediateMesh.new()
var _ring_glow_mat: ShaderMaterial
var _hole: MeshInstance3D
var _bloom: MeshInstance3D
var _shape: PackedVector2Array = PackedVector2Array()
var _spawn: Node3D
var _swirl: MeshInstance3D
var _embers: Array[MeshInstance3D] = []
var _ember_t: Array[float] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 1000.0) + int(global_position.z * 7.0) + get_index()
	var n := 22
	for i in range(n):
		var a := TAU * float(i) / n
		var r := 0.42 + rng.randf_range(-0.09, 0.09)
		_shape.append(Vector2(cos(a) * r, sin(a) * r * 0.85))
	_shape.append(_shape[0])
	_ring_mat = Neon.glow_material(Neon.CYAN, true)
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring.material_override = _ring_mat
	_ring.position.y = HEIGHT
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring_glow_mat = Neon.glow_material(Neon.VIOLET, false)
	_ring_glow = MeshInstance3D.new()
	_ring_glow.mesh = _ring_glow_mesh
	_ring_glow.material_override = _ring_glow_mat
	_ring_glow.position.y = HEIGHT
	_ring_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_glow)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.95, 0.8)
	_hole = MeshInstance3D.new()
	_hole.mesh = quad
	var hole_mat := StandardMaterial3D.new()
	hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hole_mat.albedo_texture = Neon.halo_texture()
	hole_mat.albedo_color = Color(0.02, 0.0, 0.06, 0.0)
	hole_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hole_mat.render_priority = -2
	_hole.material_override = hole_mat
	_hole.position = Vector3(0, HEIGHT, 0.01)
	_hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hole)
	_bloom = Neon.make_halo(Neon.VIOLET, 1.8, 0.0)
	_bloom.position = Vector3(0, HEIGHT, 0.03)
	add_child(_bloom)
	_spawn = Node3D.new()
	_spawn.position = Vector3(0, HEIGHT, 0.15)
	add_child(_spawn)
	_swirl = Neon.make_ring_mesh(Neon.VIOLET.lerp(Neon.CYAN, 0.3), 0.2, 0.006)
	_swirl.position = Vector3(0, HEIGHT, 0.02)
	add_child(_swirl)
	for i in range(8):
		var e := Neon.make_halo(Neon.CYAN, 0.05, 0.0)
		add_child(e)
		_embers.append(e)
		_ember_t.append(randf())
	visible = false
	_rebuild(0.0)


## Mounts on a surface point with `normal` pointing into the room. Walls are
## given their floor point and the ring is lifted to HEIGHT; a ceiling point
## (normal pointing down) puts the ring right at the point.
func mount(origin: Vector3, normal: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	var z := normal.normalized()
	var hint := up_hint
	if absf(z.dot(hint)) > 0.9:
		hint = Vector3.FORWARD if absf(z.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := hint.cross(z).normalized()
	var y := z.cross(x).normalized()
	global_transform = Transform3D(Basis(x, y, z), origin)
	on_ceiling = absf(z.y) > 0.7
	var lift := 0.0 if on_ceiling else HEIGHT
	_ring.position.y = lift
	_ring_glow.position.y = lift
	_hole.position = Vector3(0, lift, 0.01)
	_bloom.position = Vector3(0, lift, 0.03)
	_spawn.position = Vector3(0, lift, 0.15)
	_swirl.position = Vector3(0, lift, 0.02)


func spawn_point() -> Vector3:
	return _spawn.global_position


func outward() -> Vector3:
	return global_basis.z.normalized()


func open() -> void:
	if mode == Mode.OPEN or mode == Mode.OPENING:
		return
	mode = Mode.OPENING
	_phase_time = 0.0
	_opened_at = _time
	visible = true


func close() -> void:
	if mode == Mode.CLOSED or mode == Mode.CLOSING:
		return
	mode = Mode.CLOSING
	_phase_time = 0.0


func is_open() -> bool:
	return mode == Mode.OPEN or mode == Mode.OPENING


func open_seconds() -> float:
	return _time - _opened_at if is_open() else 0.0


func _process(delta: float) -> void:
	_time += delta
	_phase_time += delta
	var amount := 0.0
	match mode:
		Mode.OPENING:
			amount = clampf(_phase_time / OPEN_SECONDS, 0.0, 1.0)
			amount = amount * amount * (3.0 - 2.0 * amount)
			if _phase_time >= OPEN_SECONDS:
				mode = Mode.OPEN
		Mode.OPEN:
			amount = 1.0
		Mode.CLOSING:
			amount = 1.0 - clampf(_phase_time / CLOSE_SECONDS, 0.0, 1.0)
			if _phase_time >= CLOSE_SECONDS:
				mode = Mode.CLOSED
				visible = false
		Mode.CLOSED:
			amount = 0.0
	var flicker := 1.0 if mode != Mode.OPENING else (0.6 + 0.4 * (1.0 if fmod(_time * 17.0, 1.0) < 0.6 else 0.0))
	_rebuild(amount)
	var pulse := 0.5 + 0.5 * sin(_time * 3.3)
	_ring_mat.set_shader_parameter("alpha_scale", amount * flicker)
	_ring_glow_mat.set_shader_parameter("alpha_scale", amount * flicker * 0.9)
	_ring_mat.set_shader_parameter("tint", Neon.CYAN.lerp(Neon.VIOLET, 0.3 + 0.3 * pulse))
	(_hole.material_override as StandardMaterial3D).albedo_color = Color(0.02, 0.0, 0.06, 0.92 * amount)
	_hole.scale = Vector3.ONE * maxf(0.01, amount)
	Neon.set_halo_color(_bloom, Neon.VIOLET, 0.2 * amount * (0.7 + 0.3 * pulse))
	_swirl.rotation.z += delta * 1.8
	_swirl.rotation.x = sin(_time * 1.1) * 0.5
	_swirl.scale = Vector3.ONE * maxf(0.01, amount) * (1.0 + 0.1 * pulse)
	(_swirl.material_override as StandardMaterial3D).albedo_color = Neon.VIOLET.lerp(Neon.CYAN, 0.3 + 0.4 * pulse)
	# Embers drift out of the crack and fade.
	var lift := _spawn.position.y
	for i in range(_embers.size()):
		_ember_t[i] += delta * (0.35 + 0.1 * i) * (1.0 if amount > 0.0 else 0.0)
		if _ember_t[i] >= 1.0:
			_ember_t[i] -= 1.0
		var t: float = _ember_t[i]
		var a := i * 0.8 + _time * 0.1
		var p := Vector3(cos(a) * (0.1 + t * 0.35), lift + sin(a * 1.7) * 0.1 + t * 0.25, 0.05 + t * 0.55)
		_embers[i].position = p
		Neon.set_halo_color(_embers[i], Neon.CYAN.lerp(Neon.VIOLET, t), amount * (1.0 - t) * 0.8)
	if hum:
		if is_open() and not hum.playing:
			hum.play()
		elif not is_open() and hum.playing and mode == Mode.CLOSED:
			hum.stop()


func _rebuild(amount: float) -> void:
	var pts := PackedVector3Array()
	var s := maxf(0.02, amount)
	for i in range(_shape.size()):
		var p := _shape[i] * s
		var jitter := sin(_time * 9.0 + i * 1.7) * 0.006 * amount
		pts.append(Vector3(p.x + jitter, p.y - jitter, 0.0))
	Neon.build_tube(_ring_mesh, pts, func(_t): return 0.008)
	Neon.build_tube(_ring_glow_mesh, pts, func(_t): return 0.05)
