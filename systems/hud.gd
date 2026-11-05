class_name Hud
extends Node3D
## Cartoon wrist board on the left hand (numbers and icons only): score and
## combo, a health bar, five wave flags, rocket and bomb stock, boost bar,
## roll-ready dot and a red warning when hit. Also: "+200" popups in the room,
## and an arrow in front of the eyes when the plane is out of sight.

var world: Node3D
var _score: Label3D
var _combo: Label3D
var _hp_fill: MeshInstance3D
var _hp_mat: ShaderMaterial
var _boost_fill: MeshInstance3D
var _flags: Array = []
var _rockets: Array = []
var _bombs: Array = []
var _roll_dot: MeshInstance3D
var _throttle_fill: MeshInstance3D
var _stall: MeshInstance3D
var _shown: float = 0.0
var _target: int = 0
var _bump: float = 0.0
var _popups: Array = []
var _arrow: Node3D
var _flash: float = 0.0


func _ready() -> void:
	position = Vector3(0.0, 0.05, 0.075)
	rotation_degrees = Vector3(-55, 0, 0)
	Toon.add(self, Toon.block(Vector3(0.14, 0.1, 0.008)), Toon.mat(Color(0.26, 0.3, 0.24), 0.3, 0.0015), Vector3(0, 0.004, -0.006))
	Toon.add(self, Toon.block(Vector3(0.13, 0.09, 0.002)), Toon.mat(Color(0.95, 0.9, 0.78), 0.2, 0.0), Vector3(0, 0.004, -0.001))
	_score = UI.number("0", 80, Color(1, 0.85, 0.2), false)
	_score.pixel_size = 0.00042
	_score.position = Vector3(-0.012, 0.03, 0.002)
	add_child(_score)
	_combo = UI.number("", 56, Color(1.0, 0.45, 0.15), false)
	_combo.pixel_size = 0.00042
	_combo.position = Vector3(0.048, 0.03, 0.002)
	add_child(_combo)
	# Health bar with a plane icon.
	var plane_icon := UI.icon("plane", Models.RED, 0.016, 0.002)
	plane_icon.position = Vector3(-0.056, 0.008, 0.002)
	add_child(plane_icon)
	Toon.add(self, Toon.block(Vector3(0.1, 0.012, 0.002)), Toon.mat(Color(0.2, 0.2, 0.22), 0.2, 0.0008), Vector3(0.006, 0.008, 0.001))
	_hp_mat = Toon.unique(Toon.mat(Color(0.3, 0.85, 0.3), 0.4, 0.0))
	_hp_fill = Toon.add(self, Toon.block(Vector3(0.096, 0.009, 0.002)), _hp_mat, Vector3(0.006, 0.008, 0.002))
	# Wave flags: four small, the last a big boss flag.
	for i in range(WarMath.WAVES.size()):
		var f := Toon.add(self, Toon.block(Vector3(0.012 if i < 4 else 0.018, 0.009 if i < 4 else 0.012, 0.002)), Toon.unique(Toon.mat(Color(0.5, 0.5, 0.5), 0.3, 0.0006)), Vector3(-0.05 + i * 0.019, -0.01, 0.002))
		_flags.append(f)
	# Stores.
	for i in range(WarMath.ROCKETS):
		var r := Toon.add(self, Toon.capsule(0.0028, 0.014, 6), Toon.mat(Models.OLIVE, 0.3, 0.0005), Vector3(-0.054 + i * 0.008, -0.03, 0.003))
		_rockets.append(r)
	for i in range(WarMath.BOMBS):
		var b := Toon.add(self, Toon.ball(0.005, 8, 4), Toon.mat(Models.OLIVE, 0.3, 0.0005), Vector3(0.006 + i * 0.013, -0.03, 0.003))
		_bombs.append(b)
	Toon.add(self, Toon.block(Vector3(0.05, 0.006, 0.002)), Toon.mat(Color(0.2, 0.2, 0.22), 0.2, 0.0006), Vector3(0.031, -0.04, 0.001))
	_boost_fill = Toon.add(self, Toon.block(Vector3(0.048, 0.004, 0.002)), Toon.mat(Color(0.35, 0.75, 1.0), 0.4, 0.0), Vector3(0.031, -0.04, 0.002))
	_roll_dot = Toon.add(self, Toon.ball(0.004, 8, 4), Toon.unique(Toon.mat(Color(1.0, 0.8, 0.2), 0.4, 0.0005)), Vector3(0.056, -0.03, 0.003))
	# Throttle: a vertical bar on the right edge; red lamp when stalling.
	Toon.add(self, Toon.block(Vector3(0.008, 0.07, 0.002)), Toon.mat(Color(0.2, 0.2, 0.22), 0.2, 0.0006), Vector3(0.076, 0.004, 0.001))
	_throttle_fill = Toon.add(self, Toon.block(Vector3(0.006, 0.068, 0.002)), Toon.mat(Color(1.0, 0.6, 0.15), 0.4, 0.0), Vector3(0.076, 0.004, 0.002))
	_stall = Toon.add(self, Toon.ball(0.006, 10, 5), Toon.unique(Toon.mat(Color(0.3, 0.1, 0.1), 0.4, 0.0006)), Vector3(0.076, 0.048, 0.003))
	# Off-screen arrow (world space, in front of the eyes).
	_arrow = UI.icon("play", Color(1.0, 0.82, 0.15), 0.05, 0.008)
	_arrow.top_level = true
	_arrow.visible = false
	add_child(_arrow)
	visible = false


func set_score(v: int) -> void:
	if v > _target:
		_bump = 1.0
	_target = v
	if v == 0:
		_shown = 0.0


func set_combo(m: float) -> void:
	_combo.text = ("×%s" % String.num(m, 2).trim_suffix("0").trim_suffix(".")) if m > 1.01 else ""


func set_wave(wave: int, cleared: bool) -> void:
	for i in range(_flags.size()):
		var c := Color(0.5, 0.5, 0.5)
		if i < wave or (i == wave and cleared):
			c = Color(0.3, 0.8, 0.3)
		elif i == wave:
			c = Color(0.95, 0.25, 0.15)
		((_flags[i] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", c)


func set_plane(p: PlayerPlane) -> void:
	var f := clampf(p.hp / WarMath.PLANE_HP, 0.0, 1.0)
	_hp_fill.scale.x = maxf(0.001, f)
	_hp_fill.position.x = 0.006 - 0.048 * (1.0 - f)
	var c := Color(0.3, 0.85, 0.3) if f > 0.55 else (Color(1.0, 0.75, 0.15) if f > 0.25 else Color(0.95, 0.2, 0.15))
	if p.hit_flash > 0.0:
		_flash = 1.0
	_hp_mat.set_shader_parameter("albedo", c)
	_hp_mat.set_shader_parameter("flash", _flash * 0.7)
	for i in range(_rockets.size()):
		(_rockets[i] as Node3D).visible = i < p.rockets
	for i in range(_bombs.size()):
		(_bombs[i] as Node3D).visible = i < p.bombs
	_boost_fill.scale.x = maxf(0.001, p.boost)
	_boost_fill.position.x = 0.031 - 0.024 * (1.0 - p.boost)
	_throttle_fill.scale.y = maxf(0.001, p.throttle)
	_throttle_fill.position.y = 0.004 - 0.034 * (1.0 - p.throttle)
	var blink := p.stalling and fmod(Time.get_ticks_msec() / 1000.0, 0.3) < 0.15
	((_stall.material_override) as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.15, 0.1) if blink else Color(0.3, 0.1, 0.1))
	((_roll_dot.material_override) as ShaderMaterial).set_shader_parameter("albedo", Color(1.0, 0.8, 0.2) if p._roll_cd <= 0.0 else Color(0.4, 0.4, 0.4))


## Shows an arrow toward the plane when it's outside the view.
func point_to(target: Vector3, cam: Node3D, show: bool) -> void:
	if not show or cam == null:
		_arrow.visible = false
		return
	var fwd := -cam.global_basis.z
	var to := (target - cam.global_position).normalized()
	if fwd.dot(to) > 0.75:
		_arrow.visible = false
		return
	_arrow.visible = true
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var dir2 := Vector2(to.dot(right), to.dot(up))
	if dir2.length() < 0.01:
		dir2 = Vector2(1, 0)
	dir2 = dir2.normalized()
	_arrow.global_position = cam.global_position + fwd * 0.6 + (right * dir2.x + up * dir2.y) * 0.18
	_arrow.global_basis = Basis.looking_at(-fwd, up) * Basis(Vector3.BACK, atan2(dir2.y, dir2.x))


func popup(at: Vector3, points: int, big: bool = false) -> void:
	if world == null:
		return
	var l := UI.number("+%d" % points, 150 if big else 90, Color(1, 0.85, 0.2))
	world.add_child(l)
	l.global_position = at + Vector3(0, 0.08, 0)
	_popups.append({"label": l, "life": 0.0})


func clear_popups() -> void:
	for p in _popups:
		if is_instance_valid(p.label):
			p.label.queue_free()
	_popups.clear()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_bump = maxf(0.0, _bump - delta * 3.0)
	_shown = lerpf(_shown, float(_target), minf(1.0, delta * 10.0))
	if absf(_shown - _target) < 1.0:
		_shown = _target
	_score.text = str(int(round(_shown)))
	_score.scale = Vector3.ONE * (1.0 + _bump * 0.35)
	for i in range(_popups.size() - 1, -1, -1):
		var p: Dictionary = _popups[i]
		p.life += delta
		var l: Label3D = p.label
		l.global_position += Vector3(0, delta * 0.3, 0)
		l.scale = Vector3.ONE * (1.0 + minf(p.life * 8.0, 1.0) * 0.25)
		l.modulate.a = clampf(1.6 - p.life * 1.6, 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a
		if p.life > 1.0:
			l.queue_free()
			_popups.remove_at(i)
