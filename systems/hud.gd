class_name Hud
extends Node3D
## Wrist display on the left hand, like a watch: score digits, five wave pips
## (the last one is a crown for the boss), a gem-energy arc, and the combo
## multiplier. Plus floating "+150" popups where critters burst. No words.

var score_label: Label3D
var combo_label: Label3D
var _pips: Array[MeshInstance3D] = []
var _crown: Node3D
var _arc: MeshInstance3D
var _arc_mesh := ImmediateMesh.new()
var _arc_mat: ShaderMaterial
var _arc_back: MeshInstance3D
var _arc_back_mesh := ImmediateMesh.new()
var _score_shown: float = 0.0
var _score_target: int = 0
var _bump: float = 0.0
var _popups: Array = []
var world: Node3D


func _ready() -> void:
	# Panel sits above the left wrist, tilted toward the eyes.
	position = Vector3(0.0, 0.06, 0.07)
	rotation_degrees = Vector3(-55, 0, 0)
	score_label = UI.digits("0", 96, Neon.WHITE)
	score_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	score_label.pixel_size = 0.00042
	score_label.position = Vector3(0, 0.022, 0)
	add_child(score_label)
	combo_label = UI.digits("", 64, Neon.AMBER)
	combo_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	combo_label.pixel_size = 0.00042
	combo_label.position = Vector3(0.062, 0.03, 0)
	add_child(combo_label)
	for i in range(SparkMath.WAVES.size() - 1):
		var pip := Neon.make_orb(Neon.CYAN_DIM, 0.0055, 8, 4)
		pip.position = Vector3(-0.036 + i * 0.018, -0.006, 0)
		add_child(pip)
		_pips.append(pip)
	_crown = UI.icon("crown", Neon.AMBER_DIM, 0.016)
	_crown.position = Vector3(0.038, -0.006, 0)
	add_child(_crown)
	_arc_mat = Neon.glow_material(Neon.CYAN, true)
	_arc = MeshInstance3D.new()
	_arc.mesh = _arc_mesh
	_arc.material_override = _arc_mat
	add_child(_arc)
	_arc_back = MeshInstance3D.new()
	_arc_back.mesh = _arc_back_mesh
	_arc_back.material_override = Neon.glow_material(Neon.CYAN_DIM, true)
	add_child(_arc_back)
	_build_arc(_arc_back_mesh, 1.0, 0.0018)
	visible = false


func _build_arc(mesh: ImmediateMesh, fraction: float, r: float) -> void:
	var pts := PackedVector3Array()
	var n := maxi(2, int(24 * fraction) + 1)
	for i in range(n):
		var a := deg_to_rad(200.0 - 220.0 * fraction * float(i) / float(n - 1))
		pts.append(Vector3(cos(a) * 0.058, sin(a) * 0.058 + 0.012, -0.002))
	Neon.build_tube(mesh, pts, func(_t): return r)


func set_score(value: int) -> void:
	if value > _score_target:
		_bump = 1.0
	_score_target = value


func set_combo(multiplier: float) -> void:
	combo_label.text = ("×%s" % String.num(multiplier, 2).trim_suffix("0").trim_suffix(".")) if multiplier > 1.01 else ""


func set_wave(wave: int, in_break: bool) -> void:
	for i in range(_pips.size()):
		var done := i < wave or (i == wave and in_break)
		var current := i == wave and not in_break
		(_pips[i].material_override as StandardMaterial3D).albedo_color = Neon.CYAN if done else (Neon.WHITE if current else Neon.CYAN_DIM)
		_pips[i].scale = Vector3.ONE * (1.5 if current else 1.0)
	var boss_now := wave >= _pips.size()
	UI.set_icon_color(_crown, Neon.AMBER if boss_now else Neon.AMBER_DIM)


func set_energy(energy: float, color: Color) -> void:
	_build_arc(_arc_mesh, clampf(energy, 0.02, 1.0), 0.0028)
	_arc_mat.set_shader_parameter("tint", color)


## A floating score number that rises and fades where a critter burst.
func popup(at: Vector3, points: int, color: Color, big: bool = false) -> void:
	if world == null:
		return
	var l := UI.digits("+%d" % points, 140 if big else 84, color)
	world.add_child(l)
	l.global_position = at + Vector3(0, 0.1, 0)
	_popups.append({"label": l, "life": 0.0})


func _process(delta: float) -> void:
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
		l.global_position += Vector3(0, delta * 0.35, 0)
		l.scale = Vector3.ONE * (1.0 + minf(p.life * 6.0, 1.0) * 0.3)
		l.modulate.a = clampf(1.5 - p.life * 1.5, 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a * 0.85
		if p.life > 1.0:
			l.queue_free()
			_popups.remove_at(i)
