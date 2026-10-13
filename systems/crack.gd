class_name Crack
extends Node3D
## A breach in a real wall (or ceiling). When it opens, plaster chunks burst
## out into the room and a jagged hole appears through which an alien world is
## visible — sky, ground, glowing spires, drifting motes, creatures milling.
##
## How the hole works over passthrough: an invisible "occluder" disc with the
## hole cut out lies on the wall plane. It draws nothing (alpha 0, so the real
## wall stays visible) but writes depth before anything of the world behind is
## drawn; that world uses the transparent pipeline with later render
## priorities, so it only shows where the occluder has a hole.
##
## Local frame: wall plane z = 0, +Z points into the room, hole centre at
## (0, HEIGHT) for walls and (0, 0) for ceilings.

enum Mode { CLOSED, OPENING, OPEN, CLOSING }

const OPEN_SECONDS := 0.7
const CLOSE_SECONDS := 1.2
const HEIGHT := 1.0
const POINTS := 26
const OCCLUDER_RADIUS := 6.0
const START_RADIUS := 0.42
const MAX_RADIUS := 0.85
const WORLD_DEPTH := 4.0

const PRI_OCCLUDER := -120
const PRI_WORLD := -100

var mode: int = Mode.CLOSED
var on_ceiling: bool = false
var hum: AudioStreamPlayer3D = null
var director: Node = null
var radius: float = START_RADIUS
var _target_radius: float = START_RADIUS
var _amount: float = 0.0
var _time: float = 0.0
var _phase_time: float = 0.0
var _opened_at: float = 0.0
var _shape: PackedVector2Array = PackedVector2Array()
var _centre: Vector3 = Vector3(0, HEIGHT, 0)
var _rng := RandomNumberGenerator.new()

var _occluder: MeshInstance3D
var _occluder_mesh := ImmediateMesh.new()
var _edge: MeshInstance3D
var _edge_mesh := ImmediateMesh.new()
var _edge_mat: ShaderMaterial
var _edge_glow: MeshInstance3D
var _edge_glow_mesh := ImmediateMesh.new()
var _edge_glow_mat: ShaderMaterial
var _world: Node3D
var _tunnel_mesh := ImmediateMesh.new()
var _tunnel: MeshInstance3D
var _world_creatures: Array[Node3D] = []
var _world_motes: Array[MeshInstance3D] = []
var _bloom: MeshInstance3D
var _spawn: Node3D
var _debris: Array = []
var _dust: Array[MeshInstance3D] = []


func _ready() -> void:
	_rng.seed = hash(str(get_index()) + str(Time.get_ticks_usec()))
	for i in range(POINTS):
		var a := TAU * float(i) / POINTS
		var r := 1.0 + _rng.randf_range(-0.22, 0.18) + (0.12 if i % 5 == 0 else 0.0)
		_shape.append(Vector2(cos(a) * r, sin(a) * r * 0.92))
	# Occluder: invisible, depth-only, first of everything transparent.
	var occ_shader := Shader.new()
	occ_shader.code = """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_disabled, shadows_disabled;
void fragment() { ALBEDO = vec3(0.0); ALPHA = 0.0; }
"""
	var occ_mat := ShaderMaterial.new()
	occ_mat.shader = occ_shader
	occ_mat.render_priority = PRI_OCCLUDER
	_occluder = MeshInstance3D.new()
	_occluder.mesh = _occluder_mesh
	_occluder.material_override = occ_mat
	_occluder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_occluder.extra_cull_margin = 8.0
	add_child(_occluder)
	_build_world()
	_edge_mat = Neon.glow_material(Neon.CYAN, true)
	_edge = MeshInstance3D.new()
	_edge.mesh = _edge_mesh
	_edge.material_override = _edge_mat
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge)
	_edge_glow_mat = Neon.glow_material(Neon.VIOLET, false)
	_edge_glow = MeshInstance3D.new()
	_edge_glow.mesh = _edge_glow_mesh
	_edge_glow.material_override = _edge_glow_mat
	_edge_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge_glow)
	_bloom = Neon.make_halo(Neon.VIOLET, 2.2, 0.0)
	(_bloom.material_override as StandardMaterial3D).no_depth_test = true
	add_child(_bloom)
	_spawn = Node3D.new()
	add_child(_spawn)
	_place_parts()
	visible = false


# --- the world behind the wall ------------------------------------------------

func _world_material(color: Color, priority: int = PRI_WORLD, unshaded: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	m.render_priority = priority
	m.disable_receive_shadows = true
	return m


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	# Sky: a big gradient plate deep behind the hole.
	var sky_shader := Shader.new()
	sky_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
uniform vec4 top : source_color = vec4(0.04, 0.02, 0.12, 1.0);
uniform vec4 horizon : source_color = vec4(0.55, 0.12, 0.55, 1.0);
uniform vec4 glow : source_color = vec4(0.1, 0.9, 1.0, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float h = UV.y;
	vec3 col = mix(top.rgb, horizon.rgb, smoothstep(0.15, 1.0, h));
	vec2 g = UV * vec2(260.0, 170.0);
	vec2 cell = floor(g);
	float s = hash(cell);
	float d = distance(fract(g), vec2(0.5));
	float twinkle = 0.5 + 0.5 * sin(TIME * (1.0 + s * 3.0) + s * 40.0);
	col += vec3(step(0.975, s) * smoothstep(0.35, 0.0, d) * twinkle * (1.0 - h));
	float planet = smoothstep(0.13, 0.12, distance(UV, vec2(0.72, 0.3)));
	col = mix(col, glow.rgb * 0.8, planet * 0.85);
	col += glow.rgb * 0.25 * smoothstep(0.25, 0.0, distance(UV, vec2(0.72, 0.3)));
	ALBEDO = col;
	ALPHA = 1.0;
}
"""
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	sky_mat.render_priority = PRI_WORLD - 10
	var sky := MeshInstance3D.new()
	var sky_quad := QuadMesh.new()
	sky_quad.size = Vector2(14.0, 9.0)
	sky.mesh = sky_quad
	sky.material_override = sky_mat
	sky.position = Vector3(0, 2.5, -WORLD_DEPTH)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(sky)
	# Ground: alien moss with glowing veins.
	var ground_shader := Shader.new()
	ground_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
uniform vec4 moss : source_color = vec4(0.06, 0.1, 0.16, 1.0);
uniform vec4 vein : source_color = vec4(0.1, 0.85, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 18.0;
	float v = abs(sin(p.x + sin(p.y * 0.7) * 1.6)) * abs(sin(p.y * 0.9 + sin(p.x * 0.5)));
	float line = smoothstep(0.06, 0.0, v);
	float fade = smoothstep(0.0, 0.8, UV.y);
	vec3 col = moss.rgb * (0.6 + 0.4 * UV.y) + vein.rgb * line * (0.4 + 0.3 * sin(TIME * 1.5 + p.x));
	ALBEDO = mix(col, vec3(0.2, 0.05, 0.25), 1.0 - fade);
	ALPHA = 1.0;
}
"""
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = ground_shader
	ground_mat.render_priority = PRI_WORLD - 5
	var ground := MeshInstance3D.new()
	var ground_plane := PlaneMesh.new()
	ground_plane.size = Vector2(12.0, WORLD_DEPTH)
	ground.mesh = ground_plane
	ground.material_override = ground_mat
	ground.position = Vector3(0, 0.0, -WORLD_DEPTH * 0.5)
	ground.name = "Ground"
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(ground)
	# Glowing crystal spires.
	for i in range(7):
		var col: Color = [Neon.CYAN, Neon.VIOLET, Color(0.4, 1.0, 0.6), Neon.AMBER][i % 4]
		var spire := Neon.make_crystal(col, _rng.randf_range(0.12, 0.3), _rng.randf_range(2.5, 5.0))
		spire.material_override = _world_material(col.lerp(Neon.WHITE, 0.15), PRI_WORLD)
		var x := _rng.randf_range(-2.4, 2.4)
		var z := -_rng.randf_range(1.2, WORLD_DEPTH - 0.4)
		spire.position = Vector3(x, 0.4, z)
		spire.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf(), _rng.randf_range(-0.25, 0.25))
		_world.add_child(spire)
	# Little residents milling about on the far side.
	for i in range(4):
		var body := Neon.make_orb(Neon.AMBER, 0.12, 10, 5)
		body.material_override = _world_material([Neon.AMBER, Neon.CYAN, Color(0.4, 1.0, 0.6), Neon.VIOLET][i], PRI_WORLD + 2)
		var eye_l := Neon.make_orb(Color(0.03, 0.02, 0.08), 0.025, 6, 3)
		eye_l.material_override = _world_material(Color(0.03, 0.02, 0.08), PRI_WORLD + 3)
		eye_l.position = Vector3(-0.04, 0.03, 0.1)
		body.add_child(eye_l)
		var eye_r := eye_l.duplicate()
		eye_r.position.x = 0.04
		body.add_child(eye_r)
		body.position = Vector3(_rng.randf_range(-1.5, 1.5), 0.15, -_rng.randf_range(1.0, 2.8))
		_world.add_child(body)
		_world_creatures.append(body)
	# Drifting motes.
	for i in range(10):
		var mote := Neon.make_orb(Neon.CYAN, 0.02, 6, 3)
		mote.material_override = _world_material(Neon.CYAN.lerp(Neon.WHITE, 0.4), PRI_WORLD + 4)
		_world.add_child(mote)
		_world_motes.append(mote)
	# Tunnel through the wall thickness.
	var tunnel_mat := _world_material(Color(0.12, 0.07, 0.18), PRI_WORLD + 6, false)
	tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tunnel = MeshInstance3D.new()
	_tunnel.mesh = _tunnel_mesh
	_tunnel.material_override = tunnel_mat
	_tunnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tunnel)


func _place_parts() -> void:
	_centre = Vector3(0, 0.0 if on_ceiling else HEIGHT, 0)
	_spawn.position = _centre + Vector3(0, 0, 0.12)
	_bloom.position = _centre + Vector3(0, 0, 0.04)
	var ground := _world.get_node_or_null("Ground") as Node3D
	if ground:
		ground.visible = not on_ceiling
	_world.position = Vector3(0, 0.0, 0.0) if not on_ceiling else Vector3(0, -2.0, 0)


## Mounts on a surface point with `normal` pointing into the room. Walls get
## their floor point (the hole sits at HEIGHT); a ceiling point puts the hole
## right there.
func mount(origin: Vector3, normal: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	var z := normal.normalized()
	var hint := up_hint
	if absf(z.dot(hint)) > 0.9:
		hint = Vector3.FORWARD if absf(z.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := hint.cross(z).normalized()
	var y := z.cross(x).normalized()
	global_transform = Transform3D(Basis(x, y, z), origin)
	on_ceiling = absf(z.y) > 0.7
	_place_parts()


func spawn_point() -> Vector3:
	return _spawn.global_position


func outward() -> Vector3:
	return global_basis.z.normalized()


func hole_centre() -> Vector3:
	return to_global(_centre)


func open() -> void:
	if mode == Mode.OPEN or mode == Mode.OPENING:
		return
	mode = Mode.OPENING
	_phase_time = 0.0
	_opened_at = _time
	radius = START_RADIUS * 0.3
	_target_radius = START_RADIUS
	visible = true
	_burst_debris(16, START_RADIUS)
	if director:
		director.call("cue", "crack_open", hole_centre(), 4.0)


## Each emergence widens the hole a little and throws more rubble.
func widen(amount: float = 0.06) -> void:
	if mode != Mode.OPEN and mode != Mode.OPENING:
		return
	var before := _target_radius
	_target_radius = minf(MAX_RADIUS, _target_radius + amount)
	if _target_radius > before + 0.01:
		_burst_debris(6, _target_radius)
		if director:
			director.call("cue", "thud", hole_centre(), -2.0)


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
	match mode:
		Mode.OPENING:
			_amount = minf(1.0, _phase_time / OPEN_SECONDS)
			if _phase_time >= OPEN_SECONDS:
				mode = Mode.OPEN
		Mode.OPEN:
			_amount = 1.0
		Mode.CLOSING:
			_amount = 1.0 - clampf(_phase_time / CLOSE_SECONDS, 0.0, 1.0)
			if _phase_time >= CLOSE_SECONDS:
				mode = Mode.CLOSED
				visible = false
				radius = START_RADIUS
				_target_radius = START_RADIUS
		Mode.CLOSED:
			_amount = 0.0
	radius = lerpf(radius, _target_radius, minf(1.0, delta * 6.0))
	var r := radius * _amount
	_rebuild(maxf(r, 0.005))
	var pulse := 0.5 + 0.5 * sin(_time * 3.1)
	_edge_mat.set_shader_parameter("alpha_scale", _amount)
	_edge_mat.set_shader_parameter("tint", Neon.CYAN.lerp(Neon.VIOLET, 0.25 + 0.3 * pulse))
	_edge_glow_mat.set_shader_parameter("alpha_scale", _amount * 0.9)
	Neon.set_halo_color(_bloom, Neon.VIOLET, 0.16 * _amount * (0.7 + 0.3 * pulse))
	_world.visible = _amount > 0.01
	# The far side lives.
	for i in range(_world_creatures.size()):
		var c := _world_creatures[i]
		var hop := absf(sin(_time * (2.0 + i * 0.4) + i))
		c.position.x += sin(_time * 0.4 + i * 2.0) * delta * 0.25
		c.position.y = 0.12 + hop * 0.12
		c.scale = Vector3(1.0 + (1.0 - hop) * 0.15, 1.0 - (1.0 - hop) * 0.15, 1.0)
	for i in range(_world_motes.size()):
		var t := fmod(_time * (0.08 + i * 0.01) + i * 0.17, 1.0)
		_world_motes[i].position = Vector3(sin(i * 2.3 + _time * 0.3) * 2.0, 0.3 + t * 2.4, -1.0 - fmod(i * 0.37, 1.0) * 2.5)
	if hum:
		if is_open() and not hum.playing:
			hum.play()
		elif mode == Mode.CLOSED and hum.playing:
			hum.stop()
	_update_debris(delta)


func _rebuild(r: float) -> void:
	var c2 := Vector2(_centre.x, _centre.y)
	# Occluder ring: hole polygon → far polygon, a triangle strip around the hole.
	_occluder_mesh.clear_surfaces()
	_occluder_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(POINTS):
		var j := (i + 1) % POINTS
		var a_in := c2 + _shape[i] * r
		var b_in := c2 + _shape[j] * r
		var a_out := c2 + _shape[i].normalized() * OCCLUDER_RADIUS
		var b_out := c2 + _shape[j].normalized() * OCCLUDER_RADIUS
		for p in [a_in, a_out, b_in, b_in, a_out, b_out]:
			_occluder_mesh.surface_add_vertex(Vector3(p.x, p.y, 0.004))
	_occluder_mesh.surface_end()
	# Jagged neon edge, slightly in front of the wall.
	var edge := PackedVector3Array()
	for i in range(POINTS + 1):
		var p := c2 + _shape[i % POINTS] * r
		var jitter := sin(_time * 9.0 + i * 1.7) * 0.004 * _amount
		edge.append(Vector3(p.x + jitter, p.y - jitter, 0.012))
	Neon.build_tube(_edge_mesh, edge, func(_t): return 0.008)
	Neon.build_tube(_edge_glow_mesh, edge, func(_t): return 0.045)
	# Tunnel through the wall: hole outline extruded 0.18 m back.
	_tunnel_mesh.clear_surfaces()
	_tunnel_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(POINTS):
		var j := (i + 1) % POINTS
		var a := c2 + _shape[i] * r
		var b := c2 + _shape[j] * r
		var a2 := c2 + _shape[i] * r * 1.08
		var b2 := c2 + _shape[j] * r * 1.08
		var n := Vector3(-(_shape[i].x), -(_shape[i].y), 0).normalized()
		var verts := [Vector3(a.x, a.y, 0.002), Vector3(a2.x, a2.y, -0.18), Vector3(b.x, b.y, 0.002), Vector3(b.x, b.y, 0.002), Vector3(a2.x, a2.y, -0.18), Vector3(b2.x, b2.y, -0.18)]
		for v in verts:
			_tunnel_mesh.surface_set_normal(n)
			_tunnel_mesh.surface_add_vertex(v)
	_tunnel_mesh.surface_end()


# --- rubble -------------------------------------------------------------------

func _burst_debris(count: int, at_radius: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in range(count):
		var size := Vector3(_rng.randf_range(0.04, 0.14), _rng.randf_range(0.04, 0.12), _rng.randf_range(0.03, 0.06))
		var body := RigidBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 1
		body.mass = 0.2
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		var tone := _rng.randf_range(0.78, 0.92)
		mat.albedo_color = Color(tone, tone * 0.98, tone * 0.94)
		mat.roughness = 0.95
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
		var glow := Neon.make_halo(Neon.VIOLET, 0.12, 0.35)
		body.add_child(glow)
		parent.add_child(body)
		var a := _rng.randf() * TAU
		var local := _centre + Vector3(cos(a), sin(a) * 0.9, 0) * at_radius * _rng.randf_range(0.6, 1.05) + Vector3(0, 0, 0.06)
		body.global_position = to_global(local)
		body.global_rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		var out := global_basis.z * _rng.randf_range(1.6, 3.4) + global_basis.x * cos(a) * 1.2 + global_basis.y * (sin(a) * 1.0 + 0.8)
		body.linear_velocity = out
		body.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
		_debris.append({"body": body, "life": 0.0, "glow": glow, "mesh": mesh})
	# Dust puff.
	for i in range(5):
		var puff := Neon.make_halo(Color(0.85, 0.8, 0.9), 0.4, 0.0)
		puff.top_level = true
		add_child(puff)
		puff.global_position = hole_centre() + outward() * 0.15 + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.1, 0.1))
		_dust.append(puff)
		puff.set_meta("life", 0.0)


func _update_debris(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		d.life += delta
		var body: RigidBody3D = d.body
		if not is_instance_valid(body):
			_debris.remove_at(i)
			continue
		Neon.set_halo_color(d.glow, Neon.VIOLET, maxf(0.0, 0.35 - d.life * 0.5))
		if d.life > 6.0:
			var k := clampf(1.0 - (d.life - 6.0) / 1.0, 0.0, 1.0)
			(d.mesh as Node3D).scale = Vector3.ONE * maxf(0.01, k)
			if k <= 0.0:
				body.queue_free()
				_debris.remove_at(i)
	for i in range(_dust.size() - 1, -1, -1):
		var p := _dust[i]
		var life: float = p.get_meta("life") + delta
		p.set_meta("life", life)
		p.global_position += outward() * delta * 0.3 + Vector3(0, delta * 0.1, 0)
		p.scale = Vector3.ONE * (1.0 + life * 2.0)
		Neon.set_halo_color(p, Color(0.85, 0.8, 0.9), maxf(0.0, 0.35 * (1.0 - life / 1.4)))
		if life > 1.4:
			p.queue_free()
			_dust.remove_at(i)
