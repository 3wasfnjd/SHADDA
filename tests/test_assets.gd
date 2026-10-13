extends SceneTree
## Every runtime GLB loads, exposes the nodes the game code depends on, and
## stays inside the Quest triangle budget. Also exercises Neon.restyle.
const BUDGET := {
	"shadda_robot_A": 45000, "shadda_robot_B": 45000, "shadda_robot_C": 45000, "shadda_robot_D": 45000,
	"shadda_battery_station": 15000, "shadda_power_cell": 9000, "shadda_rift": 9000,
	"shadda_gauntlet_left": 16000, "shadda_gauntlet_right": 16000,
}
const REQUIRED := {
	"shadda_robot_A": ["TetherPoint_Crown", "GrabPoint_R", "FACE_Eye_L"],
	"shadda_robot_B": ["TetherPoint_Crown", "GrabPoint_Backpack_R", "FACE_Eye_R"],
	"shadda_robot_C": ["TetherPoint_Crown", "GrabPoint_R", "FACE_Eye_L"],
	"shadda_robot_D": ["TetherPoint_Crown", "GrabPoint_Arm_R", "FACE_Eye_L"],
	"shadda_battery_station": ["BatterySocket_01", "BatterySocket_02", "BatterySocket_03", "DISPLAY_Count_seg_a", "DISPLAY_Count_seg_g", "DISPLAY_Slot_03_Level"],
	"shadda_power_cell": ["GrabPoint", "CORE_Level_01", "CORE_Level_04", "CORE_Helix_0", "CORE_EnergySymbol"],
	"shadda_rift": ["SpawnInside", "SpawnOutside", "SpawnThreshold"],
	"shadda_gauntlet_left": ["TetherOrigin", "AimAxis", "GripAnchor"],
	"shadda_gauntlet_right": ["TetherOrigin", "AimAxis", "GripAnchor"],
}
const ANIMS := {
	"shadda_gauntlet_left": ["Open", "Fist", "Aim", "TetherGrip", "Pull", "Release"],
	"shadda_rift": ["Portal_Sequence"],
}
func _initialize() -> void:
	var total := 0
	for name in BUDGET.keys():
		var packed: PackedScene = load("res://assets/models/runtime/%s.glb" % name)
		assert(packed != null, name + " did not load")
		var inst := packed.instantiate()
		var tris := Neon.count_triangles(inst)
		assert(tris > 0 and tris <= BUDGET[name], "%s has %d triangles" % [name, tris])
		total += tris
		for required in REQUIRED[name]:
			assert(inst.find_child(required, true, false) != null, "%s missing %s" % [name, required])
		if ANIMS.has(name):
			var player := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			for clip in ANIMS[name]:
				assert(player.has_animation(clip), "%s missing clip %s" % [name, clip])
		var restyled := Neon.restyle(inst)
		assert(restyled.size() > 0, name + " has no emitter materials to restyle")
		if name.begins_with("shadda_robot"):
			var eye := inst.find_child("FACE_Eye_L", true, false) as MeshInstance3D
			assert(eye.mesh.get_blend_shape_count() == 3)
		inst.free()
	# Worst case on screen: 3 raiders (A-class), station, 3 cells, 3 rifts, 2 gauntlets.
	var worst := BUDGET["shadda_robot_A"] * 3 + BUDGET["shadda_battery_station"] + BUDGET["shadda_power_cell"] * 3 + BUDGET["shadda_rift"] * 3 + BUDGET["shadda_gauntlet_left"] * 2
	assert(worst < 260000, "worst-case scene %d triangles" % worst)
	print("PASS: assets — 9 runtime GLBs, %d triangles total, worst-case frame budget %d" % [total, worst])
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
