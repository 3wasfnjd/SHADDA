class_name Shot
extends Node3D
## One projectile, moved and resolved by the battle each physics step with
## exact segment tests.
## player: bullet, rocket, bomb      enemy: ebullet, shell, flak, ebomb

var kind: String = "bullet"
var hostile: bool = false
var velocity: Vector3 = Vector3.ZERO
var prev: Vector3 = Vector3.ZERO
var life: float = 0.0
var max_life: float = 1.0
var damage: float = 1.0
var target: Node3D = null
var dead: bool = false
var fuse: float = 0.0
var gravity: float = 0.0
var _trail_timer: float = 0.0


static func make(shot_kind: String, from: Vector3, dir: Vector3, inherit: Vector3 = Vector3.ZERO) -> Shot:
	var s := Shot.new()
	s.kind = shot_kind
	s.hostile = shot_kind in ["ebullet", "shell", "flak", "ebomb", "sam"]
	var d := dir.normalized()
	match shot_kind:
		"bullet":
			s.velocity = d * WarMath.BULLET_SPEED + inherit
			s.max_life = 0.55
			s.damage = WarMath.BULLET_DAMAGE
		"rocket":
			s.velocity = d * 1.5 + inherit
			s.max_life = 3.0
			s.damage = WarMath.ROCKET_DAMAGE
		"bomb", "ebomb":
			s.velocity = inherit + d * 0.2
			s.max_life = 3.0
			s.damage = WarMath.BOMB_DAMAGE if shot_kind == "bomb" else 10.0
			s.gravity = WarMath.GRAVITY * 0.85
		"ebullet":
			s.velocity = d * WarMath.ENEMY_BULLET_SPEED + inherit * 0.5
			s.max_life = 0.9
			s.damage = WarMath.ENEMY_BULLET_DAMAGE
		"shell":
			s.velocity = d * WarMath.SHELL_SPEED
			s.max_life = 2.5
			s.damage = WarMath.SHELL_DAMAGE
			s.gravity = WarMath.SHELL_GRAVITY
		"sam":
			s.velocity = d * 1.2
			s.max_life = 5.0
			s.damage = WarMath.SAM_DAMAGE
		"flak":
			s.velocity = d * WarMath.FLAK_SPEED
			s.max_life = 1.4
			s.damage = WarMath.FLAK_DAMAGE
	s.position = from
	s.prev = from
	return s


func _ready() -> void:
	match kind:
		"bullet", "ebullet":
			var col := Color(1.0, 0.9, 0.35, 1.0) if kind == "bullet" else Color(1.0, 0.35, 0.25, 1.0)
			Toon.add(self, Toon.capsule(0.0026, 0.05, 6), Toon.flat(col), Vector3.ZERO, Vector3(90, 0, 0))
		"rocket":
			add_child(Models.rocket())
			Toon.add(self, Toon.ball(0.007, 8, 4), Toon.flat(Color(1.0, 0.7, 0.2, 1.0)), Vector3(0, 0, 0.032), Vector3.ZERO, Vector3(1, 1, 2.2))
		"bomb":
			add_child(Models.bomb())
		"ebomb":
			var b := Models.bomb()
			b.scale = Vector3.ONE * 1.4
			add_child(b)
		"shell":
			Toon.add(self, Toon.capsule(0.006, 0.02, 8), Toon.mat(Color(0.25, 0.25, 0.25), 0.6, 0.001), Vector3.ZERO, Vector3(90, 0, 0))
		"flak":
			Toon.add(self, Toon.ball(0.006, 8, 4), Toon.flat(Color(1.0, 0.5, 0.15, 1.0)))
		"sam":
			var r := Models.rocket(true)
			r.scale = Vector3.ONE * 1.5
			add_child(r)
			Toon.add(self, Toon.ball(0.008, 8, 4), Toon.flat(Color(1.0, 0.45, 0.15, 1.0)), Vector3(0, 0, 0.045), Vector3.ZERO, Vector3(1, 1, 2.5))


func step(delta: float, world: Node3D) -> void:
	prev = global_position
	life += delta
	if kind == "rocket" or kind == "sam":
		var top := WarMath.ROCKET_SPEED if kind == "rocket" else WarMath.SAM_SPEED
		var turn := WarMath.ROCKET_TURN if kind == "rocket" else WarMath.SAM_TURN
		var speed := minf(top, velocity.length() + (9.0 if kind == "rocket" else 3.0) * delta)
		var heading := velocity.normalized()
		if is_instance_valid(target) and life > (0.1 if kind == "rocket" else 0.35) and target.has_method("hit_center"):
			heading = WarMath.steer(heading, target.hit_center() - global_position, turn, delta)
		velocity = heading * speed
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.035
			Fx.smoke(world, global_position - velocity.normalized() * 0.03, 0.009 if kind == "rocket" else 0.013)
	if gravity > 0.0:
		velocity += Vector3(0, -gravity, 0) * delta
	global_position += velocity * delta
	if velocity.length_squared() > 1e-6:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)
	if life >= max_life:
		dead = true


## Enemy anti-air missiles can be shot down by the player's guns.
func can_be_shot() -> bool:
	return kind == "sam"
