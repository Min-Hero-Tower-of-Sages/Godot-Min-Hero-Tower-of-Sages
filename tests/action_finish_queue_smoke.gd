extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var actor := main.combatant_views["player-1"] as BattleCombatantView
	var enemy := main.combatant_views["enemy-1"] as BattleCombatantView
	var move_starts: Array[int] = []
	var heal_times: Array[int] = []
	var cost_times: Array[int] = []
	var decision_times: Array[int] = []
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		match event.kind:
			&"move_used": move_starts.append(Time.get_ticks_usec())
			&"healed": heal_times.append(Time.get_ticks_usec())
			&"cost_paid": cost_times.append(Time.get_ticks_usec())
			&"decision_requested": decision_times.append(Time.get_ticks_usec())
	)
	# White-flash has a literal .4s source lifetime and .3s effects wait.
	# No resource change means HP animation cannot accidentally supply the tail.
	await process_frame
	var events: Array[BattleEvent] = [
		BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": "base:move/titan_restore/tier2", "target_ids": ["player-1"], "hit": true}),
		BattleEvent.new(1, &"healed", &"player-1", &"player-1", {"health": int(actor.state_cache.health), "amount": 0}),
		BattleEvent.new(2, &"cost_paid", &"enemy-1", &"enemy-1", {"move_id": "base:move/titan_restore/tier2", "energy": int(enemy.state_cache.energy)}),
		BattleEvent.new(3, &"move_used", &"enemy-1", &"", {"move_id": "base:move/titan_restore/tier2", "target_ids": ["enemy-1"], "hit": true}),
		BattleEvent.new(4, &"healed", &"enemy-1", &"enemy-1", {"health": int(enemy.state_cache.health), "amount": 0}),
		BattleEvent.new(5, &"decision_requested", &"player-1", &""),
	]
	await main._present(events)
	assert(move_starts.size() == 2 and heal_times.size() == 2 and cost_times.size() == 1)
	assert(cost_times[0] - heal_times[0] >= 570000, "Automatic next action paid its cost before prior source .2+.4 finish")
	assert(move_starts[1] - heal_times[0] >= 570000, "Automatic cast overlapped the prior finishing queue")
	assert(Time.get_ticks_usec() - heal_times[1] >= 570000, "Full-health heal skipped source finish because no HP tween ran")
	assert(decision_times.size() == 1 and decision_times[0] - heal_times[1] >= 570000, "Awaiting-decision prompt appeared during prior finishing queue")
	assert(Time.get_ticks_usec() - heal_times[1] < 850000, "No-op heal added another unnecessary finishing pause")
	assert(not main.current_turn_indicator.visible)
	assert(main.get_node_or_null("SourceTestVisualWhiteFlash") == null)
	main.queue_free()
	await process_frame
	print("PASS: unconditional .2+.4 source finish, no-op healing, automatic cost/cast isolation and hidden indicator")
	quit()
