class_name ShaddaAudio
extends Node3D
var voices: Array[AudioStreamPlayer3D] = []
var cursor: int = 0

func _ready() -> void:
	for i in range(6):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 8.0
		voice.unit_size = 1.5
		voice.volume_db = -18.0
		add_child(voice)
		voices.append(voice)

func play_cue(cue: String, point: Vector3) -> void:
	var path := "res://assets/audio/" + cue + ".wav"
	if voices.is_empty() or not ResourceLoader.exists(path):
		return
	var voice := voices[cursor]
	cursor = (cursor + 1) % voices.size()
	voice.stop()
	voice.stream = load(path)
	voice.global_position = point
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()
