extends SceneTree
## One-off asset prep for the user's vintage weapon model (run on a desktop):
##   godot --headless --path . -s tools/import_enemy_gun.gd
## Reads assets/models/source/vintage_weapon_21k.glb (decoded and simplified
## from 520k to 21k triangles with gltfpack -si 0.04), keeps its largest part
## (the multi-barrel cannon on its wheeled tripod — the rifle, shells and
## grenades are dropped), turns the barrels from -X to -Z, sets the base on
## y = 0, length 22 cm, and writes:
##   assets/models/aa_gun.res, assets/models/aa_gun_albedo.jpg (via .png)
const SRC := "res://assets/models/source/vintage_weapon_21k.glb"
const LENGTH := 0.22
const SIGN := -1.0  # barrels toward +X in the source

func _find(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i

func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	assert(doc.append_from_file(SRC, st) == OK)
	var scene: Node3D = doc.generate_scene(st)
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var a := mi.mesh.surface_get_arrays(0)
	var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var par := PackedInt32Array()
	par.resize(v.size())
	for i in v.size():
		par[i] = i
	var weld := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 2000), roundi(v[i].y * 2000), roundi(v[i].z * 2000))
		if weld.has(key):
			par[_find(par, i)] = _find(par, weld[key])
		else:
			weld[key] = i
	for t in range(0, idx.size(), 3):
		var r0 := _find(par, idx[t])
		for k in [1, 2]:
			var r := _find(par, idx[t + k])
			if r != r0:
				par[r] = r0
	var count := {}
	for t in range(0, idx.size(), 3):
		var r := _find(par, idx[t])
		count[r] = count.get(r, 0) + 1
	var roots := count.keys()
	roots.sort_custom(func(x, y): return count[x] > count[y])
	var keep_roots := {roots[0]: true}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if keep_roots.has(_find(par, idx[t])):
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			for k in 3:
				lo = lo.min(v[idx[t + k]])
				hi = hi.max(v[idx[t + k]])
	var s := LENGTH / (hi.x - lo.x)
	var c := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	var muzzle := Vector3.ZERO
	var mc := 0
	for j in keep:
		if not remap.has(j):
			remap[j] = nv.size()
			var q := (v[j] - c) * s
			nv.append(Vector3(q.z * -SIGN, q.y, q.x * SIGN))
			nn.append(Vector3(n[j].z * -SIGN, n[j].y, n[j].x * SIGN))
			nuv.append(uv[j])
			if (v[j].x < lo.x + 0.03) if SIGN > 0 else (v[j].x > hi.x - 0.03):
				var qm := (v[j] - c) * s
				muzzle += Vector3(qm.z * -SIGN, qm.y, qm.x * SIGN)
				mc += 1
		ni.append(remap[j])
	muzzle /= maxf(1, mc)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	ResourceSaver.save(mesh, "res://assets/models/aa_gun.res", ResourceSaver.FLAG_COMPRESS)
	var img: Image = mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://assets/models/aa_gun_albedo.png")
	print("GUN triangles=%d verts=%d scale=%.4f height=%.4f width=%.4f muzzle=%s" % [ni.size() / 3, nv.size(), s, (hi.y - lo.y) * s, (hi.z - lo.z) * s, muzzle])
	quit()
