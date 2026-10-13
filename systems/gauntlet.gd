class_name Gauntlet
extends Node3D
## One player hand: a procedural neon gauntlet (no imported model — a ring
## around the wrist, a palm emitter and a knuckle bar), the rope, lights and
## haptics. Trigger: fire/hold the rope along the controller's aim pose (light
## press shows a faint guide). Grip: reel in, or crush a roped spark within
## reach. A/X: let go.

enum Light { READY, CONNECTED, HIGH_TENSION, RELEASE }

const CRUSH_REACH := 0.5

var index: int = 0
var controller: XRController3D
var aim_node: Node3D
var tether: Tether
var tether_origin: Node3D
var director: Node = null
var trigger: float = 0.0
var grip: float = 0.0
var _light: int = Light.READY
var _light_pulse: float = 0.0
var _halo: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mesh := ImmediateMesh.new()
var _ring_mat: ShaderMaterial
var _bar: MeshInstance3D
var _bar_mesh := ImmediateMesh.new()
var _bar_mat: ShaderMaterial
var _guide: MeshInstance3D
var _guide_mesh := ImmediateMesh.new()
var _trigger_was_down: bool = false
var _grip_was_down: bool = false
var _haptic_cooldown: float = 0.0
var _creak_timer: float = 0.0
var _refire_timer: float = 0.0
var _time: float = 0.0
var _finger_meshes: Array[ImmediateMesh] = []
var _fingers: Array[MeshInstance3D] = []


static func create(hand_index: int) -> Gauntlet:
	var g := Gauntlet.new()
	g.index = hand_index
	return g


func _ready() -> void:
	# Emitter sits in the palm, slightly ahead of the grip pose.
	tether_origin = Node3D.new()
	tether_origin.position = Vector3(0, -0.01, -0.06)
	add_child(tether_origin)
	tether = Tether.new()
	add_child(tether)
	tether.setup(tether_origin, index)
	_halo = Neon.make_halo(Neon.CYAN, 0.12, 0.3)
	tether_origin.add_child(_halo)
	_ring_mat = Neon.glow_material(Neon.CYAN, true)
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	for f in range(5):
		var fm := ImmediateMesh.new()
		_finger_meshes.append(fm)
		var fi := MeshInstance3D.new()
		fi.mesh = fm
		fi.material_override = Neon.glow_material(Neon.CYAN, true)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fi)
		_fingers.append(fi)
	_bar_mat = Neon.glow_material(Neon.AMBER, true)
	_bar = MeshInstance3D.new()
	_bar.mesh = _bar_mesh
	_bar.material_override = _bar_mat
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	_guide = MeshInstance3D.new()
	_guide.mesh = _guide_mesh
	_guide.top_level = true
	var gm := Neon.halo_material(Neon.CYAN, 0.0)
	gm.albedo_texture = null
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	gm.vertex_color_use_as_albedo = true
	_guide.material_override = gm
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.extra_cull_margin = 16.0
	add_child(_guide)
	_build_hand(0.0)


## Wrist ring + knuckle bar, built in local space. `squeeze` 0..1 tightens the ring.
func _build_hand(squeeze: float) -> void:
	# Wrist ring.
	var ring := PackedVector3Array()
	var r := 0.045 - squeeze * 0.006
	for i in range(25):
		var a := TAU * i / 24.0
		ring.append(Vector3(cos(a) * r, sin(a) * r * 0.8, 0.045))
	Neon.build_tube(_ring_mesh, ring, func(_t): return 0.005)
	# Five neon fingers that curl with the grip (controller space: -Z forward, +Y up).
	var curl := squeeze * 1.45
	var pts := PackedVector3Array()
	for f in range(5):
		var is_thumb := f == 4
		var base := Vector3(lerpf(-0.03, 0.03, f / 3.0), 0.012, -0.035) if not is_thumb else Vector3((0.03 if index == 1 else -0.03), 0.004, -0.02)
		var lengths := [0.035, 0.028, 0.022] if not is_thumb else [0.03, 0.025]
		var dir := Vector3(0, 0, -1) if not is_thumb else Vector3((0.6 if index == 1 else -0.6), 0.1, -0.8).normalized()
		var axis := Vector3.RIGHT if not is_thumb else Vector3(0, 1, 0)
		var p := base
		var seg := PackedVector3Array()
		seg.append(p)
		var d := dir
		for L in lengths:
			d = d.rotated(axis, (-curl if not is_thumb else (curl * 0.8 * (1.0 if index == 1 else -1.0))))
			p += d * L
			seg.append(p)
		_finger_meshes[f].clear_surfaces()
		Neon.build_tube(_finger_meshes[f], seg, func(t): return 0.0045 - t * 0.0015)
		if f == 0 or f == 3:
			pts.append(base)
	# Knuckle bar joins the finger bases.
	var bar := PackedVector3Array()
	for i in range(7):
		var t := i / 6.0
		bar.append(Vector3(lerpf(-0.03, 0.03, t), 0.012 + sin(t * PI) * 0.005, -0.035))
	Neon.build_tube(_bar_mesh, bar, func(_t): return 0.004)


func aim_direction() -> Vector3:
	if aim_node:
		return -aim_node.global_basis.z.normalized()
	return -global_basis.z.normalized()


func aim_origin() -> Vector3:
	return aim_node.global_position if aim_node else tether_origin.global_position


func hand_position() -> Vector3:
	return tether_origin.global_position


func update(delta: float, trigger_value: float, grip_value: float, targets: Array, allow_play: bool) -> void:
	_time += delta
	trigger = trigger_value
	grip = grip_value
	_haptic_cooldown = maxf(0.0, _haptic_cooldown - delta)
	_refire_timer = maxf(0.0, _refire_timer - delta)
	var trigger_down := trigger > 0.55
	var grip_down := grip > 0.6
	if allow_play:
		var want_fire := trigger_down and not tether.is_busy() and (not _trigger_was_down or (tether.state == Tether.State.IDLE and _refire_timer <= 0.0))
		if want_fire:
			var hit := tether.fire(aim_direction(), targets, aim_origin())
			_haptic(0.35 if hit else 0.12, 0.05)
			_cue("fire")
			_refire_timer = 0.45
		if not trigger_down and tether.state == Tether.State.ATTACHED:
			tether.release()
			set_light(Light.RELEASE)
			_cue("release")
		if grip_down and not _grip_was_down:
			_try_crush()
	elif tether.is_busy():
		tether.release()
	_trigger_was_down = trigger_down
	_grip_was_down = grip_down
	tether.update(delta, grip)
	if tether.state == Tether.State.ATTACHED:
		if _light == Light.READY or _light == Light.RELEASE:
			_cue("attach")
		set_light(Light.HIGH_TENSION if tether.tension > 0.55 else Light.CONNECTED)
		var amplitude := TetherMath.haptic_amplitude(tether.tension, grip > 0.3)
		if amplitude > 0.05 and _haptic_cooldown <= 0.0:
			_haptic(amplitude, 0.08)
			_haptic_cooldown = 0.08
		_creak_timer -= delta
		if tether.tension > 0.6 and _creak_timer <= 0.0:
			_creak_timer = randf_range(0.25, 0.5)
			_cue("creak")
	elif tether.state == Tether.State.SNAP:
		if _light != Light.RELEASE:
			_cue("snap")
			_haptic(0.9, 0.15)
		set_light(Light.RELEASE)
	elif _light != Light.READY and tether.state == Tether.State.IDLE:
		_light_pulse += delta
		if _light_pulse > 0.4:
			set_light(Light.READY)
	_build_hand(grip)
	_apply_light(delta)
	_draw_guide(allow_play and not tether.is_busy() and trigger > 0.08)


func _try_crush() -> void:
	if tether.state != Tether.State.ATTACHED:
		return
	var target := tether.target
	if target and target.has_method("crush") and target.tether_anchor().global_position.distance_to(hand_position()) < CRUSH_REACH:
		_haptic(1.0, 0.25)
		target.crush()


func _draw_guide(show: bool) -> void:
	_guide.visible = show
	if not show:
		return
	var from := tether_origin.global_position
	var to := aim_origin() + aim_direction() * 3.0
	var strength := clampf((trigger - 0.08) / 0.4, 0.15, 1.0)
	_guide_mesh.clear_surfaces()
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_guide_mesh.surface_set_color(Color(Neon.CYAN.r, Neon.CYAN.g, Neon.CYAN.b, 0.35 * strength))
	_guide_mesh.surface_add_vertex(from)
	_guide_mesh.surface_set_color(Color(Neon.CYAN.r, Neon.CYAN.g, Neon.CYAN.b, 0.0))
	_guide_mesh.surface_add_vertex(to)
	_guide_mesh.surface_end()


func set_light(light: int) -> void:
	if _light == light:
		return
	_light = light
	_light_pulse = 0.0


func _apply_light(_delta: float) -> void:
	var cyan := Neon.CYAN
	var amber := Neon.AMBER_DIM
	var halo := 0.25
	match _light:
		Light.CONNECTED:
			cyan = Neon.WHITE.lerp(Neon.CYAN, 0.5)
			amber = Neon.AMBER
			halo = 0.5
		Light.HIGH_TENSION:
			cyan = Neon.WHITE
			amber = Neon.WHITE.lerp(Neon.AMBER, 0.4)
			halo = 0.8
		Light.RELEASE:
			cyan = Neon.CYAN_DIM
			amber = Neon.AMBER_DIM
			halo = 0.06
	_ring_mat.set_shader_parameter("tint", cyan)
	_bar_mat.set_shader_parameter("tint", amber)
	for fi in _fingers:
		(fi.material_override as ShaderMaterial).set_shader_parameter("tint", cyan)
	Neon.set_halo_color(_halo, cyan, halo)


func _cue(name: String) -> void:
	if director:
		director.call("cue", name, hand_position())


func _haptic(amplitude: float, seconds: float) -> void:
	if controller:
		controller.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


func release_everything() -> void:
	if tether.is_busy():
		tether.release()
