class_name Toon
extends RefCounted
## Cartoon look: two-band cel shading with a soft rim and a crisp highlight,
## plus a black ink outline (inverted hull). Simple chunky primitives and a
## `bake()` that merges a model's static parts into one mesh per material so a
## whole plane costs a handful of draw calls on Quest.
##
## Everything here renders in the transparent pass at priority 0 with full
## alpha and depth writes, so the real-room occluders (priority -100, depth
## only) can hide models that fly behind a real wall, couch or table.

const PRI_OCCLUDER := -100
const INK := Color(0.07, 0.06, 0.08)

const TOON_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_toon, specular_toon;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.55, 0.5, 0.65, 1.0);
uniform float gloss = 0.5;
uniform float rim = 0.35;
uniform float flash = 0.0;
uniform bool use_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(tex, UV).rgb;
	}
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 1.0 - gloss * 0.6;
	SPECULAR = gloss * 0.5;
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = base * smoothstep(0.62, 0.7, f) * rim + vec3(flash * 0.6);
	ALPHA = 1.0;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.02, 0.04, ndl) * 0.55 + smoothstep(0.5, 0.56, ndl) * 0.2;
	vec3 tint = mix(shade.rgb, vec3(1.0), band);
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * ATTENUATION * 0.9;
	vec3 h = normalize(LIGHT + VIEW);
	float s = smoothstep(0.93, 0.95, dot(NORMAL, h)) * gloss;
	SPECULAR_LIGHT += vec3(s) * LIGHT_COLOR * ATTENUATION * 0.6;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_front, shadows_disabled;
uniform vec4 ink : source_color = vec4(0.07, 0.06, 0.08, 1.0);
uniform float width = 0.0025;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = ink.rgb;
	ALPHA = 1.0;
}
"""

const FLAT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
}
"""

const OCCLUDER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_disabled, shadows_disabled;
void fragment() { ALBEDO = vec3(0.0); ALPHA = 0.0; }
"""

static var _shaders: Dictionary = {}
static var _cache: Dictionary = {}


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]


## Shared toon material with an ink outline pass. `outline` is the hull
## width in metres (0 = no outline). Materials are cached by their settings.
static func mat(color: Color, gloss: float = 0.5, outline: float = 0.0022) -> ShaderMaterial:
	var key := "%s|%s|%s" % [color.to_html(), gloss, outline]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("toon", TOON_SHADER)
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("shade", Color(color.r * 0.45 + 0.1, color.g * 0.42 + 0.08, color.b * 0.5 + 0.16))
	m.set_shader_parameter("gloss", gloss)
	if outline > 0.0:
		m.next_pass = ink(outline)
	_cache[key] = m
	return m


## Toon material over a texture (for imported models).
static func textured(texture: Texture2D, gloss: float = 0.45, outline: float = 0.0022) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("toon", TOON_SHADER)
	m.set_shader_parameter("albedo", Color(1.0, 1.0, 1.0))
	m.set_shader_parameter("shade", Color(0.55, 0.52, 0.62))
	m.set_shader_parameter("rim", 0.12)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("tex", texture)
	if outline > 0.0:
		m.next_pass = ink(outline)
	return m


## A private copy (for hit flashes on one enemy).
static func unique(m: ShaderMaterial) -> ShaderMaterial:
	var c := m.duplicate() as ShaderMaterial
	return c


static func ink(width: float) -> ShaderMaterial:
	var key := "ink|%s" % width
	if not _cache.has(key):
		var o := ShaderMaterial.new()
		o.shader = _shader("ink", OUTLINE_SHADER)
		o.set_shader_parameter("width", width)
		_cache[key] = o
	return _cache[key]


## Unlit flat colour (muzzle flashes, tracers, lights). Alpha allowed.
static func flat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("flat", FLAT_SHADER)
	m.set_shader_parameter("albedo", color)
	return m


static func occluder() -> ShaderMaterial:
	var key := "occluder"
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("occ", OCCLUDER_SHADER)
		m.render_priority = PRI_OCCLUDER
		_cache[key] = m
	return _cache[key]


# --- primitives -----------------------------------------------------------------

static func add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func ball(r: float, segs: int = 14, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


## Cylinder along Y.
static func can(r_top: float, r_bottom: float, h: float, segs: int = 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func capsule(r: float, h: float, segs: int = 14) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = segs
	c.rings = 4
	return c


static func block(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func torus(r: float, thickness: float, segs: int = 18) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thickness
	t.outer_radius = r + thickness
	t.rings = segs
	t.ring_segments = 8
	return t


## Rounded wing/fin: an outline in XZ extruded `thickness` in Y, with the
## leading/trailing edges bevelled by scaling the bottom face slightly.
static func slab(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(outline)
	var h := thickness * 0.5
	var c := Vector2.ZERO
	for p in outline:
		c += p
	c /= outline.size()
	var bottom := PackedVector2Array()
	for p in outline:
		bottom.append(c + (p - c) * 0.94)
	var cw := Geometry2D.is_polygon_clockwise(outline)
	for i in range(0, tris.size(), 3):
		var ia := tris[i]
		var ib := tris[i + 1]
		var ic := tris[i + 2]
		if cw:
			var tmp := ib
			ib = ic
			ic = tmp
		for k in [ia, ib, ic]:
			st.add_vertex(Vector3(outline[k].x, h, outline[k].y))
		for k in [ia, ic, ib]:
			st.add_vertex(Vector3(bottom[k].x, -h, bottom[k].y))
	for i in range(outline.size()):
		var j := (i + 1) % outline.size()
		var t0 := Vector3(outline[i].x, h, outline[i].y)
		var t1 := Vector3(outline[j].x, h, outline[j].y)
		var b0 := Vector3(bottom[i].x, -h, bottom[i].y)
		var b1 := Vector3(bottom[j].x, -h, bottom[j].y)
		if not cw:
			for v in [t0, t1, b1, t0, b1, b0]:
				st.add_vertex(v)
		else:
			for v in [t0, b1, t1, t0, b0, b1]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func mirror_x(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(outline.size() - 1, -1, -1):
		out.append(Vector2(-outline[i].x, outline[i].y))
	return out


## Five-point star outline in XZ (radius r), for insignia.
static func star(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.42
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	return pts


## Merges every MeshInstance3D under `root` that is not inside a node marked
## with meta "live" into one MeshInstance3D per material, in root space.
## Animated parts (propellers, turrets, gear) keep their own nodes.
static func bake(root: Node3D) -> void:
	var groups: Dictionary = {}
	var victims: Array = []
	_collect(root, root, Transform3D.IDENTITY, groups, victims)
	for v in victims:
		v.get_parent().remove_child(v)
		v.queue_free()
	for key in groups:
		var material: Material = key[0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for item in groups[key]:
			var mesh: Mesh = item[0]
			for s in range(mesh.get_surface_count()):
				st.append_from(mesh, s, item[1])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Baked"
		root.add_child(mi)
		root.move_child(mi, 0)


static func _collect(root: Node3D, node: Node, xf: Transform3D, groups: Dictionary, victims: Array) -> void:
	for child in node.get_children():
		if not (child is Node3D):
			continue
		if child.has_meta("live"):
			continue
		var cxf: Transform3D = xf * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null and child.get_child_count() == 0:
			var mi := child as MeshInstance3D
			var key := [mi.material_override, mi.mesh is ArrayMesh]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([mi.mesh, cxf])
			victims.append(mi)
		else:
			_collect(root, child, cxf, groups, victims)


## A soft dark blob that sits on the surface under a flying object (fake
## shadow — the single strongest cue that a toy is really in the room).
static func shadow_blob(diameter: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(diameter, diameter)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = blob_texture()
	m.albedo_color = Color(0, 0, 0, 0.5)
	m.render_priority = -50
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	return mi


static var _blob: ImageTexture
static func blob_texture() -> ImageTexture:
	if _blob == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in range(n):
			for x in range(n):
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_blob = ImageTexture.create_from_image(img)
	return _blob
