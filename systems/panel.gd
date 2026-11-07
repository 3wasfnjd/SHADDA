class_name Panel3D
extends Node3D
## A flat menu board floating in the room (XY plane, facing +Z). SAQR's look
## is a 1940s aviation poster: cream paper with an olive frame, a red ribbon
## banner, olive "dog-tag" buttons that lift toward you, amber highlight.
## Two more papers: "map" (an operations map with a grid, for the campaign)
## and "blueprint" (the hangar). Widgets are hit-tested with the controller
## ray in the board's local plane: buttons, segmented choices, sliders.

# Colours used by callers for things ON buttons (cream text on olive/red).
const BG := Color(0.95, 0.9, 0.78, 1.0)
const EDGE := Color(0.2, 0.24, 0.16)
const HEADER := Color(0.76, 0.16, 0.1)
const BTN := Color(0.3, 0.36, 0.22)
const BTN_HOVER := Color(1.0, 0.72, 0.18)
const PRIMARY := Color(0.78, 0.18, 0.1)
const DISABLED := Color(0.62, 0.6, 0.54)
const TEXT := Color(0.98, 0.95, 0.86)
const DIM := Color(0.7, 0.72, 0.66)
const GOLD := Color(1.0, 0.78, 0.2)
const DARK_TEXT := Color(0.12, 0.09, 0.06)
const PX := 0.00046       # metres per font pixel (48 px ≈ 2.2 cm, ≈1.3° at 1 m)

const STYLES := {
	"poster": {"bg": Color(0.95, 0.9, 0.78), "edge": Color(0.2, 0.24, 0.16), "inset": Color(0.88, 0.82, 0.68), "ink": Color(0.2, 0.14, 0.09), "dim": Color(0.48, 0.42, 0.34), "accent": Color(0.72, 0.14, 0.1), "star": Color(0.95, 0.62, 0.06), "btn": Color(0.3, 0.36, 0.22), "line": Color(0.72, 0.14, 0.1, 0.45)},
	"map": {"bg": Color(0.87, 0.8, 0.62), "edge": Color(0.32, 0.25, 0.16), "inset": Color(0.8, 0.72, 0.55), "ink": Color(0.22, 0.15, 0.08), "dim": Color(0.48, 0.4, 0.28), "accent": Color(0.72, 0.14, 0.1), "star": Color(0.95, 0.62, 0.06), "btn": Color(0.3, 0.36, 0.22), "line": Color(0.45, 0.36, 0.22, 0.35)},
	"blueprint": {"bg": Color(0.13, 0.3, 0.55), "edge": Color(0.9, 0.93, 0.98), "inset": Color(0.1, 0.24, 0.46), "ink": Color(0.96, 0.98, 1.0), "dim": Color(0.72, 0.82, 0.94), "accent": Color(1.0, 0.8, 0.3), "star": Color(1.0, 0.8, 0.3), "btn": Color(0.08, 0.17, 0.34), "line": Color(0.45, 0.62, 0.86, 0.45)},
}

var size: Vector2 = Vector2(0.8, 0.55)
var widgets: Array = []
var hovered: Dictionary = {}
var dragging: Dictionary = {}
var open_t: float = 0.0
var rtl: bool = true
var style: String = "poster"
var pal: Dictionary = STYLES.poster
var ink: Color = STYLES.poster.ink
var dim: Color = STYLES.poster.dim
var accent: Color = STYLES.poster.accent
var inset: Color = STYLES.poster.inset
var _press_lock: float = 0.25
var anims: Array = []          # {node, kind: "pulse"|"orbit", ...}


func setup(w: float, h: float, title: String = "", header: Color = HEADER, board_style: String = "poster") -> Panel3D:
	size = Vector2(w, h)
	style = board_style
	pal = STYLES.get(style, STYLES.poster)
	ink = pal.ink
	dim = pal.dim
	accent = pal.accent
	inset = pal.inset
	rtl = Lang.code() == "ar"
	scale = Vector3.ONE * 0.92
	# Soft drop shadow, frame, paper.
	shape(self, rrect(w + 0.02, h + 0.02, 0.03), Vector3(0.012, -0.016, -0.012), Color(0, 0, 0, 0.32), 0.001)
	shape(self, rrect(w + 0.016, h + 0.016, 0.026), Vector3(0, 0, -0.004), pal.edge, 0.002)
	shape(self, rrect(w, h, 0.02), Vector3(0, 0, -0.002), pal.bg, 0.002)
	# Thin printed border line inside the paper.
	_frame_line(w - 0.03, h - 0.03, 0.0015, fade(pal.line, 0.8))
	match style:
		"map":
			_grid(w, h, 0.06)
			for blob in [[Vector2(-0.3, -0.2), 0.12], [Vector2(0.28, 0.12), 0.09], [Vector2(0.05, -0.28), 0.07]]:
				var pts := PackedVector2Array()
				for i in range(14):
					var a := TAU * i / 14.0
					pts.append(Vector2(cos(a), sin(a) * 0.65) * float(blob[1]) * (0.8 + 0.25 * sin(a * 3.0 + blob[1] * 40.0)))
				shape(self, pts, Vector3(blob[0].x * w, blob[0].y * h, 0.0002), fade(Color(0.6, 0.52, 0.32), 0.45), 0.0004)
		"blueprint":
			_grid(w, h, 0.04)
		_:
			# Masking tape holding the poster up.
			for cx: float in [-1.0, 1.0]:
				var d := Vector2(cos(-cx * 0.6), sin(-cx * 0.6)) * 0.05
				shape(self, bar(-d, d, 0.028), Vector3(cx * (w * 0.5 - 0.02), h * 0.5 - 0.005, 0.004), Color(0.92, 0.86, 0.66, 0.85), 0.001)
	if title != "":
		_ribbon(title, h * 0.5 - 0.055, minf(w * 0.7, 0.62), header)
	return self


## A colour mixed into the paper (opaque — see-through bits show the room).
func fade(c: Color, a: float) -> Color:
	return Color(pal.bg).lerp(Color(c, 1.0), clampf(a, 0.0, 1.0))


func _frame_line(w: float, h: float, t: float, c: Color) -> void:
	for spec in [[Vector2(0, h * 0.5), Vector2(w, t)], [Vector2(0, -h * 0.5), Vector2(w, t)], [Vector2(w * 0.5, 0), Vector2(t, h)], [Vector2(-w * 0.5, 0), Vector2(t, h)]]:
		var sz: Vector2 = spec[1]
		shape(self, PackedVector2Array([Vector2(-sz.x * 0.5, -sz.y * 0.5), Vector2(sz.x * 0.5, -sz.y * 0.5), Vector2(sz.x * 0.5, sz.y * 0.5), Vector2(-sz.x * 0.5, sz.y * 0.5)]), Vector3(spec[0].x, spec[0].y, 0.0006), c, 0.0005)


func _grid(w: float, h: float, step: float) -> void:
	var c: Color = fade(pal.line, pal.line.a * 0.7)
	var x := -w * 0.5 + step
	while x < w * 0.5 - 0.01:
		shape(self, PackedVector2Array([Vector2(-0.0007, -h * 0.48), Vector2(0.0007, -h * 0.48), Vector2(0.0007, h * 0.48), Vector2(-0.0007, h * 0.48)]), Vector3(x, 0, 0.0004), c, 0.0003)
		x += step
	var y := -h * 0.5 + step
	while y < h * 0.5 - 0.01:
		shape(self, PackedVector2Array([Vector2(-w * 0.48, -0.0007), Vector2(w * 0.48, -0.0007), Vector2(w * 0.48, 0.0007), Vector2(-w * 0.48, 0.0007)]), Vector3(0, y, 0.0004), c, 0.0003)
		y += step


## The red ribbon banner across the top, with folded tails.
func _ribbon(title: String, y: float, bw: float, color: Color) -> void:
	var bh := 0.078
	var dark := color.darkened(0.35)
	for side: float in [-1.0, 1.0]:
		var x0 := side * (bw * 0.5 - 0.01)
		var tail := PackedVector2Array([Vector2(0, -bh * 0.5 + 0.012), Vector2(side * 0.07, -bh * 0.5 + 0.012), Vector2(side * 0.05, 0.006), Vector2(side * 0.07, bh * 0.5 - 0.006), Vector2(0, bh * 0.5 - 0.006)])
		if side < 0:
			tail.reverse()
		shape(self, tail, Vector3(x0, y - 0.016, 0.001), dark, 0.0015)
	shape(self, PackedVector2Array([Vector2(-bw * 0.5, -bh * 0.5), Vector2(bw * 0.5, -bh * 0.5), Vector2(bw * 0.5, bh * 0.5), Vector2(-bw * 0.5, bh * 0.5)]), Vector3(0, y, 0.003), color, 0.002)
	# Stitched edges.
	for yy: float in [bh * 0.5 - 0.008, -bh * 0.5 + 0.008]:
		var n := int(bw / 0.016)
		for i in range(n):
			var x := -bw * 0.5 + 0.008 + i * 0.016
			shape(self, PackedVector2Array([Vector2(-0.004, -0.0008), Vector2(0.004, -0.0008), Vector2(0.004, 0.0008), Vector2(-0.004, 0.0008)]), Vector3(x, y + yy, 0.0045), Color(1, 0.9, 0.75, 0.6), 0.0004)
	var l := label(title, Vector2(0, y + 0.004), 84, TEXT, "title")
	l.position.z = 0.007


## Sunburst rays (poster style) behind a title.
func sunburst(center: Vector2, r: float, rays: int = 18, y_min: float = 0.0) -> void:
	var box := Rect2(Vector2(-size.x * 0.5 + 0.022, y_min), Vector2(size.x - 0.044, size.y * 0.5 - 0.022 - y_min))
	for i in range(rays):
		if i % 2 == 1:
			continue
		var a0 := TAU * i / rays
		var a1 := TAU * (i + 1) / rays
		var tri := PackedVector2Array([Vector2.ZERO, _clip_ray(center, Vector2(cos(a0), sin(a0)), r, box), _clip_ray(center, Vector2(cos(a1), sin(a1)), r, box)])
		shape(self, tri, Vector3(center.x, center.y, 0.0003), fade(Color(0.98, 0.7, 0.3), 0.35), 0.0003)


## A bar from a to b, `t` thick (for dashed routes, tape, rays).
static func bar(a: Vector2, b: Vector2, t: float) -> PackedVector2Array:
	var n := (b - a).orthogonal().normalized() * t * 0.5
	return PackedVector2Array([a - n, b - n, b + n, a + n])


## A ring (for a pulsing "you are here" marker).
func ring(center: Vector2, r: float, t: float, color: Color, pulse: bool = false) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(center.x, center.y, 0.001)
	add_child(node)
	var n := 28
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		shape(node, PackedVector2Array([Vector2(cos(a0), sin(a0)) * (r - t), Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r, Vector2(cos(a1), sin(a1)) * (r - t)]), Vector3.ZERO, color, 0.0006)
	if pulse:
		anims.append({"node": node, "kind": "pulse"})
	return node


## A small model flying an oval in front of the board.
func orbit(model: Node3D, center: Vector3, radius: Vector2) -> void:
	add_child(model)
	anims.append({"node": model, "kind": "orbit", "c": center, "r": radius, "a": 0.6})


func _animate(delta: float) -> void:
	for an in anims:
		var node: Node3D = an.node
		if not is_instance_valid(node):
			continue
		if an.kind == "pulse":
			var k := fmod(open_t * 0.9, 1.0)
			node.scale = Vector3.ONE * (0.85 + k * 0.6)
			for c in node.get_children():
				((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", fade(accent, 0.9 * (1.0 - k)))
		else:
			an.a += delta * 0.7
			var a: float = an.a
			var r: Vector2 = an.r
			var c: Vector3 = an.c
			var pos := c + Vector3(cos(a) * r.x, sin(a * 2.0) * 0.012, sin(a) * r.y)
			var tangent := Vector3(-sin(a) * r.x, cos(a * 2.0) * 0.024, cos(a) * r.y).normalized()
			node.position = pos
			node.basis = Basis.looking_at(tangent, Vector3.UP).scaled(node.basis.get_scale()) * Basis(Vector3.FORWARD, 0.45)
			if node.has_meta("prop"):
				(node.get_meta("prop") as Node3D).rotate_object_local(Vector3.FORWARD, delta * 40.0)


static func _clip_ray(c: Vector2, d: Vector2, r: float, box: Rect2) -> Vector2:
	var t := r
	if d.x > 1e-4: t = minf(t, (box.end.x - c.x) / d.x)
	if d.x < -1e-4: t = minf(t, (box.position.x - c.x) / d.x)
	if d.y > 1e-4: t = minf(t, (box.end.y - c.y) / d.y)
	if d.y < -1e-4: t = minf(t, (box.position.y - c.y) / d.y)
	return d * maxf(t, 0.0)


func _process(delta: float) -> void:
	open_t += delta
	_animate(delta)
	_press_lock = maxf(0.0, _press_lock - delta)
	var s := 1.0 - pow(1.0 - clampf(open_t / 0.18, 0.0, 1.0), 3.0) * 0.08
	scale = Vector3.ONE * s
	for w in widgets:
		if w.kind == "button":
			var target := 1.0 if (hovered == w and w.enabled) else 0.0
			w.hover = move_toward(w.hover, target, delta * 8.0)
			var base: Color = w.color
			var c := base.lerp(BTN_HOVER, w.hover * (0.0 if w.selected else 1.0)) if w.enabled else (DISABLED if style != "blueprint" else Color(0.2, 0.3, 0.45))
			(w.mat as ShaderMaterial).set_shader_parameter("albedo", c)
			(w.node as Node3D).scale = Vector3.ONE * (1.0 + w.hover * 0.04 - w.get("press", 0.0) * 0.05)
			# Tags lift toward you when pointed at.
			(w.node as Node3D).position.z = 0.002 + w.hover * 0.01 - w.get("press", 0.0) * 0.006
			w.press = maxf(0.0, w.get("press", 0.0) - delta * 5.0)
			if w.label:
				var dark: bool = (w.hover > 0.5 and not w.selected) or w.selected
				(w.label as Label3D).modulate = DARK_TEXT if dark and w.enabled else (TEXT if w.enabled else Color(0.4, 0.38, 0.34))
				(w.label as Label3D).outline_size = 0 if dark else 6


# --- building blocks -------------------------------------------------------------------------

## Mirror an x position for right-to-left layouts (Arabic).
func sx(x: float) -> float:
	return -x if rtl else x


func start_align() -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT


static func rrect(w: float, h: float, r: float, segs: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5)
	var cs := [Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r), Vector2(-w * 0.5 + r, -h * 0.5 + r), Vector2(w * 0.5 - r, -h * 0.5 + r)]
	for k in range(4):
		for i in range(segs + 1):
			var a := PI * 0.5 * k + PI * 0.5 * i / segs
			pts.append((cs[k] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


static var _flats: Dictionary = {}
static func _flat(c: Color) -> ShaderMaterial:
	var k := c.to_html()
	if not _flats.has(k):
		_flats[k] = Toon.flat(c)
	return _flats[k]


## A flat shape (y up) facing +Z at `pos`.
static func shape(parent: Node3D, pts: PackedVector2Array, pos: Vector3, color: Color, depth: float = 0.002) -> MeshInstance3D:
	var area := 0.0
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		pts = pts.duplicate()
		pts.reverse()
	var flipped := PackedVector2Array()
	for p in pts:
		flipped.append(Vector2(p.x, -p.y))
	var m := Toon.flat(color)
	var mi := Toon.add(parent, Toon.slab(flipped, depth), m, pos, Vector3(90, 0, 0))
	return mi


func label(text: String, pos: Vector2, px: int, color: Color, font: String = "body", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, width: float = 0.0, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.font = UI.font(font)
	l.text = text
	l.font_size = px
	l.pixel_size = PX
	l.modulate = color
	# Ink printed on paper has no outline; light text keeps a dark one.
	var light := color.get_luminance() > 0.55
	l.outline_size = (6 if font != "title" else 14) if light else 0
	l.outline_modulate = Color(0.06, 0.05, 0.04)
	l.render_priority = 30
	l.outline_render_priority = 29
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.no_depth_test = false
	if width > 0.0:
		l.width = width / PX
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# With a width, `pos.x` is the start edge for left/right-aligned text.
	var ax := 0.0
	l.position = Vector3(pos.x + ax, pos.y, 0.004)
	(parent if parent else self).add_child(l)
	return l


func icon(kind: String, pos: Vector2, s: float, color: Color, parent: Node3D = null) -> Node3D:
	var ic := UI.icon(kind, color, s, 0.002)
	var shape_mi := ic.get_node("Shape") as MeshInstance3D
	shape_mi.material_override = _flat(color)
	ic.position = Vector3(pos.x, pos.y, 0.004)
	(parent if parent else self).add_child(ic)
	return ic


func stars(n: int, pos: Vector2, s: float, of: int = 3) -> void:
	for k in range(of):
		var x := (k - (of - 1) * 0.5) * s * 1.15
		icon("star", Vector2(pos.x + x, pos.y), s, pal.star if k < n else fade(pal.dim, 0.45))


func divider(y: float, w: float = -1.0) -> void:
	var ww := (size.x - 0.08) if w < 0.0 else w
	shape(self, PackedVector2Array([Vector2(-ww * 0.5, -0.001), Vector2(ww * 0.5, -0.001), Vector2(ww * 0.5, 0.001), Vector2(-ww * 0.5, 0.001)]), Vector3(0, y, 0.001), fade(pal.line, 0.8), 0.001)


## Clipped-corner tag outline.
static func tag(w: float, h: float) -> PackedVector2Array:
	var c := minf(0.016, h * 0.28)
	return PackedVector2Array([Vector2(-w * 0.5 + c, -h * 0.5), Vector2(w * 0.5 - c, -h * 0.5), Vector2(w * 0.5, -h * 0.5 + c), Vector2(w * 0.5, h * 0.5 - c), Vector2(w * 0.5 - c, h * 0.5), Vector2(-w * 0.5 + c, h * 0.5), Vector2(-w * 0.5, h * 0.5 - c), Vector2(-w * 0.5, -h * 0.5 + c)])


## A push button. style: normal · primary · ghost. Returns its widget dict
## (its "node" can take extra children, e.g. a mission card's contents).
func button(text: String, center: Vector2, bsize: Vector2, action: Callable, style: String = "normal", icon_kind: String = "", px: int = 50, enabled: bool = true) -> Dictionary:
	var node := Node3D.new()
	node.position = Vector3(center.x, center.y, 0.002)
	add_child(node)
	var color: Color = PRIMARY if style == "primary" else (Color(pal.btn).lerp(pal.edge, 0.35) if style == "ghost" else pal.btn)
	# A stencilled dog-tag: clipped corners, a printed shadow under it.
	var outline := tag(bsize.x, bsize.y)
	if style == "pin":
		color = pal.btn
		outline = rrect(bsize.x, bsize.y, bsize.x * 0.5, 7)
		shape(node, rrect(bsize.x + 0.012, bsize.y + 0.012, bsize.x * 0.5 + 0.006, 7), Vector3(0, 0, -0.001), Color(0.98, 0.94, 0.84), 0.003)
	shape(node, outline, Vector3(0.004, -0.005, -0.001), Color(pal.bg).darkened(0.3), 0.001)
	var mi := shape(node, outline, Vector3.ZERO, color, 0.004)
	if style != "pin" and (style == "primary" or bsize.y >= 0.07):
		# Rivet dots at the two ends.
		for e: float in [-1.0, 1.0]:
			if icon_kind == "" or e > 0 != rtl:
				shape(node, rrect(0.008, 0.008, 0.004, 3), Vector3(e * (bsize.x * 0.5 - 0.014), 0, 0.0045), color.lightened(0.35), 0.001)
	var mat := mi.material_override as ShaderMaterial
	var l: Label3D = null
	var tx := 0.0
	if icon_kind != "":
		var ix := sx(-bsize.x * 0.5 + bsize.y * 0.5) if text != "" else 0.0
		icon(icon_kind, Vector2(ix, 0), bsize.y * 0.5, TEXT if enabled else DIM, node)
		tx = sx(bsize.y * 0.3) if text != "" else 0.0
	if text != "":
		l = label(text, Vector2(tx, 0.002), px, TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
		l.position.z = 0.006
	var w := {"kind": "button", "rect": Rect2(center - bsize * 0.5, bsize), "node": node, "mat": mat, "color": color, "hover": 0.0, "action": action, "enabled": enabled, "label": l, "selected": false, "press": 0.0}
	widgets.append(w)
	return w


## Segmented choice: options = [[value, text], …]; the current one is lit.
func choice(center: Vector2, csize: Vector2, options: Array, current, on_pick: Callable, px: int = 44) -> void:
	var n := options.size()
	var gap := 0.008
	var bw := (csize.x - gap * (n - 1)) / n
	for i in range(n):
		var k := i if not rtl else n - 1 - i
		var x := center.x - csize.x * 0.5 + bw * 0.5 + k * (bw + gap)
		var val = options[i][0]
		var w := button(str(options[i][1]), Vector2(x, center.y), Vector2(bw, csize.y), func(): on_pick.call(val), "normal", "", px)
		if val == current:
			w.selected = true
			w.color = BTN_HOVER


## A 0…1 slider; `on_change(value)` fires while dragging and on release.
func slider(center: Vector2, ssize: Vector2, value: float, on_change: Callable) -> void:
	var node := Node3D.new()
	node.position = Vector3(center.x, center.y, 0.002)
	add_child(node)
	shape(node, rrect(ssize.x, 0.014, 0.007), Vector3.ZERO, fade(pal.dim, 0.5), 0.003)
	var fill := shape(node, rrect(ssize.x, 0.014, 0.007), Vector3(0, 0, 0.001), BTN_HOVER, 0.003)
	var knob := Toon.add(node, Toon.can(0.018, 0.018, 0.012, 20), Toon.mat(EDGE, 0.5, 0.0012), Vector3.ZERO, Vector3(90, 0, 0))
	var val_l := label("", Vector2(sx(ssize.x * 0.5 + 0.045), 0), 44, ink, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
	var w := {"kind": "slider", "rect": Rect2(center - Vector2(ssize.x * 0.5 + 0.02, 0.03), Vector2(ssize.x + 0.04, 0.06)), "width": ssize.x, "node": node, "fill": fill, "knob": knob, "value": value, "action": on_change, "enabled": true, "label": val_l}
	_set_slider(w, value)
	widgets.append(w)


func _set_slider(w: Dictionary, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	w.value = v
	var width: float = w.width
	# Sliders fill from the reading start (right in Arabic).
	var start := sx(-width * 0.5)
	var fx := start + sx(width * v)
	(w.knob as Node3D).position.x = fx
	(w.fill as Node3D).scale.x = maxf(0.001, v)
	(w.fill as Node3D).position.x = (start + fx) * 0.5
	(w.label as Label3D).text = "%d%%" % int(round(v * 100.0))


# --- pointer --------------------------------------------------------------------------------

## Where the ray meets the board, in board coordinates (or null).
func hit(origin: Vector3, dir: Vector3):
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	if absf(d.z) < 1e-4:
		return null
	var t := -o.z / d.z
	if t < 0.05:
		return null
	var p := o + d * t
	if absf(p.x) > size.x * 0.5 + 0.05 or absf(p.y) > size.y * 0.5 + 0.05:
		return null
	return Vector2(p.x, p.y)


## Returns the pointer's board point (or null). `pressed` = trigger just went down.
func pointer(origin: Vector3, dir: Vector3, pressed: bool, held: bool) -> Variant:
	var p = hit(origin, dir)
	if not dragging.is_empty():
		if held and p != null:
			var local_x: float = (p as Vector2).x - (dragging.rect as Rect2).get_center().x
			var v: float = (local_x / float(dragging.width)) + 0.5
			if rtl:
				v = 1.0 - v
			_set_slider(dragging, v)
			(dragging.action as Callable).call(dragging.value)
		elif not held:
			(dragging.action as Callable).call(dragging.value)
			dragging = {}
		return p
	hovered = {}
	if p != null:
		for w in widgets:
			if w.enabled and (w.rect as Rect2).grow(0.004).has_point(p):
				hovered = w
				break
	if pressed and not hovered.is_empty() and _press_lock <= 0.0:
		if hovered.kind == "button":
			hovered.press = 1.0
			_press_lock = 0.2
			(hovered.action as Callable).call()
		elif hovered.kind == "slider":
			dragging = hovered
	return p


func hovering_something() -> bool:
	return not hovered.is_empty()
