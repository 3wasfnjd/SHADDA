class_name Neon
extends RefCounted
## SHADDA neon toolkit: flat emitter materials, premultiplied halos and a
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
