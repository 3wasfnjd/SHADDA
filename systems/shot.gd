class_name Shot
extends Node3D
## One projectile. The battle director moves every shot in _physics_process and
## resolves hits with exact segment tests, so even 34 m/s rounds never skip
## through a 10 cm drone.
##
## kinds — player: bullet, missile, bomb, flare
##         enemy:  pellet, emissile, flak

var kind: String = "bullet"
var hostile: bool = false
var velocity: Vector3 = Vector3.ZERO
var prev: Vector3 = Vector3.ZERO
var life: float = 0.0
var max_life: float = 1.0
var damage: float = 1.0
var radius: float = 0.004       # its own hit radius (for being shot down)
var target: Node3D = null        # homing target (Enemy, player jet or Shot flare)
var speed: float = 0.0
var turn: float = 0.0
var hp: float = 1.0
var dead: bool = false
var fuse: float = 0.0            # flak: arm distance
var _trail: Array = []
var _trail_mesh: ImmediateMesh
var _trail_node: MeshInstance3D
var _trail_color: Color
var _visual: Node3D


static func make(shot_kind: String, from: Vector3, dir: Vector3, inherit: Vector3 = Vector3.ZERO) -> Shot:
	var s := Shot.new()
	s.kind = shot_kind
	s.hostile = shot_kind in ["pellet", "emissile", "flak"]
	var d := dir.normalized()
	match shot_kind:
		"bullet":
			s.speed = CombatMath.CANNON_SPEED
			s.velocity = d * s.speed + inherit
			s.max_life = 0.4
			s.damage = CombatMath.CANNON_DAMAGE
		"missile":
			s.speed = 1.2
			s.velocity = d * s.speed + inherit
			s.max_life = CombatMath.MISSILE_LIFE
			s.damage = CombatMath.MISSILE_DAMAGE
			s.turn = CombatMath.MISSILE_TURN
		"bomb":
			s.velocity = inherit + d * 0.5
			s.max_life = 3.0
			s.damage = CombatMath.BOMB_DAMAGE
		"flare":
			s.velocity = d * 1.6 + inherit * 0.3
			s.max_life = 2.6
		"pellet":
			s.speed = CombatMath.PELLET_SPEED
			s.velocity = d * s.speed
			s.max_life = 3.0
			s.damage = CombatMath.PELLET_DAMAGE
			s.radius = 0.012
		"emissile":
			s.speed = CombatMath.ENEMY_MISSILE_SPEED
			s.velocity = d * 1.0
			s.max_life = 6.0
			s.damage = CombatMath.ENEMY_MISSILE_DAMAGE
			s.turn = CombatMath.ENEMY_MISSILE_TURN
			s.radius = 0.035
		"flak":
			s.speed = CombatMath.FLAK_SPEED
			s.velocity = d * s.speed
			s.max_life = 1.6
			s.damage = CombatMath.FLAK_DAMAGE
			s.radius = 0.015
	s.position = from
	s.prev = from
	return s


func _ready() -> void:
	match kind:
		"bullet":
			_visual = MeshInstance3D.new()
			(_visual as MeshInstance3D).mesh = Models.box(Vector3(0.0022, 0.0022, 0.07))
			(_visual as MeshInstance3D).material_override = Neon.emitter_material(Color(1.0, 0.86, 0.45))
			add_child(_visual)
		"missile":
			_visual = Models.missile(false)
			add_child(_visual)
			_start_trail(Color(0.9, 0.92, 1.0))
		"emissile":
			_visual = Models.missile(true)
			_visual.scale = Vector3.ONE * 1.3
			add_child(_visual)
			var warn := Neon.make_halo(Neon.RED, 0.09, 0.55)
			add_child(warn)
			_start_trail(Color(1.0, 0.45, 0.3))
		"bomb":
			_visual = Models.bomb()
			add_child(_visual)
		"flare":
			_visual = Neon.make_orb(Color(1.0, 0.85, 0.5), 0.012, 8, 4)
			add_child(_visual)
			add_child(Neon.make_halo(Color(1.0, 0.6, 0.2), 0.16, 0.7))
			_start_trail(Color(0.9, 0.9, 0.9))
		"pellet":
			_visual = Neon.make_orb(Neon.RED, 0.01, 8, 4)
			add_child(_visual)
			add_child(Neon.make_halo(Neon.RED, 0.07, 0.5))
		"flak":
			_visual = Neon.make_orb(Neon.AMBER, 0.009, 6, 3)
			add_child(_visual)
			add_child(Neon.make_halo(Neon.AMBER, 0.06, 0.45))
	for c in find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _start_trail(color: Color) -> void:
	_trail_color = color
	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	_trail_node.material_override = Neon.glow_material(color, false, true)
	_trail_node.top_level = true
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_node.extra_cull_margin = 4.0
	add_child(_trail_node)


## Integrates one physics step. Homing shots steer toward `target`.
func step(delta: float) -> void:
	prev = global_position
	life += delta
	match kind:
		"missile", "emissile":
			# Boost phase, then cruise.
			var cruise := speed if kind == "emissile" else CombatMath.MISSILE_SPEED
			var cur := velocity.length()
			cur = minf(cruise, cur + (14.0 if kind == "missile" else 5.0) * delta)
			var heading := velocity.normalized() if velocity.length_squared() > 1e-6 else -global_basis.z
			if is_instance_valid(target) and life > 0.08:
				heading = CombatMath.steer(heading, target.global_position - global_position, turn, delta)
			velocity = heading * cur
		"bomb":
			velocity += Vector3(0, -CombatMath.GRAVITY, 0) * delta
			velocity *= 1.0 - 0.15 * delta
		"flare":
			velocity += Vector3(0, -1.1, 0) * delta
			velocity *= 1.0 - 1.8 * delta
	global_position += velocity * delta
	if velocity.length_squared() > 1e-6 and kind != "flare" and kind != "pellet" and kind != "flak":
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)
	if _trail_mesh:
		_trail.append(global_position)
		if _trail.size() > (18 if kind != "flare" else 10):
			_trail.pop_front()
		_trail_mesh.clear_surfaces()
		if _trail.size() >= 2:
			var w := 0.006 if kind == "missile" else (0.009 if kind == "emissile" else 0.01)
			var newest_first := _trail.duplicate()
			newest_first.reverse()
			Neon.build_tube(_trail_mesh, PackedVector3Array(newest_first), func(t): return w * (1.0 - 0.7 * t))
	if life >= max_life:
		dead = true


## Bombs, missiles and flak should not be confused with cosmetic shots when the
## director looks for things the cannon can shoot down.
func can_be_shot() -> bool:
	return kind == "emissile"
