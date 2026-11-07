extends SceneTree
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
	var m := Models.player_plane()
	w.add_child(m.root)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 20
	var out := OS.get_cmdline_user_args()[0]
	var views := {"tip_top": [Vector3(0.13, 0.25, 0.0), Vector3(0.13, 0.0, 0.0), Vector3.FORWARD], "tip_front": [Vector3(0.13, 0.0, -0.4), Vector3(0.13, -0.01, 0.0), Vector3.UP], "tip_rear": [Vector3(0.13, 0.05, 0.35), Vector3(0.13, -0.01, 0.0), Vector3.UP]}
	for k in views:
		cam.position = views[k][0]
		cam.look_at(views[k][1], views[k][2])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out + "/" + k + ".png")
	quit()
