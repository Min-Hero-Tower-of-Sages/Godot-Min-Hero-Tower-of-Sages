extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _template() -> Dictionary:
	return {"definition_id": "base:minion/fire_pig_1", "level": 20, "move_ids": [&"base:move/claw/tier1"], "max_health": 5000, "health": 5000, "max_energy": 5000, "energy": 5000, "attack": 100, "healing": 100, "max_attack_stat": 100, "max_healing_stat": 100, "speed": 20}

func _setup(players: int) -> Dictionary:
	var combatants: Array[Dictionary] = []
	for slot in players:
		var player := _template()
		player.instance_id = "handoff-owned-%d" % slot
		player.team = 0
		player.slot_index = slot
		player.health = 1
		combatants.append(player)
	var enemy := _template()
	enemy.instance_id = "handoff-enemy"
	enemy.team = 1
	enemy.speed = 100000
	enemy.max_attack_stat = 100000
	combatants.append(enemy)
	return {"combatants": combatants, "battle_id": "replacement-handoff-fixture"}

func _rules(players: int, timer: bool) -> RuleSetDefinition:
	var rules := RuleSetDefinition.new()
	var modifiers := {"extra_minions": {"player": {"count": players, "templates": [_template()]}}}
	if timer:
		var actor := _template()
		actor.instance_id = "handoff-timer"
		actor.team = 1
		modifiers.move_timer = {"interval": 1, "move_id": "base:move/burn/tier1", "actor": actor}
	rules.configuration = {"ai_teams": [], "battle_modifiers": modifiers}
	return rules

func _play(main: Control, events: Array[BattleEvent], completion: Dictionary) -> void:
	await main._present(events)
	completion.done = true

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.catalog = catalog
	main.busy = true
	var rules := _rules(1, true)
	var events: Array[BattleEvent] = []
	var before: Dictionary
	# Controlled native lethal action: replacement and the timer's attack are
	# resolved in one command response. Select a seed where that timer hits.
	for seed in 16:
		assert(main.controller.engine.start(_setup(1), catalog, rules, BattleRng.new(seed + 1)).accepted)
		before = main.controller.engine.snapshot()
		var decision: Dictionary = main.controller.engine.get_decision()
		var response: BattleResponse = main.controller.engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"base:move/claw/tier1", [&"handoff-owned-0"], int(decision.revision)))
		if response.events.any(func(event: BattleEvent) -> bool: return event.kind == &"move_used" and event.actor_id == &"handoff-timer" and bool(event.values.get("hit", false))):
			events = response.events
			break
	assert(not events.is_empty())
	var final_snapshot: Dictionary = main.controller.engine.snapshot()
	main.controller.engine.restore(before)
	main._original_player_ids["handoff-owned-0"] = true
	main._sync_from_engine()
	var original := main.combatant_views["handoff-owned-0"] as BattleCombatantView
	main.controller.engine.restore(final_snapshot)
	main.active_battle_modifiers = rules.configuration.battle_modifiers.duplicate(true)
	main._sync_battle_modifier_visuals(main.active_battle_modifiers)
	var spawn: BattleEvent
	for event in events:
		if event.kind == &"battle_mod_extra_spawned": spawn = event
	assert(spawn != null and spawn.values.has("combatant"))
	var replacement_id := String(spawn.target_id)
	var spawn_health := int(spawn.values.combatant.health)
	var final_health := int((main.controller.engine._state.combatants[spawn.target_id] as CombatantState).health)
	assert(final_health < spawn_health and main.combatant_views.get(replacement_id) == null)
	var times: Dictionary = {}
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"battle_mod_extra_spawned": times["spawn"] = Time.get_ticks_usec()
		if event.kind == &"battle_mod_timer_triggered":
			times["timer"] = Time.get_ticks_usec()
			var view := main.combatant_views.get(replacement_id) as BattleCombatantView
			assert(view != null and int(view.state_cache.health) == spawn_health, "Spawn view used the engine's future damaged health")
			assert(view.minion_sprite.modulate.a >= 0.98, "Timer targeted a replacement still entering")
		if event.kind == &"move_used" and event.actor_id == &"handoff-timer":
			times["cast"] = Time.get_ticks_usec()
			var view := main.combatant_views[replacement_id] as BattleCombatantView
			assert(not view.move_order_label.text.is_empty(), "Replacement had no source order badge before automatic cast")
			assert(is_equal_approx(view.minion_sprite.modulate.a, 1.0), "Automatic attack started before minion entry completed")
		if event.kind == &"damage" and event.actor_id == &"handoff-timer": times["timer_vfx_duration"] = main._last_move_visual_duration_seconds
	)
	var completed := {"done": false}
	_play(main, events, completed)
	await main._wait_until_usec(Time.get_ticks_usec() + 400000)
	assert(not main.combatant_views.has(replacement_id) and main.combatant_views["handoff-owned-0"] == original, "Replacement appeared before attack/death playback")
	while not completed.done: await process_frame
	assert(times.has("spawn") and times.timer - times.spawn >= int(main.BATTLE_REPLACEMENT_HANDOFF_SECONDS * 1000000.0))
	assert(times.timer - times.spawn < 1400000, "Replacement reused the unsourced full-intro pause")
	assert(times.cast - times.timer >= 700000)
	var replacement := main.combatant_views[replacement_id] as BattleCombatantView
	assert(int(replacement.state_cache.health) == final_health and not replacement.state_cache.statuses.is_empty())
	assert(float(times.get("timer_vfx_duration", 0.0)) > 0.0 and not main.current_turn_indicator.visible, "Timer did not animate its newly spawned target")
	assert(main._pending_extra_minion_animation_ids.is_empty(), "Already-presented replacement requested another entry after response")
	assert(main._retired_player_views["handoff-owned-0"] == original and not original.visible)
	assert(main.controller.engine.snapshot() == final_snapshot, "Event presentation mutated authoritative engine state")
	main._apply_event_values(BattleEvent.new(0, &"decision_requested", spawn.target_id, &"", {"turn_order": [spawn.target_id, &"handoff-enemy"]}))
	assert(replacement.move_order_label.text == "1" and (main.combatant_views["handoff-enemy"] as BattleCombatantView).move_order_label.text == "2", "Handoff badges read the engine's future order instead of their event")
	assert(main.controller.engine.snapshot() == final_snapshot)
	main._sync_from_engine()
	assert(main.combatant_views[replacement_id] == replacement and main._pending_extra_minion_animation_ids.is_empty())
	main._restore_player_replacement_views()
	assert(main.combatant_views["handoff-owned-0"] == original and original.visible)
	main.queue_free()
	await process_frame
	# Two native spawn events belong to one entry phase, not two serial waits.
	var grouped: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(grouped)
	grouped.catalog = catalog
	grouped.busy = true
	assert(grouped.controller.engine.start(_setup(2), catalog, _rules(2, false), BattleRng.new(4)).accepted)
	grouped._original_player_ids = {"handoff-owned-0": true, "handoff-owned-1": true}
	grouped._sync_from_engine()
	grouped.controller.engine._current_events.clear()
	for slot in 2:
		var actor := grouped.controller.engine._state.combatants[StringName("handoff-owned-%d" % slot)] as CombatantState
		actor.health = 0
		actor.defeated = true
	grouped.controller.engine._inject_extra_minions()
	var spawn_times: Array[int] = []
	grouped.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"battle_mod_extra_spawned": spawn_times.append(Time.get_ticks_usec())
	)
	await grouped._present(grouped.controller.engine._current_events)
	assert(spawn_times.size() == 2 and spawn_times[1] - spawn_times[0] < 100000, "Sibling replacement entries were serialized")
	assert(grouped._pending_extra_minion_animation_ids.is_empty() and grouped._retired_player_views.size() == 2)
	grouped.queue_free()
	await process_frame
	print("PASS: native same-response lethal replacement/timer, spawn-time HP rather than future state, entry/lead-in gates, owned finish restoration, no double entry, grouped sibling spawns and unchanged engine snapshot")
	quit(0)
