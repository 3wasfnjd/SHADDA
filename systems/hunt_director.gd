class_name HuntDirector
extends Node3D
## SHARARA match flow, with no rounds and no text:
## SCANNING (room anchors) → PLACING (the gem floats where you look; A drops
## it) → PLAYING (sparks pour from wall cracks, pressure rising for five
## minutes) → ENDED (the gem goes dark, or the cracks seal and the gem blazes;
## A plays again).

enum Phase { SCANNING, PLACING, PLAYING, ENDED }

const MAX_CRACKS := 4
const FALLBACK_CEILING := 2.45          # metres above the floor when the room is unknown
const FALLBACK_DISTANCE := 1.6
const FALLBACK_ANGLES := [-60.0, 0.0, 60.0, 180.0]
const START_DELAY := 2.0

var phase: int = Phase.SCANNING
var head: XRCamera3D
var gauntlets: Array[Gauntlet] = []
var gem: Gem
var cracks: Array[Crack] = []
var sparks: Array = []
var audio: GameAudio
var floor_offset: float = 0.0
var room_found: bool = false
var room_mounts: Array = []
var match_time: float = 0.0
var next_spawn: float = 0.0
var kills: int = 0
var survived: bool = false
var mode: String = "sparks"
var _mascot: Spark = null
var _mascots: Array = []
var _picker_anchor: Transform3D = Transform3D.IDENTITY
var _mode_cooldown: float = 0.0
var combo: int = 0
var _combo_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _crack_cursor: int = 0
var _end_timer: float = 0.0
var _floor_body: StaticBody3D
var _gaze_point: Vector3 = Vector3(0, 0, -1.5)


func build(camera: XRCamera3D, hands: Array[Gauntlet]) -> void:
	head = camera
	gauntlets = hands
	_rng.randomize()
	audio = GameAudio.new()
	add_child(audio)
	_floor_body = StaticBody3D.new()
	_floor_body.collision_layer = 1
	_floor_body.collision_mask = 0
	var slab := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	slab.shape = box
	slab.position.y = -0.1
	_floor_body.add_child(slab)
	add_child(_floor_body)
	gem = Gem.new()
	add_child(gem)
	gem.begin_placement()
	for i in range(MAX_CRACKS):
		var crack := Crack.new()
		add_child(crack)
		crack.hum = audio.attach_loop("hum", crack, -24.0)
		cracks.append(crack)
	for g in gauntlets:
		g.director = self
	phase = Phase.SCANNING
	apply_fallback_layout()


func on_room_ready(mounts: Array, floor_y: float, found: bool) -> void:
	room_mounts = mounts
	room_found = found and not mounts.is_empty()
	if found:
		floor_offset = floor_y
		position.y = floor_offset
	if room_found:
		_mount_cracks_on_room()
	else:
		apply_fallback_layout()
	phase = Phase.PLACING
	set_mode(mode)
	anchor_picker()


## Doors and windows first, then at most two walls, then one ceiling point,
## then whatever is left — never a crack floating in the room.
func _mount_cracks_on_room() -> void:
	var chosen: Array = []
	var walls := 0
	var ceilings := 0
	for pass_kind in [["door", "window"], ["wall"], ["ceiling"], ["wall", "ceiling"]]:
		for m in room_mounts:
			if chosen.size() >= cracks.size() or not pass_kind.has(m.kind):
				continue
			if m.kind == "wall" and walls >= 2 and pass_kind.size() == 1:
				continue
			if m.kind == "ceiling" and ceilings >= 1 and pass_kind.size() == 1:
				continue
			var too_close := false
			for c in chosen:
				if c.origin.distance_to(m.origin) < 1.0:
					too_close = true
			if too_close or chosen.has(m):
				continue
			chosen.append(m)
			if m.kind == "wall":
				walls += 1
			elif m.kind == "ceiling":
				ceilings += 1
	for i in range(cracks.size()):
		if i < chosen.size():
			var m: Dictionary = chosen[i]
			var origin: Vector3 = m.origin if m.kind == "ceiling" else Vector3(m.origin.x, floor_offset, m.origin.z)
			var hint := Vector3.UP
			if m.kind == "ceiling":
				hint = head.global_position - origin
				hint.y = 0.0
				hint = hint.normalized() if hint.length() > 0.01 else Vector3.FORWARD
			cracks[i].mount(origin, m.normal, hint)
		else:
			cracks[i].global_position = Vector3(0, -50, 0)


## No room data: cracks open on an estimated ceiling above the player
## (never floating mid-room). B/Y re-centres them on the current gaze.
func apply_fallback_layout() -> void:
	var forward := -head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var feet := feet_local()
	for i in range(cracks.size()):
		var direction := forward.rotated(Vector3.UP, deg_to_rad(FALLBACK_ANGLES[i]))
		var point := to_global(feet + direction * FALLBACK_DISTANCE + Vector3(0, FALLBACK_CEILING, 0))
		cracks[i].mount(point, Vector3.DOWN, -direction)


func active_cracks() -> Array:
	var out: Array = []
	for c in cracks:
		if c.global_position.y > -10.0:
			out.append(c)
	return out


func feet_local() -> Vector3:
	var local := to_local(head.global_position)
	return Vector3(local.x, 0.0, local.z)


## Left stick sideways before the match cycles the mode; a floating mascot
## above the gem shows which critters will come. No text needed.
func cycle_mode(axis: float, delta: float) -> void:
	_mode_cooldown = maxf(0.0, _mode_cooldown - delta)
	if phase != Phase.PLACING or absf(axis) < 0.6 or _mode_cooldown > 0.0:
		return
	_mode_cooldown = 0.45
	var i := SparkMath.MODES.find(mode)
	i = (i + (1 if axis > 0.0 else -1) + SparkMath.MODES.size()) % SparkMath.MODES.size()
	set_mode(SparkMath.MODES[i])
	cue("attach", gem.global_position)


func set_mode(new_mode: String) -> void:
	mode = new_mode
	_ensure_picker()
	_mascot = _mascots[SparkMath.MODES.find(mode)]


## Four mascots hang in an arc in front of the player while placing: one per
## mode. Aim at one and pull the trigger (or flick the left stick) to choose.
func _ensure_picker() -> void:
	if not _mascots.is_empty():
		return
	for m in SparkMath.MODES:
		var mascot := Spark.create(SparkMath.mode_kinds(m)[0])
		mascot.preview_only = true
		add_child(mascot)
		mascot.player_head = head
		_mascots.append(mascot)
	anchor_picker()


func anchor_picker() -> void:
	var forward := -head.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	_picker_anchor = Transform3D(Basis.looking_at(forward, Vector3.UP), head.global_position + forward * 1.4 + Vector3(0, -0.25, 0))


func _update_picker(delta: float) -> void:
	if _mascots.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(_mascots.size()):
		var mascot: Spark = _mascots[i]
		if not is_instance_valid(mascot):
			continue
		var x := (i - 1.5) * 0.42
		var local := Vector3(x, sin(t * 1.6 + i) * 0.04, -0.12 * absf(i - 1.5))
		var selected: bool = SparkMath.MODES[i] == mode
		mascot.global_position = _picker_anchor * local
		mascot.velocity = Vector3(0, 0, 0)
		mascot.scale = mascot.scale.lerp(Vector3.ONE * (1.45 if selected else 0.8), minf(1.0, delta * 8.0))
		mascot.visible = phase == Phase.PLACING
		mascot._hit_flash = 0.35 if selected else 0.0


## Trigger pull while placing: pick the mascot closest to the aim ray.
func aim_select(origin: Vector3, direction: Vector3) -> bool:
	if phase != Phase.PLACING:
		return false
	var best := -1
	var best_d := 0.28
	for i in range(_mascots.size()):
		var p: Vector3 = _mascots[i].global_position
		var along := (p - origin).dot(direction)
		if along < 0.2:
			continue
		var d := (origin + direction * along).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	if SparkMath.MODES[best] != mode:
		set_mode(SparkMath.MODES[best])
		cue("attach", _mascots[best].global_position)
	return true


func _clear_picker() -> void:
	for m in _mascots:
		if is_instance_valid(m):
			m.queue_free()
	_mascots.clear()
	_mascot = null


func adjust_floor(axis: float, delta: float) -> float:
	if phase == Phase.PLAYING or absf(axis) < 0.25:
		return floor_offset
	floor_offset = clampf(floor_offset + axis * delta * 0.25, -1.2, 1.2)
	position.y = floor_offset
	return floor_offset


func cue(name: String, point: Vector3, volume_db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, point, volume_db)


func on_button(action: StringName, hand_index: int) -> void:
	if action == &"ax_button":
		match phase:
			Phase.PLACING:
				_place_and_start()
			Phase.ENDED:
				if _end_timer > 1.5:
					_reset_for_placement()
			Phase.PLAYING:
				if hand_index < gauntlets.size():
					gauntlets[hand_index].release_everything()
	elif action == &"by_button" and phase == Phase.PLACING:
		anchor_picker()
		if not room_found:
			apply_fallback_layout()


func _place_and_start() -> void:
	gem.place()
	cue("gem_place", gem.global_position)
	for g in gauntlets:
		g.release_everything()
	_clear_picker()
	match_time = 0.0
	combo = 0
	next_spawn = START_DELAY + SparkMath.FIRST_SPAWN
	kills = 0
	survived = false
	phase = Phase.PLAYING


func _reset_for_placement() -> void:
	for s in sparks:
		if is_instance_valid(s):
			s.queue_free()
	sparks.clear()
	for c in cracks:
		c.close()
	gem.begin_placement()
	phase = Phase.PLACING
	set_mode(mode)
	anchor_picker()


func _process(delta: float) -> void:
	if head == null:
		return
	match phase:
		Phase.PLACING:
			_update_gaze_placement(delta)
		Phase.PLAYING:
			match_time += delta
			_combo_timer = maxf(0.0, _combo_timer - delta)
			_spawning(delta)
			_drain(delta)
			_crack_moods()
			_check_end()
		Phase.ENDED:
			_end_timer += delta


func _update_gaze_placement(delta: float) -> void:
	var origin := head.global_position
	var dir := -head.global_basis.z
	var floor_plane := Plane(Vector3.UP, global_position.y)
	var hit = floor_plane.intersects_ray(origin, dir)
	var target: Vector3
	if hit != null:
		target = hit
	else:
		var forward := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.FORWARD
		target = Vector3(origin.x, global_position.y, origin.z) + forward * 2.0
	var feet := Vector3(origin.x, global_position.y, origin.z)
	var away := target - feet
	var d := away.length()
	if d < 1.0 or d > 3.0:
		away = away.normalized() * clampf(d, 1.0, 3.0)
	_gaze_point = _gaze_point.lerp(feet + away, minf(1.0, delta * 6.0))
	gem.global_position = _gaze_point
	if _mascots.is_empty():
		set_mode(mode)
	_update_picker(delta)


func _spawning(delta: float) -> void:
	var t := match_time - START_DELAY
	if t < 0.0:
		return
	if t >= SparkMath.MATCH_SECONDS:
		return
	if match_time >= next_spawn and sparks.size() < SparkMath.max_alive(t):
		next_spawn = match_time + SparkMath.gap(t)
		_spawn(SparkMath.pick(t, _rng.randf(), mode))


func _spawn(kind: String, at_crack: Crack = null, at_point: Vector3 = Vector3.INF) -> Spark:
	var available := active_cracks()
	if available.is_empty():
		return null
	var crack: Crack = at_crack if at_crack else available[_crack_cursor % available.size()]
	_crack_cursor += 1
	crack.open()
	if crack.mode == Crack.Mode.OPENING and crack.open_seconds() < 0.1:
		cue("crack_open", crack.global_position)
	var spark := Spark.create(kind)
	spark.director = self
	add_child(spark)
	spark.configure(crack, gem, head)
	if at_point != Vector3.INF:
		spark.global_position = at_point
		spark.state = Spark.State.APPROACH
	spark.died.connect(_on_spark_died)
	spark.escaped.connect(_on_spark_escaped)
	spark.shard_taken.connect(_on_shard_taken)
	spark.shard_dropped.connect(_on_shard_dropped)
	spark.split.connect(_on_split)
	spark.bit_player.connect(_on_bite)
	sparks.append(spark)
	cue("spark_spawn", crack.spawn_point())
	return spark


func _drain(delta: float) -> void:
	var draining := 0
	for s in sparks:
		if is_instance_valid(s) and s.state == Spark.State.DRAIN:
			draining += 1
	gem.drain(delta, draining)


func _crack_moods() -> void:
	for c in active_cracks():
		var busy := false
		for s in sparks:
			if is_instance_valid(s) and s.home == c and s.state != Spark.State.DEAD:
				busy = true
		if not busy and c.is_open() and c.open_seconds() > 2.0:
			c.close()
			cue("crack_close", c.global_position, -8.0)


func _on_spark_died(spark: Spark) -> void:
	kills += 1
	sparks.erase(spark)
	# Combo: quick successive kills pitch the pop up and shake the gem brighter.
	combo = combo + 1 if _combo_timer > 0.0 else 1
	_combo_timer = 2.0
	var heavy := spark.mass >= 3.0
	cue("spark_big_pop" if heavy else "spark_pop", spark.global_position, minf(combo - 1, 6) * 1.0)
	if audio and audio.voices.size() > 0:
		audio.voices[(audio.cursor + audio.voices.size() - 1) % audio.voices.size()].pitch_scale = 1.0 + minf(combo - 1, 6) * 0.08
	gem.flash(minf(0.3 + combo * 0.1, 0.8))
	for g in gauntlets:
		g.pulse(0.5 + minf(combo, 5) * 0.1)


func _on_bite(spark: Spark) -> void:
	cue("gem_hit", spark.global_position, 2.0)
	for g in gauntlets:
		g.bitten()


func _on_spark_escaped(spark: Spark, with_shard: bool) -> void:
	sparks.erase(spark)
	if with_shard:
		gem.lose_shard()
		cue("shard_lost", gem.global_position)


func _on_shard_taken(_spark: Spark) -> void:
	cue("drain", gem.global_position)


func _on_shard_dropped(_spark: Spark, _at: Vector3) -> void:
	gem.recover_shard()
	cue("gem_hit", gem.global_position, -4.0)


func _on_split(spark: Spark, at: Vector3) -> void:
	cue("split", at)
	for i in range(2):
		var mote := _spawn("mote", spark.home, at + Vector3(randf_range(-0.2, 0.2), 0.1, randf_range(-0.2, 0.2)))
		if mote:
			mote.velocity = Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1))


func _check_end() -> void:
	if gem.energy <= 0.0:
		_end(false)
	elif match_time - START_DELAY >= SparkMath.MATCH_SECONDS and sparks.is_empty():
		_end(true)


func _end(won: bool) -> void:
	phase = Phase.ENDED
	survived = won
	_end_timer = 0.0
	gem.set_alive(won)
	if won:
		gem.energy = 1.0
	for c in cracks:
		if c.is_open():
			cue("crack_close", c.global_position)
		c.close()
	for g in gauntlets:
		g.release_everything()
	cue("win" if won else "loss", gem.global_position)


func targets() -> Array:
	return sparks.duplicate()


func update_hands(delta: float, triggers: Array, grips: Array) -> void:
	var list := targets()
	for i in range(gauntlets.size()):
		gauntlets[i].update(delta, triggers[i], grips[i], list, phase == Phase.PLAYING)
