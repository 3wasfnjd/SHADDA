extends SceneTree
func _initialize() -> void:
	_go()
func _go() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	for k in ["fighter", "ace", "diver", "cargo", "bomber", "player"]:
		var m: Dictionary
		match k:
			"fighter": m = Models.fighter(Models.ENEMY, 0.002)
			"ace": m = Models.fighter(Models.ACE, 0.002)
			"diver": m = Models.fighter(Models.DIVER, 0.002)
			"cargo": m = Models.transport(Models.FRIEND)
			"bomber": m = Models.bomber()
			"player": m = Models.player_plane()
		root.add_child(m.root)
		await process_frame
		var tris := 0
		for mi in m.root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh is ArrayMesh:
				for si in mesh.get_surface_count():
					var a = mesh.surface_get_arrays(si)
					tris += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var t0 := Time.get_ticks_usec()
		var pieces := Debris.pieces_of(m.root, "")
		print("%s: name=%s children=%d arraymesh_tris=%d cut=%.1f ms pieces=%d" % [k, m.root.name, m.root.get_child_count(), tris, (Time.get_ticks_usec() - t0) / 1000.0, pieces.size()])
		m.root.queue_free()
	quit()
