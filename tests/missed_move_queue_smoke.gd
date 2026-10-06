extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sample := preload("res://content/sample/sample_content_factory.gd")
	var catalog := sample.build_catalog()
	catalog.rebuild_index()
	var strike := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	strike.target_mode = MoveDefinition.TargetMode.RANDOM
	strike.target_count = 2
	strike.accuracy_percent = 0
	var engine := BattleEngine.new()
	var setup := sample.battle_setup()
	var second_enemy: Dictionary = setup.combatants[1].duplicate(true)
	second_enemy.instance_id = "enemy-2"
	setup.combatants.append(second_enemy)
	engine.start(setup, catalog, sample.build_rules(), BattleRng.new(1, [0, 0, 0, 900000, 0, 0]))
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [], int(decision.revision)))
	assert(response.accepted)
	var used: BattleEvent
	var missed: BattleEvent
	for event in response.events:
		if event.kind == &"move_used": used = event
		if event.kind == &"missed": missed = event
	assert(used != null and missed != null and not bool(used.values.hit) and used.values.target_ids.size() == 2)
	assert(used.values.target_ids == missed.values.target_ids and String(missed.target_id) == String(used.values.target_ids[0]), "Random miss lost its locked recipients")
	assert(not response.events.any(func(event: BattleEvent) -> bool: return event.kind == &"damage"))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var move := main.catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	var casts: Array[int] = []
	main.move_vfx_layer.child_entered_tree.connect(func(child: Node) -> void:
		if child is Sprite2D and (child as Sprite2D).texture == main.MISS_TEXTURE:
			casts.append(Time.get_ticks_usec())
		else:
			assert(false, "Miss played the hit animation")
	)
	await process_frame
	for mode in ["buffered", "simultaneous", "single_visual"]:
		move.visuals_have_buffer = mode != "simultaneous"
		move.hit_each_target = mode != "single_visual"
		casts.clear()
		var before_one: Dictionary = (main.combatant_views["enemy-1"] as BattleCombatantView).state_cache.duplicate(true)
		var targets := ["enemy-1", "enemy-2"]
		var events: Array[BattleEvent] = [BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": String(move.id), "hit": false, "target_ids": targets}), BattleEvent.new(1, &"missed", &"player-1", &"enemy-1", {"move_id": String(move.id), "target_ids": targets})]
		await main._present(events)
		assert(casts.size() == (1 if mode == "single_visual" else 2), "Miss callouts missing or duplicated at final event")
		if mode == "buffered":
			assert(casts[1] - casts[0] >= 850000 and casts[1] - casts[0] < 1100000, "Miss ignored source per-target .1+.8 queue")
		elif mode == "simultaneous":
			assert(casts[1] - casts[0] < 50000, "Simultaneous misses were staggered")
		assert(main.move_vfx_layer.get_child_count() == 0, "Miss callout survived actor handoff")
		assert((main.combatant_views["enemy-1"] as BattleCombatantView).state_cache.health == before_one.health)
	main.queue_free()
	await process_frame
	print("PASS: random miss recipients, buffered/simultaneous/single-per-team callouts, no hit animation, duplicate popup or HP damage")
	quit()
