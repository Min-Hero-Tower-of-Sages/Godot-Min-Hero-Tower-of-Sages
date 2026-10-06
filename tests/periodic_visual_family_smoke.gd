extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var target := main.combatant_views["player-1"] as BattleCombatantView
	var periodic_ids: Dictionary = {}
	var families: Dictionary = {}
	for content in main.catalog._by_id.values():
		if not content is MoveDefinition:
			continue
		for effect in content.effects:
			if effect.kind in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL]:
				periodic_ids[main._resolved_dot_visual_id(content)] = {"move": content, "kind": effect.kind}
	assert(not periodic_ids.is_empty())
	var longest := 0.0
	var orbit_ticks := 0
	for visual_id in periodic_ids:
		var entry: Dictionary = periodic_ids[visual_id]
		var move := entry.move as MoveDefinition
		var profile: Dictionary = main.vfx_catalog.profile_for(visual_id)
		var family := String(profile.get("family", ""))
		families[family] = int(families.get(family, 0)) + 1
		assert(not family.is_empty(), "Authored periodic move lacks its visual profile: %s" % move.id)
		for kind in [&"periodic_applied", &"periodic_tick"]:
			main._last_move_visual_duration_seconds = 0.0
			var event := BattleEvent.new(0, kind, &"hidden-timer-caster", &"player-1", {"move_id": String(move.id), "kind": entry.kind, "amount": 1})
			var previous_objects: Array = main.move_vfx_layer.get_children()
			var contact := float(main._animate_periodic_tick(event) if kind == &"periodic_tick" else main._animate_periodic_application(event))
			var duration: float = main._last_move_visual_duration_seconds
			var native_objects := 0
			for child in main.move_vfx_layer.get_children():
				if child is Sprite2D and child.texture == main.vfx_catalog.texture_for(visual_id) and not previous_objects.has(child):
					native_objects += 1
			assert(duration > 0.0, "Periodic visual did not establish its lifetime: %s" % move.id)
			longest = maxf(longest, duration)
			if family == "orbit_into_target":
				orbit_ticks += 1 if kind == &"periodic_tick" else 0
				var count := clampi(int(profile.get("count", 8)), 1, main.TARGET_ORBIT_X.size())
				assert(native_objects == count, "Periodic orbit must create the recovered objects, not a generic single fade")
				var speed := maxf(0.05, float(profile.get("movement_speed", 0.7)))
				var hang := maxf(0.0, float(profile.get("hang_time", 0.5)))
				assert(is_equal_approx(contact, 0.2 + hang + speed))
				var stagger := 0.0 if bool(profile.get("all_enter_at_same_time", false)) else count * float(profile.get("delay", 0.1))
				var expected_duration := float(profile.final_hang_time) + hang + speed + stagger - 0.2
				assert(is_equal_approx(duration, expected_duration), "Periodic orbit does not use recovered m_moveTime cleanup")
			elif family == "burn_at_target":
				assert(native_objects == mini(int(profile.get("count", 3)), 8))
				assert(is_equal_approx(contact, 0.5) and is_equal_approx(duration, 1.2))
			elif family == "rise_out_of_target":
				assert(native_objects == clampi(int(profile.get("count", 1)), 1, 12), "Unexpected native rise-object count for %s: %d" % [move.id, native_objects])
			elif family in ["rotate_into_target", "fall_onto_target", "fall_from_top"]:
				assert(native_objects == clampi(int(profile.get("count", 3 if family == "fall_from_top" else 1)), 1, 8), "Periodic %s still uses a generic fade instead of native objects" % family)
	print("Authored periodic visual families: ", families, " IDs: ", periodic_ids.size(), " orbit ticks: ", orbit_ticks)
	# Independently exercise the simultaneous orbit lifetime even if this source
	# catalog's periodic moves use only other families.
	main._last_move_visual_duration_seconds = 0.0
	main._animate_visual_instance(162, target)
	assert(main._last_move_visual_duration_seconds < 1.5, "Simultaneous orbit still waits for a fictitious seven-object stagger")
	longest = maxf(longest, main._last_move_visual_duration_seconds)
	await create_timer(longest + 0.8).timeout
	assert(main.move_vfx_layer.get_child_count() == 0, "Periodic visual objects did not clean up after their declared lifetime")
	main.queue_free()
	await process_frame
	print("PASS: all authored periodic application/tick families, hidden caster anchors, native object counts/contact/lifetime, simultaneous orbit gate and cleanup")
	quit()
