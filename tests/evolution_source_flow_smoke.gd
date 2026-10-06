extends SceneTree

class MemorySession extends CampaignSession:
	var reject := false
	var saved_state: Dictionary = {}
	func _save_candidate(candidate) -> Dictionary:
		assert(candidate.validation_errors(catalog).is_empty())
		if reject:
			return {"ok": false, "code": "fixture_save_rejected"}
		saved_state = candidate.to_dictionary(catalog.content_version)
		return {"ok": true}

class RecordingAudio extends BattleAudioController:
	var started := 0
	var sounds: Array[Dictionary] = []
	func play_sound(sound_id: String, volume: float = 1.0) -> bool:
		sounds.append({"id": sound_id, "time": float(Time.get_ticks_msec() - started) / 1000.0, "volume": volume})
		return true

var completed := false
var evolved := false

func _initialize() -> void:
	_run.call_deferred()

func _play(presenter: BattleProgressionPresenter, owned: OwnedMinionState, definition: MinionDefinition, view: BattleCombatantView, catalog: ContentCatalog, audio: BattleAudioController, save: Callable) -> void:
	completed = false
	evolved = await presenter._present_evolution(presenter._sequence_id, owned, definition, view, catalog, audio, save)
	completed = true

func _wait_finished() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not completed and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(completed, "Evolution must hand control back to the result queue")

func _capture(filename: String) -> void:
	if "--capture-evolution" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://development/" + filename)

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var definition := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var next_definition := catalog.get_definition(definition.evolution_id) as MinionDefinition
	var owned := OwnedMinionState.new()
	owned.instance_id = &"evolution-fixture"
	owned.definition_id = definition.id
	owned.nickname = definition.display_name
	owned.level = definition.evolution_level
	owned.experience = owned.level * 1000 + 250
	owned.learned_move_ids.assign(definition.initial_move_ids)
	owned.persistent_health = 21
	owned.persistent_energy = 17
	var session := MemorySession.new()
	session.catalog = catalog
	session.state = CampaignState.new()
	session.state.campaign_id = &"base:campaign/standard_tower"
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.party.append(owned)
	CampaignProgressionService.refresh_minion_pedia(session.state)
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	presenter.visible = true
	presenter._sequence_active = true
	presenter._sequence_id = 51
	var old_texture := presenter._presentation_texture(definition, catalog)
	var new_texture := presenter._presentation_texture(next_definition, catalog)
	var stats := CampaignProgressionService.owned_stats(owned, definition)
	var view := BattleCombatantView.new()
	root.add_child(view)
	view.position = Vector2(500, 350)
	view.setup({"instance_id": String(owned.instance_id), "team": 0, "slot_index": 0, "level": owned.level, "health": 21, "max_health": stats.health, "energy": 17, "max_energy": stats.energy, "shield": 0, "max_shield": 0}, definition, old_texture)
	var audio := RecordingAudio.new()
	root.add_child(audio)
	audio.started = Time.get_ticks_msec()
	_play(presenter, owned, definition, view, catalog, audio, session.save)
	var modal := presenter.get_node("ProgressionModal") as Control
	var panel := modal.get_node("Panel") as Control
	var old_sprite := panel.get_node("OldMask/OldSprite") as Sprite2D
	var new_sprite := panel.get_node("NewSprite") as Sprite2D
	assert(panel.position == Vector2.ZERO and not panel is Panel, "No generic centered frame or duplicate title")
	assert(panel.get_node("OldMask").clip_children == CanvasItem.CLIP_CHILDREN_ONLY)
	assert(panel.get_node("NewCover").position == Vector2(13, 7))
	assert(old_sprite.scale == Vector2.ONE and new_sprite.scale == Vector2.ONE)
	var old_start := old_sprite.position
	var new_start := new_sprite.position
	assert(new_start == Vector2(96 - new_texture.get_width() * 0.5, 169 - new_texture.get_height()))
	assert(panel.get_node("Message").position == Vector2(33, 246))
	assert(panel.get_node("CloseButton").position == Vector2(323, 7))
	await create_timer(0.8).timeout
	assert(old_sprite.position == old_start and owned.definition_id == definition.id)
	await _capture("evolution_source_start.png")
	await create_timer(2.3).timeout
	assert(old_sprite.position.x > old_start.x and old_sprite.position.x < old_start.x + 173)
	assert(is_equal_approx(old_sprite.position.x - old_start.x, new_sprite.position.x - new_start.x))
	assert(owned.definition_id == definition.id and session.saved_state.is_empty())
	await _capture("evolution_source_reveal.png")
	await create_timer(1.6).timeout
	assert(owned.definition_id == next_definition.id and owned.nickname == next_definition.display_name)
	assert(view.minion_sprite.texture == new_texture and not panel.get_node("CloseButton").visible)
	assert(panel.get_node("Message").text == "%s has grown into a %s!" % [definition.display_name, next_definition.display_name])
	assert(session.state.party[0] == owned, "Saving must preserve the presenter's live owned-minion reference")
	assert(String(next_definition.id) in session.saved_state.progression.owned_minion_ids and String(next_definition.id) in session.saved_state.progression.seen_minion_ids)
	assert(audio.sounds.size() == 2 and audio.sounds[0].id == "battle_whoosh_magic2" and audio.sounds[1].id == "battle_levelUp")
	assert(absf(audio.sounds[0].time - 2.0) < 0.25 and absf(audio.sounds[1].time - 3.7) < 0.25)
	await _capture("evolution_source_finished.png")
	await _wait_finished()
	assert(evolved and owned.persistent_health == 21 and owned.persistent_energy == 17)
	var bar := presenter._create_experience_bar(view, owned.experience)
	presenter._reposition_experience_bar(bar, view)
	assert(is_equal_approx(bar.get_node("Fill").position.y, view.position.y - new_texture.get_height() - 27))
	# Source close button cancels evolution, rather than applying it silently.
	owned.definition_id = definition.id
	owned.nickname = "Custom nickname"
	var before := owned.to_dictionary()
	_play(presenter, owned, definition, view, catalog, null, session.save)
	presenter.get_node("ProgressionModal/Panel/CloseButton").pressed.emit()
	await _wait_finished()
	assert(not evolved and owned.to_dictionary() == before)
	# Reject the evolution save: neither owned data nor the battle sprite commits.
	view.apply_campaign_evolution(definition, old_texture, stats.health, stats.energy, 21, 17)
	session.reject = true
	session.state.progression.owned_minion_ids.erase(String(next_definition.id))
	session.state.progression.seen_minion_ids.erase(String(next_definition.id))
	var prior_history: Dictionary = session.state.progression.duplicate(true)
	_play(presenter, owned, definition, view, catalog, null, session.save)
	await _wait_finished()
	assert(not evolved and owned.to_dictionary() == before and view.minion_sprite.texture == old_texture)
	assert(session.state.progression == prior_history)
	bar.queue_free()
	view.queue_free()
	audio.queue_free()
	presenter.queue_free()
	await process_frame
	print("PASS: source evolution geometry/mask/reveal/audio timing, committed sprite, Pedia persistence, nickname/health/energy, cancel and rejected-save rollback")
	quit()
