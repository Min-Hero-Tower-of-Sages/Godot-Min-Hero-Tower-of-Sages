extends SceneTree

class MemorySaveRepository extends SaveRepository:
	var saved_state: Dictionary = {}

	func save_slot(_slot: int, payload: Dictionary) -> Dictionary:
		saved_state = payload.duplicate(true)
		return {"ok": true}

	func load_slot(_slot: int) -> Dictionary:
		return {"ok": true, "state": saved_state.duplicate(true)} if not saved_state.is_empty() else {"ok": false, "code": "not_found"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	for starter_count in [2, 5]:
		var session := CampaignSession.new()
		session.catalog = runtime.catalog
		session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
		session.save_repository = MemorySaveRepository.new()
		var state := CampaignState.new()
		state.campaign_id = session.campaign.id
		state.current_room_id = &"base:room/main_tower_lobby"
		state.character = {"name": "Titan fixture", "gender": "male"}
		state.progression["highest_beaten_floor"] = 32
		state.progression["unlocked_floor_indices"] = [0, 31, 32]
		state.progression["in_tower_lobby"] = true
		state.safe_location = {"room_id": String(state.current_room_id), "spawn_id": "lobby_from_floor", "position": Vector2(1498, 128)}
		for index in starter_count:
			var starter := OwnedMinionState.new()
			starter.instance_id = StringName("titan-fixture-%d" % index)
			starter.definition_id = &"base:minion/fire_pig_1"
			starter.level = 5
			state.party.append(starter)
		session.state = state
		assert(session.lobby_titan_status().can_claim_titans, "Tower completion did not unlock both Titans")
		var claimed: Dictionary = session.claim_lobby_titan()
		assert(claimed.ok and claimed.rewards.size() == 2, "Titan claim did not grant both rewards atomically")
		assert(session.state.party.size() == mini(5, starter_count + 2), "Titan party placement is wrong")
		assert(session.state.storage.size() == maxi(0, starter_count + 2 - 5), "Titan overflow was not stored")
		assert(session.lobby_titan_status().all_titans_owned, "Titan ownership was not committed")
		var loaded := session.load(1)
		assert(loaded.ok and session.lobby_titan_status().all_titans_owned, "Both Titans did not survive save/reload")
		assert(not session.claim_lobby_titan().ok, "An already claimed Titan reward was duplicated")
	print("PASS: two Titans granted directly, party/storage placement and save reload")
	quit(0)
