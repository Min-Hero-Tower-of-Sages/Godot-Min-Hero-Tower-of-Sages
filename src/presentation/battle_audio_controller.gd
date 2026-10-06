class_name BattleAudioController
extends Node

const MANIFEST_PATH := "res://content/base/audio/battle_visual_sounds.json"
const ANIMATION_PROFILES_PATH := "res://content/base/art/battle/battle_animation_profiles.json"

var sound_paths: Dictionary = {}
var visual_sounds: Dictionary = {}
var animation_profiles: Dictionary = {}
var stream_cache: Dictionary = {}
var music_player: AudioStreamPlayer
var music_fade: Tween
## Campaign scenes share the shell's persistent music player; local SFX remain
## owned by their scene. This prevents two competing background tracks.
var music_owner: BattleAudioController
var current_music_id := ""
var _music_positions: Dictionary = {}

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	music_player.bus = "Music"
	add_child(music_player)
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("Recovered audio manifest is missing")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		push_error("Recovered audio manifest is invalid")
		return
	sound_paths = parsed.get("sound_paths", {})
	visual_sounds = parsed.get("visual_sounds", {})
	if FileAccess.file_exists(ANIMATION_PROFILES_PATH):
		var profiles_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANIMATION_PROFILES_PATH))
		if profiles_parsed is Dictionary:
			animation_profiles = (profiles_parsed as Dictionary).get("profiles", {})

func binding_for_visual(visual_id: int) -> Dictionary:
	var binding: Dictionary = visual_sounds.get(str(visual_id), {})
	if binding.is_empty() and String(_profile_for_visual(visual_id).get("family", "")) == "burn_at_target":
		# BaseBurnMove sets this in its constructor. Source dispatch cases for
		# Burn, Intense Flame and Crazed return directly without SetSounds, so
		# their inherited cue is absent from the explicit-override manifest.
		return {"main": "battle_flamethrower", "main_volume": 0.4, "impact": "", "impact_volume": 1.0}
	return binding

func _profile_for_visual(visual_id: int) -> Dictionary:
	return animation_profiles.get(str(visual_id), {})

func prepare_visual_profile(visual_id: int) -> Dictionary:
	var profile := _profile_for_visual(visual_id).duplicate(true)
	if String(profile.get("family", "")) == "fall_from_top":
		# CreateMove samples once, shared by audio and the falling sprites.
		profile["random_start_in_game"] = randf_range(0.0, maxf(0.0, float(profile.get("random_start_time", 0.0))))
	return profile

func play_visual(visual_id: int, prepared_profile: Dictionary) -> void:
	for cue in visual_sound_events(visual_id, prepared_profile):
		_play_sound_after(String(cue.sound_id), float(cue.volume), float(cue.time))

## Cues belong to each PlayMove instance, not its damage/heal events. Source
## hit callbacks can run repeatedly and even when their impact sprite is hidden.
func visual_sound_events(visual_id: int, profile: Dictionary) -> Array[Dictionary]:
	var binding := binding_for_visual(visual_id)
	var family := String(profile.get("family", ""))
	var count := maxi(1, int(profile.get("count", 1)))
	var delay := maxf(0.0, float(profile.get("delay", 0.0)))
	var main_times: Array[float] = []
	var secondary_times: Array[float] = []
	var hit_times: Array[float] = []
	match family:
		"fall_from_top":
			var random_start := maxf(0.0, float(profile.get("random_start_in_game", 0.0)))
			for index in count:
				main_times.append(random_start + delay * index + 0.05)
				hit_times.append(random_start + delay * index + maxf(0.0, float(profile.get("impact_speed", 0.75)) - 0.2) + 0.1)
		"fall_onto_target":
			var bounce_count := maxi(0, int(profile.get("pre_impact_bounces", 0)))
			var bounce_speed := maxf(0.0, float(profile.get("up_down_speed", 0.3)))
			var hang_time := 0.2 + 2.0 * bounce_count * bounce_speed
			secondary_times.append(0.0)
			for index in count:
				for bounce_index in range(bounce_count + 1):
					# Object spacing delays descent, not the fade-in/bounce cues.
					main_times.append(0.2 + bounce_index * 2.0 * bounce_speed)
				hit_times.append(hang_time + delay * index + maxf(0.0, float(profile.get("impact_speed", 0.35)) - 0.2) + 0.1)
		"rotate_into_target":
			for index in count:
				# PlayMainSound is called directly inside the creation loop.
				main_times.append(0.0)
				hit_times.append(delay * index + maxf(0.0, float(profile.get("impact_speed", 0.4)) - 0.2) + 0.1)
		"orbit_into_target":
			var stagger := delay if not bool(profile.get("all_enter_at_same_time", true)) else 0.0
			for index in count:
				var main_time := 0.2 + stagger * index
				var secondary_time := main_time + maxf(0.0, float(profile.get("hang_time", 0.5)))
				main_times.append(main_time)
				secondary_times.append(secondary_time)
				hit_times.append(secondary_time + maxf(0.0, float(profile.get("movement_speed", 0.7))))
		"rise_out_of_target":
			main_times.append(0.0)
			var move_time := maxf(0.0, float(profile.get("final_hang_time", 0.5))) + maxf(0.0, float(profile.get("rise_speed", 1.6))) + count * delay + 0.15
			var shake_count := maxi(0, int(profile.get("shake_count", 0)))
			for index in count:
				for shake_index in shake_count:
					# The sound-only shake timeline has no per-object spacing delay.
					secondary_times.append(0.05 + 0.4 * shake_index)
				hit_times.append(maxf(0.0, move_time - 0.5) + delay * index + 0.1)
		"test_white_flash":
			return [{"sound_id": "battle_hit_thump_splat", "volume": 1.0, "time": 0.0}]
		_:
			main_times.append(0.0)
	var cues: Array[Dictionary] = []
	_append_visual_cues(cues, binding, "main", "main_volume", main_times)
	_append_visual_cues(cues, binding, "main2", "main2_volume", secondary_times)
	_append_visual_cues(cues, binding, "impact", "impact_volume", hit_times)
	return cues

func _append_visual_cues(cues: Array[Dictionary], binding: Dictionary, sound_key: String, volume_key: String, times: Array[float]) -> void:
	var sound_id := String(binding.get(sound_key, ""))
	var volume := float(binding.get(volume_key, 1.0))
	if sound_id.is_empty() or volume <= 0.0: return
	for time in times:
		cues.append({"sound_id": sound_id, "volume": volume, "time": maxf(0.0, time)})

func _play_sound_after(sound_id: String, volume: float, delay: float) -> void:
	if delay <= 0.0:
		play_sound(sound_id, volume)
		return
	_play_sound_after_delay(sound_id, volume, delay)

func _play_sound_after_delay(sound_id: String, volume: float, delay: float) -> void:
	var deadline_usec := Time.get_ticks_usec() + int(delay * 1000000.0)
	while deadline_usec > Time.get_ticks_usec():
		await get_tree().create_timer(float(deadline_usec - Time.get_ticks_usec()) / 1000000.0).timeout
	if is_inside_tree():
		play_sound(sound_id, volume)

func play_sound(sound_id: String, volume: float = 1.0) -> bool:
	if sound_id.is_empty() or volume <= 0.0:
		return false
	var stream := _stream_for(sound_id)
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	player.name = sound_id
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = linear_to_db(clampf(volume, 0.001, 1.0))
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true

func play_battle_music() -> void:
	play_music("battleTrack", 1.0, 6.0)

func play_music(sound_id: String, volume: float, fade_seconds: float) -> void:
	if is_instance_valid(music_owner):
		music_owner.play_music(sound_id, volume, fade_seconds)
		return
	var original := _stream_for(sound_id)
	if original == null:
		push_warning("Cannot play music track %s: recovered audio is unavailable" % sound_id)
		return
	if current_music_id == sound_id and music_player.playing:
		fade_music_to(volume, fade_seconds)
		return
	var previous_volume := db_to_linear(music_player.volume_db) if music_player.playing else 0.0
	if music_player.playing and not current_music_id.is_empty():
		_music_positions[current_music_id] = music_player.get_playback_position()
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	music_player.stop()
	current_music_id = sound_id
	music_player.stream = original.duplicate() as AudioStream
	if music_player.stream is AudioStreamMP3:
		(music_player.stream as AudioStreamMP3).loop = true
	music_player.volume_db = linear_to_db(maxf(0.0001, previous_volume))
	music_player.play(float(_music_positions.get(sound_id, 0.0)))
	fade_music_to(volume, fade_seconds)

func fade_music_to(linear_volume: float, duration: float) -> void:
	if is_instance_valid(music_owner):
		music_owner.fade_music_to(linear_volume, duration)
		return
	if music_player == null or not music_player.playing:
		return
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	var from_volume := db_to_linear(music_player.volume_db)
	var to_volume := clampf(linear_volume, 0.0, 1.0)
	music_fade = create_tween()
	music_fade.tween_method(_set_music_volume_linear, from_volume, to_volume, maxf(0.0, duration))

func _set_music_volume_linear(value: float) -> void:
	if music_player != null:
		music_player.volume_db = linear_to_db(maxf(0.0001, value))

func stop_music() -> void:
	if is_instance_valid(music_owner):
		music_owner.stop_music()
		return
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	if music_player != null:
		if music_player.playing and not current_music_id.is_empty():
			_music_positions[current_music_id] = music_player.get_playback_position()
		music_player.stop()

func _stream_for(sound_id: String) -> AudioStream:
	if stream_cache.has(sound_id):
		return stream_cache[sound_id] as AudioStream
	var path := String(sound_paths.get(sound_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		stream_cache[sound_id] = stream
	return stream
