extends SceneTree
## Pure arithmetic: flight model, wall avoidance, hits, cone, ballistics,
## room box and wall-with-openings decomposition.

func _initialize() -> void:
	var box := {"min": Vector3(-2, 0, -2), "max": Vector3(2, 2.5, 2)}
	# The plane always flies forward and turns toward its goal at a capped rate.
	var s := {"pos": Vector3(0, 1.2, 1.2), "fwd": Vector3.FORWARD, "speed": WarMath.CRUISE, "bank": 0.0}
	var goal := Vector3(1.0, 1.4, -1.0)
	var closest := INF
	var banked := 0.0
	for i in range(72 * 6):
		s = WarMath.fly(s, goal, WarMath.CRUISE, 1.0 / 72.0, box)
		closest = minf(closest, (s.pos as Vector3).distance_to(goal))
		banked = maxf(banked, absf(s.bank))
		assert(WarMath.inside(s.pos, box, 0.0), "stays inside the room: %s" % [s.pos])
		assert(s.speed >= WarMath.MIN_SPEED)
	assert(closest < 0.25, "reached the steer point (%f)" % closest)
	assert(banked > 0.3, "banks into turns (%f)" % banked)
	# Steering straight into a wall: avoidance keeps it inside for 10 s.
	s = {"pos": Vector3(0, 1.2, 0), "fwd": Vector3.RIGHT, "speed": WarMath.BOOST, "bank": 0.0}
	for i in range(720):
		s = WarMath.fly(s, Vector3(9, 1.2, 0), WarMath.BOOST, 1.0 / 72.0, box)
		assert(WarMath.inside(s.pos, box, 0.0), "avoids the wall: %s" % [s.pos])
	# Climbing costs speed.
	var c := {"pos": Vector3(0, 0.5, 0), "fwd": Vector3(0, 0.6, -0.8).normalized(), "speed": WarMath.CRUISE, "bank": 0.0}
	c = WarMath.fly(c, Vector3(0, 2.4, -1.4), WarMath.CRUISE, 0.1, box)
	assert(c.speed < WarMath.CRUISE)
	# Visual basis: nose along fwd.
	var b := WarMath.plane_basis(Vector3(1, 0, 0), 0.4)
	assert((-b.z).distance_to(Vector3(1, 0, 0)) < 1e-4)
	# Steer point stays clear of walls and the floor.
	var sp := WarMath.steer_point(Vector3(0, 1.4, 0), Vector3(0, -1, -1).normalized(), 2.0, box)
	assert(sp.y >= 0.3 and WarMath.inside(sp, box, 0.0))
	# Exact hits (no tunnelling at bullet speed).
	var step := WarMath.BULLET_SPEED / 72.0
	assert(WarMath.segment_sphere(Vector3(0, 0, 0.12), Vector3(0, 0, 0.12 - step), Vector3.ZERO, 0.1) >= 0.0)
	assert(WarMath.segment_sphere(Vector3(0.12, 0, 1), Vector3(0.12, 0, -1), Vector3.ZERO, 0.1) < 0.0)
	assert(absf(WarMath.ray_sphere(Vector3(0, 0, 2), Vector3.FORWARD, Vector3.ZERO, 0.5) - 1.5) < 1e-4)
	assert(WarMath.in_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(0.3, 0, -2)))
	assert(not WarMath.in_cone(Vector3.ZERO, Vector3.FORWARD, Vector3(1.2, 0, -2)))
	# Ballistic shell passes through its target.
	var from := Vector3(0, 0.05, 0)
	var tgt := Vector3(1.2, 1.1, -0.6)
	var d := WarMath.ballistic_dir(from, tgt, WarMath.SHELL_SPEED, WarMath.SHELL_GRAVITY)
	var p := from
	var v := d * WarMath.SHELL_SPEED
	var best := INF
	for i in range(400):
		v += Vector3(0, -WarMath.SHELL_GRAVITY, 0) * 0.002
		p += v * 0.002
		best = minf(best, p.distance_to(tgt))
	assert(best < 0.03, "shell lands on target (%f)" % best)
	assert(WarMath.bomb_impact(Vector3(0, 1, 0), Vector3.ZERO, 0.0).distance_to(Vector3.ZERO) < 1e-4)
	# Room box and walls with holes.
	var walls := [
		{"origin": Vector3(0, 0, -2), "normal": Vector3(0, 0, 1), "width": 4.0},
		{"origin": Vector3(0, 0, 2), "normal": Vector3(0, 0, -1), "width": 4.0},
		{"origin": Vector3(2, 0, 0), "normal": Vector3(-1, 0, 0), "width": 4.0},
	]
	var rb := WarMath.room_box(walls, 0.0, 2.6, Vector3.ZERO)
	assert(rb.min.distance_to(Vector3(-2, 0, -2)) < 1e-4 and rb.max.distance_to(Vector3(2, 2.6, 2)) < 1e-4)
	var cells := WarMath.rect_minus_holes(Rect2(-2, 0, 4, 2.6), [Rect2(-0.5, 1.0, 1.0, 0.8)])
	var area := 0.0
	for cell in cells:
		area += (cell as Rect2).get_area()
		assert(not (cell as Rect2).intersects(Rect2(-0.49, 1.01, 0.98, 0.78)), "no cell covers the window")
	assert(absf(area - (4.0 * 2.6 - 0.8)) < 1e-4, "area %f" % area)
	assert(WarMath.combo(1) == 1.0 and WarMath.combo(9) == 3.0)
	assert(WarMath.stars(0.8, true) == 3 and WarMath.stars(0.9, false) == 0)
	assert(WarMath.WAVES.size() == 5 and WarMath.WAVES[4].has("bomber"))
	print("PASS: war math (free flight stays in the room, reaches the steer point, banks, climbs cost speed; hits; ballistics; walls with openings)")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
