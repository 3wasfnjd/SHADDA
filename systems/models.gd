class_name Models
extends RefCounted
## Every model in SAQR is built here from a few clean primitives: faceted
## cylinders, extruded plates and boxes. Simple, crisp silhouettes, matte
## paint, small emissive lights. All models face -Z (Godot forward).

const PLAYER_BODY := Color(0.62, 0.67, 0.73)
const PLAYER_DARK := Color(0.20, 0.23, 0.27)
const PLAYER_ACCENT := Color(0.10, 0.80, 1.0)
const ENEMY_BODY := Color(0.24, 0.25, 0.28)
const ENEMY_DARK := Color(0.10, 0.10, 0.12)
const ENEMY_ACCENT := Color(1.0, 0.18, 0.12)
const GLASS := Color(0.16, 0.34, 0.42)

const PRI_OCCLUDER := -40
const PRI_INTERIOR := -20

static var _mat_cache: Dictionary = {}


static func paint(color: Color, metallic: float = 0.25, roughness: float = 0.55) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), metallic, roughness]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		m.metallic_specular = 0.6
		_mat_cache[key] = m
	return _mat_cache[key]


static func light(color: Color) -> StandardMaterial3D:
	return Neon.emitter_material(color)


static func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Faceted cylinder lying along Z. r_front is the -Z end.
static func tube(r_front: float, r_back: float, length: float, sides: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_front
	c.bottom_radius = r_back
	c.height = length
	c.radial_segments = sides
	c.rings = 1
	return c


static func sphere(radius: float, radial: int = 8, rings: int = 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Flat plate from an outline in the XZ plane, `thickness` thick in Y,
## with hard edges (flat normals).
static func plate(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(outline)
	var h := thickness * 0.5
	var ccw := Geometry2D.is_polygon_clockwise(outline) == false
	for i in range(0, tris.size(), 3):
		var a := outline[tris[i]]
		var b := outline[tris[i + 1]]
		var c := outline[tris[i + 2]]
		# Top (+Y) and bottom faces.
		var top := [Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(c.x, h, c.y)]
		var bot := [Vector3(a.x, -h, a.y), Vector3(c.x, -h, c.y), Vector3(b.x, -h, b.y)]
		if ccw:
			top = [top[0], top[2], top[1]]
			bot = [bot[0], bot[2], bot[1]]
		for v in top:
			st.add_vertex(v)
		for v in bot:
			st.add_vertex(v)
	for i in range(outline.size()):
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var p0 := Vector3(p.x, h, p.y)
		var q0 := Vector3(q.x, h, q.y)
		var p1 := Vector3(p.x, -h, p.y)
		var q1 := Vector3(q.x, -h, q.y)
		if ccw:
			for v in [p0, q0, q1, p0, q1, p1]:
				st.add_vertex(v)
		else:
			for v in [p0, q1, q0, p0, p1, q1]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func mirror_x(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(outline.size() - 1, -1, -1):
		out.append(Vector2(-outline[i].x, outline[i].y))
	return out


# --- weapons ------------------------------------------------------------------

## Air-to-air missile, ~6 cm. Returns a Node3D facing -Z.
static func missile(hostile: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Missile"
	var body := paint(Color(0.86, 0.87, 0.86) if not hostile else Color(0.30, 0.30, 0.32), 0.2, 0.45)
	_add(root, tube(0.0045, 0.0045, 0.05, 8), body, Vector3(0, 0, 0.002), Vector3(-90, 0, 0))
	_add(root, tube(0.0, 0.0045, 0.014, 8), light(ENEMY_ACCENT) if hostile else paint(Color(0.85, 0.20, 0.15), 0.1, 0.5), Vector3(0, 0, -0.03), Vector3(-90, 0, 0))
	var fin := box(Vector3(0.016, 0.0008, 0.008))
	for a: float in [0.0, 90.0]:
		_add(root, fin, paint(PLAYER_DARK), Vector3(0, 0, 0.022), Vector3(0, 0, a))
	return root


static func bomb() -> Node3D:
	var root := Node3D.new()
	root.name = "Bomb"
	_add(root, tube(0.004, 0.0075, 0.03, 8), paint(Color(0.32, 0.36, 0.26), 0.15, 0.6), Vector3(0, 0, 0.0), Vector3(-90, 0, 0))
	_add(root, tube(0.0, 0.004, 0.008, 8), paint(Color(0.32, 0.36, 0.26), 0.15, 0.6), Vector3(0, 0, -0.019), Vector3(-90, 0, 0))
	var fin := box(Vector3(0.018, 0.0008, 0.007))
	for a: float in [45.0, 135.0]:
		_add(root, fin, paint(PLAYER_DARK), Vector3(0, 0, 0.016), Vector3(0, 0, a))
	_add(root, tube(0.0076, 0.0076, 0.003, 8), paint(Color(0.9, 0.75, 0.1), 0.1, 0.5), Vector3(0, 0, -0.008), Vector3(-90, 0, 0))
	return root


# --- jets -----------------------------------------------------------------------

## The player's fighter (hostile = false) or the enemy fighter (hostile = true).
## Returns {root, pylons: Array[Node3D], bombs: Array[Node3D], burner: MeshInstance3D,
##          muzzles: Array[Node3D], laser: Node3D, nose: Node3D}.
static func jet(hostile: bool = false) -> Dictionary:
	var root := Node3D.new()
	root.name = "EnemyFighter" if hostile else "PlayerJet"
	var body := paint(ENEMY_BODY if hostile else PLAYER_BODY, 0.3, 0.5)
	var dark := paint(ENEMY_DARK if hostile else PLAYER_DARK, 0.3, 0.6)
	var accent: Color = ENEMY_ACCENT if hostile else PLAYER_ACCENT
	# Fuselage, nose, canopy.
	_add(root, tube(0.021, 0.025, 0.19, 8), body, Vector3(0, 0, 0.025), Vector3(-90, 0, 0))
	_add(root, tube(0.0, 0.021, 0.085, 8), body, Vector3(0, 0, -0.1125), Vector3(-90, 0, 0))
	var canopy := SphereMesh.new()
	canopy.radius = 0.013
	canopy.height = 0.026
	canopy.radial_segments = 10
	canopy.rings = 5
	_add(root, canopy, paint(GLASS, 0.6, 0.15), Vector3(0, 0.019, -0.062), Vector3.ZERO, Vector3(1.0, 0.95, 2.6))
	# Delta wings (hostile: sharper, forward-raked tips).
	var wing := PackedVector2Array([Vector2(0.018, -0.045), Vector2(0.125, 0.055), Vector2(0.125, 0.078), Vector2(0.018, 0.085)])
	if hostile:
		wing = PackedVector2Array([Vector2(0.018, -0.02), Vector2(0.11, 0.035), Vector2(0.118, 0.07), Vector2(0.018, 0.08)])
	_add(root, plate(wing, 0.005), body, Vector3(0, -0.006, 0))
	_add(root, plate(mirror_x(wing), 0.005), body, Vector3(0, -0.006, 0))
	# Tailplanes.
	var stab := PackedVector2Array([Vector2(0.02, 0.085), Vector2(0.07, 0.12), Vector2(0.07, 0.135), Vector2(0.02, 0.135)])
	_add(root, plate(stab, 0.004), dark, Vector3(0, -0.004, 0))
	_add(root, plate(mirror_x(stab), 0.004), dark, Vector3(0, -0.004, 0))
	# Twin canted fins: a plate rotated upright.
	var fin := PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.06, 0.115), Vector2(0.06, 0.135), Vector2(0.0, 0.125)])
	for side: float in [-1.0, 1.0]:
		_add(root, plate(fin, 0.004), dark, Vector3(0.016 * side, 0.016, 0), Vector3(0, 0, 90.0 - 14.0 * side))
	# Intakes.
	for side: float in [-1.0, 1.0]:
		_add(root, box(Vector3(0.016, 0.022, 0.07)), dark, Vector3(0.028 * side, -0.004, -0.005))
	# Nozzle + afterburner.
	_add(root, tube(0.019, 0.015, 0.025, 10), dark, Vector3(0, 0, 0.13), Vector3(-90, 0, 0))
	var burner_mesh := ImmediateMesh.new()
	Neon.build_tube(burner_mesh, PackedVector3Array([Vector3(0, 0, 0.143), Vector3(0, 0, 0.21)]), func(t): return 0.013 * (1.0 - t * 0.85))
	var burner := MeshInstance3D.new()
	burner.mesh = burner_mesh
	burner.material_override = Neon.glow_material(Color(1.0, 0.55, 0.15) if hostile else Color(0.35, 0.75, 1.0), true, true)
	burner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(burner)
	# Nav lights: port red, starboard green, plus the faction accent stripe.
	_add(root, sphere(0.003, 6, 3), light(Color(1, 0.15, 0.1)), Vector3(-0.125, -0.006, 0.066))
	_add(root, sphere(0.003, 6, 3), light(Color(0.1, 1, 0.3)), Vector3(0.125, -0.006, 0.066))
	_add(root, box(Vector3(0.002, 0.003, 0.11)), light(accent), Vector3(0, 0.024, 0.04))
	# Twin cannons at the wing roots.
	var muzzles: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		_add(root, tube(0.0022, 0.0022, 0.04, 6), dark, Vector3(0.026 * side, -0.002, -0.07), Vector3(-90, 0, 0))
		var m := Node3D.new()
		m.position = Vector3(0.026 * side, -0.002, -0.092)
		root.add_child(m)
		muzzles.append(m)
	var nose := Node3D.new()
	nose.position = Vector3(0, 0, -0.16)
	root.add_child(nose)
	# Laser pod under the nose.
	_add(root, tube(0.004, 0.006, 0.03, 8), dark, Vector3(0, -0.02, -0.075), Vector3(-90, 0, 0))
	_add(root, sphere(0.003, 6, 3), light(accent), Vector3(0, -0.02, -0.091))
	var laser := Node3D.new()
	laser.position = Vector3(0, -0.02, -0.092)
	root.add_child(laser)
	# Pylons with missiles (player shows its stock).
	var pylons: Array[Node3D] = []
	for x: float in [-0.092, -0.058, 0.058, 0.092]:
		_add(root, box(Vector3(0.002, 0.006, 0.03)), dark, Vector3(x, -0.011, 0.04))
		var m := missile(hostile)
		m.position = Vector3(x, -0.0185, 0.035)
		root.add_child(m)
		pylons.append(m)
	var bombs: Array[Node3D] = []
	if not hostile:
		for x: float in [-0.011, 0.011]:
			var b := bomb()
			b.position = Vector3(x, -0.03, 0.03)
			root.add_child(b)
			bombs.append(b)
	return {"root": root, "pylons": pylons, "bombs": bombs, "burner": burner, "muzzles": muzzles, "laser": laser, "nose": nose}


# --- enemies --------------------------------------------------------------------

## Quad drone ~20 cm across. Returns {root, rotors: Array, eye}.
static func drone() -> Dictionary:
	var root := Node3D.new()
	root.name = "Drone"
	var body := paint(ENEMY_BODY, 0.3, 0.5)
	var dark := paint(ENEMY_DARK, 0.2, 0.7)
	var core := SphereMesh.new()
	core.radius = 0.045
	core.height = 0.05
	core.radial_segments = 10
	core.rings = 5
	_add(root, core, body, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1.2))
	var rotors: Array = []
	for i in range(4):
		var a := deg_to_rad(45.0 + 90.0 * i)
		var dir := Vector3(cos(a), 0, sin(a))
		var arm := _add(root, box(Vector3(0.075, 0.008, 0.012)), dark, dir * 0.055, Vector3(0, -rad_to_deg(a), 0))
		arm.name = "Arm"
		_add(root, tube(0.012, 0.012, 0.016, 8), dark, dir * 0.092 + Vector3(0, 0.006, 0))
		var disc := CylinderMesh.new()
		disc.top_radius = 0.034
		disc.bottom_radius = 0.034
		disc.height = 0.002
		disc.radial_segments = 16
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.7, 0.72, 0.75, 0.28)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var rotor := _add(root, disc, rm, dir * 0.092 + Vector3(0, 0.016, 0))
		var blade := _add(rotor, box(Vector3(0.066, 0.002, 0.006)), dark)
		blade.name = "Blade"
		rotors.append(rotor)
	var eye := _add(root, sphere(0.009, 8, 4), light(ENEMY_ACCENT), Vector3(0, -0.004, -0.05))
	_add(root, tube(0.003, 0.003, 0.03, 6), dark, Vector3(0, -0.026, -0.03), Vector3(-90, 0, 0))
	return {"root": root, "rotors": rotors, "eye": eye}


## Flak tank ~22 cm long. Returns {root, turret, barrels: Node3D (pitch), muzzle}.
static func tank() -> Dictionary:
	var root := Node3D.new()
	root.name = "Tank"
	var body := paint(Color(0.30, 0.31, 0.27), 0.2, 0.65)
	var dark := paint(ENEMY_DARK, 0.2, 0.7)
	_add(root, box(Vector3(0.13, 0.04, 0.2)), body, Vector3(0, 0.036, 0))
	_add(root, plate(PackedVector2Array([Vector2(-0.065, -0.1), Vector2(0.065, -0.1), Vector2(0.05, -0.125), Vector2(-0.05, -0.125)]), 0.03), body, Vector3(0, 0.035, 0))
	for side: float in [-1.0, 1.0]:
		_add(root, box(Vector3(0.03, 0.036, 0.22)), dark, Vector3(0.075 * side, 0.018, 0))
		for k in range(4):
			_add(root, tube(0.012, 0.012, 0.032, 8), paint(Color(0.18, 0.18, 0.18), 0.4, 0.5), Vector3(0.075 * side, 0.016, -0.075 + k * 0.05), Vector3(0, 0, 90))
	var turret := Node3D.new()
	turret.position = Vector3(0, 0.058, 0.01)
	root.add_child(turret)
	_add(turret, tube(0.045, 0.05, 0.026, 8), body, Vector3(0, 0.012, 0))
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 0.02, -0.02)
	turret.add_child(pitch)
	for side: float in [-1.0, 1.0]:
		_add(pitch, tube(0.004, 0.005, 0.08, 6), dark, Vector3(0.012 * side, 0, -0.04), Vector3(-90, 0, 0))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -0.085)
	pitch.add_child(muzzle)
	_add(turret, sphere(0.006, 6, 3), light(ENEMY_ACCENT), Vector3(0, 0.028, 0.03))
	return {"root": root, "turret": turret, "barrels": pitch, "muzzle": muzzle}


## Boss gunship ~70 cm. Returns {root, turret, muzzles: Array, engines: Array, eye}.
static func gunship() -> Dictionary:
	var root := Node3D.new()
	root.name = "Gunship"
	var body := paint(ENEMY_BODY, 0.35, 0.45)
	var dark := paint(ENEMY_DARK, 0.3, 0.6)
	_add(root, tube(0.07, 0.085, 0.5, 8), body, Vector3(0, 0, 0.04), Vector3(-90, 0, 0))
	_add(root, tube(0.025, 0.07, 0.16, 8), body, Vector3(0, -0.01, -0.29), Vector3(-90, 0, 0))
	_add(root, box(Vector3(0.11, 0.02, 0.05)), light(ENEMY_ACCENT), Vector3(0, 0.035, -0.31))
	var wing := PackedVector2Array([Vector2(0.07, -0.08), Vector2(0.3, 0.0), Vector2(0.3, 0.09), Vector2(0.07, 0.12)])
	_add(root, plate(wing, 0.018), body, Vector3(0, 0.0, 0.05))
	_add(root, plate(mirror_x(wing), 0.018), body, Vector3(0, 0.0, 0.05))
	_add(root, plate(PackedVector2Array([Vector2(0, 0.17), Vector2(0.12, 0.3), Vector2(0.12, 0.33), Vector2(0, 0.31)]), 0.012), dark, Vector3(0, 0.06, 0), Vector3(0, 0, 90))
	var engines: Array = []
	for x: float in [-0.27, -0.14, 0.14, 0.27]:
		_add(root, tube(0.035, 0.03, 0.14, 10), dark, Vector3(x, -0.03, 0.06), Vector3(-90, 0, 0))
		var glow := _add(root, sphere(0.026, 10, 5), light(Color(1.0, 0.45, 0.1)), Vector3(x, -0.03, 0.132), Vector3.ZERO, Vector3(1, 1, 0.35))
		engines.append(glow)
	var turret := Node3D.new()
	turret.position = Vector3(0, -0.08, -0.2)
	root.add_child(turret)
	_add(turret, tube(0.04, 0.04, 0.04, 8), dark)
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		_add(turret, tube(0.006, 0.006, 0.09, 6), dark, Vector3(0.016 * side, -0.01, -0.05), Vector3(-90, 0, 0))
		var m := Node3D.new()
		m.position = Vector3(0.016 * side, -0.01, -0.098)
		turret.add_child(m)
		muzzles.append(m)
	for x: float in [-0.2, 0.2]:
		for k in range(3):
			var mm := missile(true)
			mm.position = Vector3(x + (k - 1) * 0.03, -0.02, 0.0)
			root.add_child(mm)
	var eye := _add(root, sphere(0.016, 8, 4), light(ENEMY_ACCENT), Vector3(0, -0.035, -0.34))
	return {"root": root, "turret": turret, "muzzles": muzzles, "engines": engines, "eye": eye}


## Practice target on an arm that swings out of the wall. Faces +Z (toward the
## room) once open. Returns {root, hinge, face}.
static func target() -> Dictionary:
	var root := Node3D.new()
	root.name = "Target"
	var dark := paint(ENEMY_DARK, 0.2, 0.7)
	_add(root, box(Vector3(0.05, 0.05, 0.012)), dark, Vector3(0, 0, 0.006))
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0, 0.012)
	root.add_child(hinge)
	_add(hinge, box(Vector3(0.012, 0.012, 0.12)), dark, Vector3(0, 0, 0.06))
	var face := Node3D.new()
	face.position = Vector3(0, 0, 0.125)
	hinge.add_child(face)
	var rings := [[0.11, Color(0.95, 0.95, 0.93)], [0.085, Color(0.85, 0.12, 0.1)], [0.06, Color(0.95, 0.95, 0.93)], [0.035, Color(0.85, 0.12, 0.1)], [0.014, Color(1.0, 0.85, 0.1)]]
	for i in range(rings.size()):
		var disc := tube(rings[i][0], rings[i][0], 0.006, 24)
		_add(face, disc, paint(rings[i][1], 0.0, 0.7), Vector3(0, 0, 0.001 * i), Vector3(90, 0, 0))
	return {"root": root, "hinge": hinge, "face": face}


# --- the hangar in the wall ----------------------------------------------------------

static func _occluder_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_disabled, shadows_disabled;
void fragment() { ALBEDO = vec3(0.0); ALPHA = 0.0; }
"""
	var m := ShaderMaterial.new()
	m.shader = s
	m.render_priority = PRI_OCCLUDER
	return m


static func _interior_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.render_priority = PRI_INTERIOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	return m


## A launch bay cut into a real wall. Local frame: the wall surface is z = 0,
## +Z points into the room, the opening is `w`×`h` centred on the origin.
## Behind the wall is a short lit tunnel, hidden outside the opening by a
## depth-only occluder ring drawn first. Returns {root, doors: Array, lights: Array, tunnel}.
static func hangar(w: float, h: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "Hangar"
	var depth := 0.55
	# Occluder: a big frame around the opening, on the wall plane.
	var ring := 1.4
	var occ := _occluder_material()
	for part in [[Vector3(0, (h + ring) * 0.5, 0), Vector2(w + ring * 2.0, ring)], [Vector3(0, -(h + ring) * 0.5, 0), Vector2(w + ring * 2.0, ring)],
			[Vector3((w + ring) * 0.5, 0, 0), Vector2(ring, h)], [Vector3(-(w + ring) * 0.5, 0, 0), Vector2(ring, h)]]:
		var q := QuadMesh.new()
		q.size = part[1]
		_add(root, q, occ, part[0] + Vector3(0, 0, 0.002))
	# Tunnel behind the wall.
	var tunnel := Node3D.new()
	root.add_child(tunnel)
	var wall_m := _interior_material(Color(0.13, 0.14, 0.16))
	var floor_m := _interior_material(Color(0.09, 0.095, 0.11))
	_add(tunnel, box(Vector3(w, 0.01, depth)), floor_m, Vector3(0, -h * 0.5, -depth * 0.5))
	_add(tunnel, box(Vector3(w, 0.01, depth)), wall_m, Vector3(0, h * 0.5, -depth * 0.5))
	_add(tunnel, box(Vector3(0.01, h, depth)), wall_m, Vector3(-w * 0.5, 0, -depth * 0.5))
	_add(tunnel, box(Vector3(0.01, h, depth)), wall_m, Vector3(w * 0.5, 0, -depth * 0.5))
	_add(tunnel, box(Vector3(w, h, 0.01)), _interior_material(Color(0.05, 0.05, 0.06)), Vector3(0, 0, -depth))
	var strip_m := light(ENEMY_ACCENT)
	strip_m.render_priority = PRI_INTERIOR + 1
	for k in range(3):
		var z := -0.1 - k * 0.17
		_add(tunnel, box(Vector3(w * 0.8, 0.006, 0.012)), strip_m, Vector3(0, -h * 0.5 + 0.008, z))
	# Frame flush with the wall.
	var frame := paint(Color(0.22, 0.23, 0.25), 0.4, 0.5)
	var t := 0.035
	_add(root, box(Vector3(w + t * 2.0, t, 0.03)), frame, Vector3(0, h * 0.5 + t * 0.5, 0.012))
	_add(root, box(Vector3(w + t * 2.0, t, 0.03)), frame, Vector3(0, -h * 0.5 - t * 0.5, 0.012))
	_add(root, box(Vector3(t, h, 0.03)), frame, Vector3(w * 0.5 + t * 0.5, 0, 0.012))
	_add(root, box(Vector3(t, h, 0.03)), frame, Vector3(-w * 0.5 - t * 0.5, 0, 0.012))
	# Hazard chevrons on the top bar.
	for k in range(6):
		_add(root, box(Vector3(0.022, t * 0.6, 0.003)), paint(Color(0.95, 0.72, 0.08), 0.0, 0.6), Vector3(-w * 0.4 + k * w * 0.16, h * 0.5 + t * 0.5, 0.0285), Vector3(0, 0, 35))
	# Two blast doors that split up/down.
	var doors: Array = []
	var door_m := paint(Color(0.30, 0.31, 0.33), 0.45, 0.45)
	for side: float in [1.0, -1.0]:
		var d := _add(root, box(Vector3(w, h * 0.5, 0.02)), door_m, Vector3(0, h * 0.25 * side, -0.012))
		d.set_meta("closed_y", h * 0.25 * side)
		d.set_meta("open_y", (h * 0.75 + 0.02) * side)
		doors.append(d)
		_add(d, box(Vector3(w * 0.9, 0.008, 0.004)), paint(Color(0.95, 0.72, 0.08), 0.0, 0.6), Vector3(0, -h * 0.22 * side, 0.012))
	# Warning lamps.
	var lights: Array = []
	for side: float in [-1.0, 1.0]:
		var l := _add(root, sphere(0.012, 8, 4), light(Neon.AMBER), Vector3((w * 0.5 + t * 0.5) * side, h * 0.5 + t * 0.5, 0.03))
		lights.append(l)
	return {"root": root, "doors": doors, "lights": lights, "tunnel": tunnel}


## Total triangles under a node (for the budget test).
static func triangles(root: Node) -> int:
	return Neon.count_triangles(root)
