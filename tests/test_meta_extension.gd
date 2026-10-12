extends SceneTree
func _initialize() -> void:
	if not ClassDB.class_exists("OpenXRFbPassthroughExtension"):
		push_error("The native Meta passthrough extension did not load")
		quit(1)
		return
	print("PASS: native Meta passthrough extension registered")
	quit(0)
