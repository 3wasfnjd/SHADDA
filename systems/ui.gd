class_name UI
extends RefCounted
## Wordless cartoon UI: chunky numbers in the studio font with a thick ink
## outline, flat icons, and big 3D push-buttons you point at.

static var _font: Font


static func font() -> Font:
	if _font == null:
		var f := FontFile.new()
		f.load_dynamic_font("res://assets/fonts/BalooBhaijaan2-Arabic.ttf")
		var v := FontVariation.new()
		v.base_font = f
		v.variation_opentype = {"wght": 800}
		_font = v
	return _font


static func number(text: String, size: int, color: Color, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.font = font()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = color
	l.outline_size = maxi(8, size / 5)
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
	return PackedVector2Array([Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)])


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
