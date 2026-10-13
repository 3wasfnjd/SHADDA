class_name RoomScan
extends Node
## Drives Meta's scene model: asks for permission, loads the room anchors
## (walls, doors, windows, floor), requests a room capture when there is no
## scene data yet, and turns what it finds into rift mounts for the director.

signal room_ready(mounts: Array, floor_y: float, found_anything: bool)

const WAIT_SECONDS := 9.0

var manager: Node
var anchors: Array = []
var floor_y: float = 0.0
var has_floor: bool = false
var _started := false
var _timer := 0.0
var _reported := false
var _capture_requested := false
var head: Node3D
var _permitted := false


func start(origin: Node3D, player_head: Node3D) -> void:
	head = player_head
	add_to_group("room_scan")
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		_finish(false)
		return
	manager = ClassDB.instantiate("OpenXRFbSceneManager")
	manager.set("auto_create", false)
	manager.set("default_scene", load("res://scenes/room_anchor.tscn"))
	manager.connect("openxr_fb_scene_data_missing", _on_missing)
	manager.connect("openxr_fb_scene_capture_completed", _on_capture_completed)
	origin.add_child(manager)
	_started = true
	if OS.has_feature("android"):
		get_tree().on_request_permissions_result.connect(_on_permission)
		if OS.request_permission("com.oculus.permission.USE_SCENE"):
			_permitted = true
			manager.call_deferred("create_scene_anchors")
		else:
			_timer = -20.0   # the system dialog is up; wait for the answer
	else:
		_permitted = true
		manager.call_deferred("create_scene_anchors")


func _on_permission(permission: String, granted: bool) -> void:
	if permission != "com.oculus.permission.USE_SCENE" or _permitted:
		return
	if granted and manager != null:
		_permitted = true
		_timer = 0.0
		manager.call_deferred("create_scene_anchors")
	else:
		_finish(false)


func _on_missing() -> void:
	if _capture_requested or manager == null:
		return
	_capture_requested = true
	if bool(manager.call("is_scene_capture_supported")):
		manager.call("request_scene_capture", "")
		_timer = -30.0   # give the system room-setup flow time
	else:
		_finish(false)


func _on_capture_completed(success: bool) -> void:
	if success and manager != null:
		if bool(manager.call("are_scene_anchors_created")):
			manager.call("remove_scene_anchors")
		manager.call("create_scene_anchors")
		_timer = 0.0
	else:
		_finish(false)


func anchor_ready(anchor: Node3D) -> void:
	anchors.append(anchor)
	if anchor.is_floor():
		has_floor = true
		floor_y = anchor.global_position.y


func _process(delta: float) -> void:
	if not _started or _reported:
		return
	_timer += delta
	var walls := 0
	for a in anchors:
		if a.is_wall() or a.is_door():
			walls += 1
	if (walls >= 2 and _timer > 2.0) or _timer > WAIT_SECONDS:
		_finish(walls > 0)


func _finish(found: bool) -> void:
	if _reported:
		return
	_reported = true
	room_ready.emit(mounts(), floor_y if has_floor else 0.0, found)


## Rift mounts: doors first, then windows, then the widest walls.
## Each: {origin: Vector3 (floor level on the surface), normal: Vector3 (into room), width: float, kind: String}
func mounts() -> Array:
	var out: Array = []
	var center := head.global_position if head else Vector3.ZERO
	for a in anchors:
		var kind := ""
		if a.is_door():
			kind = "door"
		elif a.is_window():
			kind = "window"
		elif a.is_wall():
			kind = "wall"
		else:
			continue
		var t: Transform3D = a.global_transform
		var normal := t.basis.z
		normal.y = 0.0
		if normal.length() < 0.01:
			continue
		normal = normal.normalized()
		var to_center := center - t.origin
		to_center.y = 0.0
		if normal.dot(to_center) < 0.0:
			normal = -normal
		var width: float = a.rect.size.x if a.rect.size.x > 0.0 else 1.0
		var height: float = a.rect.size.y if a.rect.size.y > 0.0 else 2.0
		var origin: Vector3 = t * Vector3(a.rect.position.x + width * 0.5, a.rect.position.y, 0.0)
		origin.y = floor_y if has_floor else minf(origin.y, 0.0)
		if kind == "wall" and width < 1.0:
			continue
		out.append({"origin": origin, "normal": normal, "width": width, "height": height, "kind": kind})
	out.sort_custom(func(x, y):
		var rank := {"door": 0, "window": 1, "wall": 2}
		if rank[x.kind] != rank[y.kind]:
			return rank[x.kind] < rank[y.kind]
		return x.width > y.width)
	return out
