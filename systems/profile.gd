class_name Profile
extends RefCounted
## Everything that survives a restart: the player's settings and their
## campaign progress (stars, best scores, coins, hangar). One JSON file.

const VERSION := 2
static var path: String = "user://saqr_profile.json"

const DEFAULT_SETTINGS := {
	"lang": "ar",
	"music": 0.7,
	"sfx": 0.9,
	"difficulty": "normal",     # easy (plane can't be lost) · normal · hard
	"hand": "right",            # which hand holds the flight stick (pitch/roll + guns)
	"invert": false,            # invert the climb/dive axis
	"sensitivity": 1.0,         # 0.6 … 1.4
	"flight": "easy",           # easy: sticks set the attitude · pro: sticks set rates
	"leveler": true,            # wings level themselves when the stick is let go
	"aim_assist": true,         # bullets bend slightly toward a target in the sight
	"haptics": true,
	"quality": "high",          # balanced · high · ultra
	"refresh": 90,              # 72 · 90 · 120
	"effects": "high",          # medium · high
}

const PRICES := {
	# Upgrade tracks: three levels each.
	"engine": [150, 300, 500], "armor": [150, 300, 500], "guns": [150, 300, 500], "rockets": [150, 300, 500],
	# Guns (right trigger) and specials (A button) and flares.
	"twin": 0, "quad": 450, "cannon": 650,
	"bombs": 0, "cluster": 350, "mines": 500, "lightning": 750,
	"flares": 300,
}
const GUNS := ["twin", "quad", "cannon"]
const SPECIALS := ["bombs", "cluster", "mines", "lightning"]
const TRACKS := ["engine", "armor", "guns", "rockets"]

static var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
static var progress: Dictionary = {}
static var _loaded := false


static func fresh_progress() -> Dictionary:
	return {"missions": {}, "coins": 0, "levels": {"engine": 0, "armor": 0, "guns": 0, "rockets": 0},
		"owned": ["twin", "bombs"], "gun": "twin", "special": "bombs", "seen_controls": false}


static func ensure() -> void:
	if not _loaded:
		load_profile()


static func load_profile() -> void:
	_loaded = true
	settings = DEFAULT_SETTINGS.duplicate()
	progress = fresh_progress()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	var s = parsed.get("settings", {})
	if s is Dictionary and int(parsed.get("version", 1)) < 2:
		# v1.0.1 and older: start the display settings fresh.
		for k in ["quality", "refresh", "effects"]:
			s.erase(k)
	if s is Dictionary:
		for k in s:
			if DEFAULT_SETTINGS.has(k) and typeof(s[k]) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING]:
				settings[k] = s[k]
	settings.refresh = int(settings.refresh)
	var p = parsed.get("progress", {})
	if p is Dictionary:
		for k in p:
			progress[k] = p[k]
	progress.coins = int(progress.get("coins", 0))
	var lv: Dictionary = fresh_progress().levels
	var saved_lv = progress.get("levels", {})
	if saved_lv is Dictionary:
		for k in lv:
			lv[k] = clampi(int(saved_lv.get(k, 0)), 0, 3)
	progress.levels = lv
	for k in ["twin", "bombs"]:
		if not (progress.owned as Array).has(k):
			(progress.owned as Array).append(k)


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": VERSION, "settings": settings, "progress": progress}, "\t"))


static func reset_progress() -> void:
	progress = fresh_progress()
	save()


static func get_s(key: String):
	ensure()
	return settings.get(key, DEFAULT_SETTINGS.get(key))


static func set_s(key: String, value) -> void:
	ensure()
	settings[key] = value
	save()


# --- campaign -------------------------------------------------------------------------------

static func mission(id: String) -> Dictionary:
	ensure()
	var m = progress.missions.get(id, {})
	return m if m is Dictionary else {}


static func stars_of(id: String) -> int:
	return int(mission(id).get("stars", 0))


static func total_stars() -> int:
	ensure()
	var n := 0
	for id in progress.missions:
		n += int(progress.missions[id].get("stars", 0))
	return n


static func unlocked(index: int, ids: Array) -> bool:
	if index == 0:
		return true
	return bool(mission(ids[index - 1]).get("done", false))


## Stores a finished mission; returns the coins earned this time.
static func record(id: String, stars: int, score: int, coins_mult: float) -> int:
	ensure()
	var m := mission(id)
	var first := not bool(m.get("done", false))
	var new_stars := maxi(0, stars - int(m.get("stars", 0)))
	m["done"] = true
	m["stars"] = maxi(int(m.get("stars", 0)), stars)
	m["best"] = maxi(int(m.get("best", 0)), score)
	progress.missions[id] = m
	var coins := int(round((40.0 + score / 25.0 + new_stars * 60.0 + (100.0 if first else 0.0)) * coins_mult))
	progress.coins = int(progress.coins) + coins
	save()
	return coins


# --- hangar ------------------------------------------------------------------------------------

static func level(track: String) -> int:
	ensure()
	return int(progress.levels.get(track, 0))


static func price(item: String) -> int:
	if TRACKS.has(item):
		var l := level(item)
		return PRICES[item][l] if l < 3 else -1
	return int(PRICES.get(item, 0))


static func owns(item: String) -> bool:
	ensure()
	return (progress.owned as Array).has(item)


static func can_buy(item: String) -> bool:
	var p := price(item)
	if p < 0 or (not TRACKS.has(item) and owns(item)):
		return false
	return int(progress.coins) >= p


static func buy(item: String) -> bool:
	if not can_buy(item):
		return false
	progress.coins = int(progress.coins) - price(item)
	if TRACKS.has(item):
		progress.levels[item] = level(item) + 1
	else:
		(progress.owned as Array).append(item)
		if GUNS.has(item):
			progress.gun = item
		elif SPECIALS.has(item):
			progress.special = item
	save()
	return true


static func equip(item: String) -> void:
	if not owns(item):
		return
	if GUNS.has(item):
		progress.gun = item
	elif SPECIALS.has(item):
		progress.special = item
	save()


static func equipped(item: String) -> bool:
	ensure()
	return progress.get("gun", "twin") == item or progress.get("special", "bombs") == item
