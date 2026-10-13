class_name SaveData
extends RefCounted
## Best score and stars per mode, kept in user://sharara.json.

var path: String = "user://sharara.json"

var data: Dictionary = {}


func load_file() -> void:
	data = {}
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data = parsed


func save_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func best(mode: String) -> int:
	return int(data.get(mode, {}).get("best", 0))


func stars(mode: String) -> int:
	return int(data.get(mode, {}).get("stars", 0))


## Records a finished match; returns true when it set a new best score.
func record(mode: String, score: int, stars_won: int) -> bool:
	var entry: Dictionary = data.get(mode, {"best": 0, "stars": 0})
	var record_score := score > int(entry.get("best", 0))
	entry["best"] = maxi(int(entry.get("best", 0)), score)
	entry["stars"] = maxi(int(entry.get("stars", 0)), stars_won)
	data[mode] = entry
	save_file()
	return record_score
