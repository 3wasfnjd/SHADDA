class_name GameDirector
extends Node3D
## Runs one SHADDA match inside the player's room: lays out the station and
## the rifts around the player, schedules waves, scores captures, and decides
## win/lose. Everything is placed relative to the headset at setup time; there
## is no room scan yet, so rifts float where real walls usually are.

enum Phase { SETUP, PLAYING, WON, LOST }

const STATION_DISTANCE := 1.15
const STATION_ANGLE := 28.0          # station sits front-right so raiders have to cross the room
const RIFT_DISTANCE := 3.0
const RIFT_ANGLES := [-72.0, 0.0, 72.0]
const SCORE_CAPTURE := 100
const SCORE_RESCUE := 60
const SCORE_CELL_BONUS := 150

var phase: int = Phase.SETUP
var head: XRCamera3D
var gauntlets: Array[Gauntlet] = []
var station: Station
var rifts: Array[Rift] = []
var robots: Array = []
var plan := RoundPlan.new()
var score: int = 0
var captures: int = 0
var match_time: float = 0.0
var font: Font

var _scenes: Dictionary = {}
var _status: Label3D
var _banner: Label3D
var _banner_time: float = 0.0
var _capture_ring: MeshInstance3D
var _rift_cursor: int = 0
var _last_wave: int = -2
var _result_time: float = 0.0


func build(camera: XRCamera3D, hands: Array[Gauntlet], ui_font: Font) -> void:
	head = camera
	gauntlets = hands
	font = ui_font
	_scenes = {
		"station": load("res://assets/models/runtime/shadda_battery_station.glb"),
		"cell": load("res://assets/models/runtime/shadda_power_cell.glb"),
		"rift": load("res://assets/models/runtime/shadda_rift_small.glb"),
		"A": load("res://assets/models/runtime/shadda_robot_A.glb"),
		"B": load("res://assets/models/runtime/shadda_robot_B.glb"),
		"C": load("res://assets/models/runtime/shadda_robot_C.glb"),
		"D": load("res://assets/models/runtime/shadda_robot_D.glb"),
	}
	station = Station.create(_scenes["station"])
	add_child(station)
	station.install_cells(_scenes["cell"], self)
	for i in range(RIFT_ANGLES.size()):
		var rift := Rift.create(_scenes["rift"])
		add_child(rift)
		rifts.append(rift)
	_capture_ring = Neon.make_floor_ring(Neon.CYAN, Robot.CAPTURE_RADIUS * 2.0, 0.3)
	_capture_ring.position.y = 0.004
	add_child(_capture_ring)
	_status = _make_label(26)
	add_child(_status)
	_banner = _make_label(44)
	add_child(_banner)
	for g in gauntlets:
		g.director = self
	place_layout()
	_set_banner("شدّة  ·  SHADDA\nاضغط A أو X لبدء الجولة\nTrigger: حبل   Grip: شدّ / إمساك   A/X: إفلات   B/Y: إعادة تمركز", 999.0)


func _make_label(size: int) -> Label3D:
	var label := Label3D.new()
	label.font = font
	label.font_size = size
	label.pixel_size = 0.0012
	label.outline_size = 10
	label.outline_modulate = Color(0, 0.05, 0.1, 0.9)
	label.modulate = Neon.CYAN.lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.render_priority = 5
	return label


## Lays the arena out in front of wherever the player is looking right now.
func place_layout() -> void:
	var forward := -head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var feet := Vector3(head.global_position.x, 0.0, head.global_position.z)
	station.global_position = feet + forward.rotated(Vector3.UP, deg_to_rad(-STATION_ANGLE)) * STATION_DISTANCE
	station.look_at(feet, Vector3.UP, true)
	station.rotation.x = 0.0
	station.rotation.z = 0.0
	for i in range(rifts.size()):
		var direction := forward.rotated(Vector3.UP, deg_to_rad(RIFT_ANGLES[i]))
		var rift := rifts[i]
		rift.global_position = feet + direction * RIFT_DISTANCE
		rift.look_at(feet, Vector3.UP, true)
		rift.rotation.x = 0.0
		rift.rotation.z = 0.0
	_status.global_position = station.global_position + Vector3(0, 0.78, 0)
	_refresh_status()


func start_match() -> void:
	for robot in robots:
		if is_instance_valid(robot):
			robot.queue_free()
	robots.clear()
	for g in gauntlets:
		g.release_everything()
	for i in range(station.cells.size()):
		var cell := station.cells[i]
		cell.charge = 1.0
		station.dock(cell, i)
	for rift in rifts:
		rift.close()
	score = 0
	captures = 0
	match_time = 0.0
	_last_wave = -2
	plan.start()
	phase = Phase.PLAYING
	_set_banner("الجولة الأولى تبدأ!\nاسحب الروبوتات إلى حلقتك لتدميرها", 3.5)


func on_button(action: StringName, hand_index: int) -> void:
	if action == &"by_button":
		if phase != Phase.PLAYING:
			place_layout()
		return
	if action == &"ax_button":
		match phase:
			Phase.SETUP:
				start_match()
			Phase.WON, Phase.LOST:
				if _result_time > 1.5:
					start_match()
			Phase.PLAYING:
				if hand_index < gauntlets.size():
					gauntlets[hand_index].release_everything()


func _process(delta: float) -> void:
	if head == null:
		return
	var feet := Vector3(head.global_position.x, 0.0, head.global_position.z)
	_capture_ring.global_position = feet + Vector3(0, 0.004, 0)
	_banner_time = maxf(0.0, _banner_time - delta)
	if _banner_time <= 0.0 and _banner.visible and phase == Phase.PLAYING:
		_banner.visible = false
	if _banner.visible:
		var forward := -head.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			_banner.global_position = head.global_position + forward.normalized() * 1.4 + Vector3(0, -0.05, 0)
	var ring_pulse := 0.25 + 0.15 * sin(match_time * 3.0)
	var tethered := false
	for robot in robots:
		if is_instance_valid(robot) and not robot.tethers.is_empty():
			tethered = true
	Neon.set_halo_color(_capture_ring, Neon.CYAN if not tethered else Neon.WHITE.lerp(Neon.CYAN, 0.4), ring_pulse + (0.35 if tethered else 0.0))
	match phase:
		Phase.PLAYING:
			match_time += delta
			_tick_waves(delta)
			_refresh_status()
			_check_end()
		Phase.WON, Phase.LOST:
			_result_time += delta


func _tick_waves(delta: float) -> void:
	if plan.wave_index != _last_wave and plan.phase == RoundPlan.Phase.WAVE:
		_last_wave = plan.wave_index
		for rift in rifts:
			rift.warn()
		_set_banner(plan.wave_name(), 3.0)
	var spawns := plan.tick(delta)
	for kind in spawns:
		_spawn(kind)
	if plan.phase == RoundPlan.Phase.REST:
		for rift in rifts:
			if rift.is_open():
				rift.close()


func _spawn(kind: String) -> void:
	var rift := rifts[_rift_cursor % rifts.size()]
	_rift_cursor += 1
	rift.open()
	var robot := Robot.create(kind, _scenes[kind])
	add_child(robot)
	robot.configure(rift, station, Callable(self, "capture_center"))
	robot.defeated.connect(_on_robot_defeated)
	robot.escaped.connect(_on_robot_escaped)
	robot.cell_taken.connect(_on_cell_taken)
	robot.cell_dropped.connect(_on_cell_dropped)
	robots.append(robot)


func capture_center() -> Vector3:
	return Vector3(head.global_position.x, 0.0, head.global_position.z)


func _on_robot_defeated(robot: Robot) -> void:
	score += SCORE_CAPTURE
	captures += 1
	plan.robot_gone()
	robots.erase(robot)
	_set_banner("إسقاط!  +%d" % SCORE_CAPTURE, 1.2)


func _on_robot_escaped(robot: Robot, with_cell: bool) -> void:
	plan.robot_gone()
	robots.erase(robot)
	if with_cell:
		_set_banner("هربت ببطارية!  تبقّى %d" % (station.cells.size() - station.lost_count()), 2.5)


func _on_cell_taken(_robot: Robot) -> void:
	_set_banner("سرقة! أوقفه قبل الفجوة", 1.8)


func _on_cell_dropped(_robot: Robot, cell: Node3D) -> void:
	var drop := cell.global_position + Vector3(0, 0.1, 0)
	(cell as PowerCell).drop_at(drop)
	_set_banner("أسقطها! التقطها بـ Grip وأعدها للمحطة", 2.2)


func on_cell_docked(_cell: PowerCell) -> void:
	score += SCORE_RESCUE
	_set_banner("استعادة!  +%d" % SCORE_RESCUE, 1.2)


func _check_end() -> void:
	if station.lost_count() >= station.cells.size():
		phase = Phase.LOST
		_result_time = 0.0
		for rift in rifts:
			rift.close()
		_set_banner("انتهت المباراة — سُرقت كل البطاريات\nالنتيجة %d · إسقاطات %d\nاضغط A أو X لإعادة اللعب" % [score, captures], 999.0)
		return
	if plan.finished() and robots.is_empty():
		phase = Phase.WON
		_result_time = 0.0
		var bonus := station.docked_count() * SCORE_CELL_BONUS
		score += bonus
		for rift in rifts:
			rift.close()
		_set_banner("انتصار! الغرفة آمنة\nالنتيجة %d · إسقاطات %d · مكافأة البطاريات %d\nاضغط A أو X لإعادة اللعب" % [score, captures, bonus], 999.0)


func _refresh_status() -> void:
	var wave := plan.wave_index + 1 if plan.wave_index >= 0 else 0
	var line := "البطاريات %d/%d" % [station.docked_count(), station.cells.size()]
	if phase == Phase.PLAYING:
		if plan.phase == RoundPlan.Phase.REST:
			line += "   ·   الجولة التالية خلال %d ث" % int(ceil(plan.rest_remaining()))
		else:
			line += "   ·   الجولة %d/%d" % [wave, plan.wave_count()]
		line += "\nالنتيجة %d" % score
	else:
		line += "\nSHADDA"
	_status.text = line
	_status.global_position = station.global_position + Vector3(0, 0.78, 0)


func _set_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_time = seconds


func all_cells() -> Array:
	return station.cells


func update_hands(delta: float, triggers: Array, grips: Array) -> void:
	for i in range(gauntlets.size()):
		gauntlets[i].update(delta, triggers[i], grips[i], robots, station.cells, station, phase == Phase.PLAYING)
