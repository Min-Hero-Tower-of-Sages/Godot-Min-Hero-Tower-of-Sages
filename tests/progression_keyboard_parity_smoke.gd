extends SceneTree

var finishes := 0

func _initialize() -> void:
	_run.call_deferred()

func _key(presenter: BattleProgressionPresenter, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	presenter._input(event)

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var definition := catalog.get_definition(&"base:minion/raptor_1") as MinionDefinition
	var stats := CampaignProgressionService.owned_stats(OwnedMinionState.new(), definition, 5)
	var owned := OwnedMinionState.new()
	owned.instance_id = &"keyboard-fixture"
	owned.definition_id = definition.id
	owned.level = 6
	owned.experience = 6070
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	var view := BattleCombatantView.new()
	root.add_child(view)
	view.setup({"instance_id": String(owned.instance_id), "team": 0, "slot_index": 0, "level": 5, "health": stats.health, "max_health": stats.health, "shield": 0, "max_shield": 0}, definition, presenter._presentation_texture(definition, catalog))
	presenter._sequence_active = true
	presenter._sequence_id = 41
	presenter.sequence_finished.connect(func() -> void: finishes += 1)
	var bar := presenter._create_experience_bar(view, 5370)
	presenter._animate_experience(bar, 1000.0, 0.6, 41)
	await create_timer(0.05).timeout
	_key(presenter, KEY_SPACE)
	await process_frame
	await process_frame
	assert(is_equal_approx(float(bar.get_node("Fill").value), 1000.0), "Space must finish XP filling at its destination")
	var popup := presenter._create_level_popup(view, owned, definition, 5, null)
	presenter._present_level_popup(popup, view, owned, definition, 5, 41)
	await create_timer(0.05).timeout
	_key(presenter, KEY_ENTER)
	await create_timer(0.05).timeout
	assert(not is_instance_valid(popup), "Enter must skip the whole level card, not only its entrance")
	var next_stats := CampaignProgressionService.owned_stats(owned, definition, 6)
	assert(view.health_bar.max_value == next_stats.health, "Skipped card must still apply its level stat display")
	for modal_name in ["TalentTreeModal", "ProgressionModal", "FirstDefeatTutorial"]:
		var modal := Control.new()
		modal.name = modal_name
		presenter.add_child(modal)
		var prior_revision := presenter._skip_revision
		_key(presenter, KEY_SPACE)
		_key(presenter, KEY_ESCAPE)
		assert(presenter._skip_revision == prior_revision and finishes == 0 and presenter._sequence_active, "Queue shortcuts must not bypass active choices/tutorials")
		modal.queue_free()
		await process_frame
	_key(presenter, KEY_ESCAPE)
	assert(finishes == 1 and not presenter._sequence_active, "Escape must finish result playback exactly once")
	assert(owned.level == 6 and owned.experience == 6070, "Playback skipping cannot undo settled rewards")
	presenter.queue_free()
	view.queue_free()
	await process_frame
	print("PASS: XP destination, whole-card skip/stat update, protected modals, Escape return and settled reward preservation")
	quit(0)
