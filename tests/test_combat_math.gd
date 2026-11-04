extends SceneTree
## Pure arithmetic: hit tests that cannot tunnel, lock cone, steering, bomb
## ballistics, room box, combo, stars, spring.

func _initialize() -> void:
	# Segment vs sphere: a 34 m/s round crossing a 10 cm drone in one 90 Hz step.
	var step := CombatMath.CANNON_SPEED / 90.0
	assert(CombatMath.segment_sphere(Vector3(0, 0, 0.2), Vector3(0, 0, 0.2 - step), Vector3.ZERO, 0.1) >= 0.0, "fast round hits")
	assert(CombatMath.segment_sphere(Vector3(0.12, 0, 0.2), Vector3(0.12, 0, -0.2), Vector3.ZERO, 0.1) < 0.0, "misses by 2 cm")
	assert(CombatMath.segment_sphere(Vector3(0, 0, 1), Vector3(0, 0, 0.5), Vector3.ZERO, 0.1) < 0.0, "stops short")
	var t := CombatMath.segment_sphere(Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3.ZERO, 0.1)
	assert(absf(t - 0.45) < 1e-4, "entry fraction %f" % t)
	assert(absf(CombatMath.ray_sphere(Vector3(0, 0, 2), Vector3.FORWARD, Vector3.ZERO, 0.5) - 1.5) < 1e-4)
	assert(CombatMath.ray_sphere(Vector3(0, 0, 2), Vector3.BACK, Vector3.ZERO, 0.5) == INF)
	# Lock cone.
	assert(CombatMath.in_lock_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0.3, 0, -2)))
	assert(not CombatMath.in_lock_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(1.0, 0, -2)), "outside 16°")
	assert(not CombatMath.in_lock_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -9)), "out of range")
	assert(not CombatMath.in_lock_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 2)), "behind")
	# Steering respects the turn rate and converges.
	var h := CombatMath.steer(Vector3.FORWARD, Vector3.RIGHT, 2.0, 0.1)
	assert(absf(rad_to_deg(Vector3.FORWARD.angle_to(h)) - rad_to_deg(0.2)) < 0.01)
	var heading := Vector3.FORWARD
	for i in range(200):
		heading = CombatMath.steer(heading, Vector3.RIGHT, 2.0, 1.0 / 90.0)
	assert(heading.distance_to(Vector3.RIGHT) < 1e-3, "converged")
	# Bomb from 1.2 m with no speed lands straight below; with speed, ahead.
	var p := CombatMath.bomb_impact(Vector3(0, 1.2, 0), Vector3.ZERO, 0.0)
	assert(p.distance_to(Vector3.ZERO) < 1e-4)
	var q := CombatMath.bomb_impact(Vector3(0, 1.2, 0), Vector3(0, 0, -1.0), 0.0)
	assert(absf(q.z + sqrt(2.4 / 9.8)) < 1e-3, "forward throw %f" % q.z)
	# Blast falloff.
	assert(CombatMath.blast_damage(0.0, 0.4, 10.0) == 10.0)
	assert(CombatMath.blast_damage(0.5, 0.4, 10.0) == 0.0)
	# Combo and score.
	assert(CombatMath.combo(1) == 1.0 and CombatMath.combo(3) == 1.5 and CombatMath.combo(40) == 3.0)
	assert(CombatMath.points("tank", 1.0, "bomb") == 375)
	assert(CombatMath.stars(0.8, true) == 3 and CombatMath.stars(0.5, true) == 2 and CombatMath.stars(0.1, true) == 1 and CombatMath.stars(1.0, false) == 0)
	assert(CombatMath.wave_total(0) == 8 and CombatMath.WAVES.size() == 5 and CombatMath.WAVES[4].has("boss"))
	# Room box from four walls of a 4 × 3 m room, clamped to 3 m half-extent.
	var mounts := [
		{"origin": Vector3(0, 0, -1.5), "normal": Vector3(0, 0, 1), "width": 4.0, "kind": "wall"},
		{"origin": Vector3(0, 0, 1.5), "normal": Vector3(0, 0, -1), "width": 4.0, "kind": "wall"},
		{"origin": Vector3(2, 0, 0), "normal": Vector3(-1, 0, 0), "width": 3.0, "kind": "wall"},
		{"origin": Vector3(-2, 0, 0), "normal": Vector3(1, 0, 0), "width": 3.0, "kind": "wall"},
		{"origin": Vector3(0, 2.6, 0), "normal": Vector3.DOWN, "width": 3.0, "kind": "ceiling"},
	]
	var box := CombatMath.room_box(mounts, 0.0, Vector3.ZERO)
	assert(box.min.distance_to(Vector3(-2, 0, -1.5)) < 1e-4 and box.max.distance_to(Vector3(2, 2.6, 1.5)) < 1e-4, "box %s" % [box])
	var fallback := CombatMath.room_box([], 0.0, Vector3(1, 1.6, 1))
	assert(fallback.min.distance_to(Vector3(-0.6, 0, -0.6)) < 1e-4)
	var c := CombatMath.clamp_into(Vector3(9, 9, -9), box, 0.3, 0.5)
	assert(c.distance_to(Vector3(1.7, 2.3, -1.2)) < 1e-4)
	assert(CombatMath.inside(Vector3(0, 1, 0), box) and not CombatMath.inside(Vector3(5, 1, 0), box))
	# Spring settles on the hand without overshooting far.
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var peak := 0.0
	for i in range(90):
		var r: Array = CombatMath.spring(pos, vel, Vector3(0.5, 0, 0), 22.0, 1.0 / 72.0)
		pos = r[0]
		vel = r[1]
		peak = maxf(peak, pos.x)
	assert(pos.distance_to(Vector3(0.5, 0, 0)) < 1e-3 and peak < 0.505, "spring %s peak %f" % [pos, peak])
	print("PASS: combat math (hits, lock cone, steering, bombs, room box, combo, spring)")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
