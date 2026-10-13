class_name Neon
extends RefCounted
## SHARARA neon toolkit: flat emitter materials, premultiplied halos and a
## material re-styler for the imported GLB assets. Everything here is cheap on
## the Mobile renderer: no glow post-process, no extra lights. The "bloom" is
## faked with premultiplied-alpha halo quads that composite correctly over
## passthrough.

const CYAN := Color(0.12, 0.82, 1.0)
const CYAN_DIM := Color(0.02, 0.22, 0.34)
const AMBER := Color(1.0, 0.42, 0.06)
const AMBER_DIM := Color(0.30, 0.10, 0.01)
const VIOLET := Color(0.58, 0.30, 1.0)
const RED := Color(1.0, 0.12, 0.22)
const WHITE := Color(1.0, 1.0, 1.0)

const EMITTER_NAMES := [
	"M_Amber_Emitter", "M_Cyan_Emitter", "M_Cyan_Diagnostics",
	"M_DisplayCount_a", "M_DisplayCount_g", "M_DisplaySlot_01",
	"M_Rift_Core", "M_Rift_Cyan", "M_Rift_Violet", "M_Rift_Pulse", "M_Rift_Surface",
]

static var _halo_texture: ImageTexture
static var _ring_texture: ImageTexture


static func halo_texture() -> ImageTexture:
	if _halo_texture == null:
		_halo_texture = _radial_texture(96, 0.0, 1.0, 1.9)
	return _halo_texture


static func ring_texture() -> ImageTexture:
	if _ring_texture == null:
		_ring_texture = _radial_texture(96, 0.62, 0.95, 1.0)
	return _ring_texture


## Premultiplied radial sprite: RGB and A both hold the falloff, so a material
## albedo of (C.rgb, k) yields colour C*f and alpha k*f.
static func _radial_texture(size: int, inner: float, outer: float, power: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var f := 0.0
			if d < outer:
				if inner <= 0.0:
					f = pow(clampf(1.0 - d / outer, 0.0, 1.0), power)
				else:
					var mid := (inner + outer) * 0.5
					var w := (outer - inner) * 0.5
					f = pow(clampf(1.0 - absf(d - mid) / w, 0.0, 1.0), power)
			image.set_pixel(x, y, Color(f, f, f, f))
	return ImageTexture.create_from_image(image)


static func emitter_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	return m


static func halo_material(color: Color, alpha: float, ring: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.albedo_texture = ring_texture() if ring else halo_texture()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if not ring else BaseMaterial3D.BILLBOARD_DISABLED
	m.render_priority = 2
	return m


## A soft light blob that always faces the player.
static func make_halo(color: Color, size: float, alpha: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = halo_material(color, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Halo"
	return mi


## A flat glowing ring lying on the floor (XZ plane).
static func make_floor_ring(color: Color, diameter: float, alpha: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	quad.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = halo_material(color, alpha, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "FloorRing"
	return mi


## A soft dark blob on the floor that grounds virtual objects in the real room.
static func make_contact_shadow(diameter: float, alpha: float = 0.45) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	quad.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = halo_texture()
	m.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	m.render_priority = -1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.004
	mi.name = "ContactShadow"
	return mi


static func set_halo_color(halo: MeshInstance3D, color: Color, alpha: float) -> void:
	var m := halo.material_override as StandardMaterial3D
	if m:
		m.albedo_color = Color(color.r, color.g, color.b, alpha)


## Replaces the emitter materials of an imported GLB with flat neon materials.
## Returns { material_name: StandardMaterial3D } so callers can animate colours
## per instance (each instance gets its own materials).
static func restyle(root: Node, overrides: Dictionary = {}) -> Dictionary:
	var created := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s)
			if source == null:
				continue
			var name := source.resource_name
			if not EMITTER_NAMES.has(name) and not overrides.has(name):
				continue
			if not created.has(name):
				var color: Color = overrides.get(name, default_color(name))
				created[name] = emitter_material(color)
			mi.set_surface_override_material(s, created[name])
	return created


static func default_color(material_name: String) -> Color:
	match material_name:
		"M_Amber_Emitter":
			return AMBER
		"M_Rift_Violet":
			return VIOLET
		"M_Rift_Core":
			return WHITE.lerp(CYAN, 0.35)
		"M_Rift_Surface":
			return Color(0.03, 0.08, 0.14)
		"M_Rift_Pulse":
			return CYAN_DIM
		_:
			return CYAN


## Hides every mesh whose material name matches one of the given names.
static func hide_materials(root: Node, names: Array) -> int:
	var hidden := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s)
			if source and names.has(source.resource_name):
				mi.visible = false
				hidden += 1
				break
	return hidden


## Moves the model so its lowest point sits on y = 0 of the parent.
static func rest_on_floor(model: Node3D) -> float:
	var aabb := merged_aabb(model)
	var lift := -aabb.position.y
	model.position.y += lift
	return lift


static func merged_aabb(model: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var inverse := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var local := (inverse * mi.global_transform) * mi.mesh.get_aabb()
		merged = local if first else merged.merge(local)
		first = false
	return merged


static func count_triangles(root: Node) -> int:
	var total := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var index = arrays[Mesh.ARRAY_INDEX]
			if index != null:
				total += index.size() / 3
			else:
				total += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return total


## Builds a 6-sided tube along `points` into an ImmediateMesh. `radius_at(t)`
## gives the radius for t in 0..1 along the tube; the mesh carries normals and
## UV.x = t so premultiplied glow shaders can shade it from any angle.
static func build_tube(mesh: ImmediateMesh, points: PackedVector3Array, radius_at: Callable, color: Color = Color.WHITE) -> void:
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
		var r0: float = radius_at.call(u0)
		var r1: float = radius_at.call(u1)
		for k in range(SIDES):
			var a0 := TAU * float(k) / SIDES
			var a1 := TAU * float(k + 1) / SIDES
			var n00 := frames_u[i] * cos(a0) + frames_v[i] * sin(a0)
			var n01 := frames_u[i] * cos(a1) + frames_v[i] * sin(a1)
			var n10 := frames_u[i + 1] * cos(a0) + frames_v[i + 1] * sin(a0)
			var n11 := frames_u[i + 1] * cos(a1) + frames_v[i + 1] * sin(a1)
			_tube_vertex(mesh, points[i] + n00 * r0, n00, u0, color)
			_tube_vertex(mesh, points[i + 1] + n10 * r1, n10, u1, color)
			_tube_vertex(mesh, points[i] + n01 * r0, n01, u0, color)
			_tube_vertex(mesh, points[i] + n01 * r0, n01, u0, color)
			_tube_vertex(mesh, points[i + 1] + n10 * r1, n10, u1, color)
			_tube_vertex(mesh, points[i + 1] + n11 * r1, n11, u1, color)
	mesh.surface_end()


static func _tube_vertex(mesh: ImmediateMesh, p: Vector3, n: Vector3, u: float, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_set_normal(n)
	mesh.surface_set_uv(Vector2(u, 0.0))
	mesh.surface_add_vertex(p)


const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.12, 0.82, 1.0, 1.0);
uniform float alpha_scale = 1.0;
uniform float pulse_speed = 2.2;
uniform float core = 0.0;
uniform float fade_along = 0.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float pulse = 0.78 + 0.22 * sin(UV.x * 22.0 - TIME * pulse_speed * 6.283);
	float along = fade_along > 0.5 ? (1.0 - UV.x) : 1.0;
	float a;
	vec3 rgb;
	if (core > 0.5) {
		a = (0.75 + 0.25 * facing) * pulse * alpha_scale * COLOR.a * along;
		rgb = mix(tint.rgb, vec3(1.0), 0.45) * a;
	} else {
		a = pow(facing, 1.9) * pulse * alpha_scale * COLOR.a * 0.32 * along;
		rgb = tint.rgb * a;
	}
	ALBEDO = rgb;
	ALPHA = a;
}
"""

static var _glow_shader: Shader


static func glow_material(color: Color, core: bool, fade_along: bool = false) -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("core", 1.0 if core else 0.0)
	m.set_shader_parameter("fade_along", 1.0 if fade_along else 0.0)
	m.render_priority = 3 if core else 2
	return m


## Low-poly neon sphere (a diamond when segments are tiny).
static func make_orb(color: Color, radius: float, radial: int = 12, rings: int = 6) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = radial
	sphere.rings = rings
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = emitter_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
