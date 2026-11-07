extends SceneTree
## Desk check: an explosion over a floor at a few moments, and the plane's floor silhouette.
func _initialize() -> void:
	_go()
func _go() -> void:
	await process_frame
	var w := Node3D.new()
	get_root().add_child(w)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.82, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	var we := WorldEnvironment.new()
	we.environment = e
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	w.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.72, 0.6, 0.45)
	floor.material_override = fm
	w.add_child(floor)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 40
	cam.position = Vector3(0, 1.0, 1.4)
	cam.look_at(Vector3(0, 0.5, 0))
	var out := OS.get_cmdline_user_args()[0]
	var f := Fx.explosion(w, Vector3(0, 0.5, 0), 0.25)
	var shots := [0.05, 0.2, 0.6, 1.4, 2.6]
	for k in shots:
		while is_instance_valid(f) and f.life < k:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out + "/boom_%.2f.png" % k)
	# Silhouette shadow (same recipe as PlayerPlane).
	var m := Models.player_plane()
	w.add_child(m.root)
	(m.root as Node3D).scale = Vector3.ONE * WarMath.PLANE_SCALE
	(m.root as Node3D).position = Vector3(0, 0.35, 0)
	(m.root as Node3D).rotation = Vector3(0.15, 0.6, 0.5)
	var sil := MeshInstance3D.new()
	sil.mesh = (m.body as MeshInstance3D).mesh
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_color = Color(0.02, 0.02, 0.04, 0.45)
	sm.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	sm.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ | BaseMaterial3D.STENCIL_FLAG_WRITE
	sm.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	sm.stencil_reference = 7
	sil.material_override = sm
	sil.top_level = true
	w.add_child(sil)
	await process_frame
	var bx := (m.body as MeshInstance3D).global_transform
	sil.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0.002, 0), Vector3(0, 0, 1)) * bx.basis, Vector3(bx.origin.x, 0.004, bx.origin.z))
	cam.position = Vector3(0.5, 0.9, 0.9)
	cam.look_at(Vector3(0, 0.15, 0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/shadow.png")
	quit()
