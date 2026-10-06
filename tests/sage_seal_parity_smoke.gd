extends SceneTree

const Presenter = preload("res://src/presentation/source_sage_seal_presenter.gd")
var completions := 0

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

class BattleFixture extends Control:
	var campaign_settlement: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var presenter := Presenter.new()
	root.add_child(presenter)
	for family in [1, 2]:
		assert(presenter.play(family, null, func() -> void: completions += 1))
		assert(presenter.get_child_count() == 5)
		var flash := presenter.get_node("SourceSealFlash") as ColorRect
		assert(flash.color == Color.WHITE and flash.size == Vector2(700, 525))
		for index in 3:
			var piece := presenter.get_node("SourceSealPiece%d" % (index + 1)) as TextureRect
			assert(piece.texture == SourceMenuArt.texture("sageSeal_%d_%d" % [family, index + 1]))
			assert(piece.position == Presenter.PIECE_POSITIONS[index] and piece.modulate.a == 0.0)
		var medallion := presenter.get_node("SourceSealMedallion") as TextureRect
		assert(medallion.texture == SourceMenuArt.texture(Presenter.MEDALLIONS[family - 1]))
		presenter._timeline.custom_step(2.4)
		assert(presenter.active and completions == family - 1)
		assert(presenter.get_node("SourceSealPiece1").modulate.a > 0.99)
		presenter._timeline.custom_step(0.46)
		assert(medallion.modulate.a > 0.9)
		assert(presenter.get_node("SourceSealPiece1").position.distance_to(Vector2(323, 167)) < 0.01)
		presenter._timeline.custom_step(1.0)
		assert(medallion.position.y < 167.0 and medallion.position.y > 157.0)
		presenter._timeline.custom_step(1.2)
		assert(not presenter.active and completions == family)
		await process_frame
	assert(presenter.play(1, null, func() -> void: completions += 10))
	presenter.cancel()
	await process_frame
	assert(not presenter.active and completions == 2, "Cancellation cannot launch stale trainer dialogue")
	var state := CampaignState.new()
	state.progression = {"floor_index": 0, "unlocked_floor_indices": [0]}
	var boss := runtime.catalog.get_definition(&"base:encounter/grass_floor1_room6_boss") as EncounterDefinition
	var boss_reward := CampaignProgressionService._grant_first_clear_rewards(state, boss)
	assert(boss_reward.sage_seal_pieces == 1 and boss_reward.sage_seals == 0)
	var rewards := BattleRewardPresenter.new()
	root.add_child(rewards)
	var boss_items := rewards._source_reward_items(boss_reward)
	assert(boss_items.size() == 2 and boss_items[0].kind == "seal" and boss_items[1].kind == "key" and boss_items[1].start_after == 1.9)
	var sage := runtime.catalog.get_definition(&"base:encounter/floor10_fire_sage") as EncounterDefinition
	var sage_reward := CampaignProgressionService._grant_first_clear_rewards(state, sage)
	assert(state.progression.sage_seals == 2 and sage_reward.sage_seals == 2)
	assert(rewards._source_reward_items(sage_reward).is_empty(), "A completed Gym seal must not also show a piece pickup")
	var same_seal := CampaignProgressionService._grant_first_clear_rewards(state, sage)
	assert(same_seal.sage_seals == 0 and state.progression.sage_seals == 2)
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.character = {"name": "Seal fixture", "gender": "male"}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	for encounter_id in [&"base:encounter/grass_floor5_sage", &"base:encounter/floor10_fire_sage"]:
		var encounter := runtime.catalog.get_definition(encounter_id) as EncounterDefinition
		var sage_room: RoomDefinition
		for candidate in runtime.catalog._by_id.values():
			if candidate is RoomDefinition and candidate.encounter_ids.has(encounter_id):
				sage_room = candidate
		assert(sage_room != null)
		session.state.current_room_id = sage_room.id
		session.state.progression = {"floor_index": encounter.source_floor_index, "sage_seals": 2}
		shell.call("_show_room_from_state")
		var battle := BattleFixture.new()
		battle.campaign_settlement = {"first_clear_rewards": {"sage_seals": 1}}
		shell.screen_host.add_child(battle)
		shell.current_battle = battle
		shell._trainer_return_location = {"room_id": String(sage_room.id), "encounter_id": String(encounter_id), "first_visit": true, "position": shell.current_room.player_position()}
		await shell.call("_on_campaign_return_requested")
		assert(shell._seal_fusion.active and not shell.current_room._controls_enabled)
		assert(shell._source_dialogue_label == null)
		shell.call("_show_campaign_menu")
		assert(shell.interaction_dialog == null, "Menus must not interrupt seal assembly")
		shell._seal_fusion._timeline.custom_step(5.0)
		await process_frame
		assert(not shell._seal_fusion.active and not shell.current_room._controls_enabled)
		assert(shell._source_dialogue_label.text == preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter).after_win_text)
		shell.call("_clear_dialog")
		var replay := BattleFixture.new()
		shell.screen_host.add_child(replay)
		shell.current_battle = replay
		shell._trainer_return_location = {"room_id": String(sage_room.id), "encounter_id": String(encounter_id), "first_visit": false, "position": shell.current_room.player_position()}
		await shell.call("_on_campaign_return_requested")
		assert(not shell._seal_fusion.active and shell._source_dialogue_label == null and shell.current_room._controls_enabled, "Rematches must not replay seal assembly or first-win dialogue")
	shell.queue_free()
	presenter.queue_free()
	rewards.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: both source seal families, 4.95s choreography, cancellation, boss piece/key feedback and nonduplicate seal frontier")
	quit(0)
