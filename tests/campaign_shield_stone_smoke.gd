extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var original_session: CampaignSession = runtime.session
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.progression = {"floor_index": 1, "battle_basics_tutorial_seen": true, "focus_targets_tutorial_seen": true, "shield_modifier_tutorial_seen": true}
	for index in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("shield-fixture-%d" % index)
		owned.definition_id = &"base:minion/fire_pig_1"
		owned.level = 60
		owned.learned_move_ids.assign((session.catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
		session.state.party.append(owned)
	var encounter_id := &"base:encounter/grass_floor2_trainer_1"
	for definition in session.catalog._by_id.values():
		if definition is RoomDefinition and encounter_id in definition.encounter_ids:
			session.state.current_room_id = definition.id
	runtime.session = session
	assert(runtime.prepare_trainer_battle(encounter_id, Vector2.ZERO).ok)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	var entry_clock := {"started": 0}
	main.battle_entry_animation_started.connect(func() -> void: entry_clock.started = Time.get_ticks_usec())
	main.call("begin_campaign_battle")
	var intro_start_usec := int(entry_clock.started)
	assert(intro_start_usec > 0)
	await create_timer(0.8).timeout
	var shielded_ids: Array = main.controller.engine.snapshot().state.combatants.filter(func(state: Dictionary) -> bool: return state.battle_mod_shield_active).map(func(state: Dictionary): return state.instance_id)
	assert(shielded_ids.size() == 2, "Authored encounter must mechanically assign one shield per team")
	for view in main.combatant_views.values():
		assert(not view.battle_mod_shield_sprite.visible and not bool(view.state_cache.get("battle_mod_shield_active", false)), "Initial shield must not leak into teleport-in")
	assert(main.busy and not main.move_panel.visible)
	while Time.get_ticks_usec() - intro_start_usec < 2800000:
		await process_frame
	for view in main.combatant_views.values():
		assert(not view.battle_mod_shield_sprite.visible)
	while Time.get_ticks_usec() - intro_start_usec < 3450000:
		await process_frame
	for id in shielded_ids:
		var view := main.combatant_views[String(id)] as BattleCombatantView
		assert(view.battle_mod_shield_sprite.visible and view._battle_mod_shield_tween.is_running())
	assert(main.busy and not main.move_panel.visible and not main.current_turn_indicator.visible, "Round's shield animation must finish before the decision is revealed")
	await _capture("first_round")
	var decision_timeout_usec := Time.get_ticks_usec() + 3000000
	while main.busy and Time.get_ticks_usec() < decision_timeout_usec:
		await process_frame
	assert(not main.busy)
	var player_views: Array = main.combatant_views.values().filter(func(view: BattleCombatantView) -> bool: return view.team == 0)
	var old_shield := player_views.filter(func(view: BattleCombatantView) -> bool: return bool(view.state_cache.battle_mod_shield_active))[0] as BattleCombatantView
	var next_shield := player_views.filter(func(view: BattleCombatantView) -> bool: return not bool(view.state_cache.battle_mod_shield_active))[0] as BattleCombatantView
	main._reset_move_selector_animation()
	main.move_panel.hide()
	main.busy = true
	var completion := {"done": false}
	var events: Array[BattleEvent] = [BattleEvent.new(0, &"battle_mod_shields_assigned", &"", &"", {"team": 0, "target_ids": [String(next_shield.instance_id)]})]
	var swap_start_usec := Time.get_ticks_usec()
	_present_and_record(main, events, completion)
	await create_timer(0.25).timeout
	assert(not old_shield.state_cache.battle_mod_shield_active and next_shield.state_cache.battle_mod_shield_active)
	assert(old_shield._battle_mod_shield_tween.is_running() and next_shield._battle_mod_shield_tween.is_running())
	assert(old_shield.battle_mod_shield_sprite.modulate.a > 0.0 and old_shield.battle_mod_shield_sprite.modulate.a < 1.0)
	assert(next_shield.battle_mod_shield_sprite.modulate.a > 0.0 and next_shield.battle_mod_shield_sprite.modulate.a < 1.0)
	assert(not completion.done and main.current_turn_indicator.modulate.a < 1.0, "Old actor marker may fade for .3s but must not be replaced during shield motion")
	await _capture("reassignment")
	while not completion.done and Time.get_ticks_usec() - swap_start_usec < 2000000:
		await process_frame
	assert(completion.done and Time.get_ticks_usec() - swap_start_usec >= 950000)
	assert(not main.current_turn_indicator.visible)
	assert(not old_shield.battle_mod_shield_sprite.visible and next_shield.battle_mod_shield_sprite.visible)
	var removal_start_usec := Time.get_ticks_usec()
	completion.done = false
	events = [BattleEvent.new(0, &"battle_mod_shield_removed", &"", next_shield.instance_id, {"team": 0})]
	_present_and_record(main, events, completion)
	await create_timer(0.25).timeout
	assert(not completion.done and next_shield._battle_mod_shield_tween.is_running())
	while not completion.done and Time.get_ticks_usec() - removal_start_usec < 2000000:
		await process_frame
	assert(completion.done and not next_shield.battle_mod_shield_sprite.visible)
	main.queue_free()
	await process_frame
	assert(runtime.cancel_unstarted_battle().ok)
	runtime.session = original_session
	print("PASS: authored shield entry deferred until StartRound, complete team reassignment, .8s source fades and 1s decision handoff for assignment/removal")
	quit(0)

func _present_and_record(main: Control, events: Array[BattleEvent], completion: Dictionary) -> void:
	await main.call("_present", events)
	completion.done = true

func _capture(suffix: String) -> void:
	if "--capture-shields" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://development/campaign_shield_%s.png" % suffix)
