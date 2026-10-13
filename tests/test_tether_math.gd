extends SceneTree
## Rope arithmetic: reeling, tension, snapping, pull direction, colours.
func _initialize() -> void:
	# Reeling shortens the rope at REEL_SPEED and never below MIN_REST.
	var rest := 2.0
	rest = TetherMath.reel(rest, 1.0, 0.5)
	assert(is_equal_approx(rest, 2.0 - TetherMath.REEL_SPEED * 0.5))
	rest = TetherMath.reel(rest, 1.0, 100.0)
	assert(is_equal_approx(rest, TetherMath.MIN_REST))
	assert(is_equal_approx(TetherMath.reel(1.0, 0.0, 1.0), 1.0))
	# Tension is 0 when slack, 1 when stretched by SLACK_BAND.
	assert(is_zero_approx(TetherMath.tension(1.0, 1.2)))
	assert(is_equal_approx(TetherMath.tension(1.0 + TetherMath.SLACK_BAND, 1.0), 1.0))
	assert(is_equal_approx(TetherMath.tension(1.0 + TetherMath.SLACK_BAND * 0.5, 1.0), 0.5))
	# Pull points from the robot toward the hand, scales down with mass, zero when slack.
	var hand := Vector3(0, 1.2, 0)
	var anchor := Vector3(0, 0.8, -1.2)
	var light := TetherMath.pull_velocity(hand, anchor, 1.0, 1.0, 1.0 / 90.0)
	var heavy := TetherMath.pull_velocity(hand, anchor, 1.0, 4.5, 1.0 / 90.0)
	assert(light.z > 0.0 and light.y > 0.0)
	assert(light.length() > heavy.length() * 2.0)
	assert(TetherMath.pull_velocity(hand, anchor, 5.0, 1.0, 0.1) == Vector3.ZERO)
	# A huge stretch is capped so raiders never teleport into the player's face.
	var yank := TetherMath.pull_velocity(hand, Vector3(0, 0.8, -6.0), 0.45, 0.5, 1.0 / 90.0)
	assert(yank.length() <= TetherMath.MAX_DRAG * 6.0 / 90.0 + 1e-6)
	# Snap timer accumulates only at full tension and decays otherwise.
	var timer := 0.0
	for i in range(int(TetherMath.SNAP_HOLD * 90.0) - 1):
		timer = TetherMath.snap_timer(timer, 1.0, 1.0 / 90.0)
	assert(not TetherMath.should_snap(timer))
	timer = TetherMath.snap_timer(timer, 1.0, 0.03)
	assert(TetherMath.should_snap(timer))
	timer = TetherMath.snap_timer(timer, 0.2, 1.0)
	assert(is_zero_approx(timer))
	# Rope geometry: endpoints exact, sag only with slack, segment count honoured.
	var taut := TetherMath.rope_points(Vector3.ZERO, Vector3(2, 0, 0), 2.0, 10)
	assert(taut.size() == 11 and taut[0] == Vector3.ZERO and taut[10] == Vector3(2, 0, 0))
	assert(is_zero_approx(taut[5].y))
	var slack := TetherMath.rope_points(Vector3.ZERO, Vector3(1, 0, 0), 1.6, 10)
	assert(slack[5].y < -0.2 and slack[0] == Vector3.ZERO)
	# Colour ramps cyan -> amber -> white.
	assert(TetherMath.rope_color(0.0).is_equal_approx(Neon.CYAN))
	assert(TetherMath.rope_color(0.5).is_equal_approx(Neon.AMBER))
	assert(TetherMath.rope_color(1.0).is_equal_approx(Neon.WHITE))
	assert(TetherMath.haptic_amplitude(0.0, false) == 0.0)
	assert(TetherMath.haptic_amplitude(1.0, true) <= 1.0)
	print("PASS: tether math — reel, tension, pull, snap, rope geometry, colours")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
