class_name Rift
extends Node3D
## A fracture in the room the raiders come through. Drives the baked
## Portal_Sequence clip (Idle 0 → Warning 0.75 → Opening 1.67 → Active 3 →
## Closing 4.67 → Gone 6) and layers neon halos on top. The fake wall chunk
## baked into the asset is hidden because passthrough shows the real room.

enum Mode { CLOSED, WARNING, OPEN, CLOSING }

const T_WARNING := 0.75
const T_ACTIVE := 3.0
const T_CLOSING := 4.67
const T_GONE := 6.0

var model: Node3D
var anim: AnimationPlayer
var mode: int = Mode.CLOSED
var _inside: Node3D
var _outside: Node3D
var _threshold: Node3D
var _halo: MeshInstance3D
var _glow: MeshInstance3D
var _ring: MeshInstance3D
var _emitters: Dictionary = {}
var _time: float = 0.0
var _hold_at: float = -1.0
var alert_level: float = 0.0


static func create(scene: PackedScene) -> Rift:
	var rift := Rift.new()
	rift.model = scene.instantiate() as Node3D
	return rift


func _ready() -> void:
	add_child(model)
	Neon.hide_materials(model, ["M_Rift_Wall_Replaceable"])
	_emitters = Neon.restyle(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
	_inside = model.find_child("SpawnInside_*", true, false) as Node3D
	_outside = model.find_child("SpawnOutside_*", true, false) as Node3D
	_threshold = model.find_child("SpawnThreshold_*", true, false) as Node3D
	_halo = Neon.make_halo(Neon.CYAN, 1.1, 0.0)
	_halo.position = Vector3(0, 0.45, 0.02)
	add_child(_halo)
	_glow = Neon.make_halo(Neon.VIOLET, 1.9, 0.0)
	_glow.position = Vector3(0, 0.45, -0.05)
	add_child(_glow)
	_ring = Neon.make_floor_ring(Neon.CYAN, 1.3, 0.0)
	_ring.position = Vector3(0, 0.008, 0.35)
	add_child(_ring)
	_seek(0.0)


func spawn_inside() -> Vector3:
	return _inside.global_position if _inside else global_position + global_basis.z * -0.3


func spawn_outside() -> Vector3:
	return _outside.global_position if _outside else global_position + global_basis.z * 0.6


func _seek(t: float) -> void:
	if anim == null:
		return
	var clip := anim.get_animation_list()[0]
	if anim.current_animation != clip:
		anim.play(clip)
	anim.seek(t, true)
	anim.pause()


func _play_to(from: float, to: float) -> void:
	if anim == null:
		return
	var clip := anim.get_animation_list()[0]
	anim.play(clip)
	anim.seek(from, true)
	_hold_at = to


func warn() -> void:
	if mode == Mode.OPEN or mode == Mode.WARNING:
		return
	mode = Mode.WARNING
	_play_to(0.0, T_WARNING)


func open() -> void:
	if mode == Mode.OPEN:
		return
	var from := T_WARNING if mode == Mode.WARNING else 0.0
	mode = Mode.OPEN
	_play_to(from, T_ACTIVE)


func close() -> void:
	if mode == Mode.CLOSED or mode == Mode.CLOSING:
		return
	mode = Mode.CLOSING
	_play_to(T_CLOSING, T_GONE)


func is_open() -> bool:
	return mode == Mode.OPEN


func _process(delta: float) -> void:
	_time += delta
	if anim and _hold_at >= 0.0 and anim.is_playing() and anim.current_animation_position >= _hold_at:
		anim.seek(_hold_at, true)
		anim.pause()
		_hold_at = -1.0
		if mode == Mode.CLOSING:
			mode = Mode.CLOSED
	var pulse := 0.5 + 0.5 * sin(_time * 3.1)
	var strength := 0.0
	match mode:
		Mode.WARNING:
			strength = 0.35 + 0.3 * pulse
		Mode.OPEN:
			strength = 0.75 + 0.25 * pulse
		Mode.CLOSING:
			strength = 0.4
	strength = maxf(strength, alert_level)
	var color := Neon.CYAN.lerp(Neon.VIOLET, 0.35 + 0.3 * pulse)
	Neon.set_halo_color(_halo, color, 0.55 * strength)
	Neon.set_halo_color(_glow, Neon.VIOLET, 0.22 * strength)
	Neon.set_halo_color(_ring, color, 0.5 * strength)
	if _emitters.has("M_Rift_Core"):
		(_emitters["M_Rift_Core"] as StandardMaterial3D).albedo_color = Neon.WHITE.lerp(Neon.CYAN, 0.3 + 0.4 * pulse)
