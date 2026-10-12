class_name ShaddaVisuals
extends RefCounted

static func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.65
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func label(text: String, size: int = 36) -> Label3D:
	var l := Label3D.new()
	l.font = load("res://assets/ui/DejaVuSans.ttf")
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0017
	l.outline_size = 5
	l.no_depth_test = false
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l

static func sphere(radius: float, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	n.mesh = mesh
	n.material_override = material(color, 0.7)
	return n

static func line(mesh: ImmediateMesh, points: PackedVector3Array, mat: Material) -> void:
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
