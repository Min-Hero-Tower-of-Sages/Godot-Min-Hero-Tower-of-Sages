extends SceneTree

const ROOM_MUSIC = preload("res://src/presentation/source_room_music.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var campaign := runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var opening := runtime.catalog.get_definition(&"base:room/level_1_1_entryhallway") as RoomDefinition
	var opening_profile := ROOM_MUSIC.profile(opening, "forestTrack", true)
	assert(opening_profile.track == "riverTrack" and opening_profile.volume == 0.1 and opening_profile.fade_seconds == 3.0)
	var hallway := RoomDefinition.new()
	hallway.payload = RoomPayloadDefinition.new()
	hallway.payload.objects.assign([{"spriteName": "generalRoom_floorTile"}])
	var inherited := ROOM_MUSIC.profile(hallway, "electricTrack")
	assert(inherited.track == "electricTrack" and inherited.volume == 0.4 and inherited.fade_seconds == 3.0)
	hallway.payload.objects.append({"spriteName": "fire_music_override"})
	assert(ROOM_MUSIC.profile(hallway, "electricTrack").track == "fireTrack")
	hallway.payload.objects.append({"spriteName": "fullVolume_music_override"})
	assert(ROOM_MUSIC.profile(hallway, "electricTrack").volume == 1.0)
	hallway.payload.objects.append({"spriteName": "plantRoom_groundTile"})
	assert(ROOM_MUSIC.profile(hallway, "electricTrack").track == "forestTrack", "Assignment order must match AddObject, not unordered marker priority")
	for floor_index in 31:
		var region := ROOM_MUSIC.regional_for_floor(runtime.catalog, campaign, floor_index)
		assert(not region.is_empty(), "Cannot recover region for old save on floor %d" % (floor_index + 1))
		assert(region == ROOM_MUSIC.regional_for_floor(runtime.catalog, campaign, floor_index + 31))
	var owner := BattleAudioController.new()
	var battle_audio := BattleAudioController.new()
	root.add_child(owner)
	root.add_child(battle_audio)
	battle_audio.music_owner = owner
	owner.play_music("forestTrack", 1.0, 0.0)
	await process_frame
	owner.music_player.seek(12.0)
	await create_timer(0.1).timeout
	var before_same_room := owner.music_player.get_playback_position()
	owner.play_music("forestTrack", 0.4, 3.0)
	assert(owner.music_player.get_playback_position() >= before_same_room - 0.1, "Same-region transition restarted music")
	battle_audio.play_battle_music()
	assert(owner.current_music_id == "battleTrack" and owner.music_player.playing)
	assert(not battle_audio.music_player.playing, "Shared battle started a second music player")
	assert(float(owner._music_positions.forestTrack) >= 12.0)
	owner.play_music("forestTrack", 1.0, 2.0)
	await process_frame
	assert(owner.current_music_id == "forestTrack" and owner.music_player.get_playback_position() >= 12.0, "Return to room did not resume regional music")
	var music_rooms := 0
	for definition in runtime.catalog._by_id.values():
		if not definition is RoomDefinition:
			continue
		var profile := ROOM_MUSIC.profile(definition, "forestTrack")
		assert(owner._stream_for(String(profile.track)) != null, "Unavailable room track in %s" % definition.id)
		music_rooms += 1
	# Check WinScreen's late return cue with scaled fixture time. Do not use a
	# progression shortcut that could bypass its source 6.4-second schedule.
	var progression := BattleProgressionPresenter.new()
	root.add_child(progression)
	progression._sequence_id = 10
	progression._sequence_active = true
	owner.play_music("battleTrack", 0.0, 0.0)
	await process_frame
	Engine.time_scale = 20.0
	progression.call("_restore_victory_music", 10, battle_audio)
	await create_timer(7.1).timeout
	assert(is_equal_approx(db_to_linear(owner.music_player.volume_db), 0.2))
	owner.fade_music_to(0.0, 0.0)
	await process_frame
	progression._music_finish_started = true
	progression.call("_restore_victory_music", 10, battle_audio)
	await create_timer(7.1).timeout
	assert(db_to_linear(owner.music_player.volume_db) < 0.001, "Late victory callback revived finishing music")
	Engine.time_scale = 1.0
	var short_victory := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(short_victory)
	short_victory.campaign_mode = true
	short_victory._campaign_victory_return_pending = true
	var handoff_seen := {"value": false}
	short_victory.campaign_return_requested.connect(func() -> void: handoff_seen.value = true)
	short_victory.call("_play_victory_presentation", BattleResult.new())
	assert(short_victory._victory_popup_tween.is_running())
	short_victory.call("_on_campaign_progression_sequence_finished")
	assert(handoff_seen.value, "Short/skipped victory queue waited unnecessarily for popup close")
	short_victory.queue_free()
	battle_audio.queue_free()
	await process_frame
	assert(owner.music_player.playing, "Removing battle scene stopped the persistent regional player")
	progression.queue_free()
	owner.queue_free()
	await process_frame
	print("PASS: source music order/overrides, 31 standard/hard region fallbacks, %d room tracks, shared player/resume and guarded victory music return" % music_rooms)
	quit(0)
