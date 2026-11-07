class_name GameAudio
extends Node3D
## Spatial one-shots from the generated WAVs, and crossfading music loops.

var voices: Array[AudioStreamPlayer3D] = []
var cursor: int = 0
var _streams: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _active: int = 0
var _music_name: String = ""
var _fade: float = 1.0
const MUSIC_DB := -15.0


func _ready() -> void:
	for i in range(16):
		var v := AudioStreamPlayer3D.new()
		v.max_distance = 10.0
		v.unit_size = 1.4
		v.volume_db = -12.0
		v.bus = &"SFX"
		add_child(v)
		voices.append(v)


func stream(cue: String) -> AudioStream:
	if not _streams.has(cue):
		var path := "res://assets/audio/" + cue + ".wav"
		_streams[cue] = load(path) if ResourceLoader.exists(path) else null
	return _streams[cue]


func play(cue: String, at: Vector3, db: float = 0.0) -> void:
	var s := stream(cue)
	if s == null or voices.is_empty():
		return
	var v := voices[cursor]
	cursor = (cursor + 1) % voices.size()
	v.stop()
	v.stream = s
	v.global_position = at
	v.volume_db = -12.0 + db
	v.pitch_scale = randf_range(0.93, 1.07)
	v.play()


func play_music(track: String) -> void:
	if track == _music_name:
		return
	var s := stream("music_" + track)
	if s == null:
		return
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	if _music.is_empty():
		for i in range(2):
			var p := AudioStreamPlayer.new()
			p.volume_db = -80.0
			p.bus = &"Music"
			add_child(p)
			_music.append(p)
	_music_name = track
	_active = 1 - _active
	var player := _music[_active]
	player.stream = s
	player.volume_db = -60.0
	player.play()
	_fade = 0.0


func _process(delta: float) -> void:
	if _music.is_empty() or _fade >= 1.0:
		return
	_fade = minf(1.0, _fade + delta / 1.2)
	_music[_active].volume_db = lerpf(-40.0, MUSIC_DB, sqrt(_fade))
	var other := _music[1 - _active]
	other.volume_db = lerpf(MUSIC_DB, -60.0, _fade)
	if _fade >= 1.0:
		other.stop()
