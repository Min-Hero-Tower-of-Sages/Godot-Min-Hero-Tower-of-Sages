extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var actor := main.controller.engine._state.combatants[&"player-1"] as CombatantState
	var target := main.controller.engine._state.combatants[&"enemy-1"] as CombatantState
	var burn := main.catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	actor.energy = maxi(actor.energy, burn.energy_cost)
	main.controller.engine._current_events.clear()
	var targets: Array[StringName] = [&"enemy-1"]
	main.controller.engine._perform_move(actor, burn, targets, true, false)
	var events: Array[BattleEvent] = main.controller.engine._current_events
	_check(events.any(func(event: BattleEvent) -> bool: return event.kind == &"move_used" and bool(event.values.get("hit", false))), "Starter Burn did not hit")
	_check(events.any(func(event: BattleEvent) -> bool: return event.kind == &"periodic_applied"), "Starter Burn did not inflict its DOT")
	main._present(events)
	await create_timer(0.3).timeout
	var cue := main.audio_controller.get_node_or_null("battle_flamethrower") as AudioStreamPlayer
	_check(cue != null and cue.stream != null and is_equal_approx(db_to_linear(cue.volume_db), 0.4), "Starter Burn is missing its inherited flamethrower sound")
	for visual_id in [1, 13, 177]:
		var binding: Dictionary = main.audio_controller.binding_for_visual(visual_id)
		_check(binding.get("main") == "battle_flamethrower" and is_equal_approx(float(binding.get("main_volume", 0.0)), 0.4), "Inherited Burn-family sound missing")
	_check(main.audio_controller.binding_for_visual(141).get("main") == "battle_wingsFlapping", "Hurricane sound override was overwritten")
	var flames := 0
	for child in main.move_vfx_layer.get_children():
		if child is Sprite2D and child.texture == main.vfx_catalog.texture_for(1):
			flames += 1
			_check(child.visible and child.modulate.a > 0.1, "Burn flame is invisible at cast")
			var rect: Rect2 = Rect2(child.global_position, child.texture.get_size() * child.scale)
			_check(rect.intersects(Rect2(Vector2.ZERO, main.size)), "Burn flame is outside the battle viewport")
	_check(flames == 3, "Burn must create exactly three cast flames, not zero or duplicated DOT flames")
	await create_timer(1.6).timeout
	_check(main.move_vfx_layer.get_child_count() == 0, "Burn leaves orphan effect sprites")
	main.queue_free()
	await process_frame
	print("%s: starter Burn damage/DOT, visible flames, inherited flamethrower cue, Burn-family defaults and Hurricane override" % ["PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
