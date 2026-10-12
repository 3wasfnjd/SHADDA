class_name ShaddaRoomSetup
extends Node3D
var manager: Node
var started: bool = false
var manual_floor: StaticBody3D
var selected := Transform3D.IDENTITY
var floor_height: float = 0.0
var has_real_floor: bool = false
var clear: bool = false
var cfg: Dictionary
var outline := MeshInstance3D.new()
var outline_mesh := ImmediateMesh.new()
var outline_material := ShaddaVisuals.material(Color(0.02,0.6,0.85),0.7)
var info: String = ""
var frozen_selection: bool = false

func setup(origin: XROrigin3D, settings: Dictionary, preview: bool) -> void:
	cfg = settings
	outline.mesh = outline_mesh
	add_child(outline)
	outline.hide()
	if not preview and ClassDB.class_exists("OpenXRFbSceneManager"):
		manager = ClassDB.instantiate("OpenXRFbSceneManager")
		manager.set("auto_create", false)
		manager.set("default_scene", load("res://scenes/room_surface.tscn"))
		manager.connect("openxr_fb_scene_capture_completed", _capture_finished)
		origin.add_child(manager)

func start() -> void:
	outline.show()
	frozen_selection = false
	if is_instance_valid(manual_floor):
		manual_floor.collision_layer = 0
		manual_floor.queue_free()
		manual_floor = null
	if started:
		return
	started = true
	if OS.has_feature("android"):
		OS.request_permission("com.oculus.permission.USE_SCENE")
	if manager != null:
		manager.call_deferred("create_scene_anchors")

func scan() -> void:
	if manager != null and bool(manager.call("is_scene_capture_supported")):
		manager.call("request_scene_capture")

func _capture_finished(success: bool) -> void:
	if success and manager != null:
		if bool(manager.call("are_scene_anchors_created")):
			manager.call("remove_scene_anchors")
		manager.call("create_scene_anchors")

func update_placement(head: Node3D, pointer: Node3D, height_input: float, delta: float) -> void:
	if frozen_selection:
		return
	var start := pointer.global_position
	var direction := -pointer.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(start,start+direction*5.0,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	has_real_floor = not hit.is_empty() and bool(hit.collider.get_meta("real_room", false)) and bool(hit.collider.get_meta("floor", false)) and hit.normal.y > 0.9
	var p: Vector3
	if has_real_floor:
		p = hit.position
		floor_height = p.y
	else:
		if absf(height_input) > 0.2:
			floor_height = clampf(floor_height + height_input * delta * 0.18, -1.0, 1.0)
		var intersection: Variant = Plane(Vector3.UP,floor_height).intersects_ray(start,direction)
		var forward := -head.global_basis.z
		forward.y = 0
		p = Vector3(head.global_position.x,floor_height,head.global_position.z)+forward.normalized()*1.8
		if intersection != null:
			var distance: float = Vector2(intersection.x-head.global_position.x,intersection.z-head.global_position.z).length()
			if distance >= 1.1 and distance <= 2.8:
				p = intersection
	var facing := head.global_position-p
	facing.y = 0
	selected = Transform3D(Basis.looking_at(facing.normalized(),Vector3.UP,true),p)
	clear = true
	if has_real_floor:
		var check := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(cfg["arena_width"]),0.95,float(cfg["arena_depth"]))
		check.shape = box
		check.transform = selected.translated_local(Vector3(0,0.52,0))
		check.collision_mask = 1
		clear = get_world_3d().direct_space_state.intersect_shape(check,1).is_empty()
		for corner in [Vector3(-0.95,0,-0.75),Vector3(0.95,0,-0.75),Vector3(-0.95,0,0.75),Vector3(0.95,0,0.75)]:
			var c: Vector3 = selected * corner
			var down := PhysicsRayQueryParameters3D.create(c+Vector3.UP*0.15,c-Vector3.UP*0.15,1)
			var support := get_world_3d().direct_space_state.intersect_ray(down)
			if support.is_empty() or not bool(support.collider.get_meta("floor",false)):
				clear = false
	info = "A تثبيت • B مسح الغرفة" if has_real_floor and clear else ("اختر مساحة خالية" if has_real_floor else "أشر للأرض • العصا اليسرى لضبط الارتفاع\nA تأكيد يدوي • B مسح الغرفة")
	draw_outline()

func draw_outline() -> void:
	var w := float(cfg["arena_width"]) * 0.5
	var d := float(cfg["arena_depth"]) * 0.5
	var points := PackedVector3Array()
	for p in [Vector3(-w,0.015,-d),Vector3(w,0.015,-d),Vector3(w,0.015,d),Vector3(-w,0.015,d),Vector3(-w,0.015,-d)]:
		points.append(selected*p)
	outline_material.albedo_color = Color(0.02,0.65,0.9) if clear else Color(1,0.28,0.03)
	ShaddaVisuals.line(outline_mesh,points,outline_material)

func confirm_manual() -> void:
	if is_instance_valid(manual_floor):
		manual_floor.queue_free()
	manual_floor = StaticBody3D.new()
	manual_floor.collision_layer = 1
	manual_floor.collision_mask = 6
	manual_floor.set_meta("floor", true)
	manual_floor.set_meta("manual_confirmed", true)
	add_child(manual_floor)
	manual_floor.global_transform = selected
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(cfg["arena_width"])+0.12,0.12,float(cfg["arena_depth"])+0.12)
	shape.shape = box
	shape.position.y = -0.06
	manual_floor.add_child(shape)
