extends Node3D
## Instanced by OpenXRFbSceneManager for every scene anchor in the room.
## Reads the anchor's labels and bounds, adds a solid collider for walls and
## the floor (physics layer 1), and reports itself to the RoomScan node.

var labels: PackedStringArray = PackedStringArray()
var rect: Rect2 = Rect2()
var entity = null


func setup_scene(spatial_entity) -> void:
	entity = spatial_entity
	labels = spatial_entity.get_semantic_labels()
	if spatial_entity.is_component_supported(3):   # BOUNDED_2D
		rect = spatial_entity.get_bounding_box_2d()
	var solid := false
	for label in labels:
		if label in ["WALL_FACE", "FLOOR", "CEILING", "TABLE", "COUCH", "STORAGE", "BED", "SCREEN", "LAMP", "PLANT", "OTHER"]:
			solid = true
	if solid:
		var shape: Node3D = spatial_entity.create_collision_shape()
		if shape:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("labels", labels)
			add_child(body)
			body.add_child(shape)
	get_tree().call_group("room_scan", "anchor_ready", self)


func is_wall() -> bool:
	return labels.has("WALL_FACE")


func is_door() -> bool:
	return labels.has("DOOR_FRAME")


func is_window() -> bool:
	return labels.has("WINDOW_FRAME")


func is_floor() -> bool:
	return labels.has("FLOOR")
