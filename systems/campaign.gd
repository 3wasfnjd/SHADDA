class_name Campaign
extends Node3D
## Five stages over the open floor, each with its own challenge, three stars,
## and an upgrade for the plane after each of the first four:
##   1 مدرسة الطيران  — fly through 8 rings in order, then pop the balloons (time)
##   2 القافلة        — stop a convoy crossing the floor; anti-air teams set up (≥3 of 5)
##   3 معركة جوية     — three waves of fighters, the last led by an ace (damage)
##   4 غارة على القاعدة — radar, fuel tanks and guns, defended by soldiers (time)
##   5 العملاق        — the four-engine bomber with escorts: kill three engines (damage)

const STAGES := [
	{"id": "rings", "title": "مدرسة الطيران", "goal": "اعبر الحلقات بالترتيب ثم فجّر البالونات"},
	{"id": "convoy", "title": "القافلة", "goal": "دمّر القافلة قبل ما تعبر — انتبه لفرق الدفاع الجوي"},
	{"id": "dogfight", "title": "معركة جوية", "goal": "أسقط المقاتلات — وآخرهم طيار نخبة أحمر"},
	{"id": "base", "title": "غارة على القاعدة", "goal": "دمّر الرادار والخزانات والمدافع"},
	{"id": "giant", "title": "العملاق", "goal": "أسقط القاذفة: دمّر ثلاث من محركاتها"},
]
const UPGRADES := {
	"engine": ["محرك أقوى", "سرعة أعلى"],
	"guns": ["رشاش ثقيل", "أسرع وأقوى"],
	"rockets": ["صواريخ أكثر", "قفل أسرع"],
	"armor": ["درع", "ضرر أقل"],
	"cluster": ["قنابل عنقودية", "انفجارات إضافية"],
}
const UPGRADE_COLOR := {"engine": Color(1.0, 0.55, 0.15), "guns": Color(0.95, 0.8, 0.2), "rockets": Color(0.85, 0.25, 0.2), "armor": Color(0.3, 0.6, 0.95), "cluster": Color(0.45, 0.6, 0.3)}

var battle = null
var stage: int = 0
var mode: String = "intro"       # intro, play, clear, upgrade, fail, done
var t: float = 0.0
var stars: Array = []
var center: Vector3
var fwd: Vector3
var side: Vector3
var objective: String = ""
var _card: Node3D
var _card_t: float = 0.0
var _rings: Array = []
var _ring_i: int = 0
var _convoy: Array = []
var _convoy_queue: Array = []
var _destroyed: int = 0
var _escaped: int = 0
var _waves: Array = []
var _wave_i: int = 0
var _targets: Array = []
var _bomber: Enemy = null
var _events: Array = []
var _damage0: float = 0.0
var _spawn_t: float = 0.0
var _markers: Array = []
var _upgrade_root: Node3D
var _rng := RandomNumberGenerator.new()


func begin(b) -> void:
	battle = b
	_rng.randomize()
	var hp: Vector3 = battle.head_position()
	var f := -(battle.head as Node3D).global_basis.z
	f.y = 0.0
	fwd = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	side = fwd.cross(Vector3.UP).normalized()
	center = Vector3(hp.x, battle.floor_y, hp.z) + fwd * 2.0
	stars.clear()
	_start_stage(0)


func total_stars() -> int:
	var n := 0
	for s in stars:
		n += int(s)
	return n


# --- flow -------------------------------------------------------------------------------

func _start_stage(i: int) -> void:
	stage = i
	t = 0.0
	mode = "intro"
	_clear_stage()
	_damage0 = battle.plane.damage_taken
	var s: Dictionary = STAGES[i]
	_show_card(str(i + 1), s.title, s.goal, 3.6)
	battle.hud.set_wave(i, false)
	battle.audio.play_music("boss" if i == 4 else "battle")
	battle.cue("siren", battle.head_position() + Vector3(0, 0.5, 0), -6.0)


func _begin_play() -> void:
	mode = "play"
	t = 0.0
	match STAGES[stage].id:
		"rings":
			_setup_rings()
		"convoy":
			_setup_convoy()
		"dogfight":
			_setup_dogfight()
		"base":
			_setup_base()
		"giant":
			_setup_giant()


func _stage_cleared(star_count: int) -> void:
	mode = "clear"
	stars.append(clampi(star_count, 1, 3))
	battle.hud.set_wave(stage, true)
	battle.cue("wave_clear", battle.head_position())
	_show_card(str(stage + 1), "تمت المرحلة!", STAGES[stage].title, 3.0)
	for k in range(3):
		var st := UI.icon("star", Color(1.0, 0.8, 0.15) if k < star_count else Color(0.4, 0.4, 0.42), 0.07, 0.008)
		st.position = Vector3(-0.1 + k * 0.1, -0.22, 0)
		_card.add_child(st)
	var to: Vector3 = battle.head_position() - _card.global_position
	to.y = 0.0
	if to.length() > 0.01:
		_card.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)
	battle.plane.repair(40.0)
	_remove_leftovers()


func _stage_failed(why: String) -> void:
	mode = "fail"
	battle.cue("loss", battle.head_position())
	_show_card(str(stage + 1), "حاول مرة ثانية", why, 3.0)
	_remove_leftovers()


func tick(delta: float) -> void:
	t += delta
	_update_card(delta)
	_update_markers()
	match mode:
		"intro":
			if t > 3.6 and battle.plane.airborne():
				_begin_play()
			elif t > 3.6:
				objective = "أقلع: ارفع البنزين ثم العصا اليمنى للأعلى"
		"play":
			_play(delta)
		"clear":
			if t > 0.0 and _card == null:
				if stage >= STAGES.size() - 1:
					mode = "done"
					battle.finish_campaign()
				else:
					_offer_upgrades()
		"fail":
			if _card == null:
				_start_stage(stage)
		"upgrade":
			objective = "اختر تطويرًا لطيارتك: أشّر واضغط الزناد"
	battle.hud.set_objective(objective)


func _play(delta: float) -> void:
	for ev in _events.duplicate():
		if t >= float(ev[0]):
			_events.erase(ev)
			(ev[1] as Callable).call()
	match STAGES[stage].id:
		"rings":
			_play_rings(delta)
		"convoy":
			_play_convoy(delta)
		"dogfight":
			_play_dogfight(delta)
		"base":
			_play_base(delta)
		"giant":
			_play_giant(delta)


# --- stage 1: rings ----------------------------------------------------------------------------

func _setup_rings() -> void:
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


var _last_plane: Vector3 = Vector3.ZERO
func _play_rings(delta: float) -> void:
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
		(r.mat as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.8, 0.15) if current else Color(0.55, 0.55, 0.6))
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
				battle.cue("pickup", c, 2.0)
				battle._add_score(100, c)
				Fx.sparks(battle, c, n, 10, Color(1.0, 0.85, 0.2))
				if _ring_i == _rings.size():
					for b in range(4):
						var a := TAU * b / 4.0 + 0.4
						battle.spawn_at("balloon", center + side * cos(a) * 1.3 + fwd * sin(a) * 0.9 + Vector3(0, 1.0 + 0.25 * b, 0), fwd)
		objective = "الحلقات %d/8 · %s" % [_ring_i, _clock()]
	else:
		var left := _alive_of(["balloon"])
		objective = "البالونات %d · %s" % [left, _clock()]
		if left == 0 and t > 1.0:
			_stage_cleared(3 if t <= 75.0 else (2 if t <= 115.0 else 1))
	_last_plane = now


# --- stage 2: convoy -------------------------------------------------------------------------------

func _setup_convoy() -> void:
	var start := center - side * 4.2 + fwd * 0.7
	var route := [center - side * 1.6 + fwd * 1.5, center + side * 1.4 + fwd * 0.2, center + side * 4.2 + fwd * 0.9]
	_convoy_queue = ["truck", "tank", "truck", "truck", "tank"]
	_destroyed = 0
	_escaped = 0
	for i in range(_convoy_queue.size()):
		var kind: String = _convoy_queue[i]
		_events.append([1.0 + i * 2.8, func():
			var e: Enemy = battle.spawn_at(kind, start, side)
			e.path = route.duplicate()
			e.path_speed = 0.24 if kind == "truck" else 0.19
			e.target_marked = true
			e.set_meta("convoy", true)
			_convoy.append(e)])
	_events.append([5.0, func(): _sam_team(center + fwd * 2.4 - side * 0.9)])
	_events.append([17.0, func(): _sam_team(center + fwd * 2.6 + side * 1.1)])
	_events.append([9.0, func(): _riflemen(center + fwd * 1.8, 3)])


func _play_convoy(_delta: float) -> void:
	var resolved := _destroyed + _escaped
	objective = "القافلة: دمرت %d · هربت %d من 5" % [_destroyed, _escaped]
	if resolved >= 5:
		if _destroyed >= 3:
			_stage_cleared(3 if _destroyed == 5 else (2 if _destroyed == 4 else 1))
		else:
			_stage_failed("لازم تدمر 3 من 5 على الأقل")


func on_escaped(e: Enemy) -> void:
	if e.has_meta("convoy"):
		_escaped += 1
		battle.cue("loss", e.global_position, -10.0)


func on_killed(e: Enemy) -> void:
	if e.has_meta("convoy"):
		_destroyed += 1
	if e == _bomber:
		_bomber = null


# --- stage 3: dogfight ----------------------------------------------------------------------------

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
				var dmg: float = battle.plane.damage_taken - _damage0
				_stage_cleared(3 if dmg < 15.0 else (2 if dmg < 40.0 else 1))
				return
			for k in range(_waves[_wave_i].size()):
				_fly_in(_waves[_wave_i][k], k)
			if _waves[_wave_i].has("ace"):
				battle.cue("alarm", battle.head_position(), 0.0)
			_spawn_t = 2.0
	objective = "الموجة %d/3 · المقاتلات %d" % [maxi(1, _wave_i + 1), _alive_of(["fighter", "ace"])]


# --- stage 4: base raid -------------------------------------------------------------------------------

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


func _target(kind: String, at: Vector3) -> Enemy:
	var e: Enemy = battle.spawn_at(kind, at, -fwd)
	e.target_marked = true
	return e


func _play_base(_delta: float) -> void:
	var left := 0
	for e in _targets:
		if is_instance_valid(e) and e.alive():
			left += 1
	objective = "أهداف القاعدة %d/6 · %s" % [6 - left, _clock()]
	if left == 0:
		_stage_cleared(3 if t <= 90.0 else (2 if t <= 140.0 else 1))


# --- stage 5: the giant ----------------------------------------------------------------------------

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
			var dmg: float = battle.plane.damage_taken - _damage0
			_stage_cleared(3 if dmg < 25.0 else (2 if dmg < 55.0 else 1))
		objective = "سقط العملاق!"
		return
	var dead := 0
	for eng in _bomber.parts.engines:
		if eng.hp <= 0.0:
			dead += 1
	objective = "محركات القاذفة %d/3" % dead
	_spawn_t -= delta
	if _spawn_t <= 0.0 and _alive_of(["fighter"]) < 2:
		_spawn_t = 7.0
		_fly_in("fighter", _rng.randi() % 3)


# --- helpers -------------------------------------------------------------------------------------------

func _fly_in(kind: String, k: int) -> void:
	var hp: Vector3 = battle.head_position()
	var a := _rng.randf() * TAU + k * 0.8
	var at := Vector3(hp.x + cos(a) * 4.8, battle.floor_y + _rng.randf_range(1.3, 2.1), hp.z + sin(a) * 4.8)
	var e: Enemy = battle.spawn_at(kind, at, (Vector3(hp.x, at.y, hp.z) - at).normalized())
	e.practice = true


## A two-man anti-air team runs in and sets up its launcher.
func _sam_team(at: Vector3) -> Enemy:
	var hp: Vector3 = battle.head_position()
	var e: Enemy = battle.spawn_at("sam", at, (Vector3(hp.x, at.y, hp.z) - at))
	e.reload_mult = 1.0
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


func _clear_stage() -> void:
	for r in _rings:
		if is_instance_valid(r.node):
			(r.node as Node3D).queue_free()
	_rings.clear()
	_convoy.clear()
	_targets.clear()
	_events.clear()
	_bomber = null


func _remove_leftovers() -> void:
	for e in battle.enemies.duplicate():
		if is_instance_valid(e):
			Fx.smoke(battle, e.hit_center(), 0.04)
			battle.enemies.erase(e)
			e.queue_free()
	for s in battle.shots.duplicate():
		if is_instance_valid(s) and s.hostile:
			s.dead = true
	_clear_stage()


# --- cards, markers, upgrades -------------------------------------------------------------------------

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
	var b := UI.number(badge, 220, Color(1.0, 0.82, 0.2))
	b.position = Vector3(0, 0.17, 0)
	_card.add_child(b)
	var tl := UI.number(title, 110, Color(1, 1, 1))
	_card.add_child(tl)
	var gl := UI.number(line, 60, Color(1.0, 0.92, 0.75))
	gl.position = Vector3(0, -0.11, 0)
	gl.width = 900
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
			wanted.append(e)
	while _markers.size() < wanted.size():
		var m := Node3D.new()
		var shape := PackedVector2Array([Vector2(-0.025, 0.0), Vector2(0.025, 0.0), Vector2(0.0, 0.03)])
		Toon.add(m, Toon.slab(shape, 0.006), Toon.mat(Color(1.0, 0.25, 0.15), 0.4, 0.0015), Vector3.ZERO, Vector3(-90, 0, 0))
		add_child(m)
		_markers.append(m)
	var cam := get_viewport().get_camera_3d()
	for i in range(_markers.size()):
		var m: Node3D = _markers[i]
		m.visible = i < wanted.size()
		if m.visible:
			var e: Enemy = wanted[i]
			m.global_position = e.hit_center() + Vector3(0, e.radius + 0.08 + 0.015 * sin(t * 5.0 + i), 0)
			if cam:
				var to := cam.global_position - m.global_position
				to.y = 0.0
				if to.length() > 0.01:
					m.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)


func _offer_upgrades() -> void:
	mode = "upgrade"
	var kinds := UPGRADES.keys()
	kinds.shuffle()
	kinds = kinds.slice(0, 3)
	_upgrade_root = Node3D.new()
	add_child(_upgrade_root)
	var hp: Vector3 = battle.head_position()
	var f := -(battle.head as Node3D).global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else fwd
	_upgrade_root.global_position = hp + f * 1.15 - Vector3(0, 0.1, 0)
	_upgrade_root.global_basis = Basis.looking_at(f, Vector3.UP)
	for i in range(3):
		var k: String = kinds[i]
		var x := (i - 1) * 0.28
		var b: UI.Button3D = battle._add_button(_upgrade_root, k, UPGRADE_COLOR[k], 0.08, Vector3(x, 0.05, 0), func(): _pick(k))
		var l := UI.number(UPGRADES[k][0], 56, Color(1, 1, 1))
		l.position = Vector3(x, -0.07, 0)
		_upgrade_root.add_child(l)
		var l2 := UI.number(UPGRADES[k][1], 40, Color(1.0, 0.9, 0.6))
		l2.position = Vector3(x, -0.12, 0)
		_upgrade_root.add_child(l2)
	var head_l := UI.number("تطوير الطيارة", 90, Color(1.0, 0.82, 0.2))
	head_l.position = Vector3(0, 0.22, 0)
	_upgrade_root.add_child(head_l)


func _pick(kind: String) -> void:
	if mode != "upgrade":
		return
	battle.plane.apply_upgrade(kind)
	battle.cue("pickup", battle.plane.global_position, 3.0)
	for b in battle._buttons.duplicate():
		if is_instance_valid(b) and _upgrade_root.is_ancestor_of(b):
			battle._buttons.erase(b)
	_upgrade_root.queue_free()
	_upgrade_root = null
	_start_stage(stage + 1)


## For tests: take the first offered upgrade.
func pick_first() -> void:
	if _upgrade_root == null:
		return
	for b in battle._buttons:
		if is_instance_valid(b) and _upgrade_root.is_ancestor_of(b):
			b.get_meta("action").call()
			return
