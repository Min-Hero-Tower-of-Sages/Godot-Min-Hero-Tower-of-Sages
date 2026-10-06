extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://development/staged_import/moves-20260911-g/moves.json"))
	var recovered := 0
	for entry in source:
		var definition := main.catalog.get_definition(StringName(entry.id)) as MoveDefinition
		assert(definition != null and definition.visuals_have_buffer == bool(entry.visuals_have_buffer), "Lost source buffer flag: %s" % entry.id)
		recovered += 1
	assert(recovered == 918)
	# The catalog audit is synchronous CPU work, not battle playback. Begin
	# animation sampling on a fresh frame so its delta cannot consume a lunge.
	await process_frame
	await process_frame
	var burn := main.catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	var cast_times: Array[int] = []
	var actor_offsets: Array[float] = []
	var damage_times: Array[int] = []
	var actor := main.combatant_views["player-1"] as BattleCombatantView
	var actor_anchor_x := actor.position.x
	main.move_vfx_layer.child_entered_tree.connect(func(_child: Node) -> void:
		var now := Time.get_ticks_usec()
		if cast_times.is_empty() or now - cast_times.back() > 300000:
			cast_times.append(now)
			actor_offsets.append(actor.position.x - actor_anchor_x)
	)
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"damage":
			damage_times.append(Time.get_ticks_usec())
	)
	for mode in ["buffered", "simultaneous", "single_visual"]:
		burn.visuals_have_buffer = mode != "simultaneous"
		burn.hit_each_target = mode != "single_visual"
		cast_times.clear()
		actor_offsets.clear()
		damage_times.clear()
		var enemy_one := main.combatant_views["enemy-1"] as BattleCombatantView
		var enemy_two := main.combatant_views["enemy-2"] as BattleCombatantView
		var events: Array[BattleEvent] = [
			BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": String(burn.id), "target_ids": ["enemy-1", "enemy-2"], "hit": true}),
			BattleEvent.new(1, &"damage", &"player-1", &"enemy-1", {"amount": 1, "health": int(enemy_one.state_cache.health) - 1}),
			BattleEvent.new(2, &"damage", &"player-1", &"enemy-2", {"amount": 1, "health": int(enemy_two.state_cache.health) - 1}),
		]
		await main._present(events)
		assert(actor_offsets.all(func(offset: float) -> bool: return offset > 10.0 and offset <= 20.1), "Source actor lunge did not lead each visual cast: %s anchor=%f" % [actor_offsets, actor_anchor_x])
		assert(is_equal_approx(actor.position.x, actor_anchor_x), "Actor did not return to its authored slot")
		assert(damage_times.size() == 2 and abs(damage_times[1] - damage_times[0]) < 50000, "ApplyEffects staggered HP per target: %s" % mode)
		if mode == "buffered":
			assert(cast_times.size() == 2 and cast_times[1] - cast_times[0] >= 1150000, "Buffered target casts overlapped")
			assert(damage_times[0] - cast_times[0] >= 2250000, "Effects applied before buffered sequence finished")
		else:
			assert(cast_times.size() == 1, "Simultaneous/single visual mode emitted multiple cast groups")
			assert(damage_times[0] - cast_times[0] >= 1050000 and damage_times[0] - cast_times[0] < 1300000, "Wrong shared effect barrier")
		assert(main.move_vfx_layer.get_child_count() == 0 and not enemy_one._health_tween.is_running() and not enemy_two._health_tween.is_running())
	main.queue_free()
	await process_frame
	print("PASS: 918 recovered buffer flags; sequential/simultaneous/single-per-team visual queues, grouped ApplyEffects and HP completion")
	quit()
