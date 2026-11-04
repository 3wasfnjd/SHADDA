class_name Fx
extends Node3D
## Short-lived effects: explosions (flash + fireball + debris), sparks,
## smoke puffs and scorch marks left on the real walls and floor.
## Each Fx frees itself. Cheap on the Mobile renderer: unshaded meshes only.

var life: float = 0.0
var duration: float = 0.6
var kind: String = "boom"
var size: float = 0.1
var _flash: MeshInstance3D
var _ball: MeshInstance3D
var _halo: MeshInstance3D
var _debris: Array = []

const MAX_SCORCH := 48
static var _scorches: Array = []


static func explosion(world: Node3D, at: Vector3, s: float, color: Color = Color(1.0, 0.55, 0.15)) -> Fx:
	var f := Fx.new()
	f.kind = "boom"
	f.size = s
	f.duration = 0.75 + s * 1.5
	world.add_child(f)
	f.global_position = at
	f._build_boom(color)
	return f


static func sparks(world: Node3D, at: Vector3, normal: Vector3, color: Color = Color(1.0, 0.8, 0.35), count: int = 5) -> Fx:
	var f := Fx.new()
	f.kind = "sparks"
	f.size = 0.02
	f.duration = 0.35
	world.add_child(f)
	f.global_position = at
	for i in range(count):
		var d := (normal + Vector3(randf_range(-0.8, 0.8), randf_range(-0.5, 0.9), randf_range(-0.8, 0.8))).normalized()
		var bit := MeshInstance3D.new()
		bit.mesh = Models.box(Vector3(0.002, 0.002, 0.018))
		bit.material_override = Neon.emitter_material(color)
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(bit)
		f._debris.append({"node": bit, "vel": d * randf_range(0.8, 1.8), "spin": Vector3.ZERO})
	return f


static func smoke(world: Node3D, at: Vector3, s: float) -> Fx:
	var f := Fx.new()
	f.kind = "smoke"
	f.size = s
	f.duration = 0.9
	world.add_child(f)
	f.global_position = at
	f._ball = MeshInstance3D.new()
	f._ball.mesh = Models.sphere(1.0, 8, 4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.25, 0.25, 0.27, 0.5)
	f._ball.material_override = m
	f._ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(f._ball)
	return f


## A dark burn mark on a real surface (wall or floor). Oldest marks recycle.
static func scorch(world: Node3D, at: Vector3, normal: Vector3, s: float) -> void:
	var q := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(s, s)
	q.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Neon.halo_texture()
	m.albedo_color = Color(0.04, 0.03, 0.02, 0.85)
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(q)
	var n := normal.normalized()
	q.global_position = at + n * 0.003
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	q.look_at(q.global_position + n, up)
	q.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	q.rotate_object_local(Vector3.UP, PI)
	_scorches.append(q)
	while _scorches.size() > MAX_SCORCH:
		var old = _scorches.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func clear_scorches() -> void:
	for s in _scorches:
		if is_instance_valid(s):
			s.queue_free()
	_scorches.clear()


func _build_boom(color: Color) -> void:
	_flash = MeshInstance3D.new()
	_flash.mesh = Models.sphere(1.0, 12, 6)
	_flash.material_override = Neon.emitter_material(Color(1.0, 0.95, 0.8))
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	_ball = MeshInstance3D.new()
	_ball.mesh = Models.sphere(1.0, 12, 6)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(color.r, color.g, color.b, 0.9)
	_ball.material_override = bm
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)
	_halo = Neon.make_halo(color, size * 7.0, 0.6)
	add_child(_halo)
	var n := 6 + int(size * 40.0)
	for i in range(n):
		var bit := MeshInstance3D.new()
		var k := randf_range(0.25, 1.0) * size * 0.35
		bit.mesh = Models.box(Vector3(k, k * 0.5, k * 0.8))
		bit.material_override = Models.paint(Color(0.18, 0.18, 0.2) if i % 2 == 0 else Color(0.35, 0.33, 0.3))
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bit)
		var d := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.2), randf_range(-1, 1)).normalized()
		_debris.append({"node": bit, "vel": d * randf_range(1.0, 2.6) * (0.5 + size * 4.0), "spin": Vector3(randf(), randf(), randf()) * 12.0})


func _process(delta: float) -> void:
	life += delta
	var u := life / duration
	if u >= 1.0:
		queue_free()
		return
	if kind == "boom":
		var fs := size * (0.6 + 2.0 * minf(1.0, life / 0.06))
		_flash.scale = Vector3.ONE * fs * maxf(0.0, 1.0 - life / 0.12)
		_flash.visible = life < 0.12
		var bs := size * (0.4 + 1.4 * sqrt(minf(1.0, u * 2.5)))
		_ball.scale = Vector3.ONE * bs
		var bm := _ball.material_override as StandardMaterial3D
		var heat := clampf(1.0 - u * 1.6, 0.0, 1.0)
		bm.albedo_color = Color(lerpf(0.25, 1.0, heat), lerpf(0.22, 0.55, heat), lerpf(0.2, 0.15, heat), clampf(1.0 - u, 0.0, 1.0) * 0.85)
		Neon.set_halo_color(_halo, Color(1.0, 0.5, 0.15), 0.6 * maxf(0.0, 1.0 - u * 2.0))
	if kind == "smoke":
		_ball.scale = Vector3.ONE * size * (1.0 + u * 2.5)
		global_position += Vector3(0, 0.12 * delta, 0)
		(_ball.material_override as StandardMaterial3D).albedo_color.a = 0.5 * (1.0 - u)
	for d in _debris:
		var node: MeshInstance3D = d.node
		d.vel += Vector3(0, -9.8 if kind == "boom" else -3.0, 0) * delta
		node.position += d.vel * delta
		node.rotation += d.spin * delta
		if kind == "sparks":
			node.look_at(node.global_position + d.vel, Vector3.UP if absf(d.vel.normalized().y) < 0.99 else Vector3.RIGHT)
			node.scale = Vector3.ONE * (1.0 - u)
		elif u > 0.7:
			node.scale = Vector3.ONE * (1.0 - u) / 0.3
