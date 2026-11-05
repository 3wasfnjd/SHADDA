class_name Menus
extends Node3D
## Every screen of the game on floating boards: main menu, campaign map,
## mission briefing, hangar, settings, controls, pause, debrief and failure.
## Pointed at with a laser from the flight-stick hand; the trigger clicks.
## Runs while the game is paused (process_mode ALWAYS).

signal settings_changed

var battle = null
var head: Node3D
var panel: Panel3D
var screen: String = ""
var args: Dictionary = {}
var _laser: MeshInstance3D
var _cursor: MeshInstance3D
var _was_held: bool = false
var _last_hover = null
var _anchor: Transform3D
var _anchored: bool = false
var _reset_armed: bool = false
var _hint: Label3D
var _pops: Array = []        # debrief star pop-ins
var _pop_t: float = 0.0
var hand: XRController3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_laser = Toon.add(self, Toon.can(0.0012, 0.0012, 1.0, 6), Toon.flat(Color(1.0, 0.85, 0.4, 0.55)))
	_laser.top_level = true
	_laser.visible = false
	_cursor = Toon.add(self, Toon.torus(0.008, 0.0025, 16), Toon.flat(Color(1.0, 0.9, 0.5, 0.95)))
	_cursor.top_level = true
	_cursor.visible = false


func is_open() -> bool:
	return panel != null and is_instance_valid(panel)


## Opens a screen. Boards appear ~1 m in front of the eyes, a little low.
func open(name: String, a: Dictionary = {}, keep_place: bool = false) -> void:
	if not keep_place or not _anchored:
		_place()
	close(true)
	if name != screen or not keep_place:
		_reset_armed = false
	screen = name
	args = a
	_pops.clear()
	match name:
		"main": _main()
		"missions": _missions()
		"brief": _brief(int(a.get("index", 0)))
		"hangar": _hangar(str(a.get("tab", "upgrades")))
		"settings": _settings(str(a.get("tab", "game")))
		"controls": _controls()
		"pause": _pause()
		"debrief": _debrief(a)
		"failed": _failed(a)
	if panel:
		panel.transform = _anchor
		panel.scale = Vector3.ONE * 0.92


func close(swapping: bool = false) -> void:
	if is_open():
		panel.queue_free()
	panel = null
	_hint = null
	if not swapping:
		screen = ""
		_laser.visible = false
		_cursor.visible = false


func refresh() -> void:
	open(screen, args, true)


func _place() -> void:
	var hp := head.global_position if head else Vector3(0, 1.6, 0)
	var f := -head.global_basis.z if head else Vector3.FORWARD
	f.y = 0.0
	f = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
	var at := hp + f * 1.0 + Vector3(0, -0.14, 0)
	# Tilt the board back a little so it faces the eyes.
	var to_eye := (hp - at).normalized()
	_anchor = Transform3D(Basis.looking_at(-to_eye, Vector3.UP), at)
	_anchored = true


func recenter() -> void:
	if is_open():
		_place()
		panel.transform = _anchor


## Per frame: the pointing hand's aim ray and trigger value.
func update(delta: float, origin: Vector3, dir: Vector3, trigger: float) -> void:
	_tick_pops(delta)
	if not is_open():
		_laser.visible = false
		_cursor.visible = false
		return
	var held := trigger > 0.6
	var pressed := held and not _was_held
	_was_held = trigger > 0.35 if _was_held else held
	var before = panel.hovered
	var p = panel.pointer(origin, dir, pressed, held)
	if panel == null or not is_instance_valid(panel):
		return
	if pressed and not panel.hovered.is_empty():
		_click()
	if panel.hovered != before and not panel.hovered.is_empty():
		_tick_haptic(0.15, 0.02)
		if _hint and panel.hovered.has("hint"):
			_hint.text = panel.hovered.hint
	var end := origin + dir * 1.6
	if p != null:
		end = panel.global_transform * Vector3(p.x, p.y, 0.006)
		_cursor.visible = true
		_cursor.global_position = end
		_cursor.global_basis = panel.global_basis * Basis(Vector3.RIGHT, PI * 0.5)
		_cursor.scale = Vector3.ONE * (1.3 if panel.hovering_something() else 1.0)
	else:
		_cursor.visible = false
	var len := origin.distance_to(end)
	_laser.visible = len > 0.02
	if _laser.visible:
		var mid := (origin + end) * 0.5
		var d := (end - origin).normalized()
		var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
		_laser.global_transform = Transform3D(Basis.looking_at(d, up) * Basis(Vector3.RIGHT, PI * 0.5), mid)
		_laser.scale = Vector3(1, len, 1)


func _click() -> void:
	if battle:
		battle.cue("click", panel.global_position, 2.0)
	_tick_haptic(0.4, 0.04)


func _tick_haptic(amp: float, dur: float) -> void:
	if hand and hand.get_is_active() and bool(Profile.get_s("haptics")):
		hand.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


func _new(w: float, h: float, title: String = "", header: Color = Panel3D.HEADER) -> Panel3D:
	panel = Panel3D.new()
	add_child(panel)
	panel.setup(w, h, title, header)
	return panel


func _wallet(p: Panel3D, pos: Vector2) -> void:
	p.icon("coin", Vector2(pos.x + p.sx(-0.115), pos.y), 0.032, Panel3D.GOLD)
	p.label("%d" % int(Profile.progress.coins), Vector2(pos.x + p.sx(-0.06), pos.y), 50, Panel3D.GOLD, "bold")
	p.icon("star", Vector2(pos.x + p.sx(0.04), pos.y), 0.032, Panel3D.GOLD)
	p.label("%d/%d" % [Profile.total_stars(), Missions.LIST.size() * 3], Vector2(pos.x + p.sx(0.1), pos.y), 50, Panel3D.TEXT, "bold")


# --- screens --------------------------------------------------------------------------------

func _main() -> void:
	var p := _new(0.74, 0.64)
	p.label(Lang.t("game"), Vector2(0, 0.2), 310, Panel3D.GOLD, "title")
	p.label("SAQR" if Lang.code() == "ar" else "صقر", Vector2(0, 0.105), 60, Panel3D.HEADER.lightened(0.25), "title")
	p.label(Lang.t("tagline"), Vector2(0, 0.06), 46, Panel3D.DIM)
	var y := 0.0
	var bs := Vector2(0.44, 0.066)
	p.button(Lang.t("campaign"), Vector2(0, y), bs, func(): open("missions"), "primary", "play", 56)
	p.button(Lang.t("hangar"), Vector2(0, y - 0.078), bs, func(): open("hangar"), "normal", "plane")
	p.button(Lang.t("settings"), Vector2(0, y - 0.156), bs, func(): open("settings"), "normal", "gear")
	p.button(Lang.t("controls"), Vector2(0, y - 0.228), Vector2(0.44, 0.054), func(): open("controls"), "ghost", "stick", 44)
	_wallet(p, Vector2(0, -0.29))


func _missions() -> void:
	var p := _new(1.0, 0.68, Lang.t("campaign"))
	var ids := Missions.ids()
	for i in range(Missions.LIST.size()):
		var m: Dictionary = Missions.LIST[i]
		var col := i % 4
		var row := i / 4
		var c := Vector2(p.sx(-0.351 + col * 0.234), 0.11 - row * 0.235)
		var open_ok := Profile.unlocked(i, ids)
		var idx := i
		var w := p.button("", c, Vector2(0.218, 0.215), func(): open("brief", {"index": idx}), "normal", "", 40, open_ok)
		var node: Node3D = w.node
		w.hint = Missions.text(m, "title") if open_ok else Lang.t("locked_hint")
		p.label(str(i + 1), Vector2(p.sx(-0.08), 0.075), 70, Panel3D.GOLD if open_ok else Panel3D.DIM, "title", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
		if open_ok:
			p.icon(m.icon, Vector2(0, 0.04), 0.06, Panel3D.TEXT, node)
			p.label(Missions.text(m, "title"), Vector2(0, -0.03), 46, Panel3D.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
			var n := Profile.stars_of(m.id)
			for k in range(3):
				p.icon("star", Vector2((k - 1) * 0.03, -0.075), 0.026, Panel3D.GOLD if k < n else Color(0.3, 0.33, 0.38), node)
			if m.get("dusk", false):
				p.label("☾", Vector2(p.sx(0.08), 0.075), 50, Panel3D.DIM, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
		else:
			p.icon("lock", Vector2(0, 0.01), 0.07, Panel3D.DIM, node)
			p.label(Lang.t("locked"), Vector2(0, -0.06), 40, Panel3D.DIM, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
	p.button(Lang.t("back"), Vector2(p.sx(-0.38), -0.29), Vector2(0.18, 0.06), func(): open("main"), "ghost", "back", 44)
	_wallet(p, Vector2(p.sx(0.3), -0.29))
	_hint = p.label("", Vector2(0, -0.29), 42, Panel3D.DIM)


func _brief(i: int) -> void:
	var m := Missions.get_m(i)
	var p := _new(0.92, 0.66, "%s %d · %s" % [Lang.t("mission"), i + 1, Missions.text(m, "title")])
	p.label(Missions.text(m, "brief"), Vector2(p.sx(-0.43), 0.15), 44, Panel3D.TEXT, "body", p.start_align(), 0.56)
	p.label(Lang.t("objectives"), Vector2(p.sx(-0.43), 0.045), 50, Panel3D.GOLD, "bold", p.start_align(), 0.56)
	var have := Profile.stars_of(m.id)
	var lines := [Lang.t("obj_complete"), Missions.text(m, "s2"), Missions.text(m, "s3")]
	for k in range(3):
		var y := -0.015 - k * 0.058
		for st in range(k + 1):
			p.icon("star", Vector2(p.sx(-0.415 + st * 0.03), y), 0.026, Panel3D.GOLD if have > k else Color(0.36, 0.4, 0.46))
		p.label(lines[k], Vector2(p.sx(-0.31), y), 42, Panel3D.TEXT if have <= k else Panel3D.DIM, "body", p.start_align(), 0.4)
	# Loadout box on the other side.
	var bx := p.sx(0.31)
	Panel3D.shape(p, Panel3D.rrect(0.24, 0.36, 0.02), Vector3(bx, 0.03, 0.0), Color(0.11, 0.14, 0.2), 0.002)
	p.label(Lang.t("loadout"), Vector2(bx, 0.18), 46, Panel3D.GOLD, "bold")
	var gun: String = Profile.progress.get("gun", "twin")
	var sp: String = Profile.progress.get("special", "bombs")
	p.icon(gun, Vector2(bx + p.sx(-0.085), 0.12), 0.04, Panel3D.TEXT)
	p.label(Lang.t(gun), Vector2(bx + p.sx(0.02), 0.12), 38, Panel3D.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER)
	p.icon(sp, Vector2(bx + p.sx(-0.085), 0.065), 0.04, Panel3D.TEXT)
	p.label(Lang.t(sp), Vector2(bx + p.sx(0.02), 0.065), 38, Panel3D.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER)
	var ty := 0.01
	for tr in Profile.TRACKS:
		p.label(Lang.t(tr), Vector2(bx + p.sx(-0.03), ty), 34, Panel3D.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
		for k in range(3):
			Panel3D.shape(p, Panel3D.rrect(0.014, 0.014, 0.004), Vector3(bx + p.sx(0.055 + k * 0.02), ty, 0.003), Panel3D.BTN_HOVER if k < Profile.level(tr) else Color(0.25, 0.28, 0.34), 0.002)
		ty -= 0.036
	var best := int(Profile.mission(m.id).get("best", 0))
	if best > 0:
		p.label("%s  %d" % [Lang.t("best"), best], Vector2(bx, -0.12), 38, Panel3D.DIM)
	var diff := str(Profile.get_s("difficulty"))
	p.label("%s: %s" % [Lang.t("difficulty"), Lang.t(diff)], Vector2(p.sx(-0.43), -0.19), 38, Panel3D.DIM, "body", p.start_align(), 0.56)
	p.button(Lang.t("start"), Vector2(p.sx(-0.24), -0.27), Vector2(0.3, 0.075), func(): _start(i), "primary", "play", 60)
	p.button(Lang.t("hangar"), Vector2(p.sx(0.06), -0.27), Vector2(0.2, 0.065), func(): open("hangar", {"back": "brief", "index": i}), "normal", "plane", 44)
	p.button(Lang.t("back"), Vector2(p.sx(0.31), -0.27), Vector2(0.17, 0.065), func(): open("missions"), "ghost", "back", 44)


func _start(i: int) -> void:
	if not bool(Profile.progress.get("seen_controls", false)):
		Profile.progress.seen_controls = true
		Profile.save()
		open("controls", {"then": i})
		return
	close()
	battle.start_mission(i)


func _hangar(tab: String) -> void:
	var p := _new(1.04, 0.74, Lang.t("hangar"))
	_wallet(p, Vector2(p.sx(-0.36), 0.225))
	var tabs := [["upgrades", Lang.t("upgrades")], ["weapons", Lang.t("weapons")]]
	p.choice(Vector2(p.sx(0.27), 0.225), Vector2(0.4, 0.06), tabs, tab, func(v): open("hangar", {"tab": v, "back": args.get("back", ""), "index": args.get("index", 0)}, true))
	if tab == "upgrades":
		var y := 0.13
		for tr in Profile.TRACKS:
			var x0 := p.sx(-0.44)
			p.icon(tr, Vector2(x0, y), 0.05, Panel3D.TEXT)
			p.label(Lang.t(tr), Vector2(p.sx(-0.4), y + 0.016), 50, Panel3D.TEXT, "bold", p.start_align(), 0.42)
			p.label(Lang.t(tr + "_d"), Vector2(p.sx(-0.4), y - 0.022), 36, Panel3D.DIM, "body", p.start_align(), 0.42)
			var lv := Profile.level(tr)
			for k in range(3):
				Panel3D.shape(p, Panel3D.rrect(0.03, 0.03, 0.008), Vector3(p.sx(0.1 + k * 0.04), y, 0.003), Panel3D.BTN_HOVER if k < lv else Color(0.25, 0.28, 0.34), 0.002)
			var price := Profile.price(tr)
			var track: String = tr
			if price < 0:
				p.button(Lang.t("maxed"), Vector2(p.sx(0.36), y), Vector2(0.2, 0.065), func(): pass, "ghost", "check", 44, false)
			else:
				var w := p.button("%d" % price, Vector2(p.sx(0.36), y), Vector2(0.2, 0.065), func(): _buy(track), "primary", "coin", 48, Profile.can_buy(tr))
				w.hint = Lang.t(tr + "_d")
			p.divider(y - 0.048, 0.94)
			y -= 0.097
	else:
		p.label(Lang.t("gun_slot"), Vector2(p.sx(-0.47), 0.145), 44, Panel3D.GOLD, "bold", p.start_align(), 0.5)
		for k in range(Profile.GUNS.size()):
			_item_card(p, Profile.GUNS[k], Vector2(p.sx(-0.32 + k * 0.32), 0.075), Vector2(0.3, 0.1))
		p.label(Lang.t("special_slot"), Vector2(p.sx(-0.47), -0.015), 44, Panel3D.GOLD, "bold", p.start_align(), 0.5)
		var items := Profile.SPECIALS + ["flares"]
		for k in range(items.size()):
			_item_card(p, items[k], Vector2(p.sx(-0.384 + k * 0.192), -0.1), Vector2(0.182, 0.13))
	var back_to := str(args.get("back", ""))
	var idx := int(args.get("index", 0))
	p.button(Lang.t("back"), Vector2(p.sx(-0.4), -0.315), Vector2(0.18, 0.06), func(): open("brief", {"index": idx}) if back_to == "brief" else open("main"), "ghost", "back", 44)
	_hint = p.label(Lang.t("c_point"), Vector2(p.sx(0.1), -0.315), 38, Panel3D.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.62)


func _item_card(p: Panel3D, item: String, c: Vector2, s: Vector2) -> void:
	var owned := Profile.owns(item)
	var on := Profile.equipped(item) or (item == "flares" and owned)
	var price := Profile.price(item)
	var w := p.button("", c, s, func(): _buy_or_equip(item), "normal", "", 40, owned or Profile.can_buy(item))
	w.hint = Lang.t(item + "_d")
	if on:
		w.selected = true
		w.color = Color(0.2, 0.42, 0.3)
	var node: Node3D = w.node
	var tall := s.y > 0.11
	p.icon(item, Vector2(0, 0.03) if tall else Vector2(p.sx(-s.x * 0.5 + 0.04), 0.012), 0.04, Panel3D.TEXT, node)
	p.label(Lang.t(item), Vector2(0, -0.012) if tall else Vector2(p.sx(0.02), 0.016), 38, Panel3D.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)
	var state := Lang.t("equipped") if on else (Lang.t("equip") if owned else "%d %s" % [price, Lang.t("coins")])
	var col := Color(0.5, 1.0, 0.6) if on else (Panel3D.TEXT if owned else Panel3D.GOLD)
	p.label(state, Vector2(0, -0.048) if tall else Vector2(p.sx(0.02), -0.024), 34, col, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.0, node)


func _buy(item: String) -> void:
	if Profile.buy(item):
		if battle:
			battle.cue("coin", panel.global_position, 3.0)
	refresh()


func _buy_or_equip(item: String) -> void:
	if Profile.owns(item):
		Profile.equip(item)
	elif not Profile.buy(item):
		return
	elif battle:
		battle.cue("coin", panel.global_position, 3.0)
	refresh()


func _settings(tab: String) -> void:
	var p := _new(1.02, 0.76, Lang.t("settings"))
	var tabs := [["game", Lang.t("tab_game")], ["controls", Lang.t("tab_controls")], ["graphics", Lang.t("tab_graphics")], ["audio", Lang.t("tab_audio")]]
	p.choice(Vector2(0, 0.235), Vector2(0.9, 0.06), tabs, tab, func(v): open("settings", {"tab": v, "back": args.get("back", "main")}, true), 46)
	var rows: Array = []
	match tab:
		"game":
			rows.append([Lang.t("language"), "choice", "lang", [["ar", "العربية"], ["en", "English"]]])
			rows.append([Lang.t("difficulty"), "choice", "difficulty", [["easy", Lang.t("easy")], ["normal", Lang.t("normal")], ["hard", Lang.t("hard")]]])
			rows.append(["", "note", Lang.t("diff_%s_d" % str(Profile.get_s("difficulty")))])
			rows.append([Lang.t("reset_progress"), "reset"])
		"controls":
			rows.append([Lang.t("stick_hand"), "choice", "hand", [["right", Lang.t("right")], ["left", Lang.t("left")]]])
			rows.append([Lang.t("invert"), "choice", "invert", [[false, Lang.t("off")], [true, Lang.t("on")]]])
			rows.append([Lang.t("sensitivity"), "slider", "sensitivity", 0.6, 1.4])
			rows.append([Lang.t("leveler"), "choice", "leveler", [[false, Lang.t("off")], [true, Lang.t("on")]]])
			rows.append([Lang.t("aim_assist"), "choice", "aim_assist", [[false, Lang.t("off")], [true, Lang.t("on")]]])
			rows.append([Lang.t("haptics"), "choice", "haptics", [[false, Lang.t("off")], [true, Lang.t("on")]]])
		"graphics":
			rows.append([Lang.t("quality"), "choice", "quality", [["balanced", Lang.t("balanced")], ["high", Lang.t("high")], ["ultra", Lang.t("ultra")]]])
			rows.append(["", "note", Lang.t("quality_d")])
			rows.append([Lang.t("refresh"), "choice", "refresh", [[72, "72 Hz"], [90, "90 Hz"], [120, "120 Hz"]]])
			rows.append([Lang.t("effects"), "choice", "effects", [["medium", Lang.t("medium")], ["high", Lang.t("high")]]])
		"audio":
			rows.append([Lang.t("music"), "slider", "music", 0.0, 1.0])
			rows.append([Lang.t("sfx"), "slider", "sfx", 0.0, 1.0])
	var y := 0.14
	for r in rows:
		var kind: String = r[1]
		if r[0] != "":
			p.label(r[0], Vector2(p.sx(-0.46), y), 48, Panel3D.TEXT, "bold", p.start_align(), 0.4)
		var cx := p.sx(0.2)
		match kind:
			"choice":
				var key: String = r[2]
				p.choice(Vector2(cx, y), Vector2(0.5, 0.062), r[3], Profile.get_s(key), func(v): _set_opt(key, v), 44)
			"slider":
				var key2: String = r[2]
				var lo: float = r[3]
				var hi: float = r[4]
				var v0 := (float(Profile.get_s(key2)) - lo) / (hi - lo)
				p.slider(Vector2(cx - p.sx(0.04), y), Vector2(0.38, 0.03), v0, func(v): _set_live(key2, lo + v * (hi - lo)))
			"note":
				p.label(r[2], Vector2(cx, y + 0.02), 36, Panel3D.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.52)
				y += 0.03
			"reset":
				var w := p.button(Lang.t("confirm_reset") if _reset_armed else Lang.t("reset_progress"), Vector2(cx, y), Vector2(0.36, 0.062), _reset, "normal", "retry", 42)
				if _reset_armed:
					w.color = Panel3D.PRIMARY
		y -= 0.085
	var back_to := str(args.get("back", "main"))
	p.button(Lang.t("back"), Vector2(p.sx(-0.4), -0.325), Vector2(0.18, 0.06), func(): open(back_to, {}, true), "ghost", "back", 44)
	p.label("SAQR v1.0 · ABODEN GAMES", Vector2(p.sx(0.3), -0.325), 32, Color(Panel3D.DIM, 0.6))


func _set_opt(key: String, v) -> void:
	Profile.set_s(key, v)
	settings_changed.emit()
	refresh()


func _set_live(key: String, v) -> void:
	Profile.settings[key] = v
	settings_changed.emit()
	if not panel or panel.dragging.is_empty():
		Profile.save()


func _reset() -> void:
	if _reset_armed:
		Profile.reset_progress()
		_reset_armed = false
	else:
		_reset_armed = true
	refresh()


func _controls() -> void:
	var p := _new(0.98, 0.7, Lang.t("controls"))
	var left_hand := str(Profile.get_s("hand")) == "left"
	var throttle_col := [Lang.t("c_throttle"), Lang.t("c_rudder"), Lang.t("c_boost"), Lang.t("c_brake"), Lang.t("c_menu")]
	var stick_col := [Lang.t("c_pitch"), Lang.t("c_roll"), Lang.t("c_guns"), Lang.t("c_rockets"), Lang.t("c_a"), Lang.t("c_b")]
	var cols := [[Lang.t("c_left"), stick_col if left_hand else throttle_col], [Lang.t("c_right"), throttle_col if left_hand else stick_col]]
	for ci in range(2):
		var x := -0.24 if ci == 0 else 0.24      # physical left/right, never mirrored
		Panel3D.shape(p, Panel3D.rrect(0.44, 0.36, 0.02), Vector3(x, 0.035, 0.0), Color(0.11, 0.14, 0.2), 0.002)
		p.icon("stick", Vector2(x, 0.185), 0.045, Panel3D.GOLD)
		p.label(cols[ci][0], Vector2(x, 0.14), 50, Panel3D.GOLD, "bold")
		var y := 0.09
		for line in cols[ci][1]:
			p.label(line, Vector2(x, y), 38, Panel3D.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.42)
			y -= 0.045
	p.label(Lang.t("c_takeoff"), Vector2(0, -0.185), 36, Panel3D.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.84)
	p.label(Lang.t("c_land"), Vector2(0, -0.24), 36, Panel3D.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.84)
	if args.has("then"):
		var i := int(args.then)
		p.button(Lang.t("start"), Vector2(0, -0.305), Vector2(0.3, 0.065), func(): close(); battle.start_mission(i), "primary", "play", 54)
	else:
		p.button(Lang.t("back"), Vector2(0, -0.305), Vector2(0.2, 0.06), func(): open(str(args.get("back", "main")), {}, true), "ghost", "back", 44)


func _pause() -> void:
	var p := _new(0.5, 0.52, Lang.t("paused"))
	var bs := Vector2(0.38, 0.068)
	p.button(Lang.t("resume"), Vector2(0, 0.12), bs, func(): battle.resume(), "primary", "play", 52)
	p.button(Lang.t("restart"), Vector2(0, 0.035), bs, func(): battle.restart_mission(), "normal", "retry", 46)
	p.button(Lang.t("settings"), Vector2(0, -0.05), bs, func(): open("settings", {"back": "pause"}, true), "normal", "gear", 46)
	p.button(Lang.t("controls"), Vector2(0, -0.135), bs, func(): open("controls", {"back": "pause"}, true), "normal", "stick", 46)
	p.button(Lang.t("quit_menu"), Vector2(0, -0.215), bs, func(): battle.quit_to_menu(), "ghost", "home", 44)


func _debrief(r: Dictionary) -> void:
	var i := int(r.get("index", 0))
	var m := Missions.get_m(i)
	var p := _new(0.82, 0.7, "", Color(0.2, 0.5, 0.3))
	var last := i >= Missions.LIST.size() - 1
	p.label(Lang.t("mission_complete"), Vector2(0, 0.27), 120, Panel3D.GOLD, "title")
	p.label("%s %d · %s" % [Lang.t("mission"), i + 1, Missions.text(m, "title")], Vector2(0, 0.19), 46, Panel3D.DIM)
	var n := int(r.get("stars", 1))
	for k in range(3):
		var st := p.icon("star", Vector2((k - 1) * 0.11, 0.1), 0.09, Panel3D.GOLD if k < n else Color(0.3, 0.33, 0.38))
		if k < n:
			st.scale = Vector3.ONE * 0.01
			_pops.append({"node": st, "at": 0.35 + k * 0.35, "done": false})
	_pop_t = 0.0
	var stats := [
		[Lang.t("score"), "%d" % int(r.get("score", 0))],
		[Lang.t("time"), "%d:%02d" % [int(r.get("time", 0.0)) / 60, int(r.get("time", 0.0)) % 60]],
		[Lang.t("kills"), "%d" % int(r.get("kills", 0))],
		[Lang.t("accuracy"), "%d%%" % int(r.get("accuracy", 0))],
		[Lang.t("hull"), "%d%%" % int(r.get("hull", 100))],
		[Lang.t("earned"), "+%d %s" % [int(r.get("coins", 0)), Lang.t("coins")]],
	]
	for k in range(stats.size()):
		var col := k % 2
		var row := k / 2
		var x := p.sx(-0.19 if col == 0 else 0.19)
		var y := 0.0 - row * 0.06
		p.label(stats[k][0], Vector2(x + p.sx(-0.06), y), 42, Panel3D.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
		p.label(stats[k][1], Vector2(x + p.sx(0.08), y), 48, Panel3D.GOLD if k == 5 else Panel3D.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER)
	if r.get("record", false):
		p.label(Lang.t("new_record"), Vector2(0, -0.175), 50, Color(1.0, 0.55, 0.2), "bold")
	if last:
		p.label(Lang.t("campaign_done"), Vector2(0, -0.175 - (0.0 if not r.get("record", false) else 0.045)), 44, Panel3D.GOLD, "bold")
	var y2 := -0.275
	var bs := Vector2(0.18, 0.065)
	if not last:
		p.button(Lang.t("next"), Vector2(p.sx(-0.29), y2), Vector2(0.22, 0.07), func(): open("brief", {"index": i + 1}), "primary", "play", 46)
	p.button(Lang.t("retry"), Vector2(p.sx(-0.08 if not last else -0.2), y2), bs, func(): close(); battle.start_mission(i), "normal", "retry", 42)
	p.button(Lang.t("hangar"), Vector2(p.sx(0.11 if not last else 0.0), y2), bs, func(): open("hangar", {"back": "brief", "index": mini(i + 1, Missions.LIST.size() - 1)}), "normal", "plane", 42)
	p.button(Lang.t("menu"), Vector2(p.sx(0.3 if not last else 0.2), y2), Vector2(0.16, 0.065), func(): battle.quit_to_menu(), "ghost", "home", 42)


func _failed(r: Dictionary) -> void:
	var i := int(r.get("index", 0))
	var crashed := str(r.get("reason", "")) == "plane_lost"
	var p := _new(0.72, 0.5, "", Color(0.45, 0.1, 0.08))
	p.label(Lang.t("plane_lost") if crashed else Lang.t("mission_failed"), Vector2(0, 0.16), 110, Color(1.0, 0.42, 0.3), "title")
	var why := Lang.t("pilot_safe") if crashed else str(r.get("why", ""))
	p.label(why, Vector2(0, 0.07), 46, Panel3D.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER, 0.64)
	p.label("%s %d · %s" % [Lang.t("mission"), i + 1, Missions.text(Missions.get_m(i), "title")], Vector2(0, 0.0), 40, Panel3D.DIM)
	var y := -0.12
	p.button(Lang.t("retry"), Vector2(p.sx(-0.2), y), Vector2(0.24, 0.072), func(): close(); battle.start_mission(i), "primary", "retry", 48)
	p.button(Lang.t("hangar"), Vector2(p.sx(0.06), y), Vector2(0.18, 0.065), func(): open("hangar", {"back": "brief", "index": i}), "normal", "plane", 42)
	p.button(Lang.t("menu"), Vector2(p.sx(0.24), y), Vector2(0.14, 0.065), func(): battle.quit_to_menu(), "ghost", "home", 42)
	if str(Profile.get_s("difficulty")) != "easy":
		p.label(Lang.t("diff_easy_d") + " — " + Lang.t("easy"), Vector2(0, -0.2), 34, Color(Panel3D.DIM, 0.8))


func _tick_pops(delta: float) -> void:
	if _pops.is_empty():
		return
	_pop_t += delta
	for pp in _pops:
		if not is_instance_valid(pp.node):
			continue
		var t: float = _pop_t - float(pp.at)
		if t < 0.0:
			continue
		if not pp.done:
			pp.done = true
			if battle:
				battle.cue("star", (pp.node as Node3D).global_position, 4.0)
			_tick_haptic(0.5, 0.06)
		var u := clampf(t / 0.3, 0.0, 1.0)
		var s := 1.0 + sin(u * PI) * 0.45 if u < 1.0 else 1.0
		(pp.node as Node3D).scale = Vector3.ONE * maxf(0.01, u) * s
