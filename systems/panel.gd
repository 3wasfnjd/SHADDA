class_name Panel3D
extends Node3D
## A flat menu board floating in the room (XY plane, facing +Z) — SAQR's own
## "squadron briefing board" look: deep navy board, cream edge, red header
## strip, amber highlight. Widgets are hit-tested with the controller ray in
## the board's local plane: buttons, segmented choices, sliders, labels.

const BG := Color(0.075, 0.1, 0.15, 1.0)
const EDGE := Color(0.96, 0.9, 0.76)
const HEADER := Color(0.78, 0.14, 0.1)
const BTN := Color(0.16, 0.21, 0.29)
const BTN_HOVER := Color(1.0, 0.74, 0.18)
const PRIMARY := Color(0.82, 0.2, 0.12)
const DISABLED := Color(0.22, 0.24, 0.27)
const TEXT := Color(0.97, 0.94, 0.86)
const DIM := Color(0.66, 0.7, 0.76)
const GOLD := Color(1.0, 0.78, 0.2)
const DARK_TEXT := Color(0.08, 0.08, 0.1)
const PX := 0.00046       # metres per font pixel (48 px ≈ 2.2 cm, ≈1.3° at 1 m)

var size: Vector2 = Vector2(0.8, 0.55)
var widgets: Array = []
var hovered: Dictionary = {}
var dragging: Dictionary = {}
var open_t: float = 0.0
var rtl: bool = true
var _press_lock: float = 0.25


func setup(w: float, h: float, title: String = "", header: Color = HEADER) -> Panel3D:
	size = Vector2(w, h)
	rtl = Lang.code() == "ar"
	scale = Vector3.ONE * 0.92
	shape(self, rrect(w + 0.012, h + 0.012, 0.03), Vector3(0, 0, -0.004), EDGE, 0.002)
	shape(self, rrect(w, h, 0.026), Vector3(0, 0, -0.002), BG, 0.002)
	if title != "":
		var hb := 0.085
		var strip := rrect(w - 0.03, hb, 0.02)
		shape(self, strip, Vector3(0, h * 0.5 - hb * 0.5 - 0.015, 0.0), header, 0.002)
		# Chevron stripes at both ends of the header — the squadron mark.
		for side: float in [-1.0, 1.0]:
			for k in range(3):
				var x := side * (w * 0.5 - 0.06 - k * 0.028)
				var chev := PackedVector2Array([Vector2(-0.006, -0.026), Vector2(0.006, -0.026), Vector2(0.018, 0.0), Vector2(0.006, 0.026), Vector2(-0.006, 0.026), Vector2(0.006, 0.0)])
				if side < 0:
					for i in range(chev.size()):
						chev[i] = Vector2(-chev[i].x, chev[i].y)
				shape(self, chev, Vector3(x, h * 0.5 - hb * 0.5 - 0.015, 0.002), Color(EDGE, 0.85), 0.001)
		label(title, Vector2(0, h * 0.5 - hb * 0.5 - 0.012), 86, TEXT, "title")
	# Rivets in the corners.
	for cx: float in [-1.0, 1.0]:
		for cy: float in [-1.0, 1.0]:
			var r := Toon.add(self, Toon.ball(0.0045, 8, 4), Toon.mat(Color(0.6, 0.6, 0.58), 0.6, 0.0))
			r.position = Vector3(cx * (w * 0.5 - 0.016), cy * (h * 0.5 - 0.016), 0.0)
	return self


func _process(delta: float) -> void:
	open_t += delta
	_press_lock = maxf(0.0, _press_lock - delta)
	var s := 1.0 - pow(1.0 - clampf(open_t / 0.18, 0.0, 1.0), 3.0) * 0.08
	scale = Vector3.ONE * s
	for w in widgets:
		if w.kind == "button":
			var target := 1.0 if (hovered == w and w.enabled) else 0.0
			w.hover = move_toward(w.hover, target, delta * 8.0)
			var base: Color = w.color
			var c := base.lerp(BTN_HOVER, w.hover * (0.0 if w.selected else 1.0)) if w.enabled else DISABLED
			(w.mat as ShaderMaterial).set_shader_parameter("albedo", c)
			(w.node as Node3D).scale = Vector3.ONE * (1.0 + w.hover * 0.035 - w.get("press", 0.0) * 0.05)
			w.press = maxf(0.0, w.get("press", 0.0) - delta * 5.0)
			if w.label:
				var dark: bool = (w.hover > 0.5 and not w.selected) or w.selected
				(w.label as Label3D).modulate = DARK_TEXT if dark and w.enabled else (TEXT if w.enabled else DIM)
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
	l.outline_size = 6 if font != "title" else 14
	l.outline_modulate = Color(0.03, 0.04, 0.06)
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
		icon("star", Vector2(pos.x + x, pos.y), s, GOLD if k < n else Color(0.3, 0.33, 0.38))


func divider(y: float, w: float = -1.0) -> void:
	var ww := (size.x - 0.08) if w < 0.0 else w
	shape(self, PackedVector2Array([Vector2(-ww * 0.5, -0.001), Vector2(ww * 0.5, -0.001), Vector2(ww * 0.5, 0.001), Vector2(-ww * 0.5, 0.001)]), Vector3(0, y, 0.001), Color(EDGE, 0.35), 0.001)


## A push button. style: normal · primary · ghost. Returns its widget dict
## (its "node" can take extra children, e.g. a mission card's contents).
func button(text: String, center: Vector2, bsize: Vector2, action: Callable, style: String = "normal", icon_kind: String = "", px: int = 50, enabled: bool = true) -> Dictionary:
	var node := Node3D.new()
	node.position = Vector3(center.x, center.y, 0.002)
	add_child(node)
	var color := PRIMARY if style == "primary" else (Color(0.12, 0.15, 0.2) if style == "ghost" else BTN)
	var mi := shape(node, rrect(bsize.x, bsize.y, minf(0.02, bsize.y * 0.3)), Vector3.ZERO, color, 0.004)
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
	shape(node, rrect(ssize.x, 0.014, 0.007), Vector3.ZERO, Color(0.2, 0.24, 0.3), 0.003)
	var fill := shape(node, rrect(ssize.x, 0.014, 0.007), Vector3(0, 0, 0.001), BTN_HOVER, 0.003)
	var knob := Toon.add(node, Toon.can(0.018, 0.018, 0.012, 20), Toon.mat(EDGE, 0.5, 0.0012), Vector3.ZERO, Vector3(90, 0, 0))
	var val_l := label("", Vector2(sx(ssize.x * 0.5 + 0.045), 0), 44, TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
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
