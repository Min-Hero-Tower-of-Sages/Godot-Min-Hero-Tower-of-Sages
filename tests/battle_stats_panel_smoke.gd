extends "res://tests/battle_replay_smoke.gd"

## Clicking a health bar: your own minion's opens its stats (name and types
## behind Details), an enemy's shows only name and types once faced before, a spectator inspects nobody, and any other click closes the panel.
##   godot --headless --path . --script res://tests/battle_stats_panel_smoke.gd

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.load_campaign(1)
	var encounter := runtime.catalog.get_definition(&"base:encounter/grass_floor1_room5_expert") as EncounterDefinition
	var replay := _record_battle(runtime, encounter, 9, 5)
	_expect(not replay.is_empty(), "a battle to inspect")
	if not replay.is_empty():
		await _test_panel(replay)
	if failures.is_empty():
		print("battle_stats_panel_smoke: %d checks passed" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("battle_stats_panel_smoke: %d of %d checks failed" % [failures.size(), checks])
		quit(1)

func _bar_point(view: BattleCombatantView) -> Vector2:
	var sprite := view.health_background_sprite
	return sprite.get_global_transform_with_canvas() * (sprite.texture.get_size() * 0.5)

func _test_panel(replay: Dictionary) -> void:
	var battle: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.call("begin_replay", replay)
	await create_timer(3.0, true, false, true).timeout
	battle.set_playback_speed(0.0) # Hold the battle still while clicking around.
	var own: BattleCombatantView = null
	var enemy: BattleCombatantView = null
	for view in battle.combatant_views.values():
		if view.team == 0 and own == null: own = view
		elif view.team == 1 and enemy == null: enemy = view
	_expect(own != null and enemy != null, "both sides are on screen")
	if own == null or enemy == null:
		battle.queue_free()
		return
	var panel: BattleStatsPanel = battle.stats_panel
	_expect(battle.call("_handle_stats_click", _bar_point(own)), "clicking your minion's health bar is used")
	_expect(panel.visible and panel.instance_id == own.instance_id, "it opens that minion's stats")
	await create_timer(0.4, true, false, true).timeout
	_expect(panel.modulate.a > 0.99, "the panel fades in even while the replay is paused")
	var text: String = panel._stats.get_parsed_text()
	for caption in ["Health", "Energy", "Attack", "Healing", "Speed"]:
		_expect(text.contains(caption), "the stats show %s" % caption)
	_expect(not text.contains("Critical"), "the compact panel leaves out critical chance")
	_expect(text.contains("%d/%d" % [int(own.state_cache.health), int(own.state_cache.max_health)]), "health matches what is on screen")
	BattleStatsPanel.details_open = false
	panel.refresh(own)
	_expect(not panel._identity.visible and panel._details_button.visible, "name and types wait behind Details")
	(panel._details_button as Button).pressed.emit()
	_expect(panel._identity.visible and panel._name.text == own.minion_definition.display_name, "Details shows the name")
	_expect(panel._types.get_child_count() == (own.state_cache.type_ids as Array).size(), "and one type badge per type")
	(panel._details_button as Button).pressed.emit()
	_expect(not panel._identity.visible, "Hide details folds them away")
	_expect(not battle.call("_handle_stats_click", _bar_point(enemy)), "an enemy in a replay opens nothing")
	_expect(not panel.visible, "and any other click closes the panel")
	battle.call("_handle_stats_click", _bar_point(own))
	_expect(battle.call("_handle_stats_click", _bar_point(own)) and not panel.visible, "clicking the same bar again closes it")
	# An enemy species from the Minion-pedia (faced in an earlier fight).
	var state = root.get_node("CampaignRuntime").session.state
	var enemy_id := String(enemy.minion_definition.id)
	state.progression["seen_minion_ids"] = [enemy_id]
	battle.net_role = &"pvp"
	_expect(battle.call("_handle_stats_click", _bar_point(enemy)) and panel.visible, "a known enemy's bar opens its panel")
	_expect(panel._identity.visible and not panel._stats.visible and not panel._details_button.visible, "an enemy shows only its name and types, no stats")
	_expect(panel.size.x < 200.0, "the enemy panel fits its badges (%d px wide)" % panel.size.x)
	battle.call("_handle_stats_click", _bar_point(enemy))
	battle.campaign_mode = true
	state.pending_battle = {"first_seen_minion_ids": [enemy_id]}
	_expect(not battle.call("_handle_stats_click", _bar_point(enemy)), "a species first met in this very fight stays unknown")
	battle.campaign_mode = false
	state.pending_battle = {}
	state.progression["seen_minion_ids"] = []
	_expect(not battle.call("_handle_stats_click", _bar_point(enemy)), "a species never faced stays unknown")
	battle.net_role = &"spectator"
	_expect(not battle.call("_handle_stats_click", _bar_point(own)) and not panel.visible, "a spectator inspects nobody")
	battle.net_role = &"replay"
	battle.call("_exit_replay")
	battle.queue_free()
	await process_frame
