class_name Gem
extends Node3D
## The gem the sparks want: a floating neon crystal (two low-poly diamonds),
## placed on the real floor where the player looks. Its colour, size and pulse
## ARE the health bar: cyan and bright when full, amber then red and small when
## drained, dark when lost.

var energy: float = 1.0
var placing: bool = true
var alive: bool = true
var _crystal: MeshInstance3D
var _crystal_inner: MeshInstance3D
var _halo: MeshInstance3D
var _shadow: MeshInstance3D
var _ring: Array[MeshInstance3D] = []
var _time: float = 0.0
var _hit: float = 0.0
var _drop: float = 0.0
var _body: StaticBody3D
var _band: MeshInstance3D


func _ready() -> void:
	_crystal = Neon.make_crystal(Neon.CYAN, 0.15, 1.5)
	_crystal.position.y = 0.55
	add_child(_crystal)
	_crystal_inner = Neon.make_crystal(Neon.WHITE, 0.07, 1.3)
	_crystal_inner.position.y = 0.55
	add_child(_crystal_inner)
	for i in range(6):
		var shard := Neon.make_crystal(Neon.CYAN, 0.028, 1.6)
		add_child(shard)
		_ring.append(shard)
	_band = Neon.make_ring_mesh(Neon.CYAN, 0.26, 0.004)
	_band.position.y = 0.55
	add_child(_band)
	_halo = Neon.make_halo(Neon.CYAN, 1.1, 0.25)
	_halo.position.y = 0.55
	add_child(_halo)
	_shadow = Neon.make_contact_shadow(0.5, 0.4)
	add_child(_shadow)
	_body = StaticBody3D.new()
	_body.collision_layer = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	shape.position.y = 0.55
	_body.add_child(shape)
	add_child(_body)


func anchor_point() -> Vector3:
	return _crystal.global_position


func begin_placement() -> void:
	placing = true
	alive = true
	energy = 1.0


func place() -> void:
	placing = false
	_drop = 1.0
	_body.collision_layer = 1


func drain(seconds: float, draining: int) -> void:
	if not alive:
		return
	energy = clampf(energy + SparkMath.energy_rate(draining) * seconds, 0.0, 1.0)


func lose_shard() -> void:
	if not alive:
		return
	energy = maxf(0.0, energy - SparkMath.SHARD_LOSS)
	_hit = 1.0


func recover_shard() -> void:
	energy = minf(1.0, energy + SparkMath.SHARD_LOSS * 0.6)


func set_alive(on: bool) -> void:
	alive = on


func health_color() -> Color:
	if energy > 0.55:
		return Neon.CYAN.lerp(Neon.WHITE, (energy - 0.55) * 0.6)
	if energy > 0.25:
		return Neon.AMBER.lerp(Neon.CYAN, (energy - 0.25) / 0.3)
	return Neon.RED.lerp(Neon.AMBER, energy / 0.25)


func _process(delta: float) -> void:
	_time += delta
	_hit = maxf(0.0, _hit - delta * 2.0)
	_drop = maxf(0.0, _drop - delta * 3.0)
	var color := health_color() if alive else Neon.CYAN_DIM
	var size := lerpf(0.55, 1.0, energy) * (1.0 + sin(_time * 2.4) * 0.04 + _hit * 0.3)
	var hover := 0.55 + sin(_time * 1.3) * 0.03 + (0.12 if placing else 0.0) - _drop * _drop * 0.1
	_crystal.position.y = hover
	_crystal_inner.position.y = hover
	_halo.position.y = hover
	_crystal.scale = Vector3.ONE * size
	_crystal_inner.scale = Vector3.ONE * size * (1.0 + sin(_time * 7.0) * 0.1)
	_crystal.rotation.y += delta * (0.9 if alive else 0.1)
	_crystal.rotation.x = sin(_time * 0.8) * 0.15
	_crystal_inner.rotation.y -= delta * 1.6
	(_crystal.material_override as ShaderMaterial).set_shader_parameter("base", color)
	(_crystal.material_override as ShaderMaterial).set_shader_parameter("heat", _hit)
	(_crystal_inner.material_override as ShaderMaterial).set_shader_parameter("base", Neon.WHITE if alive else Neon.CYAN_DIM)
	# Six satellites on three tilted orbits; the number lit = energy.
	for i in range(_ring.size()):
		var a := _time * (1.4 + 0.2 * (i % 3)) + i * TAU / _ring.size()
		var tilt := (i % 3) * 1.05
		var r := 0.3 + 0.02 * sin(_time * 2.0 + i)
		_ring[i].position = Vector3(cos(a) * r, hover + sin(a) * r * sin(tilt) * 0.6, sin(a) * r * cos(tilt))
		_ring[i].rotation = Vector3(_time * 1.3 + i, _time * 0.9, 0.0)
		_ring[i].visible = alive and (i < int(ceil(energy * _ring.size())))
		(_ring[i].material_override as ShaderMaterial).set_shader_parameter("base", color)
	_band.position.y = hover
	_band.rotation = Vector3(sin(_time * 0.7) * 0.5, _time * 0.6, cos(_time * 0.5) * 0.5)
	_band.scale = Vector3.ONE * size
	(_band.material_override as StandardMaterial3D).albedo_color = color if alive else Neon.CYAN_DIM
	var halo_alpha := (0.12 + 0.1 * (0.5 + 0.5 * sin(_time * (2.0 + (6.0 if placing else 0.0)))) + _hit * 0.5) if alive else 0.02
	Neon.set_halo_color(_halo, color, halo_alpha)
	(_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.4 if alive else 0.15)
