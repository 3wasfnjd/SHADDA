extends SceneTree
## Desktop turntable of every model (CI artwork check; not a Quest capture).
## godot --path . --xr-mode off --rendering-method gl_compatibility -s tools/look.gd -- <out_dir>
var cam: Camera3D
var stage: Node3D
func _initialize() -> void:
	_run()
func _shot(name: String, out: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("look ", name)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "build/look"
	DirAccess.make_dir_recursive_absolute(out)
	stage = Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.78, 0.8, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 0.45
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35
	stage.add_child(cam)
	cam.current = true
	var items := {
		"player_glb": func(): return Models.player_plane().root,
		"player": func(): return Models.fighter(Models.PLAYER).root,
		"enemy_fighter": func(): return Models.fighter(Models.ENEMY).root,
		"transport": func(): return Models.transport().root,
		"bomber": func(): return Models.bomber().root,
		"tank": func(): return Models.tank().root,
		"aa_gun": func():
			var d := Models.aa_gun()
			var mk := MeshInstance3D.new()
			mk.mesh = Toon.ball(0.006)
			(d.muzzles[0] as Node3D).add_child(mk)
			return d.root,
		"balloon": func(): return Models.balloon().root,
		"crate": func(): return Models.crate().root,
	}
	for k in items:
		var m: Node3D = items[k].call()
		stage.add_child(m)
		var aabb := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if mi.name == "Cable" or mi.name == "Blur":
				continue
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		var c := aabb.get_center()
		var r := aabb.size.length() * 0.5
		m.rotation_degrees = Vector3(0, 0, 0)
		cam.look_at_from_position(c + Vector3(-1.0, 0.55, -0.9).normalized() * r * 3.4, c, Vector3.UP)
		await _shot(k, out)
		cam.look_at_from_position(c + Vector3(0.9, 0.9, 0.6).normalized() * r * 3.4, c, Vector3.UP)
		await _shot(k + "_b", out)
		m.queue_free()
	quit(0)
