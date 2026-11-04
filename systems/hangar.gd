class_name Hangar
extends Node3D
## A launch bay cut into one of the room's real walls (doors and walls from
## Meta Scene). Air bays sit at chest height; ground bays sit on the floor.
## Local frame: wall surface z = 0, +Z into the room.

var ground: bool = false
var big: bool = false
var width: float = 0.42
var height: float = 0.3
var parts: Dictionary = {}
var open_amount: float = 0.0
var open_target: float = 0.0
var hold: float = 0.0
var _blink: float = 0.0


static func create(is_ground: bool, is_big: bool = false) -> Hangar:
	var h := Hangar.new()
	h.ground = is_ground
	h.big = is_big
	if is_big:
		h.width = 0.86
		h.height = 0.44
	elif is_ground:
		h.width = 0.32
		h.height = 0.15
	return h


func _ready() -> void:
	parts = Models.hangar(width, height)
	add_child(parts.root)
	_apply()


## Places the bay on a wall: `base` is a point on the wall at floor level,
## `normal` points into the room, `centre_height` is above the floor.
func mount(base: Vector3, normal: Vector3, centre_height: float) -> void:
	var n := normal
	n.y = 0.0
	n = n.normalized()
	global_position = base + Vector3(0, centre_height, 0)
	look_at(global_position - n, Vector3.UP)   # -Z into the wall, +Z into the room


func request_open(seconds: float) -> void:
	open_target = 1.0
	hold = maxf(hold, seconds)


## Where a unit starts (inside the tunnel) and where it ends its exit.
func inside_point() -> Vector3:
	return global_transform * Vector3(0, -height * 0.5 + 0.0 if ground else 0.0, -0.32)


func exit_point(distance: float = 0.35) -> Vector3:
	return global_transform * Vector3(0, -height * 0.5 if ground else 0.0, distance)


func room_normal() -> Vector3:
	return global_basis.z.normalized()


func is_open() -> bool:
	return open_amount > 0.95


func _process(delta: float) -> void:
	if hold > 0.0:
		hold -= delta
		if hold <= 0.0:
			open_target = 0.0
	var rate := 1.6 if open_target > open_amount else 1.1
	open_amount = move_toward(open_amount, open_target, delta * rate)
	_blink += delta
	_apply()


func _apply() -> void:
	if parts.is_empty():
		return
	var e := open_amount * open_amount * (3.0 - 2.0 * open_amount)
	for d in parts.doors:
		var door := d as Node3D
		door.position.y = lerpf(float(door.get_meta("closed_y")), float(door.get_meta("open_y")), e)
	var on := open_target > 0.0 and fmod(_blink, 0.5) < 0.25
	for l in parts.lights:
		var m := (l as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_color = Neon.AMBER if on else Neon.AMBER_DIM
	(parts.tunnel as Node3D).visible = open_amount > 0.001
