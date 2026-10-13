class_name UI
extends RefCounted
## Wordless UI kit: neon line icons, filled stars, digit labels and aimable
## buttons. Everything is built from tubes and polygons at runtime, so there
## are no texture assets and no words — only shapes and numbers.

static var _font: Font


static func font() -> Font:
	if _font == null:
		var f := FontFile.new()
		f.load_dynamic_font("res://assets/fonts/BalooBhaijaan2-Arabic.ttf")
		var variation := FontVariation.new()
		variation.base_font = f
		variation.variation_opentype = {"wght": 760}
		_font = variation
	return _font


## Big rounded digits that always face the viewer.
static func digits(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.font = font()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0011
	l.modulate = color
	l.outline_size = maxi(4, size / 7)
	l.outline_modulate = Color(0.02, 0.02, 0.06, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Outline shapes in the icon's local XY plane, unit size ≈ 1.
static func icon_points(kind: String) -> Array:
	match kind:
		"play":
			return [PackedVector3Array([Vector3(-0.32, -0.45, 0), Vector3(0.48, 0, 0), Vector3(-0.32, 0.45, 0), Vector3(-0.32, -0.45, 0)])]
		"retry":
			var arc := PackedVector3Array()
			for i in range(19):
				var a := deg_to_rad(40.0 + i * 15.0)
				arc.append(Vector3(cos(a) * 0.42, sin(a) * 0.42, 0))
			var head := PackedVector3Array([Vector3(0.2, 0.05, 0), Vector3(0.33, 0.28, 0), Vector3(0.52, 0.07, 0)])
			return [arc, head]
		"home":
			return [PackedVector3Array([Vector3(-0.38, -0.4, 0), Vector3(-0.38, 0.05, 0), Vector3(0, 0.42, 0), Vector3(0.38, 0.05, 0), Vector3(0.38, -0.4, 0), Vector3(-0.38, -0.4, 0)]), PackedVector3Array([Vector3(-0.1, -0.4, 0), Vector3(-0.1, -0.12, 0), Vector3(0.1, -0.12, 0), Vector3(0.1, -0.4, 0)])]
		"crown":
			return [PackedVector3Array([Vector3(-0.45, -0.3, 0), Vector3(-0.45, 0.25, 0), Vector3(-0.2, 0.0, 0), Vector3(0, 0.4, 0), Vector3(0.2, 0.0, 0), Vector3(0.45, 0.25, 0), Vector3(0.45, -0.3, 0), Vector3(-0.45, -0.3, 0)])]
		"heart":
			var h := PackedVector3Array()
			for i in range(33):
				var t := TAU * i / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				h.append(Vector3(x, y, 0) / 34.0)
			return [h]
		_:
			return [star_outline()]


static func star_outline() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in range(11):
		var a := PI * 0.5 + TAU * i / 10.0
		var r := 0.5 if i % 2 == 0 else 0.21
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0))
	return pts


## A neon line icon (core + glow), `size` metres across.
static func icon(kind: String, color: Color, size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Icon_" + kind
	for stroke in icon_points(kind):
		var scaled := PackedVector3Array()
		for p in stroke:
			scaled.append(p * size)
		for core in [true, false]:
			var mesh := ImmediateMesh.new()
			var r := size * (0.035 if core else 0.11)
			Neon.build_tube(mesh, scaled, func(_t): return r)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = Neon.glow_material(color, core)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	return root


static func set_icon_color(icon_node: Node3D, color: Color, alpha: float = 1.0) -> void:
	for c in icon_node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("tint", color)
			m.set_shader_parameter("alpha_scale", alpha)


## A filled five-point star (flat, faces +Z).
static func filled_star(color: Color, size: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := star_outline()
	for i in range(10):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(outline[i] * size)
		st.add_vertex(outline[i + 1] * size)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := Neon.emitter_material(color)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## An aimable round button: ring + icon + soft halo. `hovered` brightens it.
class Button3D:
	extends Node3D
	var kind: String = "play"
	var color: Color = Neon.CYAN
	var radius: float = 0.11
	var hovered: float = 0.0
	var pressed_flash: float = 0.0
	var _ring: MeshInstance3D
	var _icon: Node3D
	var _halo: MeshInstance3D
	var _time: float = 0.0

	func _init(icon_kind: String = "play", tint: Color = Neon.CYAN, r: float = 0.11) -> void:
		kind = icon_kind
		color = tint
		radius = r

	func _ready() -> void:
		_ring = Neon.make_ring_mesh(color, radius, radius * 0.06)
		_ring.rotation_degrees.x = 90.0
		add_child(_ring)
		_icon = UI.icon(kind, color, radius * 1.1)
		add_child(_icon)
		_halo = Neon.make_halo(color, radius * 4.0, 0.15)
		add_child(_halo)

	func _process(delta: float) -> void:
		_time += delta
		pressed_flash = maxf(0.0, pressed_flash - delta * 3.0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			look_at(cam.global_position, Vector3.UP, true)
		var glow := color.lerp(Neon.WHITE, hovered * 0.4 + pressed_flash * 0.6)
		var s := 1.0 + hovered * 0.18 + sin(_time * 3.0) * 0.02 + pressed_flash * 0.25
		_ring.scale = Vector3.ONE * s
		_icon.scale = Vector3.ONE * s
		(_ring.material_override as StandardMaterial3D).albedo_color = glow
		UI.set_icon_color(_icon, glow)
		Neon.set_halo_color(_halo, color, 0.12 + hovered * 0.3 + pressed_flash * 0.5)

	## Distance from the aim ray to the button centre, or INF if behind.
	func ray_distance(origin: Vector3, direction: Vector3) -> float:
		var along := (global_position - origin).dot(direction)
		if along < 0.15:
			return INF
		return (origin + direction * along).distance_to(global_position)
