extends SceneTree
## One-off asset prep for the player's own plane model (run on a desktop):
##   godot --headless --path . -s tools/import_player_plane.gd
## Reads assets/models/source/vintage_plane_25k.glb (the user's model, already
## decoded and simplified from 503k to 25k triangles with gltfpack -si 0.05),
## removes the fused propeller blades (the game spins its own), turns the
## nose to -Z, scales the wingspan to 34 cm, and writes:
##   assets/models/player_plane.res          (ArrayMesh)
##   assets/models/player_plane_albedo.png   (texture, 2048², then saved as .jpg)
const SRC := "res://assets/models/source/vintage_plane_25k.glb"
const SPAN := 0.34

func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(SRC, st)
	assert(err == OK)
	var scene: Node3D = doc.generate_scene(st)
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var tip := Vector3(0, 0, -INF)
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
		if p.z > tip.z:
			tip = p
	var s := SPAN / (hi.x - lo.x)
	# Drop blade triangles: in front of the cowling and away from the spinner.
	var keep := PackedInt32Array()
	var dropped := 0
	for i in range(0, idx.size(), 3):
		var blade := true
		var far := false
		for k in range(3):
			var p := v[idx[i + k]]
			if p.z < hi.z - 0.054:
				blade = false
			if Vector2(p.x - tip.x, p.y - tip.y).length() > 0.05:
				far = true
		if blade and far:
			dropped += 1
			continue
		keep.append_array([idx[i], idx[i + 1], idx[i + 2]])
	# Compact vertices, rotate 180° about Y (nose → -Z), scale, centre on the bbox.
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	var c := (lo + hi) * 0.5
	for j in keep:
		if not remap.has(j):
			remap[j] = nv.size()
			var p := v[j] - Vector3(c.x, c.y, c.z)
			nv.append(Vector3(-p.x, p.y, -p.z) * s)
			nn.append(Vector3(-n[j].x, n[j].y, -n[j].z))
			nuv.append(uv[j])
		ni.append(remap[j])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	DirAccess.make_dir_recursive_absolute("res://assets/models")
	ResourceSaver.save(mesh, "res://assets/models/player_plane.res", ResourceSaver.FLAG_COMPRESS)
	var img: Image = mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(2048, 2048, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://assets/models/player_plane_albedo.png")
	var spinner_z := -(tip.z - c.z) * s
	var blade_z := -((hi.z - 0.03) - c.z) * s
	print("PLANE triangles=%d dropped_blade_tris=%d verts=%d scale=%.4f wheels_y=%.4f spinner_z=%.4f prop_z=%.4f prop_r=%.4f span=%.3f length=%.3f" % [ni.size() / 3, dropped, nv.size(), s, (lo.y - c.y) * s, spinner_z, blade_z, 0.223 * s, (hi.x - lo.x) * s, (hi.z - lo.z) * s])
	quit()
