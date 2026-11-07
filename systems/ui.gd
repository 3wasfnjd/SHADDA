class_name UI
extends RefCounted
## SAQR's own look: Lalezar poster titles, Changa text, flat icons. The panel
## menus live in panel.gd / menus.gd; this file has the shared text helpers.

static var _fonts: Dictionary = {}


## "title" (Lalezar), "body" (Changa 600) or "bold" (Changa 800).
## Glyphs are multichannel signed-distance fields: in the headset text is
## always shrunk and moving with your head, and plain bitmap glyphs (no
## mipmaps) shimmer and break up. MSDF stays sharp at any size and distance.
static func font(kind: String = "bold") -> Font:
	if not _fonts.has(kind):
		var f := FontFile.new()
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 48
		f.msdf_size = 64
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		if kind == "title":
			f.load_dynamic_font("res://assets/fonts/Lalezar-Regular.ttf")
			_fonts[kind] = f
		else:
			f.load_dynamic_font("res://assets/fonts/Changa.ttf")
			var v := FontVariation.new()
			v.base_font = f
			v.variation_opentype = {"wght": 800 if kind == "bold" else 600}
			_fonts[kind] = v
	return _fonts[kind]


static func number(text: String, size: int, color: Color, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.font = font("bold")
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = color
	l.outline_size = clampi(size / 5, 8, 22)
	l.outline_modulate = Toon.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.render_priority = 20
	l.outline_render_priority = 19
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Flat icon outline (XY plane, ~1 unit) for the given kind.
static func icon_shape(kind: String) -> PackedVector2Array:
	match kind:
		"play":
			return PackedVector2Array([Vector2(-0.3, -0.42), Vector2(0.45, 0), Vector2(-0.3, 0.42)])
		"home":
			return PackedVector2Array([Vector2(-0.38, -0.4), Vector2(0.38, -0.4), Vector2(0.38, 0.05), Vector2(0, 0.42), Vector2(-0.38, 0.05)])
		"retry":
			var pts := PackedVector2Array()
			for i in range(15):
				var a := deg_to_rad(60.0 + i * 17.0)
				pts.append(Vector2(cos(a), sin(a)) * 0.42)
			for i in range(14, -1, -1):
				var a2 := deg_to_rad(60.0 + i * 17.0)
				pts.append(Vector2(cos(a2), sin(a2)) * 0.24)
			return pts
		"star":
			var s := Toon.star(0.5)
			var flipped := PackedVector2Array()
			for p in s:
				flipped.append(Vector2(p.x, -p.y))
			return flipped
		"engine":
			var g := PackedVector2Array()
			for i in range(16):
				var a := TAU * i / 16.0
				var r := 0.45 if i % 2 == 0 else 0.32
				g.append(Vector2(cos(a), sin(a)) * r)
			return g
		"guns":
			return PackedVector2Array([Vector2(-0.45, -0.12), Vector2(0.45, -0.12), Vector2(0.45, 0.12), Vector2(-0.1, 0.12), Vector2(-0.18, 0.4), Vector2(-0.38, 0.4), Vector2(-0.3, 0.12), Vector2(-0.45, 0.12)])
		"rockets":
			return PackedVector2Array([Vector2(0, 0.48), Vector2(0.14, 0.25), Vector2(0.14, -0.2), Vector2(0.3, -0.42), Vector2(-0.3, -0.42), Vector2(-0.14, -0.2), Vector2(-0.14, 0.25)])
		"armor":
			return PackedVector2Array([Vector2(0, 0.46), Vector2(0.38, 0.32), Vector2(0.34, -0.1), Vector2(0, -0.46), Vector2(-0.34, -0.1), Vector2(-0.38, 0.32)])
		"cluster":
			var c := PackedVector2Array()
			for i in range(20):
				var a := TAU * i / 20.0
				c.append(Vector2(cos(a) * 0.3, sin(a) * 0.3 - 0.08))
			c.insert(5, Vector2(0.08, 0.45))
			c.insert(6, Vector2(-0.08, 0.45))
			return c
		"plane":
			return PackedVector2Array([Vector2(0, 0.45), Vector2(0.06, 0.2), Vector2(0.45, 0.05), Vector2(0.45, -0.05), Vector2(0.06, -0.05), Vector2(0.05, -0.3), Vector2(0.18, -0.38), Vector2(0.18, -0.45), Vector2(-0.18, -0.45), Vector2(-0.18, -0.38), Vector2(-0.05, -0.3), Vector2(-0.06, -0.05), Vector2(-0.45, -0.05), Vector2(-0.45, 0.05), Vector2(-0.06, 0.2)])
		"rings":
			return _arc(0.44, 0.28, 5.0, 355.0)
		"coin":
			return _arc(0.45, 0.0, 0.0, 360.0)
		"truck":
			return PackedVector2Array([Vector2(-0.45, -0.25), Vector2(0.45, -0.25), Vector2(0.45, 0.0), Vector2(0.3, 0.2), Vector2(0.1, 0.2), Vector2(0.1, 0.3), Vector2(-0.45, 0.3)])
		"shield":
			return PackedVector2Array([Vector2(0, 0.46), Vector2(0.38, 0.32), Vector2(0.34, -0.1), Vector2(0, -0.46), Vector2(-0.34, -0.1), Vector2(-0.38, 0.32)])
		"radar":
			var r := _arc(0.45, 0.3, 200.0, 340.0)
			r.append(Vector2(0.05, -0.05))
			r.append(Vector2(0.05, -0.45))
			r.append(Vector2(-0.05, -0.45))
			r.append(Vector2(-0.05, -0.05))
			return r
		"bomber":
			return PackedVector2Array([Vector2(0, 0.45), Vector2(0.07, 0.25), Vector2(0.48, 0.1), Vector2(0.48, -0.02), Vector2(0.07, 0.0), Vector2(0.06, -0.3), Vector2(0.2, -0.4), Vector2(0.2, -0.46), Vector2(-0.2, -0.46), Vector2(-0.2, -0.4), Vector2(-0.06, -0.3), Vector2(-0.07, 0.0), Vector2(-0.48, -0.02), Vector2(-0.48, 0.1), Vector2(-0.07, 0.25)])
		"lock":
			var l := PackedVector2Array([Vector2(-0.32, -0.42), Vector2(0.32, -0.42), Vector2(0.32, 0.05), Vector2(0.22, 0.05)])
			l.append_array(_arc_pts(0.22, 0.0, 180.0, Vector2(0, 0.05), true))
			l.append_array(_arc_pts(0.12, 180.0, 0.0, Vector2(0, 0.05), false))
			l.append(Vector2(-0.22, 0.05))
			l.append(Vector2(-0.32, 0.05))
			return l
		"gear":
			var g2 := PackedVector2Array()
			for i in range(24):
				var a := TAU * i / 24.0
				var rr := 0.45 if (i / 2) % 2 == 0 else 0.33
				g2.append(Vector2(cos(a), sin(a)) * rr)
			return g2
		"mines":
			var m := PackedVector2Array()
			for i in range(16):
				var a := TAU * i / 16.0
				m.append(Vector2(cos(a), sin(a)) * (0.46 if i % 2 == 0 else 0.28))
			return m
		"lightning":
			return PackedVector2Array([Vector2(0.1, 0.48), Vector2(-0.28, -0.02), Vector2(-0.02, -0.02), Vector2(-0.12, -0.48), Vector2(0.3, 0.06), Vector2(0.04, 0.06)])
		"flares":
			return PackedVector2Array([Vector2(0, 0.48), Vector2(0.12, 0.12), Vector2(0.46, 0.0), Vector2(0.12, -0.12), Vector2(0, -0.48), Vector2(-0.12, -0.12), Vector2(-0.46, 0.0), Vector2(-0.12, 0.12)])
		"bombs":
			var bo := _arc(0.3, 0.0, 0.0, 360.0)
			for i in range(bo.size()):
				bo[i] += Vector2(0, -0.1)
			bo.insert(4, Vector2(0.08, 0.45))
			bo.insert(5, Vector2(-0.08, 0.45))
			return bo
		"quad":
			return PackedVector2Array([Vector2(-0.45, -0.3), Vector2(0.45, -0.3), Vector2(0.45, -0.16), Vector2(-0.2, -0.16), Vector2(-0.2, -0.06), Vector2(0.45, -0.06), Vector2(0.45, 0.08), Vector2(-0.2, 0.08), Vector2(-0.2, 0.18), Vector2(0.45, 0.18), Vector2(0.45, 0.32), Vector2(-0.45, 0.32)])
		"cannon":
			return PackedVector2Array([Vector2(-0.45, -0.18), Vector2(0.1, -0.18), Vector2(0.1, -0.08), Vector2(0.48, -0.08), Vector2(0.48, 0.08), Vector2(0.1, 0.08), Vector2(0.1, 0.18), Vector2(-0.45, 0.18)])
		"twin":
			return PackedVector2Array([Vector2(-0.45, -0.24), Vector2(0.45, -0.24), Vector2(0.45, -0.08), Vector2(-0.2, -0.08), Vector2(-0.2, 0.08), Vector2(0.45, 0.08), Vector2(0.45, 0.24), Vector2(-0.45, 0.24)])
		"back":
			return PackedVector2Array([Vector2(0.45, -0.1), Vector2(-0.1, -0.1), Vector2(-0.1, -0.35), Vector2(-0.48, 0.0), Vector2(-0.1, 0.35), Vector2(-0.1, 0.1), Vector2(0.45, 0.1)])
		"pause":
			return PackedVector2Array([Vector2(-0.3, -0.4), Vector2(-0.08, -0.4), Vector2(-0.08, 0.4), Vector2(-0.3, 0.4)])
		"stick":
			return PackedVector2Array([Vector2(-0.4, -0.45), Vector2(0.4, -0.45), Vector2(0.4, -0.25), Vector2(0.06, -0.25), Vector2(0.06, 0.06), Vector2(0.2, 0.2), Vector2(0.2, 0.42), Vector2(-0.2, 0.42), Vector2(-0.2, 0.2), Vector2(-0.06, 0.06), Vector2(-0.06, -0.25), Vector2(-0.4, -0.25)])
		"minigun":
			var mg := PackedVector2Array([Vector2(-0.45, -0.3), Vector2(-0.1, -0.3)])
			for k in range(6):
				var y := -0.26 + k * 0.1
				mg.append(Vector2(0.46, y))
				mg.append(Vector2(0.46, y + 0.06))
			mg.append(Vector2(-0.1, 0.3))
			mg.append(Vector2(-0.45, 0.3))
			return mg
		"swarm":
			return PackedVector2Array([Vector2(-0.46, -0.06), Vector2(0.1, -0.06), Vector2(0.1, -0.2), Vector2(0.24, -0.06), Vector2(0.46, 0.0), Vector2(0.24, 0.06), Vector2(0.1, 0.2), Vector2(0.1, 0.06), Vector2(-0.46, 0.06), Vector2(-0.3, 0.0)])
		"napalm":
			return PackedVector2Array([Vector2(0, 0.48), Vector2(0.14, 0.18), Vector2(0.3, 0.3), Vector2(0.38, -0.05), Vector2(0.28, -0.35), Vector2(0, -0.46), Vector2(-0.28, -0.35), Vector2(-0.38, -0.05), Vector2(-0.3, 0.3), Vector2(-0.14, 0.18)])
		"heli":
			return PackedVector2Array([Vector2(-0.48, 0.34), Vector2(0.48, 0.34), Vector2(0.48, 0.28), Vector2(0.04, 0.28), Vector2(0.04, 0.18), Vector2(0.2, 0.12), Vector2(0.24, -0.04), Vector2(0.12, -0.16), Vector2(-0.1, -0.16), Vector2(-0.2, -0.06), Vector2(-0.48, -0.02), Vector2(-0.48, 0.06), Vector2(-0.22, 0.08), Vector2(-0.12, 0.18), Vector2(-0.04, 0.18), Vector2(-0.04, 0.28), Vector2(-0.48, 0.28)])
		"missile":
			return PackedVector2Array([Vector2(0, 0.48), Vector2(0.1, 0.3), Vector2(0.1, -0.2), Vector2(0.24, -0.4), Vector2(0.1, -0.36), Vector2(0.06, -0.46), Vector2(-0.06, -0.46), Vector2(-0.1, -0.36), Vector2(-0.24, -0.4), Vector2(-0.1, -0.2), Vector2(-0.1, 0.3)])
		"check":
			return PackedVector2Array([Vector2(-0.45, 0.02), Vector2(-0.3, 0.16), Vector2(-0.12, -0.04), Vector2(0.32, 0.42), Vector2(0.46, 0.28), Vector2(-0.12, -0.32)])
	return PackedVector2Array([Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)])


static func _arc_pts(r: float, a0: float, a1: float, c: Vector2, _ccw: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(13):
		var a := deg_to_rad(lerpf(a0, a1, i / 12.0))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## A ring (or disc when inner = 0) as one simple polygon with a hairline slit.
static func _arc(outer: float, inner: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 28
	for i in range(n + 1):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
		pts.append(Vector2(cos(a), sin(a)) * outer)
	if inner > 0.0:
		for i in range(n, -1, -1):
			var a2 := deg_to_rad(lerpf(a0, a1, float(i) / n))
			pts.append(Vector2(cos(a2), sin(a2)) * inner)
	elif a1 - a0 >= 359.0:
		pts.remove_at(pts.size() - 1)
	return pts


## A flat icon facing +Z, `size` metres across.
static func icon(kind: String, color: Color, size: float, depth: float = 0.004) -> Node3D:
	var root := Node3D.new()
	var shape := icon_shape(kind)
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(Vector2(p.x, -p.y) * size)
	var mi := Toon.add(root, Toon.slab(pts, depth), Toon.mat(color, 0.4, size * 0.03), Vector3.ZERO, Vector3(90, 0, 0))
	mi.name = "Shape"
	return root


## A big cartoon push-button: a fat disc with a rim and an icon. Faces +Z.
class Button3D:
	extends Node3D
	var kind: String = "play"
	var color: Color = Color(0.2, 0.75, 0.3)
	var radius: float = 0.1
	var hovered: float = 0.0
	var pressed: float = 0.0
	var _cap: Node3D
	var _t: float = 0.0

	func _init(icon_kind: String = "play", tint: Color = Color(0.2, 0.75, 0.3), r: float = 0.1) -> void:
		kind = icon_kind
		color = tint
		radius = r

	func _ready() -> void:
		Toon.add(self, Toon.can(radius * 1.12, radius * 1.18, radius * 0.25, 28), Toon.mat(Color(0.18, 0.18, 0.2), 0.3, radius * 0.03), Vector3(0, 0, -radius * 0.1), Vector3(90, 0, 0))
		_cap = Node3D.new()
		add_child(_cap)
		Toon.add(_cap, Toon.can(radius, radius, radius * 0.3, 28), Toon.mat(color, 0.6, radius * 0.03), Vector3(0, 0, radius * 0.08), Vector3(90, 0, 0))
		var ic := UI.icon(kind, Color(1, 1, 1), radius * 1.1, radius * 0.08)
		ic.position = Vector3(0, 0, radius * 0.25)
		_cap.add_child(ic)

	func _process(delta: float) -> void:
		_t += delta
		pressed = maxf(0.0, pressed - delta * 4.0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to := cam.global_position - global_position
			to.y *= 0.3
			if to.length() > 0.05:
				look_at(global_position - to, Vector3.UP)
		var s := 1.0 + hovered * 0.12 + sin(_t * 4.0) * 0.015 * (1.0 - hovered)
		scale = Vector3.ONE * s
		_cap.position.z = -pressed * radius * 0.15

	func ray_distance(origin: Vector3, direction: Vector3) -> float:
		var along := (global_position - origin).dot(direction)
		if along < 0.1:
			return INF
		return (origin + direction * along).distance_to(global_position)
