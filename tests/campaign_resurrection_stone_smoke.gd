extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	main._reset_move_selector_animation()
	main.move_panel.hide()
	var view := main.combatant_views["enemy-1"] as BattleCombatantView
	var death_events: Array[BattleEvent] = [
		BattleEvent.new(0, &"defeated", &"player-1", &"enemy-1", {"health": 0}),
		BattleEvent.new(1, &"battle_mod_resurrection_progressed", &"", &"enemy-1", {"elapsed": 1, "required": 3}),
	]
	var death_completion := {"done": false}
	var death_started := Time.get_ticks_usec()
	_present(main, death_events, death_completion)
	await create_timer(0.4).timeout
	assert(not main.resurrection_tombstones.has("enemy-1"), "Tombstone must wait until defeat playback finishes")
	var appearance_deadline := Time.get_ticks_usec() + 2500000
	while not main.resurrection_tombstones.has("enemy-1") and Time.get_ticks_usec() < appearance_deadline:
		await process_frame
	assert(main.resurrection_tombstones.has("enemy-1"))
	var marker: Dictionary = main.resurrection_tombstones["enemy-1"]
	var marker_root := marker.root as Node2D
	assert(marker_root.visible and marker_root.modulate.a < 0.5 and marker.label.text == "1")
	assert(not death_completion.done and not main.current_turn_indicator.visible)
	while not death_completion.done:
		await process_frame
	assert(Time.get_ticks_usec() - death_started >= 2700000, "Death tail and source tombstone handoff must both finish")
	assert(is_equal_approx(marker_root.modulate.a, 1.0))
	view.state_cache.statuses = [{"kind": &"periodic", "move_id": &"base:move/burn/tier1"}]
	view.state_cache.stat_stages = {"attack": -1}
	var revive_events: Array[BattleEvent] = [BattleEvent.new(2, &"battle_mod_resurrected", &"", &"enemy-1", {"health": 20})]
	var revival_completion := {"done": false}
	var revival_started := Time.get_ticks_usec()
	_present(main, revive_events, revival_completion)
	await create_timer(0.25).timeout
	assert(not revival_completion.done and marker_root.visible and marker_root.modulate.a < 1.0)
	assert(not view._death_started and view.visible and view.state_cache.statuses.is_empty() and view.state_cache.stat_stages.is_empty())
	while not revival_completion.done:
		await process_frame
	assert(Time.get_ticks_usec() - revival_started >= 1000000)
	assert(not marker_root.visible and not main.current_turn_indicator.visible)
	main.queue_free()
	await process_frame
	print("PASS: resurrection follows death playback, tombstone countdown/fades, immediate effect clearing and source 1s revival handoff")
	quit(0)

func _present(main: Control, events: Array[BattleEvent], completion: Dictionary) -> void:
	await main._present(events)
	completion.done = true
