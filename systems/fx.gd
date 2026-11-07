class_name Fx
extends Node3D
## Cartoon effects, each frees itself: puffy explosions (flash → fireball →
## grey smoke balls → debris), flak puffs, smoke trails, muzzle stars, sparks,
## and scorch / bullet marks on the real walls, floor and furniture.

var kind: String = "boom"
var life: float = 0.0
var duration: float = 1.0
var size: float = 0.1
var _parts: Array = []
var _flash: MeshInstance3D

const MAX_MARKS := 30
## Performance budget (Quest): how many effect nodes may be alive at once.
## Smoke, flames and sparks are skipped when over it; the battle lowers it
## automatically if the frame rate drops.
static var live: int = 0
static var budget: int = 60
static var _marks: Array = []
static var _fire_mats: Array = []


static var _ball_mesh: SphereMesh
static var _ring_mesh: TorusMesh
## One shared low-poly unit sphere for every puff (no per-effect meshes).
static func _ball() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = Toon.ball(1.0, 10, 6)
	return _ball_mesh


static func _puff_mat(color: Color) -> ShaderMaterial:
	return Toon.mat(color, 0.1, 0.0)


static func over_budget() -> bool:
	return live > budget


func _enter_tree() -> void:
	live += 1


func _exit_tree() -> void:
	live -= 1


static func explosion(world: Node3D, at: Vector3, s: float) -> Fx:
	var f := Fx.new()
	f.kind = "boom"
	f.size = s
	var lean := over_budget()
	f.duration = 1.1 + s * 3.0 + (0.0 if lean else 0.6 + s * 4.0)
	world.add_child(f)
	f.global_position = at
	f._flash = Toon.add(f, _ball(), _flame_mat(Color(1.0, 0.97, 0.7, 1.0)))
	var fire := [Color(1.0, 0.85, 0.2), Color(1.0, 0.55, 0.1), Color(0.95, 0.3, 0.08)]
	var n := (3 if lean else 5) + int(s * (10.0 if lean else 18.0))
	for i in range(n):
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.4, 1.0), randf_range(-1, 1)).normalized()
		var r := s * randf_range(0.4, 0.65)
		var ball := Toon.add(f, _ball(), Toon.mat(fire[i % 3], 0.2, 0.0))
		ball.scale = Vector3.ONE * 0.001
		f._parts.append({"node": ball, "kind": "fire", "dir": dir, "r": r, "delay": randf() * 0.08, "speed": s * randf_range(2.0, 4.0)})
	for i in range((1 if lean else 2) + int(s * (6.0 if lean else 12.0))):
		var bit := Toon.add(f, Toon.block(Vector3.ONE * s * randf_range(0.12, 0.25)), Toon.mat(Color(0.25, 0.24, 0.24), 0.2, 0.0))
		var v := Vector3(randf_range(-1, 1), randf_range(0.3, 1.4), randf_range(-1, 1)).normalized() * randf_range(1.0, 2.2) * (0.6 + s * 3.0)
		f._parts.append({"node": bit, "kind": "debris", "vel": v, "spin": Vector3(randf(), randf(), randf()) * 14.0})
	if lean:
		return f
	# Shock ring: a thin hoop that snaps outward in the first third of a second.
	if _ring_mesh == null:
		_ring_mesh = Toon.torus(1.0, 0.025, 32)
	var ring := Toon.add(f, _ring_mesh, Toon.flat(Color(1.0, 0.93, 0.7, 0.8)))
	ring.basis = Basis(Vector3.RIGHT, randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, randf_range(-0.4, 0.4))
	ring.scale = Vector3.ONE * 0.001
	f._parts.append({"node": ring, "kind": "ring", "r": s * 2.2})
	# Embers flicking up and out.
	for i in range(3 + int(s * 20.0)):
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.3), randf_range(-1, 1)).normalized()
		var e := Toon.add(f, Toon.block(Vector3(0.004, 0.004, 0.012)), _flame_mat(Color(1.0, 0.75, 0.25)))
		f._parts.append({"node": e, "kind": "ember", "vel": d * randf_range(0.6, 1.4) * (0.7 + s * 4.0)})
	# Thick smoke that rolls out of the fireball, rises and lingers.
	var greys := [Color(0.32, 0.31, 0.32), Color(0.22, 0.21, 0.22), Color(0.42, 0.41, 0.42)]
	for i in range(2 + int(s * 16.0)):
		var dir2 := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0), randf_range(-1, 1)).normalized()
		var puff := Toon.add(f, _ball(), Toon.mat(greys[i % 3], 0.1, 0.0))
		puff.scale = Vector3.ONE * 0.001
		f._parts.append({"node": puff, "kind": "plume", "dir": dir2, "r": s * randf_range(0.45, 0.8), "delay": 0.15 + randf() * 0.25, "speed": s * randf_range(0.8, 1.6)})
	return f


## A black flak puff with an orange core (AA bursts).
static func flak(world: Node3D, at: Vector3) -> Fx:
	if over_budget():
		return null
	var f := Fx.new()
	f.kind = "flak"
	f.size = 0.06
	f.duration = 1.2
	world.add_child(f)
	f.global_position = at
	f._flash = Toon.add(f, _ball(), _flame_mat(Color(1.0, 0.7, 0.2, 1.0)))
	for i in range(5):
		var ball := Toon.add(f, _ball(), Toon.mat(Color(0.16, 0.15, 0.16), 0.1, 0.0))
		ball.scale = Vector3.ONE * 0.001
		f._parts.append({"node": ball, "kind": "smoke", "dir": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), "r": randf_range(0.022, 0.035), "delay": randf() * 0.05, "speed": 0.08})
	return f


## One grey smoke ball that rises and grows (trails from damaged planes).
static func smoke(world: Node3D, at: Vector3, s: float, dark: bool = false) -> Fx:
	if over_budget():
		return null
	var f := Fx.new()
	f.kind = "smoke"
	f.size = s
	f.duration = 1.0
	world.add_child(f)
	f.global_position = at
	var ball := Toon.add(f, _ball(), Toon.mat(Color(0.2, 0.2, 0.22), 0.1, 0.0) if dark else _flame_mat(Color(0.86, 0.86, 0.88, 1.0)))
	ball.scale = Vector3.ONE * s
	f._parts.append({"node": ball, "kind": "trail"})
	return f


## A lick of flame that rises and fades (burning wrecks, incendiary hits).
static func flame(world: Node3D, at: Vector3, s: float) -> Fx:
	if over_budget():
		return null
	var f := Fx.new()
	f.kind = "smoke"
	f.size = s
	f.duration = 0.45
	world.add_child(f)
	f.global_position = at
	var c: Color = [Color(1.0, 0.82, 0.25), Color(1.0, 0.55, 0.12), Color(0.98, 0.35, 0.08)][randi() % 3]
	var ball := Toon.add(f, _ball(), _flame_mat(c))
	ball.scale = Vector3.ONE * s
	f._parts.append({"node": ball, "kind": "trail"})
	return f


static var _flame_mats: Dictionary = {}
static func _flame_mat(c: Color) -> ShaderMaterial:
	var k := c.to_html()
	if not _flame_mats.has(k):
		_flame_mats[k] = Toon.flat(c)
	return _flame_mats[k]


## A jagged lightning bolt between two points (the Thunderbolt weapon).
static func bolt(world: Node3D, a: Vector3, b: Vector3) -> Fx:
	var f := Fx.new()
	f.kind = "bolt"
	f.duration = 0.24
	world.add_child(f)
	f.global_position = a
	var pts: Array = [a]
	var n := 7
	var d := b - a
	var side := d.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d).normalized()
	for i in range(1, n):
		var j := (side * randf_range(-1, 1) + up * randf_range(-1, 1)) * d.length() * 0.07
		pts.append(a + d * (float(i) / n) + j)
	pts.append(b)
	var core := _flame_mat(Color(0.92, 0.97, 1.0))
	var glow := _flame_mat(Color(0.45, 0.75, 1.0))
	for i in range(pts.size() - 1):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg := p1 - p0
		if seg.length() < 0.001:
			continue
		var holder := Toon.add(f, Toon.block(Vector3(0.004, 0.004, seg.length())), core)
		holder.global_position = (p0 + p1) * 0.5
		var upv := Vector3.UP if absf(seg.normalized().y) < 0.98 else Vector3.RIGHT
		holder.look_at(holder.global_position + seg, upv)
		Toon.add(holder, Toon.block(Vector3(0.011, 0.011, seg.length())), glow).transparency = 0.5
		f._parts.append({"node": holder, "kind": "flicker"})
	return f


## A four-point muzzle star.
static func muzzle(world: Node3D, at: Vector3, dir: Vector3, s: float = 0.018) -> Fx:
	var f := Fx.new()
	f.kind = "muzzle"
	f.duration = 0.05
	world.add_child(f)
	f.global_position = at
	var star := Toon.add(f, Toon.slab(Toon.star(s), 0.001), _flame_mat(Color(1.0, 0.85, 0.3, 1.0)))
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT
	f.look_at(at + dir, up)
	star.rotation_degrees = Vector3(90, randf() * 72.0, 0)
	return f


static func sparks(world: Node3D, at: Vector3, normal: Vector3, count: int = 5, color: Color = Color(1.0, 0.8, 0.3)) -> Fx:
	if over_budget():
		return null
	var f := Fx.new()
	f.kind = "sparks"
	f.duration = 0.35
	world.add_child(f)
	f.global_position = at
	for i in range(count):
		var d := (normal + Vector3(randf_range(-0.9, 0.9), randf_range(-0.4, 0.9), randf_range(-0.9, 0.9))).normalized()
		var bit := Toon.add(f, Toon.block(Vector3(0.003, 0.003, 0.014)), _flame_mat(color))
		f._parts.append({"node": bit, "kind": "spark", "vel": d * randf_range(0.7, 1.6)})
	return f


## A cartoon mark on a real surface: a dark star-burst (explosions) or a small
## hole with a light rim (bullets). Oldest marks recycle.
static func mark(world: Node3D, at: Vector3, normal: Vector3, s: float, bullet: bool = false) -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	var n := normal.normalized()
	holder.global_position = at + n * 0.002
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	holder.look_at(holder.global_position + n, up)
	holder.rotate_object_local(Vector3.RIGHT, PI * 0.5)    # +Y = surface normal
	holder.rotate_object_local(Vector3.UP, randf() * TAU)
	if bullet:
		Toon.add(holder, Toon.can(s * 0.5, s * 0.5, 0.0008, 10), _flame_mat(Color(0.8, 0.75, 0.65, 1)))
		Toon.add(holder, Toon.can(s * 0.3, s * 0.3, 0.0012, 10), _flame_mat(Color(0.08, 0.07, 0.07, 1)))
	else:
		var burst := Toon.star(s * 0.5)
		for i in range(burst.size()):
			if i % 2 == 1:
				burst[i] *= 1.4
		Toon.add(holder, Toon.slab(burst, 0.0008), _flame_mat(Color(0.12, 0.1, 0.09, 0.85)))
	_marks.append(holder)
	while _marks.size() > MAX_MARKS:
		var old = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func clear_marks() -> void:
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()


func _process(delta: float) -> void:
	life += delta
	var u := life / duration
	if u >= 1.0:
		queue_free()
		return
	if _flash:
		var fs := size * 1.4 * clampf(1.0 - life / 0.1, 0.0, 1.0) * (1.0 if kind == "boom" else 0.6)
		_flash.scale = Vector3.ONE * maxf(fs, 0.0001)
		_flash.visible = life < 0.1
	for p in _parts:
		var node: MeshInstance3D = p.node
		match p.kind:
			"fire", "smoke":
				var t: float = maxf(0.0, life - p.delay)
				var grow := 1.0 - exp(-t * 9.0)
				var r: float = p.r * grow * (1.0 + t * 0.6)
				var base_d: float = 1.1 + size * 3.0 if kind == "boom" else duration
				var tail := clampf((life / base_d - 0.45) / 0.55, 0.0, 1.0)
				node.scale = Vector3.ONE * maxf(0.0001, r * (1.0 - tail))
				node.position = p.dir * p.speed * minf(t, 0.4) + Vector3(0, t * 0.08, 0)
			"debris":
				p.vel += Vector3(0, -9.8, 0) * delta
				node.position += p.vel * delta
				node.rotation += p.spin * delta
				node.scale = Vector3.ONE * clampf((1.0 - life / (1.1 + size * 3.0)) * 3.0, 0.0, 1.0)
			"ring":
				var k := clampf(life / 0.32, 0.0, 1.0)
				var rr: float = p.r * (1.0 - pow(1.0 - k, 3.0))
				node.scale = Vector3(rr, rr * 0.6, rr) if k < 1.0 else Vector3.ONE * 0.0001
				node.visible = k < 1.0
			"ember":
				p.vel += Vector3(0, -3.0, 0) * delta
				p.vel *= 1.0 - delta * 1.5
				node.position += p.vel * delta
				var upe := Vector3.UP if absf(p.vel.normalized().y) < 0.99 else Vector3.RIGHT
				node.look_at(node.global_position + p.vel, upe)
				node.scale = Vector3.ONE * clampf(1.4 - life * 1.6, 0.0, 1.0)
				node.visible = node.scale.x > 0.01 and fmod(life + p.vel.x, 0.1) < 0.075
			"plume":
				var tp: float = life - p.delay
				if tp <= 0.0:
					continue
				var g := 1.0 - exp(-tp * 4.0)
				var fade_out := clampf((u - 0.7) / 0.3, 0.0, 1.0)
				node.scale = Vector3.ONE * maxf(0.0001, p.r * g * (1.0 + tp * 0.5) * (1.0 - fade_out))
				node.position = p.dir * p.speed * (1.0 - exp(-tp * 2.0)) + Vector3(0, tp * (0.05 + size * 0.6), 0)
			"spark":
				p.vel += Vector3(0, -4.0, 0) * delta
				node.position += p.vel * delta
				var up := Vector3.UP if absf(p.vel.normalized().y) < 0.99 else Vector3.RIGHT
				node.look_at(node.global_position + p.vel, up)
				node.scale = Vector3.ONE * (1.0 - u)
			"flicker":
				node.visible = fmod(life, 0.06) < 0.045
			"trail":
				node.scale = Vector3.ONE * size * (1.0 + u * 2.2) * (1.0 - u * u)
				position += Vector3(0, 0.1 * delta, 0)
