extends Node3D

func setup_scene(entity: Object) -> void:
	var labels: PackedStringArray = entity.call("get_semantic_labels")
	# Avoid duplicate contacts from the global mesh and semantic surfaces.
	if "global_mesh" in labels:
		return
	var shape: CollisionShape3D = entity.call("create_collision_shape")
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 6
	body.set_meta("real_room", true)
	body.set_meta("floor", "floor" in labels)
	body.set_meta("surface_labels", labels)
	add_child(body)
	body.add_child(shape)
	if "floor" in labels:
		body.add_to_group("shadda_real_floor")
