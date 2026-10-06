class_name CampaignSettingsService
extends RefCounted

signal settings_changed

const SETTINGS_PATH := "user://campaign_settings.cfg"
const SECTION := "settings"
const QUALITY_NAMES: Array[String] = ["Low", "Mid", "High"]

var sound_enabled := true
var music_enabled := true
var tips_enabled := true
var quality_level := 2

func _init() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		sound_enabled = bool(config.get_value(SECTION, "sound_enabled", true))
		music_enabled = bool(config.get_value(SECTION, "music_enabled", true))
		tips_enabled = bool(config.get_value(SECTION, "tips_enabled", true))
		quality_level = clampi(int(config.get_value(SECTION, "quality_level", 2)), 0, 2)
	else:
		sound_enabled = true
		music_enabled = true
		tips_enabled = true
		quality_level = 2
	_ensure_audio_buses()
	apply_audio_settings()
	apply_quality_settings()

func set_sound_enabled(enabled: bool) -> void:
	if sound_enabled == enabled:
		return
	sound_enabled = enabled
	_save_and_apply()

func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled:
		return
	music_enabled = enabled
	_save_and_apply()

func set_tips_enabled(enabled: bool) -> void:
	if tips_enabled == enabled:
		return
	tips_enabled = enabled
	_save_and_apply()

func set_quality_level(level: int) -> void:
	var next_level := clampi(level, 0, QUALITY_NAMES.size() - 1)
	if quality_level == next_level:
		return
	quality_level = next_level
	_save_and_apply()

func cycle_quality(step: int) -> void:
	set_quality_level(posmod(quality_level + step, QUALITY_NAMES.size()))

func quality_name() -> String:
	return QUALITY_NAMES[clampi(quality_level, 0, QUALITY_NAMES.size() - 1)]

func route_player(player: AudioStreamPlayer, is_music: bool) -> void:
	if player == null:
		return
	_ensure_audio_buses()
	player.bus = "Music" if is_music else "SFX"

func route_existing_players(root: Node) -> void:
	_ensure_audio_buses()
	_route_node(root)

func apply_audio_settings() -> void:
	_ensure_audio_buses()
	var sound_bus := AudioServer.get_bus_index("SFX")
	var music_bus := AudioServer.get_bus_index("Music")
	if sound_bus >= 0:
		AudioServer.set_bus_mute(sound_bus, not sound_enabled)
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, not music_enabled)

func apply_quality_settings(viewport: Viewport = null) -> void:
	var target_viewport := viewport
	if target_viewport == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			target_viewport = (loop as SceneTree).root
	if target_viewport == null:
		return
	match quality_level:
		0:
			target_viewport.msaa_2d = Viewport.MSAA_DISABLED
			target_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		1:
			target_viewport.msaa_2d = Viewport.MSAA_2X
			target_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		_:
			target_viewport.msaa_2d = Viewport.MSAA_4X
			target_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _save_and_apply() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "sound_enabled", sound_enabled)
	config.set_value(SECTION, "music_enabled", music_enabled)
	config.set_value(SECTION, "tips_enabled", tips_enabled)
	config.set_value(SECTION, "quality_level", quality_level)
	var result := config.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Could not save campaign settings (%s)" % error_string(result))
	apply_audio_settings()
	apply_quality_settings()
	settings_changed.emit()

func _ensure_audio_buses() -> void:
	_ensure_audio_bus("SFX")
	_ensure_audio_bus("Music")
	var sound_bus := AudioServer.get_bus_index("SFX")
	var music_bus := AudioServer.get_bus_index("Music")
	if sound_bus >= 0:
		AudioServer.set_bus_send(sound_bus, "Master")
	if music_bus >= 0:
		AudioServer.set_bus_send(music_bus, "Master")

func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _route_node(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		var is_music := player.name == &"Music" or player.name == &"BattleMusic"
		player.bus = "Music" if is_music else "SFX"
	for child in node.get_children():
		_route_node(child)
