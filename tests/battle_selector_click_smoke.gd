extends "res://tests/battle_replay_smoke.gd"

## Move selection clicks as in the source (BattleScreenVisualController.reportClick):
## empty ground closes the selector, your acting minion reopens it, another of
## your minions shows its moves greyed out (not choosable); health bar stats
## still open meanwhile. Also: the move tooltip's type badge is not clipped.
##   godot --headless --path . --script res://tests/battle_selector_click_smoke.gd

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.load_campaign(1)
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	runtime.session.state.current_room_id = &"base:room/level_1_1_a"
	_expect(runtime.prepare_trainer_battle(&"base:encounter/grass_floor1_room1_normal", Vector2.ZERO).get("ok", false), "a trainer battle is prepared")
	var battle: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	battle.call("begin_campaign_battle")
	var deadline := Time.get_ticks_msec() + 20000
	while not (battle.move_panel.visible and not battle.busy) and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.2).timeout
	_expect(battle.move_panel.visible, "your move selector opens on your turn")
	var decision: Dictionary = battle.controller.engine.get_decision()
	var actor: BattleCombatantView = battle.combatant_views[String(decision.actor_id)]
	var teammate: BattleCombatantView = null
	var enemy: BattleCombatantView = null
	for view in battle.combatant_views.values():
		if view.team == 0 and view != actor and teammate == null: teammate = view
		elif view.team == 1 and enemy == null: enemy = view
	_expect(battle._selector_minion_id == actor.instance_id, "the selector starts on the acting minion")
	# Stats on a health bar while choosing.
	_expect(battle.call("_handle_stats_click", _bar(actor)), "a health bar opens stats during your move selection")
	battle.stats_panel.close()
	# Empty ground closes the selector and the grey layer.
	_expect(battle.call("_handle_selector_click", Vector2(350.0, 515.0)), "a click on empty ground is used")
	await create_timer(1.5).timeout
	_expect(not battle.move_panel.visible and not battle.battle_grey_layer.visible, "it closes the selector and the grey layer")
	# Your acting minion brings it back.
	_expect(battle.call("_handle_selector_click", _body(actor)), "clicking your acting minion is used")
	await create_timer(0.8).timeout
	_expect(battle.move_panel.visible and battle._selector_minion_id == actor.instance_id, "it reopens the selector")
	_expect(_choosable_buttons(battle) > 0, "the acting minion's moves can be chosen")
	if teammate != null:
		# A teammate under the open selector is covered by it (in the source a
		# click hitting both does nothing); close it first, as a player would.
		battle.call("_handle_selector_click", Vector2(350.0, 515.0))
		await create_timer(1.5).timeout
		_expect(battle.call("_handle_selector_click", _body(teammate)), "clicking another of your minions is used")
		await create_timer(0.8).timeout
		_expect(battle._selector_minion_id == teammate.instance_id and battle.move_panel.visible, "it shows that minion's moves")
		_expect(_choosable_buttons(battle) == 0, "which cannot be chosen")
		_expect(battle.move_panel.modulate.r < 0.9, "and are greyed out")
		battle.call("_handle_selector_click", _body(actor))
		await create_timer(0.8).timeout
		_expect(_choosable_buttons(battle) > 0 and battle.move_panel.modulate.r > 0.99, "back on the acting minion, moves can be chosen again")
	# The move tooltip's type badge stays whole.
	var tooltip: BattleMoveTooltip = battle.move_tooltip
	tooltip.show_move(runtime.catalog.get_definition(&"base:move/claw/tier1"))
	await process_frame
	await process_frame
	_expect(not tooltip.details.clip_contents, "the tooltip text no longer clips the type badge")
	if tooltip.type_icon.visible:
		var badge := tooltip.type_icon.get_global_rect()
		_expect(tooltip.get_global_rect().grow(1.0).encloses(badge), "the type badge sits inside the tooltip frame (%s in %s)" % [badge, tooltip.get_global_rect()])
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("battle_selector_click_smoke: %d checks passed" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("battle_selector_click_smoke: %d of %d checks failed" % [failures.size(), checks])
		quit(1)

func _bar(view: BattleCombatantView) -> Vector2:
	var sprite := view.health_background_sprite
	return sprite.get_global_transform_with_canvas() * (sprite.texture.get_size() * 0.5)

func _body(view: BattleCombatantView) -> Vector2:
	return view.minion_sprite.get_global_transform_with_canvas().origin

func _choosable_buttons(battle: Node) -> int:
	var count := 0
	for child in battle.move_buttons.get_children():
		if child is Button and (child as Button).pressed.get_connections().size() > 0:
			count += 1
	return count
