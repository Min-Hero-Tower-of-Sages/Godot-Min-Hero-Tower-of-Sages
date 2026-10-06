extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CATALOG := preload("res://content/imported/recovered-20260911/catalog.tres")
const BATTLE_DEMO_PACK := preload("res://content/base/packs/battle_demo.tres")
const CAMPAIGN_SLICE_PACK := preload("res://content/base/packs/campaign_slice.tres")
const LegacyMinionStats = preload("res://src/domain/battle/legacy_minion_stats.gd")

var failures: Array[String] = []
var checks := 0
var save_calls := 0

func _initialize() -> void:
	var main := MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	call_deferred("_run_progression_flow", main)

func _run_progression_flow(main: Control) -> void:
	await process_frame
	var catalog := CATALOG.duplicate(true) as ContentCatalog
	for extra_pack in [BATTLE_DEMO_PACK, CAMPAIGN_SLICE_PACK]:
		var already_loaded := false
		for loaded_pack in catalog.packs:
			if loaded_pack != null and loaded_pack.id == extra_pack.id:
				already_loaded = true
				break
		if not already_loaded:
			catalog.packs.append(extra_pack)
	var catalog_errors := catalog.rebuild_index()
	_check(catalog_errors.is_empty(), "campaign content must resolve before progression visuals are built")
	main.catalog = catalog
	var definition := catalog.get_definition(&"base:minion/raptor_1") as MinionDefinition
	var texture: Texture2D = main._presentation_texture(definition)
	var old_stats := LegacyMinionStats.current_stats(definition, 5)
	var next_stats := LegacyMinionStats.current_stats(definition, 6)
	var owned := OwnedMinionState.new()
	owned.instance_id = &"progression-smoke-minion"
	owned.definition_id = definition.id
	owned.level = 5
	owned.experience = 5370
	owned.learned_move_ids.assign(definition.initial_move_ids)
	var view := BattleCombatantView.new()
	main.combatant_layer.add_child(view)
	view.setup({
		"instance_id": String(owned.instance_id),
		"team": 0,
		"slot_index": 0,
		"level": 5,
		"health": int(old_stats.health) - 3,
		"max_health": int(old_stats.health),
		"max_shield": 0,
		"shield": 0,
	}, definition, texture)
	_check(definition != null and texture != null, "a campaign minion definition must resolve to its recovered battle sprite")
	var presenter := main.campaign_progression_presenter as BattleProgressionPresenter
	var popup := presenter._create_level_popup(view, owned, definition, 5, main.audio_controller)
	_check((popup.get_node("LevelLabel") as Label).text == "lv.5" and popup.has_node("CurrentStat4") and popup.has_node("NextStat4"), "level-up card must show the current level and all five stat deltas")
	var skill_badge := popup.get_child(popup.get_child_count() - 1) as TextureRect
	_check(skill_badge != null and skill_badge.visible, "the source level cadence must show the talent marker for the level-six point")
	var prior_health := view.health_bar.value
	var health_increase := int(next_stats.health) - int(old_stats.health)
	popup.queue_free()
	# CampaignSession applies the reward before playback. The presenter must
	# receive the final owned level/XP, plus the old values in the award record.
	owned.level = 6
	owned.experience = 6070
	presenter.begin_sequence(
		[owned],
		{String(owned.instance_id): {"experience": 700, "old_experience": 5370, "new_experience": 6070, "old_level": 5, "new_level": 6}},
		catalog,
		{String(owned.instance_id): view},
		false,
		main.audio_controller,
		Callable(self, "_save_stub")
	)
	await create_timer(0.85).timeout
	var bar := presenter.get_node_or_null("ExperienceBar_%s" % String(owned.instance_id)) as Control
	_check(bar != null and bar.visible and float((bar.get_node("Fill") as TextureProgressBar).value) > 370.0, "post-battle experience must reveal the recovered bar and animate toward level-up")
	await create_timer(2.9).timeout
	var active_card := presenter.get_node_or_null("LevelUp_%s_6" % String(owned.instance_id)) as Control
	_check(active_card != null and (active_card.get_node("LevelLabel") as Label).text == "lv.6" and (active_card.get_node("CurrentStat0") as Label).text == str(next_stats.health), "the level card must apply and display the next-level stats at the source update point")
	main.campaign_mode = true
	main.result_overlay.visible = true
	main.restart_button.disabled = true
	var remaining_frames := 600
	var talent_modal := presenter.get_node_or_null("TalentTreeModal") as Control
	while talent_modal == null and remaining_frames > 0:
		await create_timer(0.02).timeout
		remaining_frames -= 1
		talent_modal = presenter.get_node_or_null("TalentTreeModal") as Control
	while talent_modal != null and talent_modal.has_node("TalentEntranceInputGuard") and remaining_frames > 0:
		await create_timer(0.02).timeout
		remaining_frames -= 1
	var specialization_button: TextureButton
	if talent_modal != null:
		for candidate in talent_modal.get_node("TalentTreePanel").get_children():
			if candidate is TextureButton and candidate.has_meta("move_id") and bool(candidate.get_meta("purchasable", false)):
				specialization_button = candidate
				break
	var selected_move_id := StringName(specialization_button.get_meta("move_id", "")) if specialization_button != null else &""
	if specialization_button != null:
		specialization_button.emit_signal("pressed")
	await process_frame
	_check_talent_selection(owned, selected_move_id)
	while main.restart_button.disabled and remaining_frames > 0:
		await create_timer(0.02).timeout
		remaining_frames -= 1
	await process_frame
	_check(not main.restart_button.disabled, "the campaign return button must unlock when the progression sequence finishes")
	_check(not presenter.visible and presenter.get_child_count() == 0, "the progression sequence must close its presentation nodes before room return")
	_check(view.level_label.text == "lv. 6" and int(view.health_bar.max_value) == int(next_stats.health) and int(round(view.health_bar.value)) == int(prior_health + health_increase), "the level-up must update the combatant display and award the source health-stat delta")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: campaign progression presentation (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d progression presentation checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _check_talent_selection(owned: OwnedMinionState, selected_move_id: StringName) -> void:
	_check(not selected_move_id.is_empty() and selected_move_id in owned.learned_move_ids, "clicking a source specialization must add the selected move to the owned minion")
	_check(save_calls == 1, "a completed talent purchase must save campaign progression immediately")

func _save_stub() -> Dictionary:
	save_calls += 1
	return {"ok": true}
