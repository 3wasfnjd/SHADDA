class_name RoomScan
extends Node
## Loads Meta's scene model (asking for the permission and the room setup
## when needed) and turns the anchors into a plain room description:
## {floor_y, ceiling_y, walls, openings, surfaces, blocks, found}
## — see Room.describe() for the format.

signal room_ready(room: Dictionary)

const WAIT_SECONDS := 9.0

var manager: Node
var anchors: Array = []
var head: Node3D
var _started := false
var _timer := 0.0
var _reported := false
var _capture_requested := false
var _permitted := false


func start(origin: Node3D, player_head: Node3D) -> void:
	head = player_head
	add_to_group("room_scan")
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		_finish()
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
			_timer = -20.0
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
		_finish()


func _on_missing() -> void:
	if _capture_requested or manager == null:
		return
	_capture_requested = true
	if bool(manager.call("is_scene_capture_supported")):
		manager.call("request_scene_capture", "")
		_timer = -30.0
	else:
		_finish()


func _on_capture_completed(success: bool) -> void:
	if success and manager != null:
		if bool(manager.call("are_scene_anchors_created")):
			manager.call("remove_scene_anchors")
		manager.call("create_scene_anchors")
		_timer = 0.0
	else:
		_finish()


func anchor_ready(anchor: Node3D) -> void:
	anchors.append(anchor)


func _process(delta: float) -> void:
	if not _started or _reported:
		return
	_timer += delta
	var walls := 0
	for a in anchors:
		if a.kind() == "wall":
			walls += 1
	if (walls >= 3 and _timer > 2.5) or _timer > WAIT_SECONDS:
		_finish()


func _finish() -> void:
	if _reported:
		return
	_reported = true
	room_ready.emit(describe())


## Converts anchors to the room description.
func describe() -> Dictionary:
	var center := head.global_position if head else Vector3.ZERO
	var floor_y := 0.0
	var ceiling_y := 2.5
	var has_floor := false
	var walls: Array = []
	var openings: Array = []
	var surfaces: Array = []
	var blocks: Array = []
	for a in anchors:
		var t: Transform3D = a.global_transform
		match a.kind():
			"floor":
				floor_y = t.origin.y
				has_floor = true
			"ceiling":
				ceiling_y = t.origin.y
	if not has_floor:
		floor_y = minf(0.0, center.y - 1.6)
	for a in anchors:
		var t: Transform3D = a.global_transform
		var k: String = a.kind()
		if (k == "wall" or k == "door" or k == "window") and a.has_rect:
			var n := t.basis.z
			n.y = 0.0
			if n.length() < 0.01:
				continue
			n = n.normalized()
			var to_c := center - t.origin
			to_c.y = 0.0
			var flip := n.dot(to_c) < 0.0
			if flip:
				n = -n
			var r: Rect2 = a.rect
			var mid: Vector3 = t * Vector3(r.get_center().x, r.get_center().y, 0.0)
			var bottom: Vector3 = t * Vector3(r.get_center().x, r.position.y, 0.0)
			var top: Vector3 = t * Vector3(r.get_center().x, r.end.y, 0.0)
			var lo_y := minf(bottom.y, top.y)
			var hi_y := maxf(bottom.y, top.y)
			if k == "wall":
				walls.append({"origin": Vector3(mid.x, floor_y, mid.z), "normal": n, "width": r.size.x, "height": hi_y - floor_y, "xform": t, "rect": r})
			else:
				openings.append({"kind": k, "center": mid, "base": Vector3(mid.x, lo_y, mid.z), "normal": n, "width": r.size.x, "height": hi_y - lo_y, "xform": t, "rect": r})
		elif k == "furniture" and a.has_box:
			var corners: Array = []
			var b: AABB = a.box
			for i in range(8):
				corners.append(t * b.get_endpoint(i))
			var top_y := -INF
			var cx := 0.0
			var cz := 0.0
			for c in corners:
				top_y = maxf(top_y, c.y)
				cx += c.x
				cz += c.z
			cx /= 8.0
			cz /= 8.0
			var ext_x := 0.0
			var ext_z := 0.0
			var ax := t.basis.x
			ax.y = 0.0
			ax = ax.normalized() if ax.length() > 0.01 else Vector3.RIGHT
			var az := Vector3(-ax.z, 0, ax.x)
			for c in corners:
				var d: Vector3 = c - Vector3(cx, c.y, cz)
				ext_x = maxf(ext_x, absf(d.dot(ax)))
				ext_z = maxf(ext_z, absf(d.dot(az)))
			blocks.append({"xform": t, "box": b})
			if top_y > floor_y + 0.25 and top_y < floor_y + 1.4 and ext_x > 0.15 and ext_z > 0.15:
				surfaces.append({"center": Vector3(cx, top_y, cz), "axis_x": ax, "axis_z": az, "half": Vector2(ext_x, ext_z), "label": a.labels[0] if a.labels.size() > 0 else ""})
	return {"floor_y": floor_y, "ceiling_y": ceiling_y, "walls": walls, "openings": openings, "surfaces": surfaces, "blocks": blocks, "found": not walls.is_empty()}
