extends Node

# One home for the game's sound: the background music, the day's crowd
# ambience, and the interface clicks. Volumes live in a small local config, not
# in the player save, so the backend payload is untouched.

signal settings_changed

const SETTINGS_PATH: String = "user://audio_settings.cfg"
const MUSIC_PATH: String = "res://library/sounds/game-music/Apple Cider.mp3"
const CROWD_PATH: String = "res://audio/crowd_ambience/crowd_ambience.wav"
const MENU_SFX_PATH: String = "res://library/sounds/rpg-sound-effects/doorOpen_2.ogg"
const CLICK_SFX_PATH: String = "res://library/sounds/rpg-sound-effects/confirmation_002.ogg"
const SFX_VOICES: int = 6

var music_volume: float = 0.55
var sfx_volume: float = 0.8
var muted: bool = false

var _music: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _sfx_voices: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _menu_sfx: AudioStream
var _click_sfx: AudioStream
var _crowd_playing: bool = false

func _ready() -> void:
	_ensure_buses()
	_load_settings()
	_music = _make_player("Music")
	_crowd = _make_player("SFX")
	_crowd.volume_db = -7.0
	for i in SFX_VOICES:
		_sfx_voices.append(_make_player("SFX"))
	_menu_sfx = _load_audio(MENU_SFX_PATH)
	_click_sfx = _load_audio(CLICK_SFX_PATH)
	_start_music()
	# Every Button in the game gets an interface sound without each menu having
	# to wire one. The tab buttons mark themselves and get the menu version.
	get_tree().node_added.connect(_on_node_added)
	_wire_existing_buttons(get_tree().root)
	_apply_volumes()

func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player

func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")

func _start_music() -> void:
	if _music == null:
		return
	_music.stream = _load_audio(MUSIC_PATH)
	if _music.stream == null:
		return
	_loop_stream(_music.stream)
	_music.play()

# Loops an imported stream at the source, because the import flags for these
# files are shared with the library.
func _loop_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD

func _load_audio(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

# --- Crowd ----------------------------------------------------------------

func set_crowd_active(active: bool) -> void:
	_crowd_playing = active
	if _crowd == null:
		return
	if active:
		if _crowd.stream == null:
			_crowd.stream = _load_audio(CROWD_PATH)
			if _crowd.stream != null:
				_loop_stream(_crowd.stream)
		if _crowd.stream != null and not _crowd.playing:
			_crowd.play()
	elif _crowd.playing:
		_crowd.stop()

func is_crowd_playing() -> bool:
	return _crowd_playing

# --- Interface sounds -----------------------------------------------------

func play_click() -> void:
	_play_sfx(_click_sfx, -3.0)

func play_menu_switch() -> void:
	_play_sfx(_menu_sfx, -5.0)

func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	if stream == null or _sfx_voices.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_voices[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_voices.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)

func _wire_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)
	for child in node.get_children():
		_wire_existing_buttons(child)

func _wire_button(button: BaseButton) -> void:
	if button.has_meta("audio_wired"):
		return
	button.set_meta("audio_wired", true)
	button.pressed.connect(_on_button_pressed.bind(button))

func _on_button_pressed(button: BaseButton) -> void:
	if button.has_meta("audio_switch"):
		play_menu_switch()
	else:
		play_click()

# --- Settings -------------------------------------------------------------

func set_muted(value: bool) -> void:
	muted = value
	_apply_volumes()
	_save_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func _apply_volumes() -> void:
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	settings_changed.emit()

func _set_bus_volume(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, muted)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	muted = bool(config.get_value("audio", "muted", muted))
	music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.save(SETTINGS_PATH)
