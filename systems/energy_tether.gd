class_name ShaddaTether
extends Node3D

signal released(reason: String)
var body: RigidBody3D
var anchor: Node3D
var local_point := Vector3.ZERO
var rest_length: float = 0.5
var tension: float = 0.0
var reel: float = 0.0
var active: bool = false
var dock_link: bool = false
var cfg: Dictionary
var blocked_time: float = 0.0
var overextended_time: float = 0.0
var last_anchor := Vector3.ZERO
var blocked: bool = false
var mesh := ImmediateMesh.new()
var visual := MeshInstance3D.new()
var mat := ShaddaVisuals.material(Color(0.02, 0.7, 1.0), 1.2)

func _ready() -> void:
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	hide()

func attach(target: RigidBody3D, point: Vector3, start: Node3D, settings: Dictionary, to_dock: bool = false) -> void:
	body = target
	local_point = body.to_local(point)
	anchor = start
	cfg = settings
	dock_link = to_dock
	last_anchor = anchor.global_position
	rest_length = 0.005 if to_dock else maxf(0.45, point.distance_to(last_anchor))
	active = true
	blocked_time = 0.0
	overextended_time = 0.0
	tension = 0.0
	show()

func release(reason: String = "manual") -> void:
	if not active:
		return
	active = false
	tension = 0.0
	body = null
	hide()
	released.emit(reason)

func resample() -> void:
	if active and is_instance_valid(body) and is_instance_valid(anchor):
		last_anchor = anchor.global_position
		if not dock_link:
			rest_length = maxf(0.45, last_anchor.distance_to(body.to_global(local_point)))

static func spring_force(distance: float, rest: float, speed_away: float, stiffness: float, damping: float, cap: float) -> float:
	if distance <= rest:
		return 0.0
	return clampf(stiffness * (distance - rest) + damping * speed_away, 0.0, cap)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(body) or not is_instance_valid(anchor):
		release("missing")
		return
	var a := anchor.global_position
	var anchor_motion := a - last_anchor
	last_anchor = a
	if not dock_link and anchor_motion.length() > 0.3:
		release("tracking_jump")
		return
	var anchor_velocity := (anchor_motion / maxf(delta, 0.001)).limit_length(2.5)
	var p := body.to_global(local_point)
	var direction := a - p
	var distance := direction.length()
	if distance < 0.0001:
		tension = 0.0
		return
	direction /= distance
	if not dock_link:
		rest_length = maxf(0.45, rest_length - float(cfg["reel_speed"]) * reel * delta)
	var query := PhysicsRayQueryParameters3D.create(p + direction * 0.025, a, 1, [body.get_rid()])
	blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	blocked_time = blocked_time + delta if blocked else 0.0
	var extended := distance > rest_length + float(cfg["max_extension"])
	overextended_time = overextended_time + delta if extended else 0.0
	if blocked_time > 0.2 or overextended_time > 0.35:
		release("blocked" if blocked else "break")
		return
	if blocked:
		tension = 0.0
		return
	var offset := p - body.global_position
	var point_velocity := body.linear_velocity + body.angular_velocity.cross(offset)
	var speed_away := (point_velocity - anchor_velocity).dot(-direction)
	var cap := 16.0 if dock_link else float(cfg["spring_max_force"])
	tension = spring_force(distance, rest_length, speed_away, float(cfg["spring_stiffness"]), float(cfg["spring_damping"]), cap)
	body.apply_force(direction * tension, offset)
	if tension > 0.01:
		body.sleeping = false

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(body):
		return
	var start := to_local(anchor.global_position)
	var end := to_local(body.to_global(local_point))
	var axis := (end - start).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	var up := axis.cross(side).normalized()
	var slack := clampf(rest_length - start.distance_to(end), 0.0, 0.8)
	var color := Color(1.0, 0.35, 0.04) if blocked or tension > 50.0 else Color(0.015, 0.65, 1.0)
	mat.albedo_color = color
	mat.emission = color
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(12):
		var t0 := float(i) / 12.0
		var t1 := float(i + 1) / 12.0
		var c0 := start.lerp(end, t0) + Vector3.DOWN * sin(t0 * PI) * (0.02 + slack * 0.35)
		var c1 := start.lerp(end, t1) + Vector3.DOWN * sin(t1 * PI) * (0.02 + slack * 0.35)
		for j in range(5):
			var a0 := TAU * j / 5.0
			var a1 := TAU * (j + 1) / 5.0
			var r0 := (side * cos(a0) + up * sin(a0)) * 0.004
			var r1 := (side * cos(a1) + up * sin(a1)) * 0.004
			for v in [c0+r0,c1+r0,c1+r1,c0+r0,c1+r1,c0+r1]:
				mesh.surface_add_vertex(v)
	mesh.surface_end()
