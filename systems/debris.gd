class_name Debris
extends Node3D
## Planes that are shot down come apart: the model is cut into its real
## pieces (wings, tail, nose with the propeller, fuselage) which tumble,
## burn and smoke, bounce on the floor and settle, then fade away.
## Any model works: big merged meshes are cut triangle by triangle (cached
## per model kind); small parts go whole to the piece they sit in.

const BUCKETS := ["nose", "body", "lwing", "rwing", "tail"]
const MAX_ALIVE := 40
const GRAVITY := 3.2           # the cartoon world is small — fall a bit slower
static var _cache: Dictionary = {}
static var _alive: Array = []
static var effects_high: bool = true

var vel: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var life: float = 0.0
var max_life: float = 9.0
var burning: float = 0.0
var resting: bool = false
var world: Node3D
var _smoke_t: float = 0.0
var _half: float = 0.03


## Which piece a point (model-local, nose toward -Z) belongs to.
static func bucket_of(p: Vector3, box: AABB) -> String:
	var hx := maxf(absf(box.position.x), absf(box.end.x))
	var w := maxf(0.035, hx * 0.22)
	if p.z > box.end.z * 0.52:
		return "tail"
	if p.x < -w:
		return "lwing"
	if p.x > w:
		return "rwing"
	if p.z < box.position.z * 0.6:
		return "nose"
	return "body"


## Cuts one mesh (transformed by `xf` into model space) into buckets.
## Returns {bucket: [ArrayMesh per surface…]} with materials kept per surface.
static func cut_mesh(mesh: Mesh, xf: Transform3D, box: AABB) -> Dictionary:
	var out := {}
	for si in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms = arr[Mesh.ARRAY_NORMAL]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n_idx: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
		var tools := {}
		for k in range(0, n_idx, 3):
			var i0: int = idx[k] if idx != null else k
			var i1: int = idx[k + 1] if idx != null else k + 1
			var i2: int = idx[k + 2] if idx != null else k + 2
			var c: Vector3 = xf * ((verts[i0] + verts[i1] + verts[i2]) / 3.0)
			var b := bucket_of(c, box)
			if not tools.has(b):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[b] = st
			var st2: SurfaceTool = tools[b]
			for i in [i0, i1, i2]:
				if norms != null:
					st2.set_normal((xf.basis * (norms[i] as Vector3)).normalized())
				if uvs != null:
					st2.set_uv(uvs[i])
				st2.add_vertex(xf * verts[i])
		for b in tools:
			if not out.has(b):
				out[b] = []
			(out[b] as Array).append({"mesh": (tools[b] as SurfaceTool).commit(), "surface": si})
	return out


## Pieces of a model: [{center, items: [[mesh, material, Transform3D]]}].
static func pieces_of(root: Node3D, key: String) -> Array:
	if key != "" and _cache.has(key):
		return _cache[key]
	var inv := root.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var mis: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = inv * mi.global_transform
		mis.append([mi, xf])
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var groups := {}
	for b in BUCKETS:
		groups[b] = []
	for pair in mis:
		var mi: MeshInstance3D = pair[0]
		var xf: Transform3D = pair[1]
		var mat: Material = mi.get_meta("orig") if mi.has_meta("orig") else mi.material_override
		var tris := 0
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0:
			var ia = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			tris = ((ia as PackedInt32Array).size() if ia != null else (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var pre: Dictionary = mi.get_meta("debris_parts", {})
		if not pre.is_empty():
			for b in pre:
				(groups[b] as Array).append([pre[b], mat, xf])
		elif tris > 400:
			var cut := cut_mesh(mi.mesh, xf, box)
			for b in cut:
				for item in cut[b]:
					var m2: Material = mat if mat else mi.mesh.surface_get_material(item.surface)
					(groups[b] as Array).append([item.mesh, m2, Transform3D.IDENTITY])
		else:
			var c: Vector3 = xf * mi.mesh.get_aabb().get_center()
			(groups[bucket_of(c, box)] as Array).append([mi.mesh, mat, xf])
	var out: Array = []
	for b in BUCKETS:
		var items: Array = groups[b]
		if items.is_empty():
			continue
		var cbox := AABB()
		var f := true
		for it in items:
			var bb: AABB = (it[2] as Transform3D) * (it[0] as Mesh).get_aabb()
			cbox = bb if f else cbox.merge(bb)
			f = false
		out.append({"name": b, "center": cbox.get_center(), "half": cbox.size.length() * 0.5, "items": items})
	if key != "":
		_cache[key] = out
	return out


## Breaks `root` (a plane model in the world) into tumbling pieces.
static func from_model(w: Node3D, root: Node3D, velocity: Vector3, at: Vector3, key: String = "") -> void:
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		burst(w, at, velocity, [Color(0.4, 0.42, 0.38), Color(0.25, 0.25, 0.27)], 8)
		return
	var k := key if key != "" else ("model:" + root.name + ":" + str(root.get_child_count()))
	var pieces := pieces_of(root, k)
	var xf := root.global_transform
	for p in pieces:
		var d := Debris.new()
		d.world = w
		w.add_child(d)
		d.global_transform = xf * Transform3D(Basis.IDENTITY, p.center)
		for it in p.items:
			var mi := MeshInstance3D.new()
			mi.mesh = it[0]
			mi.material_override = it[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(Basis.IDENTITY, -(p.center as Vector3)) * (it[2] as Transform3D)
			d.add_child(mi)
		var out_dir: Vector3 = xf.basis * (p.center as Vector3)
		out_dir = out_dir.normalized() if out_dir.length() > 0.001 else Vector3.UP
		d.vel = velocity + out_dir * randf_range(0.5, 1.1) + Vector3(0, randf_range(0.5, 1.1), 0)
		d.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(4.0, 9.0)
		d._half = maxf(0.01, float(p.half) * 0.5)
		d.burning = randf_range(1.5, 4.0) if p.name in ["body", "nose"] or randf() < 0.5 else 0.0
		_track(d)


## Generic chunks when there is no model to cut.
static func burst(w: Node3D, at: Vector3, velocity: Vector3, colors: Array, count: int) -> void:
	for i in range(count):
		var d := Debris.new()
		d.world = w
		w.add_child(d)
		d.global_position = at
		var s := randf_range(0.012, 0.03)
		Toon.add(d, Toon.block(Vector3(s * 2.0, s * 0.5, s)), Toon.mat(colors[i % colors.size()], 0.3, 0.001))
		d.vel = velocity + Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)) * 0.9
		d.spin = Vector3(randf(), randf(), randf()) * 10.0
		d._half = s
		d.max_life = 6.0
		_track(d)


static func _track(d: Debris) -> void:
	_alive.append(d)
	while _alive.size() > MAX_ALIVE:
		var old = _alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func clear_all() -> void:
	for d in _alive:
		if is_instance_valid(d):
			d.queue_free()
	_alive.clear()


func _process(delta: float) -> void:
	life += delta
	if life > max_life:
		var u := clampf((life - max_life) / 1.2, 0.0, 1.0)
		scale = Vector3.ONE * maxf(0.01, 1.0 - u)
		if u >= 1.0:
			_alive.erase(self)
			queue_free()
		return
	var floor_y := 0.0
	if world and world.has_method("surface_below"):
		floor_y = world.surface_below(global_position + Vector3(0, 0.1, 0))
	if not resting:
		vel += Vector3(0, -GRAVITY, 0) * delta
		vel *= 1.0 - minf(1.0, delta * 0.4)
		global_position += vel * delta
		rotate(spin.normalized() if spin.length() > 0.01 else Vector3.UP, spin.length() * delta)
		if global_position.y < floor_y + _half * 0.4:
			global_position.y = floor_y + _half * 0.4
			if absf(vel.y) > 0.35:
				vel = Vector3(vel.x * 0.5, -vel.y * 0.3, vel.z * 0.5)
				spin *= 0.5
				if world and world.has_method("cue") and randf() < 0.6:
					world.cue("clatter", global_position, -10.0)
				Fx.sparks(world, global_position, Vector3.UP, 3)
			else:
				resting = true
				# Settle flat-ish on the floor.
				var b := global_basis.orthonormalized()
				var up := b.y if absf(b.y.y) > absf(b.x.y) else b.x
				global_basis = Basis(Quaternion(up.normalized(), Vector3.UP if up.y > 0 else Vector3.DOWN)) * b
	_smoke_t -= delta
	if _smoke_t <= 0.0 and world:
		var flying := not resting
		if burning > 0.0 or flying:
			_smoke_t = (0.05 if flying else 0.18) * (1.0 if effects_high else 2.0)
			if burning > 0.0 and randf() < 0.6:
				Fx.flame(world, global_position, _half * 0.6)
			Fx.smoke(world, global_position, _half * 0.5, true)
	burning -= delta


## The pilot bails out: shoots up, the chute pops, and he drifts down to the
## floor, swaying — then the canopy folds over him and he waves.
static func eject(w: Node3D, from: Vector3, velocity: Vector3) -> void:
	var c := Chute.new()
	c.world = w
	w.add_child(c)
	c.global_position = from
	c.vel = velocity + Vector3(0, 1.5, 0)
	_alive.append(c)
	if w.has_method("cue"):
		w.cue("eject", from, 0.0)


class Chute:
	extends Node3D
	var world: Node3D
	var vel: Vector3
	var t: float = 0.0
	var landed: float = -1.0
	var pilot: Dictionary
	var canopy: Node3D

	func _ready() -> void:
		pilot = Models.pilot()
		pilot.root.scale = Vector3.ONE * 1.35 * WarMath.PLANE_SCALE
		add_child(pilot.root)
		canopy = Node3D.new()
		add_child(canopy)
		canopy.position = Vector3(0, 0.11, 0)
		var dome := SphereMesh.new()
		dome.radius = 0.07
		dome.height = 0.07
		dome.is_hemisphere = true
		dome.radial_segments = 16
		dome.rings = 6
		Toon.add(canopy, dome, Toon.mat(Models.WHITE, 0.3, 0.0015), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.7, 1))
		var stripe := SphereMesh.new()
		stripe.radius = 0.0705
		stripe.height = 0.0705
		stripe.is_hemisphere = true
		stripe.radial_segments = 16
		stripe.rings = 6
		Toon.add(canopy, stripe, Toon.mat(Models.RED, 0.3, 0.0), Vector3.ZERO, Vector3.ZERO, Vector3(0.35, 0.71, 1.0))
		for k in range(4):
			var a := TAU * k / 4.0 + PI * 0.25
			var top := Vector3(cos(a) * 0.062, 0.0, sin(a) * 0.062)
			var bottom := Vector3(0, -0.095, 0)
			var mid := (top + bottom) * 0.5
			var line := Toon.add(canopy, Toon.can(0.0007, 0.0007, top.distance_to(bottom), 4), Toon.flat(Color(0.2, 0.2, 0.2, 1.0)), mid)
			line.basis = Basis(Quaternion(Vector3.UP, (top - bottom).normalized()))
		canopy.scale = Vector3.ONE * 0.01

	func _process(delta: float) -> void:
		t += delta
		var floor_y := 0.0
		if world and world.has_method("surface_below"):
			floor_y = world.surface_below(global_position + Vector3(0, 0.05, 0))
		if landed < 0.0:
			if t < 0.45:
				vel += Vector3(0, -3.0, 0) * delta
			else:
				var open_u := clampf((t - 0.45) / 0.35, 0.0, 1.0)
				canopy.scale = Vector3.ONE * maxf(0.01, open_u * (1.0 + 0.15 * sin(open_u * PI)))
				vel = vel.lerp(Vector3(sin(t * 1.3) * 0.08, -0.13, cos(t * 0.9) * 0.05), minf(1.0, delta * 2.5))
				rotation.z = sin(t * 1.6) * 0.18
				rotation.x = cos(t * 1.2) * 0.12
			global_position += vel * delta
			if global_position.y <= floor_y + 0.002 and t > 0.6:
				global_position.y = floor_y
				landed = 0.0
				rotation = Vector3.ZERO
		else:
			landed += delta
			# The canopy settles over to one side and he waves.
			canopy.rotation.z = lerpf(canopy.rotation.z, 1.35, minf(1.0, delta * 2.0))
			canopy.position = canopy.position.lerp(Vector3(-0.07, 0.02, 0), minf(1.0, delta * 2.0))
			var head: Node3D = pilot.head
			head.rotation.z = sin(landed * 6.0) * 0.25
			if landed > 7.0:
				scale = Vector3.ONE * maxf(0.01, 1.0 - (landed - 7.0))
				if landed > 8.0:
					queue_free()
