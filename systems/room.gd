class_name Room
extends Node3D
## The real room as the game sees it: floor, walls, doors and windows,
## furniture tops, the flyable box, and invisible depth-only occluders so
## that anything flying behind a real wall, couch or table is hidden by it
## (and planes really come in through the doorway or the window opening).

var floor_y: float = 0.0
var ceiling_y: float = 2.5
var walls: Array = []
var openings: Array = []
var surfaces: Array = []
var blocks: Array = []
var box: Dictionary = {"min": Vector3(-1.6, 0, -1.6), "max": Vector3(1.6, 2.5, 1.6)}
var found: bool = false
var virtual_openings: bool = false
var physics_room: bool = false
var _rng := RandomNumberGenerator.new()


func setup(room: Dictionary, head_pos: Vector3, use_physics: bool) -> void:
	_rng.randomize()
	for c in get_children():
		c.queue_free()
	floor_y = room.get("floor_y", 0.0)
	ceiling_y = maxf(floor_y + 1.9, room.get("ceiling_y", floor_y + 2.5))
	walls = room.get("walls", [])
	openings = room.get("openings", []).duplicate()
	surfaces = room.get("surfaces", [])
	blocks = room.get("blocks", [])
	found = room.get("found", false)
	physics_room = use_physics
	box = WarMath.room_box(walls, floor_y, ceiling_y, head_pos)
	virtual_openings = false
	if openings.filter(func(o): return o.kind == "window" or o.kind == "door").is_empty():
		_add_virtual_openings(head_pos)
	_build_occluders()


## Without a door or window in the scene data we cut one of each into the
## two widest walls (or the box edges when there are no walls at all).
func _add_virtual_openings(head_pos: Vector3) -> void:
	virtual_openings = true
	var ws := walls.duplicate()
	if ws.is_empty():
		var lo: Vector3 = box.min
		var hi: Vector3 = box.max
		var c := (lo + hi) * 0.5
		ws = [{"origin": Vector3(c.x, floor_y, lo.z), "normal": Vector3(0, 0, 1), "width": hi.x - lo.x, "height": ceiling_y - floor_y},
			{"origin": Vector3(hi.x, floor_y, c.z), "normal": Vector3(-1, 0, 0), "width": hi.z - lo.z, "height": ceiling_y - floor_y}]
	ws.sort_custom(func(a, b): return float(a.width) > float(b.width))
	var w0: Dictionary = ws[0]
	openings.append(_virtual(w0, "window", 0.0, 1.25, 0.8, 0.55))
	var w1: Dictionary = ws[1] if ws.size() > 1 else ws[0]
	openings.append(_virtual(w1, "door", 0.6 if w1 == w0 else 0.0, 0.0, 0.85, 1.95))


func _virtual(w: Dictionary, k: String, along: float, bottom: float, width: float, height: float) -> Dictionary:
	var n: Vector3 = w.normal
	var side := Vector3(-n.z, 0, n.x)
	var base: Vector3 = w.origin + side * along
	base.y = floor_y + bottom
	return {"kind": k, "center": base + Vector3(0, height * 0.5, 0), "base": base, "normal": n, "width": width, "height": height, "virtual": true}


func _build_occluders() -> void:
	var occ := Toon.occluder()
	for w in walls:
		var holes: Array = []
		var t: Transform3D
		var outer: Rect2
		if w.has("xform"):
			t = w.xform
			outer = w.rect
		else:
			# Virtual wall frame: X along the wall, Y up, Z = normal.
			var n: Vector3 = w.normal
			var x := Vector3(n.z, 0, -n.x)
			t = Transform3D(Basis(x, Vector3.UP, n), w.origin)
			outer = Rect2(-float(w.width) * 0.5, 0.0, float(w.width), float(w.height))
		var inv := t.affine_inverse()
		for o in openings:
			var corners: Array = _opening_corners(o)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			var near := true
			for c in corners:
				var l: Vector3 = inv * c
				if absf(l.z) > 0.3:
					near = false
				lo = Vector2(minf(lo.x, l.x), minf(lo.y, l.y))
				hi = Vector2(maxf(hi.x, l.x), maxf(hi.y, l.y))
			if near:
				holes.append(Rect2(lo, hi - lo))
		for cell in WarMath.rect_minus_holes(outer, holes):
			var q := QuadMesh.new()
			q.size = (cell as Rect2).size
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = occ
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_transform = t * Transform3D(Basis.IDENTITY, Vector3((cell as Rect2).get_center().x, (cell as Rect2).get_center().y, 0.0))
	for b in blocks:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = (b.box as AABB).size
		mi.mesh = bm
		mi.material_override = occ
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_transform = (b.xform as Transform3D) * Transform3D(Basis.IDENTITY, (b.box as AABB).get_center())
	# The floor hides anything below it.
	var fq := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(30, 30)
	fq.mesh = fm
	fq.material_override = occ
	add_child(fq)
	fq.global_position = Vector3(((box.min as Vector3) + (box.max as Vector3)).x * 0.5, floor_y - 0.002, ((box.min as Vector3) + (box.max as Vector3)).z * 0.5)


func _opening_corners(o: Dictionary) -> Array:
	if o.has("xform"):
		var t: Transform3D = o.xform
		var r: Rect2 = o.rect
		return [t * Vector3(r.position.x, r.position.y, 0), t * Vector3(r.end.x, r.position.y, 0), t * Vector3(r.position.x, r.end.y, 0), t * Vector3(r.end.x, r.end.y, 0)]
	var n: Vector3 = o.normal
	var side := Vector3(-n.z, 0, n.x) * (float(o.width) * 0.5)
	var b: Vector3 = o.base
	var up := Vector3(0, float(o.height), 0)
	return [b - side, b + side, b - side + up, b + side + up]


# --- queries ---------------------------------------------------------------------------

func center() -> Vector3:
	return ((box.min as Vector3) + (box.max as Vector3)) * 0.5


## Height of the floor or furniture top directly below p.
func surface_below(p: Vector3) -> float:
	var y := floor_y
	for s in surfaces:
		var d: Vector3 = p - (s.center as Vector3)
		if absf(d.dot(s.axis_x)) <= s.half.x and absf(d.dot(s.axis_z)) <= s.half.y and float(s.center.y) <= p.y + 0.02:
			y = maxf(y, s.center.y)
	return y


func air_openings() -> Array:
	return openings.filter(func(o): return o.kind == "window" or (o.kind == "door" and float(o.height) > 1.2))


func doors() -> Array:
	return openings.filter(func(o): return o.kind == "door")


## A random spot on the floor or a furniture top, clear of the walls and of
## the player's feet. Returns {point, on_furniture}.
func ground_spot(avoid: Vector3, prefer_furniture: bool = false) -> Dictionary:
	if prefer_furniture and not surfaces.is_empty() and _rng.randf() < 0.75:
		var s: Dictionary = surfaces[_rng.randi() % surfaces.size()]
		var hx: float = maxf(0.0, s.half.x - 0.1)
		var hz: float = maxf(0.0, s.half.y - 0.1)
		var p: Vector3 = (s.center as Vector3) + (s.axis_x as Vector3) * _rng.randf_range(-hx, hx) + (s.axis_z as Vector3) * _rng.randf_range(-hz, hz)
		return {"point": p, "on_furniture": true}
	for i in range(24):
		var lo: Vector3 = box.min
		var hi: Vector3 = box.max
		var p := Vector3(_rng.randf_range(lo.x + 0.35, hi.x - 0.35), floor_y, _rng.randf_range(lo.z + 0.35, hi.z - 0.35))
		if Vector2(p.x - avoid.x, p.z - avoid.z).length() < 0.6:
			continue
		if surface_below(p + Vector3(0, 2, 0)) > floor_y + 0.05:
			continue
		return {"point": p, "on_furniture": false}
	return {"point": Vector3(center().x, floor_y, center().z), "on_furniture": false}


## Segment against the real room (physics layer 1), the floor plane, and the
## room box when there is no physics room. Returns {} or {position, normal}.
func wall_hit(a: Vector3, b: Vector3) -> Dictionary:
	if physics_room and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			return {"position": r.position, "normal": r.normal}
	var top := surface_below(b)
	if b.y < top and a.y >= top - 0.001:
		var t := (a.y - top) / maxf(1e-6, a.y - b.y)
		return {"position": a.lerp(b, t), "normal": Vector3.UP}
	if not physics_room:
		var lo: Vector3 = box.min
		var hi: Vector3 = box.max
		var d := b - a
		var best_t := 2.0
		var n := Vector3.ZERO
		for axis: int in [0, 1, 2]:
			if absf(d[axis]) < 1e-7:
				continue
			for face: float in [lo[axis], hi[axis]]:
				if axis == 1 and face == lo[axis]:
					continue
				var t2: float = (face - a[axis]) / d[axis]
				if t2 < 0.0 or t2 > 1.0 or t2 >= best_t:
					continue
				if (face == hi[axis] and d[axis] > 0.0) or (face == lo[axis] and d[axis] < 0.0):
					if _through_opening(a + d * t2):
						continue
					best_t = t2
					n = Vector3.ZERO
					n[axis] = -signf(d[axis])
		if best_t <= 1.0:
			return {"position": a + d * best_t, "normal": n}
	return {}


## True when a point on a wall lies inside a door or window opening.
func _through_opening(p: Vector3) -> bool:
	for o in openings:
		var n: Vector3 = o.normal
		var side := Vector3(-n.z, 0, n.x)
		var d: Vector3 = p - (o.center as Vector3)
		if absf(d.dot(n)) < 0.3 and absf(d.dot(side)) < float(o.width) * 0.5 and absf(d.y) < float(o.height) * 0.5:
			return true
	return false
