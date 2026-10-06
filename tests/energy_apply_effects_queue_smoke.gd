extends SceneTree

const SOURCE_QUEUE := preload("res://src/presentation/source_battle_event_queue.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var unmatched := BattleEvent.new(0, &"cost_paid", &"a", &"a", {"move_id": "other"})
	var next := BattleEvent.new(1, &"decision_requested", &"b", &"")
	var fallback := SOURCE_QUEUE.build([unmatched, next])
	assert(fallback.events == [unmatched, next] and fallback.resource_events.is_empty())
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var actor := main.combatant_views["player-1"] as BattleCombatantView
	var presented: Array = []
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		presented.append({"kind": event.kind, "time": Time.get_ticks_usec(), "energy": int(actor.state_cache.energy)})
	)
	for hit in [true, false]:
		presented.clear()
		var energy_before := int(actor.state_cache.energy)
		var target := "player-1" if hit else "enemy-1"
		var events: Array[BattleEvent] = [
			BattleEvent.new(0, &"cost_paid", &"player-1", &"player-1", {"move_id": "base:move/titan_restore/tier2", "energy": energy_before - 4}),
			BattleEvent.new(1, &"energy_changed", &"player-1", &"player-1", {"amount": 1, "energy": energy_before - 3}),
			BattleEvent.new(2, &"move_used", &"player-1", &"", {"move_id": "base:move/titan_restore/tier2", "target_ids": [target], "hit": hit}),
		]
		if hit:
			events.append(BattleEvent.new(3, &"healed", &"player-1", &"player-1", {"amount": 0, "health": int(actor.state_cache.health)}))
		else:
			events.append(BattleEvent.new(3, &"missed", &"player-1", &"enemy-1", {"move_id": "base:move/titan_restore/tier2"}))
		events.append(BattleEvent.new(4, &"decision_requested", &"enemy-1", &""))
		var originals := events.duplicate()
		var queue := SOURCE_QUEUE.build(events)
		assert(queue.events[0] == events[2] and queue.events[1] == events[0] and queue.events[2] == events[1])
		assert(queue.resource_events.size() == 2 and events == originals)
		var completed := [false]
		_play(main, events, completed)
		await create_timer(0.2).timeout
		assert(int(actor.state_cache.energy) == energy_before, "Energy changed before ApplyEffects")
		while not completed[0]:
			await process_frame
		assert(presented[0].kind == &"move_used")
		assert(presented[1].kind == &"cost_paid" and presented[2].kind == &"energy_changed")
		var effect_delay := int(presented[1].time) - int(presented[0].time)
		assert(effect_delay >= (370000 if hit else 850000), "Resources did not wait for the hit/miss queue")
		assert(abs(int(presented[2].time) - int(presented[1].time)) < 50000, "Spending and restoration introduced an extra event pause")
		assert(int(actor.state_cache.energy) == energy_before - 3)
		assert(int(presented[4].time) - int(presented[2].time) >= 570000, "Next decision skipped source finishing tail")
	main.queue_free()
	await process_frame
	print("PASS: immutable source event ordering; energy spending/restoration at grouped ApplyEffects on hit and miss, no added resource pauses, decision handoff")
	quit(0)

func _play(main: Control, events: Array[BattleEvent], completed: Array) -> void:
	await main._present(events)
	completed[0] = true
