extends Node3D
## Instanced by OpenXRFbSceneManager for each scene anchor (wall, door,
## window, floor, ceiling, table, couch …). Records its labels and bounds,
## adds a solid collider (physics layer 1) and reports to the room scan.

var labels: PackedStringArray = PackedStringArray()
var rect: Rect2 = Rect2()          # BOUNDED_2D, in the anchor's local XY plane
var box: AABB = AABB()             # BOUNDED_3D, in anchor local space
var has_rect: bool = false
var has_box: bool = false


static func _component(name: String, fallback: int) -> int:
	if ClassDB.class_exists("OpenXRFbSpatialEntity") and ClassDB.class_has_integer_constant("OpenXRFbSpatialEntity", name):
		return ClassDB.class_get_integer_constant("OpenXRFbSpatialEntity", name)
	return fallback


func setup_scene(entity) -> void:
	labels = entity.get_semantic_labels()
	var c2 := _component("COMPONENT_TYPE_BOUNDED_2D", 3)
	var c3 := _component("COMPONENT_TYPE_BOUNDED_3D", 4)
	if entity.is_component_supported(c2) and entity.is_component_enabled(c2):
		rect = entity.get_bounding_box_2d()
		has_rect = true
	if entity.is_component_supported(c3) and entity.is_component_enabled(c3):
		box = entity.get_bounding_box_3d()
		has_box = true
	var shape: Node3D = entity.create_collision_shape()
	if shape:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		body.add_child(shape)
	get_tree().call_group("room_scan", "anchor_ready", self)


func kind() -> String:
	for pair in [["DOOR_FRAME", "door"], ["WINDOW_FRAME", "window"], ["WALL_FACE", "wall"], ["INVISIBLE_WALL_FACE", "wall"], ["FLOOR", "floor"], ["CEILING", "ceiling"],
			["TABLE", "furniture"], ["COUCH", "furniture"], ["STORAGE", "furniture"], ["BED", "furniture"], ["SCREEN", "furniture"], ["LAMP", "furniture"], ["PLANT", "furniture"], ["OTHER", "furniture"]]:
		if labels.has(pair[0]):
			return pair[1]
	return ""
