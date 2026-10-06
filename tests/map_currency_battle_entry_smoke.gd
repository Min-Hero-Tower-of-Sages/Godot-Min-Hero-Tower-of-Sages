extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	var original_room := catalog.get_definition(&"base:room/level_1_2_e")
	var cache_started := Time.get_ticks_usec()
	for index in 10:
		_check(catalog.ensure_index().is_empty(), "Cached catalog reports errors")
	_check(catalog.get_definition(original_room.id) == original_room, "Battle indexing rebuilt room instances")
	var cache_ms := (Time.get_ticks_usec() - cache_started) / 1000.0
	var map_count := 0
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	var starter := OwnedMinionState.new()
	starter.instance_id = &"map-currency-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	session.state.party.append(starter)
	for definition in catalog._by_id.values():
		if definition is not RoomDefinition: continue
		var room: RoomDefinition = definition
		for interaction in room.interactions:
			if StringName(interaction.get("kind", "")) != &"map_station": continue
			session.state.current_room_id = room.id
			session.state.progression["floor_index"] = int(room.minimap_metadata.floor_index)
			session.state.progression["map_unlocked"] = false
			session.reject_save = true
			var rejected: Dictionary = session.interact(StringName(interaction.id))
			_check(not rejected.ok and not session.state.progression.map_unlocked, "Rejected map save changes state")
			session.reject_save = false
			var granted: Dictionary = session.interact(StringName(interaction.id))
			_check(granted.ok and granted.kind == &"map_granted", "Cannot talk to map giver in %s" % room.id)
			_check(session.interact(StringName(interaction.id)).get("kind") == &"map_hint", "Map giver repeat dialogue missing")
			map_count += 1
	_check(map_count > 2, "Only the historical first two map givers are registered")
	var currency = preload("res://src/presentation/campaign_currency_text.gd")
	_check(currency.format_amount(6.750000000000004) == "$6", "Money display must use whole coins")
	_check(currency.format_amount(7.0) == "$7", "Whole currency has unwanted decimal tail")
	_check(currency.format_amount(7.0 / 3.0) == "$2", "Fractional money is displayed")
	var legacy_state := CampaignState.new()
	legacy_state.load_dictionary({"progression": {"currency": 6.750000000000004}})
	_check(legacy_state.progression.currency is int and legacy_state.progression.currency == 6, "Old fractional balance was not normalized")
	var audio := BattleAudioController.new()
	root.add_child(audio)
	audio.play_battle_music()
	_check(audio.music_player.playing and audio.music_player.stream != null, "Battle track cannot play")
	audio.queue_free()
	print("%s: %d standard map givers, atomic grant/repeat; currency precision; battle music; ten cached catalog checks %.2f ms" % ["PASS" if failures.is_empty() else "FAIL", map_count, cache_ms])
	quit(0 if failures.is_empty() else 1)
