class_name Campaign
extends Node3D
## Runs one mission of the campaign over the open floor (see Missions.LIST):
## an intro card → take off → the mission's challenge → the result goes back
## to the battle (stars, or the reason it failed).

var battle = null
var index: int = 0
var id: String = ""
var mode: String = "intro"       # intro, play, won, failed
var t: float = 0.0               # mission clock (starts when you take off)
var center: Vector3
var fwd: Vector3
var side: Vector3
var objective: String = ""
var stars_won: int = 0
var _card: Node3D
var _card_t: float = 0.0
var _end_t: float = 0.0
var _rings: Array = []
var _ring_i: int = 0
var _convoy: Array = []
var _destroyed: int = 0
var _escaped: int = 0
var _waves: Array = []
var _wave_i: int = 0
var _targets: Array = []
var _bomber: Enemy = null
var _cargo: Enemy = null
var _hangars: Array = []
var _events: Array = []
var _damage0: float = 0.0
var _spawn_t: float = 0.0
var _markers: Array = []
var _rng := RandomNumberGenerator.new()
var _intro_t: float = 0.0


func begin(b, i: int) -> void:
	battle = b
	index = i
	id = Missions.get_m(i).id
	_rng.randomize()
	var hp: Vector3 = battle.head_position()
	var f := -(battle.head as Node3D).global_basis.z
	f.y = 0.0
	fwd = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	side = fwd.cross(Vector3.UP).normalized()
	center = Vector3(hp.x, battle.floor_y, hp.z) + fwd * 2.0
	mode = "intro"
	t = 0.0
	_intro_t = 0.0
	_damage0 = battle.plane.damage_taken
	var m := Missions.get_m(i)
	_show_card(str(i + 1), Missions.text(m, "title"), Lang.t("take_off_hint"), 3.4)
	battle.hud.set_wave(i, false)
	battle.audio.play_music("boss" if id == "giant" else "battle")
	battle.cue("siren", battle.head_position() + Vector3(0, 0.5, 0), -8.0)
	battle.set_dusk(bool(m.get("dusk", false)))
	# Ground missions set their stage before you take off, so you can look it over.
	match id:
		"convoy", "base", "airfield":
			_setup()


func hull_lost() -> float:
	return battle.plane.damage_taken - _damage0


# --- flow -------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_update_card(delta)
	_update_markers()
	match mode:
		"intro":
			_intro_t += delta
			objective = Lang.t("take_off_hint")
			if battle.plane.airborne() and _intro_t > 1.0:
				mode = "play"
				t = 0.0
				if not id in ["convoy", "base", "airfield"]:
					_setup()
				battle.callout(Lang.t("go"), Color(1.0, 0.85, 0.3))
		"play":
			t += delta
			for ev in _events.duplicate():
				if t >= float(ev[0]):
					_events.erase(ev)
					(ev[1] as Callable).call()
			call("_play_" + id, delta)
		"won", "failed":
			_end_t -= delta
			if _end_t <= 0.0:
				battle.mission_over(mode == "won", stars_won, objective)
				mode = "over"
	battle.hud.set_objective(objective)


func _setup() -> void:
	call("_setup_" + id)


func _win(s2: bool, s3: bool) -> void:
	if mode != "play":
		return
	mode = "won"
	stars_won = 1 + (1 if s2 else 0) + (1 if s3 else 0)
	_end_t = 2.2
	battle.hud.set_wave(index, true)
	battle.cue("wave_clear", battle.head_position(), 2.0)
	battle.callout(Lang.t("mission_complete"), Color(1.0, 0.85, 0.3), 2.2)
	for e in battle.enemies.duplicate():
		if is_instance_valid(e) and e.alive() and not e.kind in ["cargo", "hangar"]:
			battle._explode(e)


func _fail(why: String) -> void:
	if mode != "play" and mode != "intro":
		return
	mode = "failed"
	objective = why
	_end_t = 2.4
	battle.cue("loss", battle.head_position())
	battle.callout(why, Color(1.0, 0.4, 0.3), 2.4)


# --- 1 flight school: rings, then balloons ------------------------------------------------

func _setup_training() -> void:
	for k in range(8):
		var a := TAU * k / 8.0
		var p := center + side * sin(a) * 2.3 + fwd * sin(2.0 * a) * 1.2
		p.y = battle.floor_y + 1.05 + 0.45 * sin(a * 2.0 + 1.0)
		var tangent := side * cos(a) * 2.3 + fwd * cos(2.0 * a) * 2.4
		var r := Models.ring()
		add_child(r.root)
		r.root.global_position = p
		r.root.global_basis = Basis.looking_at(tangent.normalized(), Vector3.UP)
		_rings.append({"node": r.root, "spin": r.spin, "mat": r.mat, "pos": p, "n": tangent.normalized(), "passed": false})
	_ring_i = 0
	_last_plane = battle.plane.global_position
	_events.append([1.5, func(): battle.callout(Lang.t("tip_rings"), Color(1, 0.9, 0.5), 3.5)])


var _last_plane: Vector3 = Vector3.ZERO
func _play_training(delta: float) -> void:
	var now: Vector3 = battle.plane.global_position
	for i in range(_rings.size()):
		var r: Dictionary = _rings[i]
		var node: Node3D = r.node
		if r.passed:
			node.scale = node.scale.move_toward(Vector3.ZERO, delta * 4.0)
			node.visible = node.scale.x > 0.02
			continue
		var current := i == _ring_i
		(r.spin as Node3D).rotate_object_local(Vector3.FORWARD, delta * (2.0 if current else 0.4))
		var target_s := 1.0 + (0.08 * sin(t * 6.0) if current else -0.25)
		node.scale = node.scale.lerp(Vector3.ONE * target_s, minf(1.0, delta * 6.0))
		var next := i == _ring_i + 1
		(r.mat as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.8, 0.15) if current else (Color(0.75, 0.75, 0.8) if next else Color(0.5, 0.5, 0.55)))
	if _ring_i < _rings.size():
		var r2: Dictionary = _rings[_ring_i]
		var n: Vector3 = r2.n
		var c: Vector3 = r2.pos
		var d0 := (_last_plane - c).dot(n)
		var d1 := (now - c).dot(n)
		if signf(d0) != signf(d1) and absf(d0 - d1) > 1e-5:
			var k := d0 / (d0 - d1)
			var hit := _last_plane.lerp(now, k)
			if hit.distance_to(c) < 0.29:
				r2.passed = true
				_ring_i += 1
				battle.cue("ring", c, 2.0)
				battle._add_score(100 + 20 * _ring_i, c)
				Fx.sparks(battle, c, n, 12, Color(1.0, 0.85, 0.2))
				if _ring_i == _rings.size():
					battle.callout(Lang.t("tip_balloons"), Color(1, 0.9, 0.5), 3.5)
					for b in range(4):
						var a := TAU * b / 4.0 + 0.4
						battle.spawn_at("balloon", center + side * cos(a) * 1.3 + fwd * sin(a) * 0.9 + Vector3(0, 1.0 + 0.25 * b, 0), fwd)
		objective = "%s %d/8 · %s" % [Lang.t("rings"), _ring_i, _clock()]
	else:
		var left := _alive_of(["balloon"])
		objective = "%s %d · %s" % [Lang.t("balloons"), left, _clock()]
		if left == 0 and t > 1.0:
			_win(t <= 100.0, t <= 70.0)
	_last_plane = now


# --- 2 dawn patrol: three scouts behind a balloon barrage -------------------------------------

func _setup_patrol() -> void:
	for k in range(5):
		var a := TAU * k / 5.0 + 0.3
		battle.spawn_at("balloon", center + side * cos(a) * 1.9 + fwd * sin(a) * 1.2 + Vector3(0, 0.9 + 0.3 * (k % 3), 0), fwd)
	_fly_in("fighter", 0)
	_fly_in("fighter", 1)
	_waves = ["fighter"]
	_events.append([3.0, func(): battle.callout(Lang.t("tip_rockets"), Color(1, 0.9, 0.5), 3.5)])


func _play_patrol(_delta: float) -> void:
	var planes := _alive_of(["fighter"]) + _falling_of(["fighter"])
	if planes == 0 and not _waves.is_empty():
		_fly_in(_waves.pop_front(), 2)
	elif planes == 0:
		_win(hull_lost() < 40.0, t <= 90.0)
	objective = "%s %d · %s" % [Lang.t("fighters"), _alive_of(["fighter"]) + _waves.size(), _clock()]


# --- 3 convoy -------------------------------------------------------------------------------

func _setup_convoy() -> void:
	var start := center - side * 4.2 + fwd * 0.7
	var route := [center - side * 1.6 + fwd * 1.5, center + side * 1.4 + fwd * 0.2, center + side * 4.2 + fwd * 0.9]
	var queue := ["truck", "tank", "truck", "truck", "tank"]
	_destroyed = 0
	_escaped = 0
	for i in range(queue.size()):
		var kind: String = queue[i]
		_events.append([1.0 + i * 3.0, func():
			var e: Enemy = battle.spawn_at(kind, start, side)
			e.path = route.duplicate()
			e.path_speed = 0.23 if kind == "truck" else 0.18
			e.target_marked = true
			e.set_meta("convoy", true)
			_convoy.append(e)])
	_events.append([2.0, func(): battle.callout(Lang.t("tip_bombs"), Color(1, 0.9, 0.5), 3.5)])
	_events.append([6.0, func():
		_sam_team(center + fwd * 2.4 - side * 0.9)
		battle.callout(Lang.t("sam_warn"), Color(1.0, 0.45, 0.3), 2.0)])
	_events.append([19.0, func(): _sam_team(center + fwd * 2.6 + side * 1.1)])
	_events.append([10.0, func(): _riflemen(center + fwd * 1.8, 3)])


func _play_convoy(_delta: float) -> void:
	objective = Lang.t("convoy_line") % [_destroyed, _escaped]
	if _destroyed + _escaped >= 5:
		if _destroyed >= 3:
			_win(_destroyed >= 4, _destroyed == 5)
		else:
			_fail(Lang.t("convoy_fail"))


func on_escaped(e: Enemy) -> void:
	if e.has_meta("convoy"):
		_escaped += 1
		battle.cue("loss", e.global_position, -10.0)


func on_killed(e: Enemy) -> void:
	if e.has_meta("convoy"):
		_destroyed += 1
	if e == _bomber:
		_bomber = null


# --- 4 escort -----------------------------------------------------------------------------

const ESCORT_TIME := 65.0
func _setup_escort() -> void:
	var start := center - side * 4.5 + Vector3(0, 1.5, 0)
	_cargo = battle.spawn_friend("cargo", start, side)
	var route: Array = []
	for k in range(18):
		var a := PI + TAU * 1.5 * k / 17.0
		route.append(center + side * cos(a) * 2.4 + fwd * sin(a) * 1.2 + Vector3(0, 1.35 + 0.25 * sin(a * 2.0), 0))
	route.append(center + side * 5.0 + Vector3(0, 1.6, 0))
	_cargo.path = route
	_cargo.path_speed = 0.0
	battle.callout(Lang.t("escort_in"), Color(1.0, 0.6, 0.3), 2.5)
	var plan := [[3.0, 2], [20.0, 2], [38.0, 3], [56.0, 2]]
	for w in plan:
		var n: int = w[1]
		_events.append([w[0], func():
			for k in range(n):
				var e := _fly_in("fighter", k)
				e.practice = false
				e.prey = _cargo
			battle.cue("alarm", battle.head_position(), -4.0)])


func _play_escort(_delta: float) -> void:
	if _cargo == null or not is_instance_valid(_cargo) or not _cargo.alive():
		_fail(Lang.t("escort_fail"))
		return
	var hp := _cargo.hp / _cargo.max_hp
	var prog := clampf(t / ESCORT_TIME, 0.0, 1.0)
	_cargo.path_speed = prog
	objective = Lang.t("escort_line") % [int(round(hp * 100.0)), int(round((1.0 - prog) * 100.0))]
	if prog >= 1.0 and _alive_of(["fighter"]) == 0:
		_win(hp > 0.5, hp > 0.85)
	elif prog >= 1.0 and t > ESCORT_TIME + 12.0:
		_win(hp > 0.5, hp > 0.85)


# --- 5 dogfight ---------------------------------------------------------------------------

func _setup_dogfight() -> void:
	_waves = [["fighter", "fighter"], ["fighter", "fighter", "fighter"], ["ace", "fighter", "fighter"]]
	_wave_i = -1
	for k in range(3):
		var a := TAU * k / 3.0
		battle.spawn_at("balloon", center + side * cos(a) * 2.2 + fwd * sin(a) * 1.4 + Vector3(0, 1.4, 0), fwd)
	_spawn_t = 0.5


func _play_dogfight(delta: float) -> void:
	var planes := _alive_of(["fighter", "ace"]) + _falling_of(["fighter", "ace"])
	if planes == 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_wave_i += 1
			if _wave_i >= _waves.size():
				_win(hull_lost() < 40.0, hull_lost() < 15.0)
				return
			for k in range(_waves[_wave_i].size()):
				_fly_in(_waves[_wave_i][k], k)
			if _waves[_wave_i].has("ace"):
				battle.cue("alarm", battle.head_position(), 0.0)
				battle.callout(Lang.t("ace_in"), Color(1.0, 0.35, 0.25), 2.5)
			_spawn_t = 2.0
	objective = "%s %d/3 · %s %d" % [Lang.t("wave"), maxi(1, _wave_i + 1), Lang.t("fighters"), _alive_of(["fighter", "ace"])]


# --- 6 base raid ------------------------------------------------------------------------------

func _setup_base() -> void:
	var b := center + fwd * 1.3
	_targets.clear()
	_targets.append(_target("radar", b + fwd * 0.6))
	_targets.append(_target("fuel", b - side * 0.7))
	_targets.append(_target("fuel", b - side * 0.7 + fwd * 0.3))
	_targets.append(_target("fuel", b - side * 0.35 + fwd * 0.55))
	_targets.append(_target("aa", b + side * 0.6 + fwd * 0.45))
	_targets.append(_target("aa", b + side * 0.2 - fwd * 0.45))
	_sam_team(b + side * 1.2)
	_sam_team(b - side * 1.3 - fwd * 0.4)
	_riflemen(b, 4)
	var tank: Enemy = battle.spawn_at("tank", b + side * 0.9 - fwd * 0.2, -fwd)
	tank.set_meta("guard", true)
	_events.append([22.0, func(): _riflemen(b, 2, true)])
	_events.append([40.0, func():
		if _alive_of(["sam"]) < 2:
			_sam_team(b + side * 0.1 + fwd * 1.0)])
	_events.append([60.0, func(): _riflemen(b, 3, true)])
	_events.append([45.0, func(): _fly_in("fighter", 0)])


func _target(kind: String, at: Vector3) -> Enemy:
	var e: Enemy = battle.spawn_at(kind, at, -fwd)
	e.target_marked = true
	return e


func _play_base(_delta: float) -> void:
	var left := 0
	for e in _targets:
		if is_instance_valid(e) and e.alive():
			left += 1
	objective = "%s · %s" % [Lang.t("base_line") % (6 - left), _clock()]
	if left == 0:
		_win(t <= 120.0, t <= 80.0)


# --- 7 hold the airfield -------------------------------------------------------------------------

func _setup_airfield() -> void:
	_hangars.clear()
	for k in range(3):
		var at := center + side * (k - 1) * 0.75 + fwd * (0.15 if k == 1 else 0.0)
		var h: Enemy = battle.spawn_friend("hangar", at, -fwd)
		_hangars.append(h)
	_waves = [["diver", "diver"], ["diver", "diver", "diver", "fighter"], ["diver", "diver", "diver", "ace"]]
	_wave_i = -1
	_spawn_t = 3.0


func _play_airfield(delta: float) -> void:
	var standing := 0
	for h in _hangars:
		if is_instance_valid(h) and h.alive():
			standing += 1
	if standing == 0:
		_fail(Lang.t("airfield_fail"))
		return
	var planes := _alive_of(["diver", "fighter", "ace"]) + _falling_of(["diver", "fighter", "ace"])
	if planes == 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_wave_i += 1
			if _wave_i >= _waves.size():
				_win(standing >= 2, standing == 3)
				return
			for k in range(_waves[_wave_i].size()):
				var e := _fly_in(_waves[_wave_i][k], k)
				if e.kind == "diver":
					e.prey = _hangars[_rng.randi() % _hangars.size()]
			battle.cue("siren", battle.head_position() + Vector3(0, 0.5, 0), -6.0)
			_spawn_t = 2.5
	objective = Lang.t("hangars_line") % [standing, maxi(1, _wave_i + 1)]


func live_hangar() -> Enemy:
	var alive: Array = _hangars.filter(func(h): return is_instance_valid(h) and h.alive())
	return alive[_rng.randi() % alive.size()] if not alive.is_empty() else null


# --- 8 the giant at dusk ------------------------------------------------------------------------

func _setup_giant() -> void:
	var from := center + fwd * 4.5 + Vector3(0, 1.9, 0)
	_bomber = battle.spawn_at("bomber", from, -fwd)
	_bomber.target_marked = true
	_sam_team(center - side * 1.4 + fwd * 0.8)
	_sam_team(center + side * 1.5 + fwd * 1.6)
	_spawn_t = 4.0


func _play_giant(delta: float) -> void:
	if _bomber == null or not is_instance_valid(_bomber) or not _bomber.alive():
		if _falling_of(["bomber"]) == 0 and t > 1.0:
			_win(hull_lost() < 40.0, t <= 120.0)
		objective = Lang.t("giant_down")
		return
	var dead := 0
	for eng in _bomber.parts.engines:
		if eng.hp <= 0.0:
			dead += 1
	objective = "%s · %s" % [Lang.t("engines_line") % dead, _clock()]
	_spawn_t -= delta
	if _spawn_t <= 0.0 and _alive_of(["fighter"]) < 2:
		_spawn_t = 8.0
		_fly_in("fighter", _rng.randi() % 3)


# --- helpers -------------------------------------------------------------------------------------------

func _fly_in(kind: String, k: int) -> Enemy:
	var hp: Vector3 = battle.head_position()
	var a := _rng.randf() * TAU + k * 0.8
	var at := Vector3(hp.x + cos(a) * 4.8, battle.floor_y + _rng.randf_range(1.3, 2.1), hp.z + sin(a) * 4.8)
	var e: Enemy = battle.spawn_at(kind, at, (Vector3(hp.x, at.y, hp.z) - at).normalized())
	e.practice = kind in ["fighter", "ace"]
	return e


## A two-man anti-air team runs in and sets up its launcher.
func _sam_team(at: Vector3) -> Enemy:
	var hp: Vector3 = battle.head_position()
	var e: Enemy = battle.spawn_at("sam", at, (Vector3(hp.x, at.y, hp.z) - at))
	e.reload_mult = 0.75 if str(Profile.get_s("difficulty")) == "hard" else 1.0
	Fx.smoke(battle, e.global_position + Vector3(0, 0.02, 0), 0.05)
	return e


func _riflemen(around: Vector3, count: int, run_in: bool = false) -> void:
	for k in range(count):
		var a := _rng.randf() * TAU
		var spot := around + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.4, 0.9)
		var from := spot + (spot - around).normalized() * (2.0 if run_in else 0.0)
		var s: Enemy = battle.spawn_at("soldier", from, -fwd)
		if run_in:
			s.run_to = Vector3(spot.x, battle.surface_below(spot + Vector3(0, 0.3, 0)), spot.z)


func _alive_of(kinds: Array) -> int:
	var n := 0
	for e in battle.enemies:
		if e.alive() and kinds.has(e.kind):
			n += 1
	return n


func _falling_of(kinds: Array) -> int:
	var n := 0
	for e in battle.enemies:
		if e.state == Enemy.State.FALLING and kinds.has(e.kind):
			n += 1
	return n


func _clock() -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func clear() -> void:
	for r in _rings:
		if is_instance_valid(r.node):
			(r.node as Node3D).queue_free()
	_rings.clear()
	_convoy.clear()
	_targets.clear()
	_events.clear()
	_bomber = null
	_cargo = null
	_hangars.clear()


# --- cards and markers ---------------------------------------------------------------------------

func _show_card(badge: String, title: String, line: String, seconds: float) -> void:
	if _card and is_instance_valid(_card):
		_card.queue_free()
	_card = Node3D.new()
	add_child(_card)
	var hp: Vector3 = battle.head_position()
	var f := -(battle.head as Node3D).global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else fwd
	_card.global_position = hp + f * 1.3 + Vector3(0, 0.12, 0)
	_card.global_basis = Basis.looking_at(f, Vector3.UP)
	Panel3D.shape(_card, Panel3D.rrect(0.62, 0.3, 0.03), Vector3(0, 0.03, -0.01), Color(0.075, 0.1, 0.15, 0.92), 0.002)
	Panel3D.shape(_card, Panel3D.rrect(0.6, 0.012, 0.004), Vector3(0, 0.105, -0.005), Panel3D.HEADER, 0.002)
	var b := UI.number("%s %s" % [Lang.t("mission"), badge], 70, Panel3D.GOLD, false)
	b.font = UI.font("title")
	b.pixel_size = 0.00055
	b.position = Vector3(0, 0.14, 0)
	_card.add_child(b)
	var tl := UI.number(title, 150, Color(1, 1, 1), false)
	tl.font = UI.font("title")
	tl.pixel_size = 0.00055
	tl.position = Vector3(0, 0.04, 0)
	_card.add_child(tl)
	var gl := UI.number(line, 60, Color(1.0, 0.92, 0.75), false)
	gl.pixel_size = 0.00055
	gl.position = Vector3(0, -0.06, 0)
	gl.width = 1000
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(gl)
	_card.scale = Vector3.ONE * 0.01
	_card_t = seconds


func _update_card(delta: float) -> void:
	if _card == null:
		return
	_card_t -= delta
	var s := minf(1.0, _card.scale.x + delta * 6.0) if _card_t > 0.3 else maxf(0.01, _card_t / 0.3)
	_card.scale = Vector3.ONE * s
	if _card_t <= 0.0:
		_card.queue_free()
		_card = null


func _update_markers() -> void:
	var wanted: Array = []
	for e in battle.enemies:
		if e.target_marked and e.alive():
			wanted.append([e, false])
	for e in battle.friends:
		if e.alive():
			wanted.append([e, true])
	while _markers.size() < wanted.size():
		var m := Node3D.new()
		var shape := PackedVector2Array([Vector2(-0.025, 0.0), Vector2(0.025, 0.0), Vector2(0.0, 0.03)])
		var mi := Toon.add(m, Toon.slab(shape, 0.006), Toon.unique(Toon.mat(Color(1.0, 0.25, 0.15), 0.4, 0.0015)), Vector3.ZERO, Vector3(-90, 0, 0))
		m.set_meta("mi", mi)
		add_child(m)
		_markers.append(m)
	var cam := get_viewport().get_camera_3d()
	for i in range(_markers.size()):
		var m: Node3D = _markers[i]
		m.visible = i < wanted.size()
		if m.visible:
			var e: Enemy = wanted[i][0]
			var friend: bool = wanted[i][1]
			((m.get_meta("mi") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", Color(0.3, 0.9, 0.45) if friend else Color(1.0, 0.25, 0.15))
			m.global_position = e.hit_center() + Vector3(0, e.radius + 0.08 + 0.015 * sin(t * 5.0 + i), 0)
			m.scale = Vector3.ONE * (0.7 if friend else 1.0)
			if cam:
				var to := cam.global_position - m.global_position
				to.y = 0.0
				if to.length() > 0.01:
					m.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)
