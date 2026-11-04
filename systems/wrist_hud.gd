class_name WristHud
extends Node3D
## Watch-style panel on the left wrist — no words, only numbers and shapes:
## score and combo, armour arc, five wave pips (crown = boss), stores
## (missiles · bombs · flares), laser heat bar and a red missile warning.
## Also owns the floating "+100" popups in the world.

var world: Node3D
var score_label: Label3D
var combo_label: Label3D
var _arc_mesh := ImmediateMesh.new()
var _arc_mat: ShaderMaterial
var _pips: Array[MeshInstance3D] = []
var _crown: Node3D
var _missile_pips: Array[MeshInstance3D] = []
var _bomb_pips: Array[MeshInstance3D] = []
var _flare_pips: Array[MeshInstance3D] = []
var _heat_fill: MeshInstance3D
var _warn: Node3D
var _warn_on: bool = false
var _time: float = 0.0
var _score_shown: float = 0.0
var _score_target: int = 0
var _bump: float = 0.0
var _popups: Array = []


func _ready() -> void:
	position = Vector3(0.0, 0.055, 0.07)
	rotation_degrees = Vector3(-55, 0, 0)
	var back := MeshInstance3D.new()
	back.mesh = Models.box(Vector3(0.13, 0.095, 0.004))
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.02, 0.03, 0.05, 0.72)
	back.material_override = bm
	back.position = Vector3(0, 0.004, -0.004)
	add_child(back)
	score_label = UI.digits("0", 90, Neon.WHITE)
	score_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	score_label.pixel_size = 0.0004
	score_label.position = Vector3(0, 0.024, 0)
	add_child(score_label)
	combo_label = UI.digits("", 60, Neon.AMBER)
	combo_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	combo_label.pixel_size = 0.0004
	combo_label.position = Vector3(0.05, 0.038, 0)
	add_child(combo_label)
	# Armour arc behind the score.
	var arc_back := ImmediateMesh.new()
	_build_arc(arc_back, 1.0, 0.0016)
	var ab := MeshInstance3D.new()
	ab.mesh = arc_back
	ab.material_override = Neon.glow_material(Color(0.1, 0.25, 0.15), true)
	add_child(ab)
	_arc_mat = Neon.glow_material(Color(0.3, 1.0, 0.5), true)
	var arc := MeshInstance3D.new()
	arc.mesh = _arc_mesh
	arc.material_override = _arc_mat
	add_child(arc)
	# Wave pips.
	for i in range(CombatMath.WAVES.size() - 1):
		var pip := Neon.make_orb(Neon.CYAN_DIM, 0.005, 8, 4)
		pip.position = Vector3(-0.032 + i * 0.016, -0.004, 0)
		add_child(pip)
		_pips.append(pip)
	_crown = UI.icon("crown", Neon.AMBER_DIM, 0.014)
	_crown.position = Vector3(0.034, -0.004, 0)
	add_child(_crown)
	# Stores row: missiles (white bars), bombs (olive dots), flares (orange dots).
	for i in range(CombatMath.MISSILE_STOCK):
		var m := MeshInstance3D.new()
		m.mesh = Models.box(Vector3(0.003, 0.011, 0.002))
		m.material_override = Neon.emitter_material(Color(0.92, 0.94, 0.96))
		m.position = Vector3(-0.056 + i * 0.0055, -0.024, 0)
		add_child(m)
		_missile_pips.append(m)
	for i in range(CombatMath.BOMB_STOCK):
		var b := Neon.make_orb(Color(0.65, 0.75, 0.35), 0.0028, 6, 3)
		b.position = Vector3(-0.004 + i * 0.0075, -0.024, 0)
		add_child(b)
		_bomb_pips.append(b)
	for i in range(CombatMath.FLARE_STOCK):
		var f := Neon.make_orb(Color(1.0, 0.6, 0.2), 0.0024, 6, 3)
		f.position = Vector3(-0.004 + i * 0.0075, -0.034, 0)
		add_child(f)
		_flare_pips.append(f)
	# Heat bar.
	var heat_back := MeshInstance3D.new()
	heat_back.mesh = Models.box(Vector3(0.05, 0.004, 0.001))
	heat_back.material_override = Neon.emitter_material(Color(0.05, 0.15, 0.2))
	heat_back.position = Vector3(-0.034, -0.035, 0)
	add_child(heat_back)
	_heat_fill = MeshInstance3D.new()
	_heat_fill.mesh = Models.box(Vector3(0.05, 0.0045, 0.0015))
	_heat_fill.material_override = Neon.emitter_material(Neon.CYAN)
	_heat_fill.position = Vector3(-0.034, -0.035, 0.001)
	add_child(_heat_fill)
	# Missile warning: a red triangle over the panel.
	_warn = UI.icon("play", Neon.RED, 0.03)
	_warn.rotation_degrees.z = 90
	_warn.position = Vector3(-0.05, 0.035, 0.002)
	_warn.visible = false
	add_child(_warn)
	visible = false


func _build_arc(mesh: ImmediateMesh, fraction: float, r: float) -> void:
	var pts := PackedVector3Array()
	var n := maxi(2, int(26 * fraction) + 1)
	for i in range(n):
		var a := deg_to_rad(205.0 - 230.0 * fraction * float(i) / float(n - 1))
		pts.append(Vector3(cos(a) * 0.05, sin(a) * 0.05 + 0.006, -0.002))
	Neon.build_tube(mesh, pts, func(_t): return r)


func set_score(value: int) -> void:
	if value > _score_target:
		_bump = 1.0
	_score_target = value
	if value == 0:
		_score_shown = 0.0


func set_combo(multiplier: float) -> void:
	combo_label.text = ("×%s" % String.num(multiplier, 2).trim_suffix("0").trim_suffix(".")) if multiplier > 1.01 else ""


func set_wave(wave: int, in_break: bool) -> void:
	for i in range(_pips.size()):
		var done := i < wave or (i == wave and in_break)
		var current := i == wave and not in_break
		(_pips[i].material_override as StandardMaterial3D).albedo_color = Neon.CYAN if done else (Neon.WHITE if current else Neon.CYAN_DIM)
		_pips[i].scale = Vector3.ONE * (1.5 if current else 1.0)
	UI.set_icon_color(_crown, Neon.AMBER if wave >= _pips.size() else Neon.AMBER_DIM)


func set_jet(jet: PlayerJet) -> void:
	var f := clampf(jet.armor / CombatMath.JET_ARMOR, 0.0, 1.0)
	_arc_mesh.clear_surfaces()
	if f > 0.0:
		_build_arc(_arc_mesh, maxf(f, 0.02), 0.0026)
	var col := Color(0.3, 1.0, 0.5) if f > 0.6 else (Neon.AMBER if f > 0.3 else Neon.RED)
	if jet.hit_flash > 0.0:
		col = col.lerp(Neon.WHITE, jet.hit_flash)
	_arc_mat.set_shader_parameter("tint", col)
	for i in range(_missile_pips.size()):
		_missile_pips[i].visible = i < jet.missiles
	for i in range(_bomb_pips.size()):
		_bomb_pips[i].visible = i < jet.bombs
	for i in range(_flare_pips.size()):
		_flare_pips[i].visible = i < jet.flares
	_heat_fill.scale.x = maxf(0.001, jet.heat)
	_heat_fill.position.x = -0.034 - 0.025 * (1.0 - jet.heat)
	var hm := _heat_fill.material_override as StandardMaterial3D
	hm.albedo_color = Neon.RED if jet.overheated else Neon.CYAN.lerp(Neon.AMBER, jet.heat)


func set_warning(on: bool) -> void:
	_warn_on = on


func popup(at: Vector3, points: int, color: Color, big: bool = false) -> void:
	if world == null:
		return
	var l := UI.digits("+%d" % points, 140 if big else 80, color)
	world.add_child(l)
	l.global_position = at + Vector3(0, 0.08, 0)
	_popups.append({"label": l, "life": 0.0})


func clear_popups() -> void:
	for p in _popups:
		if is_instance_valid(p.label):
			p.label.queue_free()
	_popups.clear()


func _process(delta: float) -> void:
	_time += delta
	_warn.visible = _warn_on and fmod(_time, 0.3) < 0.18
	_bump = maxf(0.0, _bump - delta * 3.0)
	_score_shown = lerpf(_score_shown, float(_score_target), minf(1.0, delta * 10.0))
	if absf(_score_shown - _score_target) < 1.0:
		_score_shown = _score_target
	score_label.text = str(int(round(_score_shown)))
	score_label.scale = Vector3.ONE * (1.0 + _bump * 0.35)
	score_label.modulate = Neon.WHITE.lerp(Neon.AMBER, _bump)
	for i in range(_popups.size() - 1, -1, -1):
		var p: Dictionary = _popups[i]
		p.life += delta
		var l: Label3D = p.label
		l.global_position += Vector3(0, delta * 0.3, 0)
		l.modulate.a = clampf(1.5 - p.life * 1.5, 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a * 0.85
		if p.life > 1.0:
			l.queue_free()
			_popups.remove_at(i)
