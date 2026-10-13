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
var _prev_pos: Vector3 = Vector3.INF
var hand_velocity: Vector3 = Vector3.ZERO
var _stunned: float = 0.0
var _reticle: Node3D
var _reticle_ring: MeshInstance3D
var _reticle_target: Node3D = null
var _yank_cooldown: float = 0.0
var _sight: MeshInstance3D
var _sight_mesh := ImmediateMesh.new()
var _sight_mat: ShaderMaterial
var _pulse: float = 0.0
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
	# Lock-on reticle: a spinning bracket ring that snaps onto the target.
	_reticle = Node3D.new()
	_reticle.top_level = true
	add_child(_reticle)
	_reticle_ring = Neon.make_ring_mesh(Neon.CYAN, 0.12, 0.006)
	_reticle_ring.rotation_degrees.x = 90.0
	_reticle.add_child(_reticle_ring)
	for i in range(4):
		var tick := Neon.make_orb(Neon.WHITE, 0.012, 6, 3)
		tick.position = Vector3(cos(i * PI * 0.5), sin(i * PI * 0.5), 0) * 0.15
		_reticle.add_child(tick)
	_reticle.visible = false
	# Aim sight: a thin beam from the emitter out to the target (or 2.5 m).
	_sight_mat = Neon.glow_material(Neon.CYAN, true)
	_sight = MeshInstance3D.new()
	_sight.mesh = _sight_mesh
	_sight.material_override = _sight_mat
	_sight.top_level = true
	_sight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sight.extra_cull_margin = 16.0
	add_child(_sight)


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
	_stunned = maxf(0.0, _stunned - delta)
	_pulse = maxf(0.0, _pulse - delta * 2.0)
	# Hand speed (for punches).
	var p := hand_position()
	if _prev_pos != Vector3.INF and delta > 0.0:
		hand_velocity = hand_velocity.lerp((p - _prev_pos) / delta, 0.5)
	_prev_pos = p
	if _stunned > 0.0:
		allow_play = false
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
			# Sling: letting go of a stretched ball flings it away from the hand.
			var t := tether.target
			if t is Spark and t.family == "ball" and tether.tension > 0.35:
				var dir: Vector3 = (t.global_position - hand_position()).normalized()
				t.fling(dir, tether.tension)
				_haptic(0.8, 0.12)
				_cue("snap")
			tether.release()
			set_light(Light.RELEASE)
			_cue("release")
		if grip_down and not _grip_was_down:
			_try_crush()
		_try_punch(targets)
	elif tether.is_busy():
		tether.release()
	if not allow_play and director and director.has_method("aim_select"):
		director.call("aim_hover", index, aim_origin(), aim_direction())
		if trigger_down and not _trigger_was_down and director.call("aim_select", aim_origin(), aim_direction()):
			_haptic(0.4, 0.06)
	_trigger_was_down = trigger_down
	_grip_was_down = grip_down
	tether.update(delta, grip)
	_yank_cooldown = maxf(0.0, _yank_cooldown - delta)
	if allow_play and tether.state == Tether.State.ATTACHED:
		_try_yank()
	if allow_play:
		_try_catch(targets)
	_update_reticle(delta, targets, allow_play)
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
	_guide.visible = false


## Jerk the hand back while roped: the critter flies at you.
func _try_yank() -> void:
	var t := tether.target
	if t == null or not t.has_method("yank") or _yank_cooldown > 0.0:
		return
	var to_hand: Vector3 = (hand_position() - t.global_position).normalized()
	var pull_speed := hand_velocity.dot(to_hand)
	if pull_speed > 1.5:
		_yank_cooldown = 0.5
		var flew: bool = t.yank(tether_origin, clampf((pull_speed - 1.5) / 2.0, 0.0, 1.0))
		_haptic(0.9, 0.12)
		_cue("snap")
		if flew:
			tether.rest_length = TetherMath.MIN_REST


## A critter that flew into the hand is caught and bursts there.
func _try_catch(targets: Array) -> void:
	var hand := hand_position()
	for t in targets:
		if not is_instance_valid(t) or not t.has_method("is_flying_to_hand") or not t.is_flying_to_hand():
			continue
		if t.global_position.distance_to(hand) < 0.32:
			if tether.target == t:
				tether.release()
			_haptic(1.0, 0.2)
			_cue("capture")
			t.hit("catch")
			pulse(1.0)
			return


func _update_reticle(delta: float, targets: Array, allow_play: bool) -> void:
	var show_sight := _stunned <= 0.0 and not tether.is_busy()
	var target: Node3D = null
	if allow_play and show_sight:
		target = tether.peek_target(aim_origin(), aim_direction(), targets)
	_reticle_target = target
	_reticle.visible = target != null
	if target:
		var cam := get_viewport().get_camera_3d()
		var r: float = target.radius if "radius" in target else 0.12
		_reticle.global_position = target.global_position
		if cam:
			_reticle.look_at(cam.global_position, Vector3.UP, true)
		_reticle.scale = Vector3.ONE * (r / 0.12 + 0.3) * (1.0 + sin(_time * 10.0) * 0.06)
		_reticle_ring.rotation.y += delta * 3.0
		(_reticle_ring.material_override as StandardMaterial3D).albedo_color = Neon.AMBER.lerp(Neon.WHITE, 0.3 + 0.3 * sin(_time * 12.0))
	# Sight beam.
	_sight.visible = show_sight and (allow_play or (director and director.call("in_menu")))
	if _sight.visible:
		var from := tether_origin.global_position
		var to := (target.global_position if target else aim_origin() + aim_direction() * 2.5)
		var pts := PackedVector3Array([from, from.lerp(to, 0.5), to])
		Neon.build_tube(_sight_mesh, pts, func(_t): return 0.0016)
		_sight_mat.set_shader_parameter("tint", Neon.AMBER if target else Neon.CYAN)
		_sight_mat.set_shader_parameter("alpha_scale", 0.55 if target else 0.25)


## A fast fist through a critter bursts it (or launches a ball).
func _try_punch(targets: Array) -> void:
	if hand_velocity.length() < 1.7 or grip < 0.5:
		return
	var hand := hand_position()
	for t in targets:
		if not is_instance_valid(t) or not t.has_method("punch") or not t.can_be_tethered():
			continue
		var to: Vector3 = t.global_position - hand
		if to.length() < t.radius + 0.14 and hand_velocity.normalized().dot(to.normalized()) > 0.2:
			t.punch(hand_velocity)
			_haptic(1.0, 0.2)
			_cue("capture")
			return


## Bitten by a diving critter: the hand goes dark for a moment.
func bitten() -> void:
	_stunned = 0.9
	if tether.is_busy():
		tether.release()
	_haptic(1.0, 0.3)


func pulse(amount: float) -> void:
	_pulse = maxf(_pulse, amount)


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
	if _stunned > 0.0:
		var flicker := 1.0 if fmod(_time * 20.0, 1.0) < 0.5 else 0.0
		cyan = Neon.RED.lerp(Neon.CYAN_DIM, flicker)
		amber = Neon.AMBER_DIM
		halo = 0.1
	cyan = cyan.lerp(Neon.WHITE, _pulse * 0.6)
	halo += _pulse * 0.5
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
