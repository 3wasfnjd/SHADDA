class_name HuntDirector
extends Node3D
## SHARARA match flow — wordless, icons and numbers only:
##  SCANNING → MENU     four mode mascots (best score + stars under each) and
##                      a big play button; aim + trigger to choose
##  PLACING             the gem hovers where you look; trigger or A drops it
##  PLAYING             five waves; each opens one more breach in your walls;
##                      wave five brings a crowned boss
##  RESULTS             score, 0-3 stars, a crown on a new best; retry / home

enum Phase { SCANNING, MENU, PLACING, PLAYING, RESULTS }

const MAX_CRACKS := 4
const FALLBACK_CEILING := 2.45
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
var hud: Hud
var save := SaveData.new()
var floor_offset: float = 0.0
var room_found: bool = false
var room_mounts: Array = []
var mode: String = "sparks"
var score: int = 0
var kills: int = 0
var combo: int = 0
var wave: int = 0
var survived: bool = false
var stars_won: int = 0
var new_best: bool = false
var boss: Spark = null
## Tests switch this off to drive spawns by hand.
var auto_spawn: bool = true

var _rng := RandomNumberGenerator.new()
var _crack_cursor: int = 0
var _floor_body: StaticBody3D
var _gaze_point: Vector3 = Vector3(0, 0, -1.5)
var _combo_timer: float = 0.0
var _wave_spawned: int = 0
var _wave_break: float = 0.0
var _next_spawn: float = 0.0
var _phase_time: float = 0.0
var _mode_cooldown: float = 0.0

# Menu.
var _menu_root: Node3D
var _menu_anchor: Transform3D = Transform3D.IDENTITY
var _mascots: Array = []
var _mascot_best: Array[Label3D] = []
var _mascot_stars: Array = []
var _play_button: UI.Button3D
var _hover_index: Array[int] = [-1, -1]
# Results.
var _results_root: Node3D
var _results_score: Label3D
var _results_stars: Array[MeshInstance3D] = []
var _results_crown: Node3D
var _retry_button: UI.Button3D
var _home_button: UI.Button3D
var _results_reveal: float = 0.0


func build(camera: XRCamera3D, hands: Array[Gauntlet]) -> void:
	head = camera
	gauntlets = hands
	_rng.randomize()
	save.load_file()
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
	gem.visible = false
	for i in range(MAX_CRACKS):
		var crack := Crack.new()
		crack.director = self
		add_child(crack)
		crack.hum = audio.attach_loop("hum", crack, -24.0)
		cracks.append(crack)
	for g in gauntlets:
		g.director = self
	hud = Hud.new()
	hud.world = self
	if gauntlets.size() > 0:
		gauntlets[0].add_child(hud)
	else:
		add_child(hud)
	phase = Phase.SCANNING
	apply_fallback_layout()


# --- room ---------------------------------------------------------------------

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
	_enter_menu()


## Doors and windows first, then at most two walls, then one ceiling point,
## then whatever is left — never a breach floating in the room.
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


## No room data: breaches open on an estimated ceiling above the player.
func apply_fallback_layout() -> void:
	var forward := _flat_forward()
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


func _flat_forward() -> Vector3:
	var forward := -head.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func adjust_floor(axis: float, delta: float) -> float:
	if phase == Phase.PLAYING or absf(axis) < 0.25:
		return floor_offset
	floor_offset = clampf(floor_offset + axis * delta * 0.25, -1.2, 1.2)
	position.y = floor_offset
	return floor_offset


func cue(name: String, point: Vector3, volume_db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, point, volume_db)


func in_menu() -> bool:
	return phase == Phase.MENU or phase == Phase.RESULTS or phase == Phase.PLACING


# --- menu ---------------------------------------------------------------------

func _enter_menu() -> void:
	phase = Phase.MENU
	_phase_time = 0.0
	_clear_results()
	gem.visible = false
	hud.visible = false
	_build_menu()
	audio.play_music("menu")


func _build_menu() -> void:
	if _menu_root:
		_menu_root.queue_free()
	_mascots.clear()
	_mascot_best.clear()
	_mascot_stars.clear()
	_menu_root = Node3D.new()
	add_child(_menu_root)
	anchor_menu()
	for i in range(SparkMath.MODES.size()):
		var m: String = SparkMath.MODES[i]
		var mascot := Spark.create(SparkMath.mode_kinds(m)[0])
		mascot.preview_only = true
		mascot.player_head = head
		_menu_root.add_child(mascot)
		_mascots.append(mascot)
		var best := UI.digits(str(save.best(m)) if save.best(m) > 0 else "", 56, Neon.WHITE)
		_menu_root.add_child(best)
		_mascot_best.append(best)
		var row: Array = []
		for k in range(3):
			var star := UI.filled_star(Neon.AMBER if k < save.stars(m) else Color(0.22, 0.24, 0.34), 0.045)
			_menu_root.add_child(star)
			row.append(star)
		_mascot_stars.append(row)
	_play_button = UI.Button3D.new("play", Neon.CYAN, 0.12)
	_menu_root.add_child(_play_button)
	_layout_menu(0.0)


func anchor_menu() -> void:
	var forward := _flat_forward()
	_menu_anchor = Transform3D(Basis.looking_at(forward, Vector3.UP), head.global_position + forward * 1.4 + Vector3(0, -0.2, 0))


func _layout_menu(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var cam_pos := head.global_position
	for i in range(_mascots.size()):
		var mascot: Spark = _mascots[i]
		var x := (i - 1.5) * 0.42
		var arc := -0.12 * absf(i - 1.5)
		var selected: bool = SparkMath.MODES[i] == mode
		var hovered: bool = _hover_index.has(i)
		mascot.global_position = _menu_anchor * Vector3(x, 0.12 + sin(t * 1.6 + i) * 0.04, arc)
		var target_scale := 1.45 if selected else (1.1 if hovered else 0.8)
		mascot.scale = mascot.scale.lerp(Vector3.ONE * target_scale, minf(1.0, delta * 8.0)) if delta > 0.0 else Vector3.ONE * target_scale
		mascot._hit_flash = 0.35 if selected else (0.2 if hovered else 0.0)
		var drop := (mascot.scale.x - 0.8) * 0.12
		_mascot_best[i].global_position = _menu_anchor * Vector3(x, -0.09 - drop, arc + 0.05)
		_mascot_best[i].modulate = Neon.WHITE if selected else Color(0.75, 0.8, 0.9)
		for k in range(3):
			var star: MeshInstance3D = _mascot_stars[i][k]
			star.global_position = _menu_anchor * Vector3(x + (k - 1) * 0.055, -0.155 - drop, arc + 0.05)
			star.look_at(cam_pos, Vector3.UP, true)
	_play_button.global_position = _menu_anchor * Vector3(0, -0.36, 0.05)
	_play_button.hovered = 1.0 if _hover_index.has(100) else 0.0


## Called every frame by each hand while in a menu: highlight what it points at.
func aim_hover(hand: int, origin: Vector3, direction: Vector3) -> void:
	_hover_index[clampi(hand, 0, 1)] = _pick(origin, direction)


func _pick(origin: Vector3, direction: Vector3) -> int:
	match phase:
		Phase.MENU:
			var best := -1
			var best_d := 0.2
			for i in range(_mascots.size()):
				var p: Vector3 = _mascots[i].global_position
				var along := (p - origin).dot(direction)
				if along < 0.2:
					continue
				var d := (origin + direction * along).distance_to(p)
				if d < best_d:
					best_d = d
					best = i
			if _play_button and _play_button.ray_distance(origin, direction) < maxf(best_d, 0.16):
				return 100
			return best
		Phase.RESULTS:
			if _results_reveal < 1.2:
				return -1
			if _retry_button and _retry_button.ray_distance(origin, direction) < 0.16:
				return 200
			if _home_button and _home_button.ray_distance(origin, direction) < 0.16:
				return 201
	return -1


## Trigger pull in a menu. Returns true when something was pressed.
func aim_select(origin: Vector3, direction: Vector3) -> bool:
	if phase == Phase.PLACING:
		_place_and_start()
		return true
	var picked := _pick(origin, direction)
	if picked < 0:
		return false
	_press(picked)
	return true


func _press(id: int) -> void:
	if id >= 0 and id < SparkMath.MODES.size():
		if SparkMath.MODES[id] != mode:
			mode = SparkMath.MODES[id]
			cue("attach", _mascots[id].global_position)
		return
	match id:
		100:
			_play_button.pressed_flash = 1.0
			cue("gem_place", _play_button.global_position)
			_enter_placing()
		200:
			_retry_button.pressed_flash = 1.0
			cue("gem_place", _retry_button.global_position)
			_enter_placing()
		201:
			_home_button.pressed_flash = 1.0
			cue("attach", _home_button.global_position)
			_enter_menu()


## Left stick sideways also cycles the mode in the menu.
func cycle_mode(axis: float, delta: float) -> void:
	_mode_cooldown = maxf(0.0, _mode_cooldown - delta)
	if phase != Phase.MENU or absf(axis) < 0.6 or _mode_cooldown > 0.0:
		return
	_mode_cooldown = 0.45
	var i := SparkMath.MODES.find(mode)
	i = (i + (1 if axis > 0.0 else -1) + SparkMath.MODES.size()) % SparkMath.MODES.size()
	_press(i)


func set_mode(new_mode: String) -> void:
	mode = new_mode


func on_button(action: StringName, hand_index: int) -> void:
	if action == &"ax_button":
		match phase:
			Phase.MENU:
				_press(100)
			Phase.PLACING:
				_place_and_start()
			Phase.RESULTS:
				if _results_reveal > 1.2:
					_press(200)
			Phase.PLAYING:
				if hand_index < gauntlets.size():
					gauntlets[hand_index].release_everything()
	elif action == &"by_button":
		match phase:
			Phase.MENU:
				anchor_menu()
				if not room_found:
					apply_fallback_layout()
			Phase.RESULTS:
				if _results_reveal > 1.2:
					_press(201)


# --- placing & playing ---------------------------------------------------------

func _enter_placing() -> void:
	if _menu_root:
		_menu_root.queue_free()
		_menu_root = null
	_mascots.clear()
	_clear_results()
	_reset_arena()
	phase = Phase.PLACING
	_phase_time = 0.0
	gem.begin_placement()
	gem.visible = true


func _reset_arena() -> void:
	for s in sparks:
		if is_instance_valid(s):
			s.queue_free()
	sparks.clear()
	boss = null
	for c in cracks:
		c.close()


func _place_and_start() -> void:
	if phase != Phase.PLACING or _phase_time < 0.3:
		return
	gem.place()
	cue("gem_place", gem.global_position)
	for g in gauntlets:
		g.release_everything()
	score = 0
	kills = 0
	combo = 0
	wave = 0
	survived = false
	phase = Phase.PLAYING
	_phase_time = 0.0
	hud.visible = true
	hud.set_score(0)
	hud.set_combo(1.0)
	_start_wave(0)
	audio.play_music("battle")


func _start_wave(index: int) -> void:
	wave = index
	_wave_spawned = 0
	_wave_break = 0.0
	_next_spawn = _phase_time + (START_DELAY if index == 0 else 0.8)
	hud.set_wave(wave, false)
	var info: Dictionary = SparkMath.WAVES[wave]
	var available := active_cracks()
	for i in range(mini(info.cracks, available.size())):
		var c: Crack = available[i]
		if not c.is_open():
			c.open()
		else:
			c.widen(0.08)
	cue("crack_open", head.global_position + _flat_forward() * 1.5, -6.0)
	if info.boss:
		audio.play_music("boss")


func _process(delta: float) -> void:
	if head == null:
		return
	_phase_time += delta
	match phase:
		Phase.MENU:
			if _menu_root:
				_layout_menu(delta)
		Phase.PLACING:
			_update_gaze_placement(delta)
		Phase.PLAYING:
			_combo_timer = maxf(0.0, _combo_timer - delta)
			if _combo_timer <= 0.0 and combo > 0:
				combo = 0
				hud.set_combo(1.0)
			_waves(delta)
			_drain(delta)
			hud.set_energy(gem.energy, gem.health_color())
			_check_end()
		Phase.RESULTS:
			_update_results(delta)


func _update_gaze_placement(delta: float) -> void:
	var origin := head.global_position
	var dir := -head.global_basis.z
	var floor_plane := Plane(Vector3.UP, global_position.y)
	var hit = floor_plane.intersects_ray(origin, dir)
	var target: Vector3
	if hit != null:
		target = hit
	else:
		target = Vector3(origin.x, global_position.y, origin.z) + _flat_forward() * 2.0
	var feet := Vector3(origin.x, global_position.y, origin.z)
	var away := target - feet
	var d := away.length()
	if d < 1.0 or d > 3.0:
		away = away.normalized() * clampf(d, 1.0, 3.0)
	_gaze_point = _gaze_point.lerp(feet + away, minf(1.0, delta * 6.0))
	gem.global_position = _gaze_point


func _waves(_delta: float) -> void:
	if not auto_spawn:
		return
	var info: Dictionary = SparkMath.WAVES[wave]
	if _wave_spawned < info.count:
		if _phase_time >= _next_spawn and sparks.size() < info.alive:
			_next_spawn = _phase_time + info.gap * _rng.randf_range(0.8, 1.2)
			if info.boss and _wave_spawned == 0:
				_spawn_boss()
			else:
				_spawn(SparkMath.wave_pick(wave, _rng.randf(), mode))
			_wave_spawned += 1
		return
	if not sparks.is_empty():
		return
	# Wave cleared.
	if wave >= SparkMath.WAVES.size() - 1:
		_end(true)
		return
	if _wave_break == 0.0:
		hud.set_wave(wave, true)
		cue("win", gem.global_position, -8.0)
	_wave_break += _delta
	if _wave_break >= SparkMath.WAVE_BREAK:
		_start_wave(wave + 1)


func _spawn(kind: String, at_crack: Crack = null, at_point: Vector3 = Vector3.INF, as_boss: bool = false) -> Spark:
	var available: Array = []
	for c in active_cracks():
		if c.is_open():
			available.append(c)
	if available.is_empty():
		available = active_cracks()
		if available.is_empty():
			return null
	var crack: Crack = at_crack if at_crack else available[_crack_cursor % available.size()]
	_crack_cursor += 1
	if not crack.is_open():
		crack.open()
	crack.widen(0.03 if not as_boss else 0.3)
	var spark := Spark.create(kind)
	if as_boss:
		spark.make_boss()
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


func _spawn_boss() -> void:
	var available := active_cracks()
	var crack: Crack = available[0] if not available.is_empty() else null
	boss = _spawn(SparkMath.mode_kinds(mode)[0], crack, Vector3.INF, true)
	cue("spark_big_pop", head.global_position + _flat_forward() * 2.0, 6.0)


func on_boss_hurt(_spark: Spark) -> void:
	cue("spark_big_pop", _spark.global_position, 3.0)
	for g in gauntlets:
		g.pulse(1.0)
	_add_score(250, _spark.global_position, Neon.AMBER, true)


func _drain(delta: float) -> void:
	var draining := 0
	for s in sparks:
		if is_instance_valid(s) and s.state == Spark.State.DRAIN:
			draining += 2 if s.is_boss else 1
	gem.drain(delta, draining)


func _add_score(points: int, at: Vector3, color: Color, big: bool = false) -> void:
	score += points
	hud.set_score(score)
	hud.popup(at, points, color, big)


func _on_spark_died(spark: Spark) -> void:
	kills += 1
	sparks.erase(spark)
	combo = combo + 1 if _combo_timer > 0.0 else 1
	_combo_timer = SparkMath.COMBO_WINDOW
	var mult := SparkMath.combo_multiplier(combo)
	hud.set_combo(mult)
	var points := int(round(SparkMath.base_points(spark.kind, spark.is_boss) * SparkMath.method_bonus(spark.last_hit) * mult / 10.0)) * 10
	_add_score(points, spark.global_position, spark.color.lerp(Neon.WHITE, 0.4), spark.is_boss or mult >= 2.0)
	var heavy := spark.mass >= 3.0 or spark.is_boss
	cue("spark_big_pop" if heavy else "spark_pop", spark.global_position, minf(combo - 1, 6) * 1.0)
	if audio and audio.voices.size() > 0:
		audio.voices[(audio.cursor + audio.voices.size() - 1) % audio.voices.size()].pitch_scale = 1.0 + minf(combo - 1, 6) * 0.08
	gem.flash(minf(0.3 + combo * 0.1, 0.8))
	for g in gauntlets:
		g.pulse(0.5 + minf(combo, 5) * 0.1)
	if spark == boss:
		boss = null


func _on_bite(spark: Spark) -> void:
	cue("gem_hit", spark.global_position, 2.0)
	for g in gauntlets:
		g.bitten()
	combo = 0
	hud.set_combo(1.0)


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


func _end(won: bool) -> void:
	survived = won
	stars_won = SparkMath.stars_for(won, gem.energy)
	new_best = save.record(mode, score, stars_won)
	gem.set_alive(won)
	if won:
		gem.energy = 1.0
	var leftovers := sparks.duplicate()
	sparks.clear()
	for s in leftovers:
		if is_instance_valid(s):
			s.queue_free()
	for c in cracks:
		c.close()
	for g in gauntlets:
		g.release_everything()
	cue("win" if won else "loss", gem.global_position)
	audio.play_music("menu")
	phase = Phase.RESULTS
	_phase_time = 0.0
	hud.visible = false
	_build_results()


# --- results ------------------------------------------------------------------

func _build_results() -> void:
	_clear_results()
	_results_reveal = 0.0
	_results_root = Node3D.new()
	add_child(_results_root)
	anchor_menu()
	_results_score = UI.digits(str(score), 200, Neon.WHITE)
	_results_root.add_child(_results_score)
	_results_stars.clear()
	for k in range(3):
		var star := UI.filled_star(Color(0.22, 0.24, 0.34), 0.09)
		_results_root.add_child(star)
		_results_stars.append(star)
	_results_crown = UI.icon("crown", Neon.AMBER, 0.12)
	_results_crown.visible = false
	_results_root.add_child(_results_crown)
	_retry_button = UI.Button3D.new("retry", Neon.CYAN, 0.1)
	_results_root.add_child(_retry_button)
	_home_button = UI.Button3D.new("home", Neon.VIOLET, 0.1)
	_results_root.add_child(_home_button)


func _clear_results() -> void:
	if _results_root:
		_results_root.queue_free()
	_results_root = null
	_retry_button = null
	_home_button = null


func _update_results(delta: float) -> void:
	if _results_root == null:
		return
	var before := _results_reveal
	_results_reveal += delta
	var cam := head.global_position
	_results_score.global_position = _menu_anchor * Vector3(0, 0.3, 0)
	_results_score.scale = Vector3.ONE * (0.6 + minf(_results_reveal * 2.0, 1.0) * 0.4)
	for k in range(3):
		var star := _results_stars[k]
		star.global_position = _menu_anchor * Vector3((k - 1) * 0.2, 0.1, 0.0)
		star.look_at(cam, Vector3.UP, true)
		var when := 0.4 + k * 0.35
		if k < stars_won and before < when and _results_reveal >= when:
			(star.material_override as StandardMaterial3D).albedo_color = Neon.AMBER
			cue("gem_place", star.global_position, k * 1.5)
		var pop := clampf((_results_reveal - when) * 5.0, 0.0, 1.0) if k < stars_won else 1.0
		star.scale = Vector3.ONE * (1.0 + (1.0 - pop) * 0.6 * float(k < stars_won and _results_reveal >= when))
	_results_crown.visible = new_best and _results_reveal > 1.4
	_results_crown.global_position = _menu_anchor * Vector3(0, 0.48, 0)
	_results_crown.look_at(cam, Vector3.UP, true)
	if new_best and before < 1.4 and _results_reveal >= 1.4:
		cue("win", _results_crown.global_position)
	_retry_button.global_position = _menu_anchor * Vector3(-0.2, -0.1, 0.1)
	_home_button.global_position = _menu_anchor * Vector3(0.2, -0.1, 0.1)
	_retry_button.visible = _results_reveal > 1.2
	_home_button.visible = _results_reveal > 1.2
	_retry_button.hovered = 1.0 if _hover_index.has(200) else 0.0
	_home_button.hovered = 1.0 if _hover_index.has(201) else 0.0


# --- hands ----------------------------------------------------------------------

func targets() -> Array:
	return sparks.duplicate()


func update_hands(delta: float, triggers: Array, grips: Array) -> void:
	var list := targets()
	for i in range(gauntlets.size()):
		gauntlets[i].update(delta, triggers[i], grips[i], list, phase == Phase.PLAYING)
