extends SceneTree

class RecordingAudio extends BattleAudioController:
	var played: Array[Dictionary] = []
	var scheduled: Array[Dictionary] = []
	func play_visual(visual_id: int, prepared_profile: Dictionary) -> void:
		scheduled.append({"visual_id": visual_id, "profile": prepared_profile.duplicate(true)})
		super.play_visual(visual_id, prepared_profile)
	func play_sound(sound_id: String, volume: float = 1.0) -> bool:
		played.append({"sound_id": sound_id, "volume": volume, "usec": Time.get_ticks_usec()})
		return true

func _initialize() -> void:
	_run.call_deferred()

func _times(cues: Array[Dictionary], sound_id: String) -> Array[float]:
	var times: Array[float] = []
	for cue in cues:
		if cue.sound_id == sound_id: times.append(float(cue.time))
	return times

func _expect_times(actual: Array[float], expected: Array) -> void:
	assert(actual.size() == expected.size(), "Wrong source callback count: %s != %s" % [actual, expected])
	for index in actual.size():
		assert(is_equal_approx(actual[index], float(expected[index])), "Wrong source callback deadline: %s != %s" % [actual, expected])

func _run() -> void:
	await process_frame
	var audio := RecordingAudio.new()
	root.add_child(audio)
	# Force all three bindings to expose callbacks even for moves which mute one.
	audio.visual_sounds["99991"] = {"main": "main", "main_volume": 0.4, "main2": "secondary", "main2_volume": 0.5, "impact": "hit", "impact_volume": 0.6}
	var cues := audio.visual_sound_events(99991, {"family": "fall_from_top", "count": 3, "delay": 0.1, "impact_speed": 0.75, "random_start_in_game": 0.25})
	_expect_times(_times(cues, "main"), [0.3, 0.4, 0.5])
	_expect_times(_times(cues, "hit"), [0.9, 1.0, 1.1])
	cues = audio.visual_sound_events(99991, {"family": "fall_onto_target", "count": 2, "delay": 0.1, "impact_speed": 0.35, "pre_impact_bounces": 2, "up_down_speed": 0.3})
	_expect_times(_times(cues, "main"), [0.2, 0.8, 1.4, 0.2, 0.8, 1.4])
	_expect_times(_times(cues, "secondary"), [0.0])
	_expect_times(_times(cues, "hit"), [1.65, 1.75])
	cues = audio.visual_sound_events(99991, {"family": "rotate_into_target", "count": 3, "delay": 0.06, "impact_speed": 0.4, "impact_visible": false})
	_expect_times(_times(cues, "main"), [0.0, 0.0, 0.0])
	_expect_times(_times(cues, "hit"), [0.3, 0.36, 0.42])
	for simultaneous in [true, false]:
		cues = audio.visual_sound_events(99991, {"family": "orbit_into_target", "count": 2, "delay": 0.1, "hang_time": 0.5, "movement_speed": 0.42, "all_enter_at_same_time": simultaneous})
		_expect_times(_times(cues, "main"), [0.2, 0.2 if simultaneous else 0.3])
		_expect_times(_times(cues, "secondary"), [0.7, 0.7 if simultaneous else 0.8])
		_expect_times(_times(cues, "hit"), [1.12, 1.12 if simultaneous else 1.22])
	cues = audio.visual_sound_events(99991, {"family": "rise_out_of_target", "count": 2, "delay": 0.1, "rise_speed": 1.6, "final_hang_time": 0.5, "shake_count": 2, "impact_minion": false})
	_expect_times(_times(cues, "main"), [0.0])
	_expect_times(_times(cues, "secondary"), [0.05, 0.45, 0.05, 0.45])
	_expect_times(_times(cues, "hit"), [2.05, 2.15])
	for family in ["burn_at_target", "fade_through_target", "screen_shake"]:
		cues = audio.visual_sound_events(99991, {"family": family, "count": 3})
		_expect_times(_times(cues, "main"), [0.0])
		assert(_times(cues, "hit").is_empty())
	assert(audio.visual_sound_events(173, {"family": "test_white_flash"}) == [{"sound_id": "battle_hit_thump_splat", "volume": 1.0, "time": 0.0}])
	# Check actual scheduling independently of the returned timeline.
	var started_usec := Time.get_ticks_usec()
	audio.play_visual(99991, {"family": "fall_from_top", "count": 2, "delay": 0.1, "impact_speed": 0.4, "random_start_in_game": 0.2})
	while Time.get_ticks_usec() < started_usec + 750000:
		await create_timer(float(started_usec + 750000 - Time.get_ticks_usec()) / 1000000.0).timeout
	assert(audio.played.size() == 4, "Scheduled cues were missing or duplicated: %s" % [audio.played])
	var played_times: Array[float] = []
	for cue in audio.played: played_times.append(float(cue.usec - started_usec) / 1000000.0)
	for index in 4:
		var expected_time := [0.25, 0.35, 0.5, 0.6][index] as float
		assert(played_times[index] >= expected_time - 0.005 and played_times[index] < expected_time + 0.15)
	# Native presenter: every target owns its visual/cues. Damage, reflection and
	# redirection must not manufacture extra attack cues.
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	main.audio_controller.queue_free()
	main.audio_controller = audio
	var targets: Array[StringName] = []
	var actor_id: StringName
	for view in main.combatant_views.values():
		if view.team == 1: targets.append(StringName(view.instance_id))
		elif actor_id.is_empty(): actor_id = StringName(view.instance_id)
	assert(targets.size() >= 2)
	var move: MoveDefinition
	for definition in main.catalog._by_id.values():
		if definition is MoveDefinition:
			var profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(definition))
			if profile.get("family", "") == "rotate_into_target" and int(profile.get("count", 1)) > 1:
				move = definition
				break
	assert(move != null)
	var visual_id := int(main._resolved_visual_id(move))
	var binding := audio.binding_for_visual(visual_id)
	var count := int(audio.prepare_visual_profile(visual_id).get("count", 1))
	audio.played.clear()
	var cast := BattleEvent.new(0, &"move_used", actor_id, targets[0], {"move_id": String(move.id), "hit": true})
	main._animate_move_visual(cast, targets[0])
	main._animate_move_visual(cast, targets[1])
	if not String(binding.get("main", "")).is_empty(): assert(audio.played.size() == count * 2)
	var casts := audio.played.size()
	for kind in [&"damage", &"healed", &"shield_set", &"reflected_damage", &"redirected_damage"]:
		main._play_event_audio(BattleEvent.new(0, kind, actor_id, targets[0], {}))
	assert(audio.played.size() == casts)
	main._play_event_audio(BattleEvent.new(0, &"frozen_turn_skipped", actor_id, targets[0], {}))
	main._play_event_audio(BattleEvent.new(0, &"stunned_turn_skipped", actor_id, targets[0], {}))
	assert(audio.played[-2].sound_id == "battle_whoosh_wind" and audio.played[-1].sound_id == "battle_spark")
	var falling_move: MoveDefinition
	for definition in main.catalog._by_id.values():
		if definition is MoveDefinition:
			var profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(definition))
			if profile.get("family", "") == "fall_from_top" and float(profile.get("random_start_time", 0.0)) > 0.0:
				falling_move = definition
				break
	assert(falling_move != null)
	var falling_cast := BattleEvent.new(0, &"move_used", actor_id, targets[0], {"move_id": String(falling_move.id), "hit": true})
	var contact := float(main._animate_move_visual(falling_cast, targets[0]))
	var shared_profile: Dictionary = audio.scheduled[-1].profile
	var shared_move_time := preload("res://src/presentation/source_visual_move_timing.gd").move_time(shared_profile)
	assert(is_equal_approx(main._last_move_visual_duration_seconds, shared_move_time) and is_equal_approx(contact, shared_move_time - 0.1), "Sound, falling cleanup and source ApplyEffects queue sampled different start delays")
	# Every authored cue must resolve to an actual recovered audio stream.
	var checked_profiles := 0
	for key in audio.animation_profiles:
		var prepared_profile := audio.prepare_visual_profile(int(key))
		for cue in audio.visual_sound_events(int(key), prepared_profile):
			assert(audio._stream_for(String(cue.sound_id)) != null, "Missing recovered sound: %s" % cue.sound_id)
		checked_profiles += 1
	main.queue_free()
	audio.queue_free()
	await process_frame
	print("PASS: %d authored visual audio profiles; source object/target callback counts and times, shared random delay, hidden-impact cues, no reflection duplicates and freeze/stun repeat sounds" % checked_profiles)
	quit(0)
