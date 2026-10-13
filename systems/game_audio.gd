class_name GameAudio
extends Node3D
## Spatial one-shot cues and looping ambiences, all from the generated CC0 WAVs.

var voices: Array[AudioStreamPlayer3D] = []
var cursor: int = 0
var _streams: Dictionary = {}


func _ready() -> void:
	for i in range(8):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 9.0
		voice.unit_size = 1.5
		voice.volume_db = -16.0
		add_child(voice)
		voices.append(voice)


func _stream(cue: String) -> AudioStream:
	if not _streams.has(cue):
		var path := "res://assets/audio/" + cue + ".wav"
		_streams[cue] = load(path) if ResourceLoader.exists(path) else null
	return _streams[cue]


func play_cue(cue: String, point: Vector3, volume_db: float = 0.0) -> void:
	var stream := _stream(cue)
	if voices.is_empty() or stream == null:
		return
	var voice := voices[cursor]
	cursor = (cursor + 1) % voices.size()
	voice.stop()
	voice.stream = stream
	voice.global_position = point
	voice.volume_db = -16.0 + volume_db
	voice.pitch_scale = randf_range(0.95, 1.05)
	voice.play()


## A looping ambience attached to a node (rift hum). Returns the player.
func attach_loop(cue: String, parent: Node3D, volume_db: float = -22.0) -> AudioStreamPlayer3D:
	var stream := _stream(cue)
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.max_distance = 7.0
	player.unit_size = 1.2
	player.volume_db = volume_db
	player.autoplay = false
	parent.add_child(player)
	return player
