extends SceneTree
func _initialize() -> void:
	var bad := 0
	for dir in ["res://systems", "res://tests", "res://tools"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") and f != "_parse.gd":
				var s = load(dir + "/" + f)
				if s == null or not (s as Script).can_instantiate():
					print("BAD ", f)
					bad += 1
	print("parsed, bad=", bad)
	quit(bad)
