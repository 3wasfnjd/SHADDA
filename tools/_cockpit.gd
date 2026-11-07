extends SceneTree
func _initialize() -> void:
	_go()
func _go() -> void:
	await process_frame
	var w := Node3D.new()
	get_root().add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.82, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	w.add_child(sun)
	var m := Models.player_plane()
	w.add_child(m.root)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 30
	var out := OS.get_cmdline_user_args()[0]
	var views := {"side": Vector3(0.35, 0.06, 0.0), "front34": Vector3(0.22, 0.12, -0.25), "rear34": Vector3(-0.2, 0.14, 0.25), "top": Vector3(0.05, 0.4, 0.02)}
	for k in views:
		cam.position = views[k]
		cam.look_at(Vector3(0, 0.02, 0.0), Vector3.UP if k != "top" else Vector3.FORWARD)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out + "/cock_" + k + ".png")
	quit()
