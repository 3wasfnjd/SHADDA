extends SceneTree
## Cuts the player's plane mesh into its crash pieces (nose, fuselage, both
## wings, tail) once, offline, so a shoot-down never stalls the headset.
## Run: godot --headless --path . -s tools/split_player_plane.gd

func _initialize() -> void:
	var mesh: Mesh = load(Models.PLAYER_MESH)
	var cut := Debris.cut_mesh(mesh, Transform3D.IDENTITY, mesh.get_aabb())
	DirAccess.make_dir_recursive_absolute("res://assets/models/player_parts")
	for b in cut:
		var m: Mesh = cut[b][0].mesh
		var tris := 0
		for si in range(m.get_surface_count()):
			tris += (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		ResourceSaver.save(m, "res://assets/models/player_parts/%s.res" % b, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d triangles, centre %s" % [b, tris, m.get_aabb().get_center()])
	quit()
