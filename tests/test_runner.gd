extends Node

const SampleFactory = preload("res://content/sample/sample_content_factory.gd")
const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyRolls = preload("res://src/domain/battle/legacy_move_rolls.gd")
const CampaignStateScript = preload("res://src/domain/campaign_state.gd")
const CampaignSessionScript = preload("res://src/application/campaign_session.gd")
const MainScene = preload("res://scenes/main.tscn")
const RuleModuleProbe = preload("res://tests/fixtures/battle_rule_module_probe.gd")

var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	_test_catalog()
	_test_recovered_catalog()
	_test_recovered_move_goldens()
	_test_legacy_current_minion_stats()
	_test_battle_determinism()
	_test_battle_result_contract()
	_test_ruleset_modules()
	_test_legacy_combat_math()
	_test_legacy_roll_boundaries()
	_test_type_chart_and_typed_damage()
	_test_periodic_lifecycle()
	_test_periodic_refresh_and_shield_block()
	_test_armor_reflection_and_redirection_order()
	_test_passive_stats_self_damage_and_shields()
	_test_derived_health_and_energy_maxima()
	_test_equal_speed_tie_preference()
	_test_shield_and_resurrection_battle_modifiers()
	_test_extra_minion_battle_modifier()
	_test_move_timer_battle_modifier()
	_test_charge_exhaust_and_cooldown_lifecycle()
	_test_defeated_cooldowns_do_not_tick()
	_test_frozen_and_stunned_turn_activation()
	_test_legacy_ai_selection_and_snapshot()
	_test_miss_cost_restore_and_cooldown_order()
	_test_shared_stat_and_condition_rolls()
	_test_rejected_command_is_atomic()
	_test_state_isolation()
	_test_presenter_independence()
	await _test_presenter_modes_are_equivalent()
	await _test_playable_recovered_battle_ui()
	_test_snapshot_restore()
	_test_save_validation()
	_test_campaign_catalog_and_progression()
	if failures.is_empty():
		print("PASS: %d checks" % checks)
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d of %d checks" % [failures.size(), checks])
		await get_tree().create_timer(3.0).timeout
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _ignore_event(_kind: StringName, _actor_id: StringName, _target_id: StringName, _values: Dictionary) -> void:
	pass

func _test_catalog() -> void:
	var catalog := SampleFactory.build_catalog()
	_expect(catalog.rebuild_index().is_empty(), "sample content must validate")
	_expect(catalog.has_definition(&"foundation:minion/apprentice"), "catalog indexes stable IDs")

func _test_recovered_catalog() -> void:
	var catalog := load("res://content/imported/recovered-20260911/catalog.tres") as ContentCatalog
	_expect(catalog != null, "maintained recovered catalog must load as a typed ContentCatalog")
	if catalog == null: return
	var errors := catalog.rebuild_index()
	_expect(errors.is_empty(), "maintained recovered catalog must validate every registered definition and reference: %s" % " | ".join(errors))
	var counts := {"types": 0, "charts": 0, "minions": 0, "moves": 0, "trees": 0, "presentations": 0, "unavailable": 0}
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is TypeDefinition: counts.types += 1
			elif definition is TypeChartDefinition: counts.charts += 1
			elif definition is MinionDefinition: counts.minions += 1
			elif definition is MoveDefinition:
				counts.moves += 1
				if not (definition as MoveDefinition).available: counts.unavailable += 1
			elif definition is TalentTreeDefinition: counts.trees += 1
			elif definition is MinionPresentationDefinition: counts.presentations += 1
	_expect(counts == {"types": 16, "charts": 1, "minions": 125, "moves": 923, "trees": 167, "presentations": 115, "unavailable": 5}, "recovered catalog must preserve the audited family counts and five unavailable source tombstones: %s" % counts)
	_expect(catalog.has_definition(&"base:move/holy_light/tier1"), "Holy Light typo correction must resolve to the exact maintained base move ID")
	_expect(catalog.has_definition(&"base:move/mud_blast/tier5"), "Ice Floor Mud Blast correction must resolve to the exact maintained base tier ID")
	_expect(ContentCatalog.canonical_mod_flag_id(&"holyBirb1") == &"holyBird1", "the source Arkvian tier-1 spelling must normalize to the maintained Bird flag")
	_expect(ContentCatalog.canonical_mod_flag_id(&"HolyBirb1") == &"holyBird1", "the inconsistent source tier-1 capitalization must normalize to the same maintained Bird flag")
	_expect(ContentCatalog.canonical_mod_flag_id(&"holyBirb2") == &"holyBird2", "the source Arkvian tier-2 spelling must normalize to the maintained Bird flag")
	_expect(catalog.get_pack_for_mod_flag(&"HolyBirb1") == catalog.get_definition(&"arkvian:pack/recovered"), "both exact source tier-1 spellings must resolve to the maintained Arkvian pack")
	_expect(catalog.get_pack_for_mod_flag(&"holyBirb2") == catalog.get_definition(&"arkvian:pack/recovered"), "the exact source tier-2 spelling must resolve to the maintained Arkvian pack")
	_expect(catalog.has_definition(&"arkvian:minion/holybird1") and catalog.has_definition(&"arkvian:minion/holybird2") and catalog.has_definition(&"base:talent_tree/holybird_flying"), "canonical Arkvian minion and talent-tree IDs must use Bird spelling")
	_expect(ContentCatalog.canonical_mod_flag_id(&"HOLYBIRB1") == &"HOLYBIRB1", "mod-flag correction must remain exact and must not add a general case-insensitive fallback")

func _test_recovered_move_goldens() -> void:
	var catalog := load("res://content/imported/recovered-20260911/catalog.tres") as ContentCatalog
	var rules := SampleFactory.build_rules()
	var setup := _recovered_setup(&"base:move/flare_up/tier1", [&"base:type/fire"])
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, rules, BattleRng.new(701, [0, 0, 0, 0, 0, 999999]))
	_expect(start.accepted, "source-derived Flare Up fixture must start from the maintained recovered catalog")
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(&"source-actor", BattleCommand.Kind.USE_MOVE, &"base:move/flare_up/tier1", [&"source-enemy"], int(decision.revision)))
	var used_event := response.events.filter(func(event: BattleEvent): return event.kind == &"move_used")[0] as BattleEvent
	_expect(used_event.values.get("target_ids", []) == ["source-enemy"], "move visuals must receive the resolved defender rather than guessing from later actor-side effects")
	var actor := _state_for(engine, "source-actor")
	var enemy := _state_for(engine, "source-enemy")
	_expect(actor.energy == 85 and enemy.health == 427, "Flare Up tier 1 must preserve source cost 15 and the level-10 25-power fire-STAB result of 73")
	_expect(enemy.statuses.size() == 1 and enemy.statuses[0].move_id == &"base:move/flare_up/tier1", "Flare Up tier 1 must attach its source three-turn periodic payload")
	_expect(actor.stat_stages.get(&"base:stat/attack") == -1 and actor.stat_stages.get(&"base:stat/speed") == -1 and enemy.stat_stages.get(&"base:stat/attack") == -1 and enemy.stat_stages.get(&"base:stat/speed") == -1, "Flare Up tier 1 must apply its four ordered source stat penalties")
	var effect_kinds: Array[StringName] = []
	for event in response.events:
		if event.kind in [&"damage", &"periodic_applied", &"stat_stage_changed"]: effect_kinds.append(event.kind)
	_expect(effect_kinds == [&"damage", &"periodic_applied", &"stat_stage_changed", &"stat_stage_changed", &"stat_stage_changed", &"stat_stage_changed"], "Flare Up effects must resolve in recovered source order")

	setup = _recovered_setup(&"base:move/drain/tier2", [&"base:type/plant"])
	setup.combatants[0].health = 150
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(704, [0, 0, 0, 0, 0, 999999]))
	decision = engine.get_decision()
	response = engine.submit(BattleCommand.new(&"source-actor", BattleCommand.Kind.USE_MOVE, &"base:move/drain/tier2", [&"source-enemy"], int(decision.revision)))
	actor = _state_for(engine, "source-actor")
	enemy = _state_for(engine, "source-enemy")
	var drain_damage_index := -1
	var drain_heal_index := -1
	var drain_heal_event: BattleEvent
	for event_index in response.events.size():
		var event := response.events[event_index] as BattleEvent
		if event.kind == &"damage" and event.target_id == &"source-enemy": drain_damage_index = event_index
		if event.kind == &"healed" and event.target_id == &"source-actor":
			drain_heal_index = event_index
			drain_heal_event = event
	_expect(start.accepted and drain_damage_index >= 0 and drain_heal_index > drain_damage_index, "Drain tier 2 must damage its selected enemy before its actor-after-targets self-heal")
	_expect(drain_heal_event != null and int(drain_heal_event.values.get("amount", 0)) > 0 and actor.health > 150 and enemy.health < 500, "Drain tier 2 must visibly restore missing HP to the move user while dealing damage to the opponent")

	setup = _recovered_setup(&"base:move/nourish/tier1", [&"base:type/plant"])
	setup.combatants.insert(1, {"instance_id": "source-ally", "definition_id": "base:minion/fire_pig_1", "team": 0, "slot_index": 1, "move_ids": [], "level": 10, "max_health": 200, "health": 100, "max_energy": 100, "energy": 100, "attack": 0, "healing": 0, "speed": 5, "type_ids": [&"base:type/none"]})
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(702, [0, 0, 0, 0, 0, 999999]))
	decision = engine.get_decision()
	response = engine.submit(BattleCommand.new(&"source-actor", BattleCommand.Kind.USE_MOVE, &"base:move/nourish/tier1", [&"source-ally"], int(decision.revision)))
	var ally := _state_for(engine, "source-ally")
	_expect(start.accepted and ally.health == 115 and ally.statuses.size() == 1 and ally.statuses[0].move_id == &"base:move/nourish/tier1", "Nourish tier 1 must heal 15 with plant STAB and attach its source periodic heal")

	setup = _recovered_setup(&"base:move/fresh_stream/tier1", [&"base:type/water"])
	setup.combatants[0].energy = 50
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(703, [0, 0, 0, 0, 0, 999999]))
	decision = engine.get_decision()
	response = engine.submit(BattleCommand.new(&"source-actor", BattleCommand.Kind.USE_MOVE, &"base:move/fresh_stream/tier1", [&"source-enemy"], int(decision.revision)))
	actor = _state_for(engine, "source-actor")
	enemy = _state_for(engine, "source-enemy")
	var ordered_kinds: Array[StringName] = []
	ordered_kinds.assign(response.events.map(func(event: BattleEvent): return event.kind))
	_expect(start.accepted and actor.energy == 58 and enemy.health == 427 and actor.stat_stages.get(&"base:stat/energy") == 1, "Fresh Stream tier 1 must pay 12, restore 20% before accuracy, deal 73 water-STAB damage, and apply its shared 10% energy stage")
	_expect(ordered_kinds.find(&"cost_paid") < ordered_kinds.find(&"energy_changed") and ordered_kinds.find(&"energy_changed") < ordered_kinds.find(&"move_used") and ordered_kinds.find(&"move_used") < ordered_kinds.find(&"damage") and ordered_kinds.find(&"damage") < ordered_kinds.find(&"stat_stage_changed"), "Fresh Stream must preserve source cost, pre-accuracy restore, move, damage, then stat-stage ordering")

func _test_legacy_current_minion_stats() -> void:
	var catalog := load("res://content/imported/recovered-20260911/catalog.tres") as ContentCatalog
	var zapig := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var stats := LegacyMinionStats.current_stats(zapig, 25)
	_expect(stats == {"health": 48, "energy": 91, "attack": 55, "healing": 17, "speed": 55}, "Zapig level-25 stats must match OwnedMinion formulas with zero IVs, no star upgrades, and no passive bonuses")
	_expect(is_equal_approx(LegacyMinionStats.max_attack_stat(zapig), 125.0) and is_equal_approx(LegacyMinionStats.max_healing_stat(zapig), 35.0), "move formulas must use the source level-60 maximum attack/healing stats rather than current-level stats")

func _test_playable_recovered_battle_ui() -> void:
	var main := MainScene.instantiate() as Control
	add_child(main)
	var entry_started: Signal = Signal(main, &"battle_entry_animation_started")
	var entry_finished: Signal = Signal(main, &"battle_entry_animation_finished")
	entry_started.connect(func(): _expect(main.busy and not main.move_panel.visible, "the move selector must remain closed while recovered teleport-in animations are running"))
	entry_finished.connect(func(): _expect(main.busy and not main.move_panel.visible, "the move selector must stay closed through the final frame of recovered teleport-in"))
	await main._start_battle()
	_expect(main.catalog.has_definition(&"base:minion/fire_pig_1") and main.catalog.has_definition(&"base:minion/fireghost_1"), "playable battle must bind to the maintained production catalog")
	var source_victory_art_matches: bool = main.victory_popup.position == Vector2(504.0, 105.0) and main.victory_background.texture.resource_path == "res://content/base/art/battle/battleScreenVictoryBackground.png" and main.victory_stars.size() == 3
	for index in main.victory_stars.size():
		var star := main.victory_stars[index] as TextureRect
		if star.texture.resource_path != "res://content/base/art/battle/battleScreenVictoryStar.png" or star.position != Vector2(21.0 + float(index) * 60.0, 66.0):
			source_victory_art_matches = false
	var victory_star_ranking_matches := true
	for defeated_count in 6:
		var result := BattleResult.new()
		for slot in 5:
			result.participants.append({"team": 0, "slot_index": slot, "instance_id": "player-%d" % (slot + 1), "survived": slot >= defeated_count})
		result.participants.append({"team": 0, "slot_index": 0, "instance_id": "battle-mod-extra-player-1", "survived": false})
		var expected_stars := 3 if defeated_count <= 1 else (2 if defeated_count == 2 else (1 if defeated_count <= 4 else 0))
		if main._source_victory_star_count(result) != expected_stars:
			victory_star_ranking_matches = false
	_expect(source_victory_art_matches and victory_star_ranking_matches, "victory art, exact popup placement, three-star layout, and party-loss star thresholds must match the source")
	var visual_modifier_config := {
		"shield": {"player": 2, "enemy": 1},
		"resurrection": {"team": 1, "turns": 3},
		"move_timer": {"interval": 2, "move_id": "base:move/blaze/tier1", "buff_move_id": "base:move/mirror_coating/tier1", "actor": {"instance_id": "timer-ui-test"}},
		"extra_minions": {
			"player": {"count": 1, "templates": [{"definition_id": "base:minion/raptor_1"}]},
			"enemy": {"count": 2, "templates": [{"definition_id": "base:minion/grasssnake_3"}]},
		},
	}
	main._sync_battle_modifier_visuals(visual_modifier_config)
	var shield_panel := main.battle_modifier_layer.get_node_or_null("ShieldModVisuals") as Node2D
	var resurrection_panel := main.battle_modifier_layer.get_node_or_null("ResurectionModVisuals") as Node2D
	var timer_panel := main.battle_modifier_layer.get_node_or_null("MoveTimerModVisuals") as Node2D
	var extra_minions_panel := main.battle_modifier_layer.get_node_or_null("ExtraMinionsModVisuals") as Node2D
	var visible_shield_counters := 0
	if shield_panel != null:
		for counter_name in ["PlayerShieldCounter0", "PlayerShieldCounter1", "PlayerShieldCounter2", "EnemyShieldCounter0", "EnemyShieldCounter1", "EnemyShieldCounter2"]:
			var counter := shield_panel.get_node(counter_name) as Sprite2D
			if counter.visible and counter.texture.resource_path == "res://content/base/art/battle/modStone_shieldStoneCounterIcon.png":
				visible_shield_counters += 1
	var timer_move := main.catalog.get_definition(&"base:move/blaze/tier1") as MoveDefinition
	var timer_icon := timer_panel.get_node("TimerMoveIcon") as Sprite2D if timer_panel != null else null
	var timer_count := timer_panel.get_node("TimerCount") as Label if timer_panel != null else null
	var extra_player_icon := extra_minions_panel.get_node("PlayerExtraMinionIcon") as Sprite2D if extra_minions_panel != null else null
	var extra_enemy_icon := extra_minions_panel.get_node("EnemyExtraMinionIcon") as Sprite2D if extra_minions_panel != null else null
	var modifier_counts := extra_minions_panel != null and (extra_minions_panel.get_node("PlayerExtraMinionCount") as Label).text == "1" and (extra_minions_panel.get_node("EnemyExtraMinionCount") as Label).text == "2"
	var recovered_modifier_panels_match_source: bool = shield_panel != null and shield_panel.position == Vector2(304.0, 119.0) and shield_panel.get_child_count() == 8 and visible_shield_counters == 3 and (shield_panel.get_node("PlayerShieldStone") as Sprite2D).position == Vector2(-164.0, -116.0) and resurrection_panel != null and resurrection_panel.position == Vector2(319.0, 123.0) and (resurrection_panel.get_node("ResurrectionStone") as Sprite2D).position == Vector2(36.0, 94.0) and timer_panel != null and timer_panel.position == Vector2(304.0, 82.0) and timer_icon != null and timer_move != null and timer_icon.texture == main._move_icon(timer_move) and extra_minions_panel != null and extra_minions_panel.position == Vector2(268.0, 82.0) and modifier_counts and extra_player_icon != null and extra_player_icon.texture != null and extra_enemy_icon != null and extra_enemy_icon.texture != null
	main._apply_event_values(BattleEvent.new(0, &"battle_mod_timer_triggered", &"timer-ui-test", &"", {"move_id": "base:move/blaze/tier1", "interval": 2}))
	var timer_event_feedback_plays: bool = timer_count != null and timer_count.text == "0" and main._move_timer_icon_tween != null and main._move_timer_icon_tween.is_running()
	main._apply_event_values(BattleEvent.new(0, &"battle_mod_extra_spawned", &"", &"enemy-extra-ui", {"team": 1, "remaining": 1, "replaced_id": "enemy-5"}))
	var spawn_counter_updates: bool = extra_minions_panel != null and (extra_minions_panel.get_node("EnemyExtraMinionCount") as Label).text == "1"
	_expect(recovered_modifier_panels_match_source and timer_event_feedback_plays and spawn_counter_updates, "all four configured modifier panels must show recovered art/placement and update timer/spawn counters from events")
	main._pending_extra_minion_animation_ids.clear()
	main._sync_battle_modifier_visuals({})
	var combatant_states: Array = main.controller.engine.snapshot().state.combatants
	var initial_turn_order: Array = main.controller.engine.snapshot().state.turn_order
	var first_player := main.combatant_views.get("player-1") as BattleCombatantView
	var second_player := main.combatant_views.get("player-2") as BattleCombatantView
	var fifth_enemy := main.combatant_views.get("enemy-5") as BattleCombatantView
	if first_player != null:
		main._animate_event(BattleEvent.new(0, &"reflected_damage", &"enemy-1", &"player-1", {"amount": 12}))
	var reflected_callout := first_player.get_node_or_null("ReflectedDamageCallout") as Sprite2D if first_player != null else null
	var reflected_callout_matches_source := reflected_callout != null and reflected_callout.texture.resource_path == "res://content/base/art/battle/visualMove_reflectedDamage.png" and reflected_callout.position == Vector2(-float(reflected_callout.texture.get_width()) * 0.5, -float(first_player.minion_sprite.texture.get_height()) - 100.0) and is_zero_approx(reflected_callout.modulate.a)
	_expect(reflected_callout_matches_source, "reflected damage must display the recovered callout at the source offset above its receiving minion")
	if reflected_callout != null:
		reflected_callout.queue_free()
	_expect(main.source_encounter.team_entries.size() == 5 and combatant_states.size() == 10, "playable battle must construct five recovered trainer minions against five player minions")
	for rank_index in initial_turn_order.size():
		var ranked_view := main.combatant_views.get(String(initial_turn_order[rank_index])) as BattleCombatantView
		_expect(ranked_view != null and ranked_view.move_order_label.text == str(rank_index + 1), "each living minion must display its global speed-order rank rather than its formation slot")
	_expect(first_player != null and fifth_enemy != null and first_player.minion_sprite.texture != null and fifth_enemy.minion_sprite.texture != null and first_player.position == BattleCombatantView.legacy_anchor(0, 0) and fifth_enemy.position == BattleCombatantView.legacy_anchor(1, 4), "all ten sprites must resolve from presentation Resources and occupy the recovered source formation")
	var source_teleport_pieces_loaded := first_player.teleport_animation_pieces.size() == 7
	for teleport_piece in first_player.teleport_animation_pieces:
		if teleport_piece.texture == null or not teleport_piece.visible:
			source_teleport_pieces_loaded = false
	_expect(source_teleport_pieces_loaded, "battle entry must create and launch all seven recovered teleport pieces")
	var original_view_state := first_player.state_cache.duplicate(true)
	var shielded_view_state := original_view_state.duplicate(true)
	shielded_view_state["battle_mod_shield_active"] = true
	first_player.update_from_state(shielded_view_state)
	var shield_appears_with_source_asset := first_player.battle_mod_shield_sprite.visible and first_player.battle_mod_shield_sprite.texture == BattleCombatantView.BATTLE_MOD_SHIELD_TEXTURE and first_player._battle_mod_shield_tween.is_running()
	var unshielded_view_state := original_view_state.duplicate(true)
	first_player.update_from_state(unshielded_view_state)
	var shield_state_removal_animates := not bool(first_player.state_cache.get("battle_mod_shield_active", false)) and first_player._battle_mod_shield_tween.is_running()
	first_player._set_battle_mod_shield(false, false)
	main._apply_event_values(BattleEvent.new(0, &"battle_mod_shields_assigned", &"", &"", {"team": 0, "target_ids": ["player-1"]}))
	var shield_assignment_event_plays := bool(first_player.state_cache.get("battle_mod_shield_active", false)) and first_player.battle_mod_shield_sprite.visible
	main._apply_event_values(BattleEvent.new(0, &"battle_mod_shield_removed", &"", &"player-1", {}))
	var shield_removal_event_plays := not bool(first_player.state_cache.get("battle_mod_shield_active", false)) and first_player._battle_mod_shield_tween.is_running()
	first_player._set_battle_mod_shield(false, false)
	_expect(shield_appears_with_source_asset and shield_state_removal_animates and shield_assignment_event_plays and shield_removal_event_plays, "battle-mod shield state and assignment/removal events must play the recovered shield animations")
	main._show_resurrection_tombstone(&"enemy-1", 2)
	var tombstone: Dictionary = main.resurrection_tombstones.get("enemy-1", {})
	var tombstone_root := tombstone.get("root") as Node2D
	var tombstone_sprite := tombstone_root.get_child(0) as Sprite2D if tombstone_root != null else null
	var tombstone_label := tombstone.get("label") as Label
	var tombstone_matches_source: bool = tombstone_root != null and tombstone_root.visible and tombstone_sprite != null and tombstone_sprite.texture.resource_path == "res://content/base/art/battle/modStone_tombstone.png" and tombstone_label != null and tombstone_label.text == "2" and tombstone_root.get_parent() == main.combatant_layer
	_expect(is_zero_approx(tombstone_root.modulate.a), "a newly created tombstone must start transparent before its source entrance fade")
	var entrance_tween := tombstone.get("tween") as Tween
	main._show_resurrection_tombstone(&"enemy-1", 1)
	_expect(main.resurrection_tombstones["enemy-1"].tween == entrance_tween and tombstone_label.text == "1", "countdown changes must update the label without restarting the tombstone fade")
	main._hide_resurrection_tombstone(&"enemy-1")
	var tombstone_fades_out: bool = tombstone_root != null and (tombstone.get("tween") as Tween).is_running()
	_expect(tombstone_matches_source and tombstone_fades_out, "resurrection must show the recovered tombstone/countdown at the minion slot and fade it on revive")
	var initial_health_display := first_player.health_bar.value
	var initial_health_fill_position := first_player.health_fill_visual.position.x
	first_player.apply_event_values({"health": maxi(1, int(initial_health_display * 0.5))})
	_expect(is_equal_approx(first_player.health_fill_visual.position.x, initial_health_fill_position) and first_player._health_tween.is_running(), "visible HP fill must begin a source-duration tween instead of jumping to the post-hit value")
	first_player.apply_event_values({"health": 0, "defeated": true})
	_expect(first_player.visible and is_equal_approx(first_player.modulate.a, 1.0) and first_player._death_started, "a defeated minion must remain visible until the delayed source fade starts")
	main._apply_event_values(BattleEvent.new(0, &"battle_mod_resurrected", &"", &"player-1", {"health": maxi(1, int(floor(float(original_view_state.get("health", 1)) / 2.0)))}))
	var revival_uses_teleport_pieces := not first_player._death_started and first_player.visible and first_player.teleport_animation_pieces.size() == 7
	for teleport_piece in first_player.teleport_animation_pieces:
		if not teleport_piece.visible:
			revival_uses_teleport_pieces = false
	_expect(revival_uses_teleport_pieces, "the battle-mod resurrection event must revive the minion through the source teleport-in choreography")
	var burn_definition := main.catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	_expect(burn_definition != null and main.vfx_catalog.texture_for(burn_definition.legacy_visual_id) != null, "playable battle must resolve Burn's source visual ID to its packaged SWF effect symbol")
	var mirror_coating := main.catalog.get_definition(&"base:move/mirror_coating/tier1") as MoveDefinition
	var passive_owner := main.controller.engine._state.combatants[&"player-5"] as CombatantState
	var first_player_state := main.controller.engine._state.combatants[&"player-1"] as CombatantState
	var original_owner_moves := passive_owner.move_ids.duplicate()
	var original_owner_health := passive_owner.health
	var original_owner_defeated := passive_owner.defeated
	var original_first_statuses := first_player_state.statuses.duplicate(true)
	if not passive_owner.move_ids.has(mirror_coating.id):
		passive_owner.move_ids.append(mirror_coating.id)
	first_player_state.statuses.append({"kind": &"periodic", "move_id": burn_definition.id, "source_id": &"enemy-1", "turns": 2})
	main._sync_from_engine()
	_expect(first_player.buff_icon_move_ids.has(mirror_coating.id) and first_player.buff_icon_move_ids.has(burn_definition.id) and second_player.buff_icon_move_ids.has(mirror_coating.id) and not second_player.buff_icon_move_ids.has(burn_definition.id), "team-global passive and per-minion periodic icons must follow the recovered source visibility rule")
	passive_owner.defeated = true
	passive_owner.health = 0
	main._sync_from_engine()
	_expect(not first_player.buff_icon_move_ids.has(mirror_coating.id) and not second_player.buff_icon_move_ids.has(mirror_coating.id), "a defeated passive owner must immediately remove its global buff icons from living teammates")
	passive_owner.move_ids = original_owner_moves
	passive_owner.health = original_owner_health
	passive_owner.defeated = original_owner_defeated
	first_player_state.statuses = original_first_statuses
	main._sync_from_engine()
	main._animate_event(BattleEvent.new(0, &"charge_started", &"player-1", &"player-1", {"move_id": "base:move/charge_blast/tier1"}))
	main._animate_event(BattleEvent.new(0, &"frozen", &"enemy-1", &"player-1", {}))
	main._animate_event(BattleEvent.new(0, &"stunned", &"enemy-1", &"player-1", {}))
	main._animate_event(BattleEvent.new(0, &"exhausted_turn_skipped", &"player-1", &"player-1", {}))
	main._animate_event(BattleEvent.new(0, &"stat_stage_changed", &"player-1", &"player-1", {"stat_type_id": "base:stat/speed", "amount": 1}))
	main._animate_event(BattleEvent.new(0, &"stat_stage_changed", &"enemy-1", &"player-1", {"stat_type_id": "base:stat/attack", "amount": -1}))
	var status_badge_textures: Array[Texture2D] = []
	var status_badge_labels: Array[String] = []
	for child in first_player.get_children():
		if child is Node2D and child.get_child_count() > 0:
			for badge_child in child.get_children():
				if badge_child is Sprite2D and (badge_child as Sprite2D).texture != null: status_badge_textures.append((badge_child as Sprite2D).texture)
				if badge_child is Label: status_badge_labels.append((badge_child as Label).text)
	_expect(status_badge_textures.has(BattleCombatantView.CHARGING_BADGE) and status_badge_textures.has(BattleCombatantView.FROZEN_BADGE) and status_badge_textures.has(BattleCombatantView.STUNNED_BADGE) and status_badge_textures.has(BattleCombatantView.EXHAUSTED_BADGE), "charge, freeze, stun, and exhaustion events must show their exact recovered status badges")
	_expect(status_badge_textures.has(BattleCombatantView.STAT_INCREASE_BADGE) and status_badge_textures.has(BattleCombatantView.STAT_DECREASE_BADGE) and status_badge_labels.has("Speed") and status_badge_labels.has("Attack"), "positive and negative stat-stage events must show the matching original badge and stat name")
	var poison_definition := main.catalog.get_definition(&"base:move/poison_tooth/tier1") as MoveDefinition
	_expect(poison_definition != null and main._resolved_dot_visual_id(poison_definition) == 189 and main.vfx_catalog.texture_for(189) != null, "Poison Tooth's end-of-round tick must resolve its separate poison-drop visual")
	# The engine can already have expired/cleansed this status when playback
	# reaches its application. Icons must follow presented events, not peek ahead.
	main._apply_event_values(BattleEvent.new(0, &"periodic_applied", &"enemy-1", &"player-1", {"move_id": String(poison_definition.id)}))
	_expect(first_player.buff_icon_move_ids.has(poison_definition.id) and not first_player_state.statuses.any(func(status: Dictionary): return StringName(status.get("move_id", "")) == poison_definition.id), "poison badge must appear at application even when the engine's final snapshot no longer contains poison")
	main._apply_event_values(BattleEvent.new(0, &"periodic_refreshed", &"enemy-2", &"player-1", {"move_id": String(poison_definition.id)}))
	_expect(first_player.state_cache.statuses.size() == original_first_statuses.size() + 1 and first_player.buff_icon_move_ids.count(poison_definition.id) == 1, "refreshing a presented status must replace its source without stacking icons")
	main._apply_event_values(BattleEvent.new(0, &"periodic_expired", &"enemy-2", &"player-1", {"move_id": String(poison_definition.id)}))
	_expect(not first_player.buff_icon_move_ids.has(poison_definition.id), "poison badge must leave at its expiry event")
	main._apply_event_values(BattleEvent.new(0, &"shield_set", &"player-1", &"player-1", {"amount": 40, "max_shield": 40}))
	_expect(int(first_player.state_cache.shield) == 40 and first_player.shield_bar.visible, "resolved shield amount must start its visible bar at contact without waiting for turn-end sync")
	main._apply_event_values(BattleEvent.new(0, &"periodic_applied", &"enemy-1", &"player-1", {"move_id": String(poison_definition.id)}))
	main._apply_event_values(BattleEvent.new(0, &"frozen", &"enemy-1", &"player-1", {}))
	main._apply_event_values(BattleEvent.new(0, &"buffs_debuffs_cleared", &"player-2", &"player-1", {}))
	_expect(not first_player.buff_icon_move_ids.has(poison_definition.id) and not bool(first_player.state_cache.frozen), "cleansing must remove the presented periodic and frozen states immediately")
	main._sync_from_engine()
	var blaze_definition := main.catalog.get_definition(&"base:move/blaze/tier1") as MoveDefinition
	var blaze_targets: Array[StringName] = [&"enemy-1"]
	var blaze_effects_before: int = main.move_vfx_layer.get_child_count()
	main._animate_event(BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": String(blaze_definition.id), "hit": true, "target_ids": ["enemy-1"]}), blaze_targets)
	var blaze_effects_after_cast: int = main.move_vfx_layer.get_child_count()
	var blaze_application_delays: Dictionary = main._animate_event(BattleEvent.new(0, &"periodic_applied", &"player-1", &"enemy-1", {"move_id": String(blaze_definition.id)}))
	_expect(blaze_definition != null and main._resolved_visual_id(blaze_definition) == main._resolved_dot_visual_id(blaze_definition) and blaze_effects_after_cast >= blaze_effects_before and blaze_application_delays.is_empty() and main.move_vfx_layer.get_child_count() == blaze_effects_after_cast, "Blaze must play one cast effect, not a duplicate identical effect when its damage-over-time status is applied")
	main._update_current_turn_indicator(&"enemy-1")
	var next_decision_events: Array[BattleEvent] = [BattleEvent.new(0, &"decision_requested", &"player-1", &"", {})]
	await main._present(next_decision_events)
	_expect(not main.current_turn_indicator.visible, "the next actor indicator must stay hidden while the preceding event presentation is still playing")
	main._update_current_turn_indicator(&"player-1")
	_expect(main.current_turn_indicator.visible and main.current_turn_indicator.position == first_player.position + Vector2(-52.0, -40.0), "the next actor indicator must reappear at the decision-ready handoff")
	var initial_effect_count: int = main.move_vfx_layer.get_child_count()
	main._animate_event(BattleEvent.new(0, &"missed", &"enemy-1", &"player-1"))
	main._animate_event(BattleEvent.new(0, &"periodic_tick", &"enemy-1", &"player-1", {"move_id": String(burn_definition.id)}))
	main._animate_event(BattleEvent.new(0, &"periodic_tick", &"enemy-1", &"player-1", {"move_id": String(poison_definition.id), "kind": EffectDefinition.Kind.PERIODIC_DAMAGE, "amount": 8, "effectiveness": 2.0}))
	var poison_apply_effects_before: int = main.move_vfx_layer.get_child_count()
	main._animate_event(BattleEvent.new(0, &"periodic_applied", &"enemy-1", &"player-1", {"move_id": String(poison_definition.id)}))
	_expect(main.move_vfx_layer.get_child_count() >= initial_effect_count + 10 and main.move_vfx_layer.get_child_count() >= poison_apply_effects_before + 3, "miss, Burn/Poison ticks, and newly applied poison must create visible source-art effects on the affected minion")
	main._animate_event(BattleEvent.new(0, &"damage", &"player-1", &"enemy-5", {"amount": 10, "effectiveness": 2.0, "critical": true}))
	main._animate_event(BattleEvent.new(0, &"damage", &"enemy-5", &"player-1", {"amount": 5, "effectiveness": 0.5, "critical": false}))
	main._animate_event(BattleEvent.new(0, &"healed", &"enemy-5", &"enemy-5", {"amount": 8, "health": 98, "effectiveness": 1.0, "critical": false}))
	main._animate_event(BattleEvent.new(0, &"redirected_damage", &"enemy-1", &"enemy-5", {"amount": 4}))
	main._animate_event(BattleEvent.new(0, &"periodic_tick", &"enemy-1", &"enemy-5", {"move_id": String(burn_definition.id), "kind": EffectDefinition.Kind.PERIODIC_DAMAGE, "amount": 12, "effectiveness": 2.0}))
	var super_popup_found := fifth_enemy.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.SUPER_EFFECTIVE_POPUP)
	var crit_popup_found := fifth_enemy.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.CRITICAL_POPUP)
	var weak_popup_found := first_player.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.NOT_EFFECTIVE_POPUP)
	var redirected_popup_found := fifth_enemy.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.REDIRECTED_POPUP)
	var centered_crit_popup_found := fifth_enemy.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.CRITICAL_POPUP and not (child as Sprite2D).centered)
	var centered_dot_super_popup_found := fifth_enemy.get_children().any(func(child: Node): return child is Sprite2D and (child as Sprite2D).texture == BattleCombatantView.SUPER_EFFECTIVE_POPUP and not (child as Sprite2D).centered)
	var heal_number_found := fifth_enemy.get_children().any(func(child: Node): return child is Label and (child as Label).text == "+8")
	_expect(super_popup_found and crit_popup_found and weak_popup_found and redirected_popup_found, "super-effective, not-effective, critical, and redirected source popups must appear on the affected minion")
	_expect(centered_crit_popup_found and centered_dot_super_popup_found, "critical and DOT effectiveness callouts must use the centered source top-left positioning convention")
	_expect(not heal_number_found, "Source healing uses its health bar, without an added floating numeric label")
	var pound_definition := main.catalog.get_definition(&"base:move/pound/tier1") as MoveDefinition
	var spike_definition := main.catalog.get_definition(&"base:move/spike/tier1") as MoveDefinition
	var pound_profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(pound_definition)) if pound_definition != null else {}
	var spike_profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(spike_definition)) if spike_definition != null else {}
	_expect(pound_definition != null and spike_definition != null and main._move_icon(pound_definition).resource_path.ends_with("moveIcon_pound.png") and main._move_icon(spike_definition).resource_path.ends_with("moveIcon_spike.png") and main.vfx_catalog.texture_for(main._resolved_visual_id(pound_definition)) != null and main.vfx_catalog.texture_for(main._resolved_visual_id(spike_definition)) != null and String(pound_profile.get("family", "")) == "fall_onto_target" and String(spike_profile.get("family", "")) == "fall_onto_target", "Pound and Spike must resolve their own icons and source fall-onto-target animation family")
	var fall_from_top_defaults: Dictionary = main.vfx_catalog.profile_for(3)
	var rotate_defaults: Dictionary = main.vfx_catalog.profile_for(15)
	_expect(int(fall_from_top_defaults.get("count", 0)) == 3 and is_equal_approx(float(fall_from_top_defaults.get("impact_speed", 0.0)), 0.75) and bool(fall_from_top_defaults.get("impact_visible", false)) and int(rotate_defaults.get("count", 0)) == 1 and is_equal_approx(float(rotate_defaults.get("impact_speed", 0.0)), 0.4) and bool(rotate_defaults.get("impact_visible", false)), "animation profiles must carry source constructor defaults for fall-from-top and rotate impacts")
	var rise_family_move_count := 0
	var orbit_family_move_count := 0
	var through_family_move_count := 0
	var rise_family_move: MoveDefinition = null
	var orbit_family_move: MoveDefinition = null
	var through_family_move: MoveDefinition = null
	for pack in main.catalog.packs:
		if pack.id == &"base:pack/battle_demo":
			continue
		for definition in pack.definitions:
			if not definition is MoveDefinition or not (definition as MoveDefinition).available:
				continue
			var move := definition as MoveDefinition
			var family := String(main.vfx_catalog.profile_for(main._resolved_visual_id(move)).get("family", ""))
			if family == "rise_out_of_target":
				rise_family_move_count += 1
				if rise_family_move == null: rise_family_move = move
			elif family == "orbit_into_target":
				orbit_family_move_count += 1
				if orbit_family_move == null: orbit_family_move = move
			elif family == "fade_through_target":
				through_family_move_count += 1
				if through_family_move == null: through_family_move = move
	_expect(rise_family_move_count >= 176 and orbit_family_move_count >= 53, "the recovered target-rise and orbit families must resolve at least all 229 source-derived move tiers, including class aliases (rise=%d, orbit=%d)" % [rise_family_move_count, orbit_family_move_count])
	var through_profile_count := 0
	for profile in main.vfx_catalog._profiles.values():
		if String(profile.get("family", "")) == "fade_through_target":
			through_profile_count += 1
	var spark_through_profile: Dictionary = main.vfx_catalog.profile_for(68)
	var slow_through_profile: Dictionary = main.vfx_catalog.profile_for(25)
	var refreshing_wave_through_profile: Dictionary = main.vfx_catalog.profile_for(134)
	_expect(through_profile_count == 29 and through_family_move_count > 0 and String(spark_through_profile.get("family", "")) == "fade_through_target" and int(spark_through_profile.get("count", 0)) == 6 and is_equal_approx(float(spark_through_profile.get("movement_speed", 0.0)), 0.5) and int(slow_through_profile.get("count", 0)) == 6 and is_equal_approx(float(slow_through_profile.get("delay", 0.0)), 0.4) and int(refreshing_wave_through_profile.get("count", 0)) == 1 and is_equal_approx(float(refreshing_wave_through_profile.get("extra_distance", 0.0)), 20.0), "the fade-through source family must cover 29 visual IDs and preserve Spark, Slow, and Refreshing Wave overrides")
	var rise_children_before: int = main.move_vfx_layer.get_child_count()
	var rise_impact_delay: float = main._animate_move_visual(BattleEvent.new(0, &"move_used", &"player-1", &"enemy-1", {"move_id": String(rise_family_move.id), "hit": true}), &"enemy-1") if rise_family_move != null else 0.0
	_expect(rise_family_move != null and rise_impact_delay > 0.0 and main.move_vfx_layer.get_child_count() > rise_children_before, "target-rise moves must spawn their recovered layered effects and report the source-derived hit time")
	var orbit_children_before: int = main.move_vfx_layer.get_child_count()
	var orbit_impact_delay: float = main._animate_move_visual(BattleEvent.new(0, &"move_used", &"player-1", &"enemy-1", {"move_id": String(orbit_family_move.id), "hit": true}), &"enemy-1") if orbit_family_move != null else 0.0
	var orbit_profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(orbit_family_move)) if orbit_family_move != null else {}
	var expected_orbit_impact := float(orbit_profile.final_hang_time) + float(orbit_profile.hang_time) + float(orbit_profile.movement_speed) + (0.0 if bool(orbit_profile.get("all_enter_at_same_time", false)) else int(orbit_profile.count) * float(orbit_profile.delay)) - 0.3
	_expect(orbit_family_move != null and main.move_vfx_layer.get_child_count() >= orbit_children_before + int(orbit_profile.get("count", 8)) and is_equal_approx(orbit_impact_delay, expected_orbit_impact), "orbiting target effects must converge in source order and queue ApplyEffects at the recovered m_moveTime-.1 barrier")
	var through_children_before: int = main.move_vfx_layer.get_child_count()
	var through_impact_delay: float = main._animate_move_visual(BattleEvent.new(0, &"move_used", &"player-1", &"enemy-1", {"move_id": String(through_family_move.id), "hit": true}), &"enemy-1") if through_family_move != null else 0.0
	var through_profile: Dictionary = main.vfx_catalog.profile_for(main._resolved_visual_id(through_family_move)) if through_family_move != null else {}
	var expected_through_duration := int(through_profile.count) * float(through_profile.delay) + float(through_profile.movement_speed) + float(through_profile.final_hang_time) + 0.15
	_expect(through_family_move != null and main.move_vfx_layer.get_child_count() >= through_children_before + int(through_profile.get("count", 3)) and is_equal_approx(through_impact_delay, expected_through_duration - 0.1) and is_equal_approx(main._last_move_visual_duration_seconds, expected_through_duration), "fade-through moves must use source-sized staggered sprites, ApplyEffects timing and instance cleanup rather than longest-tween timing")
	var quake_move := main.catalog.get_definition(&"base:move/earthquake/tier1") as MoveDefinition
	var destabilize_profile: Dictionary = main.vfx_catalog.profile_for(55)
	var earthquake_profile: Dictionary = main.vfx_catalog.profile_for(61)
	var stonequake_profile: Dictionary = main.vfx_catalog.profile_for(62)
	var expected_quake_duration := (0.05 + float(earthquake_profile.get("intensity", 0.05)) * (float(earthquake_profile.get("shake_count", 5)) * 0.5)) * float(earthquake_profile.get("shake_count", 5)) + 0.15
	main._last_move_visual_duration_seconds = 0.0
	var quake_impact_delay: float = main._animate_move_visual(BattleEvent.new(0, &"move_used", &"player-1", &"enemy-1", {"move_id": "base:move/earthquake/tier1", "hit": true}), &"enemy-1")
	_expect(quake_move != null and main.vfx_catalog.texture_for(61) == null and String(destabilize_profile.get("family", "")) == "screen_shake" and String(earthquake_profile.get("family", "")) == "screen_shake" and String(stonequake_profile.get("family", "")) == "screen_shake" and main._earthquake_tween.is_running() and is_equal_approx(quake_impact_delay, expected_quake_duration - 0.1) and is_equal_approx(main._last_move_visual_duration_seconds, expected_quake_duration), "Earthquake, Destabilize, and Stonequake must use source field shaking and the ApplyEffects barrier despite having no particle texture")
	var player_decision: Dictionary = main.controller.engine.get_decision()
	var before_forfeit_revision := int(main.controller.engine.snapshot().state.revision)
	main._forfeit()
	_expect(main.forfeit_confirmation.visible and int(main.controller.engine.snapshot().state.revision) == before_forfeit_revision, "Forfeit must show the recovered confirmation box without ending the battle immediately")
	main._cancel_forfeit()
	var legal_move_ids: Array[StringName] = []
	for legal_move in player_decision.get("legal_moves", []): legal_move_ids.append(StringName(legal_move.move_id))
	var rendered_move_ids: Array[StringName] = []
	for button in main.move_buttons.get_children(): rendered_move_ids.append(StringName(button.get_meta("move_id", "")))
	_expect(int(player_decision.get("team", -1)) == 0 and not legal_move_ids.is_empty() and not rendered_move_ids.has(&"base:move/desperation/tier1") and rendered_move_ids.size() == (main.controller.engine._state.combatants[StringName(player_decision.actor_id)] as CombatantState).move_ids.size(), "the menu must show learned moves and hide Desperation while another move is usable (actor=%s, legal=%s, shown=%s)" % [player_decision.get("actor_id", ""), legal_move_ids, rendered_move_ids])
	var active_actor := main.controller.engine._state.combatants[StringName(player_decision.actor_id)] as CombatantState
	_expect(not main._is_energy_limited_fallback({"energy": 90, "move_ids": [&"base:move/spike/tier1"]}) and main._is_energy_limited_fallback({"energy": 0, "move_ids": [&"base:move/spike/tier1"]}), "a near-full Spike user on cooldown must not be called out of energy")
	var saved_cooldowns := active_actor.cooldowns.duplicate(true)
	for move_id in active_actor.move_ids: active_actor.cooldowns[move_id] = 1
	main._build_move_buttons(main.controller.engine.get_decision())
	await get_tree().process_frame
	var cooldown_buttons: Array = main.move_buttons.get_children()
	var cooldown_indicators: Array = cooldown_buttons.filter(func(button: Button): return button.get_node_or_null("CooldownOverlay") != null)
	_expect(main.cooldown_tip.visible and cooldown_buttons.size() == active_actor.move_ids.size() + 1 and cooldown_indicators.size() == active_actor.move_ids.size(), "all cooling-down moves must remain dimmed and overlaid while Desperation appears")
	active_actor.cooldowns = saved_cooldowns
	var saved_energy := active_actor.energy
	active_actor.energy = 0
	main._build_move_buttons(main.controller.engine.get_decision())
	await get_tree().process_frame
	var low_energy_move_ids: Array[StringName] = []
	for button in main.move_buttons.get_children(): low_energy_move_ids.append(StringName(button.get_meta("move_id", "")))
	_expect(low_energy_move_ids.size() == active_actor.move_ids.size() + 1 and low_energy_move_ids.has(&"base:move/desperation/tier1") and main.out_of_energy_tip.visible, "low energy must leave learned moves visible but unusable and offer Desperation")
	active_actor.energy = saved_energy
	main._build_move_buttons(player_decision)
	var entrance_buttons: Array = main.move_buttons.get_children()
	var first_entrance_button := entrance_buttons[0] as Button if not entrance_buttons.is_empty() else null
	_expect(first_entrance_button != null and main._move_selector_tweens.size() >= 3 and first_entrance_button.position == Vector2(-142.0, 69.0), "the move selector must begin its staggered source-style fan-in from the shared staging position")
	await get_tree().process_frame
	var legal_move: Dictionary = {}
	for candidate in player_decision.get("legal_moves", []):
		var candidate_definition := main.catalog.get_definition(StringName(candidate.move_id)) as MoveDefinition
		if candidate_definition != null and candidate_definition.id != &"base:move/desperation/tier1" and candidate_definition.target_count == 1 and not candidate.get("target_ids", []).is_empty():
			legal_move = candidate
			break
	var legal_targets: Array = legal_move.get("target_ids", [])
	var selected_move := main.catalog.get_definition(StringName(legal_move.get("move_id", ""))) as MoveDefinition
	var required_target_count := selected_move.target_count if selected_move != null else -1
	var revision := int(main.controller.engine.snapshot().state.revision)
	if not legal_move.is_empty(): main._choose_move(legal_move)
	_expect(not main.pending_move.is_empty() and main.cancel_target.visible and main.battle_grey_layer.visible and not legal_targets.is_empty(), "chosen-target moves must dim the arena, expose the source return button, and wait for a sprite click")
	var target_view := main.combatant_views.get(String(legal_targets[0])) as BattleCombatantView if not legal_targets.is_empty() else null
	var click_position := target_view.minion_sprite.get_global_transform_with_canvas() * Vector2.ZERO if target_view != null else Vector2.ZERO
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.position = click_position
	click_event.pressed = true
	# Recreate a stale selector that survives until the target click; submission
	# must close it before the attack's presentation begins.
	main.move_panel.visible = true
	if target_view != null: get_viewport().push_input(click_event, true)
	await get_tree().process_frame
	click_event.pressed = false
	if target_view != null: get_viewport().push_input(click_event, true)
	await get_tree().process_frame
	_expect(required_target_count == 1 and target_view != null and main.pending_move.is_empty() and not main.cancel_target.visible, "a legal sprite click must finish a single-target choice without a separate confirmation panel")
	_expect(main._move_selector_exiting and main._move_selector_exit_deadline_usec > Time.get_ticks_usec(), "submitting a selected target must begin the source-style selector fan-out before attack presentation")
	_expect(int(main.controller.engine.snapshot().state.revision) > revision, "clicking the recovered target sprite must submit the selected production move through BattleController")
	await get_tree().create_timer(1.5).timeout
	_expect(not main._move_selector_exiting and main._move_selector_exit_deadline_usec == 0, "the old selector must finish its delayed fade before the next decision becomes available")
	var loss_result := BattleResult.new()
	loss_result.winning_team = 1
	main._show_result(loss_result)
	var defeat_flow_starts_source_matched: bool = main.defeat_transition_layer.visible and not main.result_overlay.visible and main.defeat_message.visible and main.defeat_black.modulate.a == 0.0 and main.defeat_message.text == "Your minions have collapsed,  you rush to heal them" and main._defeat_presentation_tweens.size() == 2
	_expect(defeat_flow_starts_source_matched, "loss presentation must start with the recovered blackout/message sequence before exposing practice restart controls")
	main.queue_free()

func _recovered_setup(move_id: StringName, actor_types: Array[StringName]) -> Dictionary:
	return {
		"battle_id": "recovered-golden", "tie_first_team": 0,
		"combatants": [
			{"instance_id": "source-actor", "definition_id": "base:minion/fire_pig_1", "team": 0, "slot_index": 0, "move_ids": [move_id], "level": 10, "max_health": 200, "health": 200, "max_energy": 100, "energy": 100, "attack": 1000, "healing": 1000, "speed": 20, "type_ids": actor_types},
			{"instance_id": "source-enemy", "definition_id": "base:minion/armadillo_1", "team": 1, "slot_index": 0, "move_ids": [], "level": 10, "max_health": 500, "health": 500, "max_energy": 100, "energy": 100, "attack": 0, "healing": 0, "speed": 10, "type_ids": [&"base:type/none"]},
		]
	}

func _run_battle() -> Dictionary:
	var engine := BattleEngine.new()
	var response := engine.start(SampleFactory.battle_setup(), SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(17, [0, 2, 0, 1, 0, 3, 0, 0, 0, 2]))
	var events: Array[Dictionary] = []
	for event in response.events: events.append(event.to_dict())
	while engine.get_result().is_empty():
		var decision := engine.get_decision()
		var legal: Dictionary = decision.legal_moves[0]
		var target_ids: Array[StringName] = [StringName(legal.target_ids[0])]
		response = engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(legal.move_id), target_ids, int(decision.revision)))
		for event in response.events: events.append(event.to_dict())
	return {"events": events, "snapshot": engine.snapshot(), "result": engine.get_result().to_dictionary()}

func _test_battle_determinism() -> void:
	var first := _run_battle()
	var second := _run_battle()
	_expect(first.events == second.events, "same setup, commands, and RNG must emit identical events")
	_expect(first.snapshot == second.snapshot, "same setup, commands, and RNG must end in identical state")
	_expect(first.result == second.result, "same setup, commands, and RNG must produce an identical typed result payload")

func _test_battle_result_contract() -> void:
	var controller := BattleController.new()
	var setup := SampleFactory.battle_setup()
	setup.battle_id = "typed-result-contract"
	var start := controller.start(setup, SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(811, [0]))
	var decision := controller.engine.get_decision()
	var actor_id := StringName(decision.get("actor_id", ""))
	var response := controller.submit(BattleCommand.new(actor_id, BattleCommand.Kind.FORFEIT, &"", [], int(decision.get("revision", -1))))
	var result = controller.engine.get_result()
	var campaign_state := {}
	var applied_once := controller.consume_result_once(campaign_state)
	var applied_twice := controller.consume_result_once(campaign_state)
	var participants: Array[Dictionary] = result.participants
	var participant_fields_valid := true
	for participant in participants:
		var changes := participant.get("persistent_changes", {}) as Dictionary
		if not participant.has("survived") or not participant.has("defeated") or not changes.has("health") or not changes.has("energy"):
			participant_fields_valid = false
	var completed_events := response.events.filter(func(event: BattleEvent): return event.kind == &"battle_completed")
	var event_result: Dictionary = completed_events[0].values if not completed_events.is_empty() else {}
	_expect(start.accepted and response.accepted and result.battle_id == &"typed-result-contract", "completed battles must expose their ID and outcome through BattleResult")
	_expect(result.winning_team == 1 - int(decision.get("team", -1)) and result.reason == &"forfeit" and participants.size() == setup.combatants.size(), "BattleResult must include outcome and every final participant in deterministic order")
	_expect(participant_fields_valid and event_result == result.to_dictionary(), "battle_completed must emit the same survival and persistent-health/energy payload returned by the engine")
	_expect(applied_once and not applied_twice and campaign_state.get("last_applied_battle", "") == "typed-result-contract" and campaign_state.get("last_battle_result", {}).get("battle_id", "") == "typed-result-contract", "BattleController must deliver a completed result into campaign state exactly once")

func _test_ruleset_modules() -> void:
	var source_configuration := {"nested": {"sentinel": 17}}
	var isolated_context := BattleRuleContext.new(BattleState.new(), SampleFactory.build_catalog(), source_configuration)
	isolated_context.configuration.nested.sentinel = 99
	_expect(source_configuration.nested.sentinel == 17, "battle rule context must deep-copy shared ruleset configuration")
	var setup := SampleFactory.battle_setup()
	var rules := SampleFactory.build_rules()
	var baseline_engine := BattleEngine.new()
	var baseline := baseline_engine.start(setup, SampleFactory.build_catalog(), rules, BattleRng.new(711, [0]))
	var baseline_snapshot: Dictionary = baseline_engine.snapshot()
	var module_rules := SampleFactory.build_rules()
	var first := RuleModuleProbe.new()
	first.marker = &"first"
	var second := RuleModuleProbe.new()
	second.marker = &"second"
	module_rules.rule_modules = [first, second]
	var module_engine := BattleEngine.new()
	var module_start := module_engine.start(setup, SampleFactory.build_catalog(), module_rules, BattleRng.new(711, [0]))
	var module_trace: Array = module_engine.snapshot().state.modifier_state.get("rule_module_trace", [])
	_expect(baseline.accepted and baseline_snapshot.state.modifier_state.get("rule_module_trace", []).is_empty(), "an empty rule-module list must leave the legacy opening state unchanged")
	_expect(module_start.accepted and module_trace == ["first", "second"], "ruleset modules must run once in declared order before the first turn is activated")
	_expect(first.invocation_count == 0 and second.invocation_count == 0, "battle startup must invoke duplicated rule modules without mutating catalog-owned resources")
	var invalid_rules := SampleFactory.build_rules()
	invalid_rules.rule_modules = [Resource.new()]
	var invalid_response := BattleEngine.new().start(setup, SampleFactory.build_catalog(), invalid_rules, BattleRng.new(711, [0]))
	_expect(not invalid_response.accepted and invalid_response.error_code == &"invalid_rules" and invalid_response.message.contains("BattleRuleModule"), "invalid module resources must reject battle startup with a useful type diagnostic")

func _test_legacy_combat_math() -> void:
	_expect(LegacyMath.calculate_scaled_amount(30, 0, 1000, 10, 0.0) == 80, "legacy power formula must preserve level/stat scale and ceil")
	_expect(LegacyMath.calculate_scaled_amount(30, 20, 1000, 10, 0.5) == 107, "legacy random bonus must be applied before scaling and ceil")

func _test_legacy_roll_boundaries() -> void:
	var rolls := LegacyRolls.draw(BattleRng.new(1, [100000, 500000, 250000, 750000]))
	_expect(rolls.buff_debuff == 10.0 and rolls.miss == 50.0 and rolls.stun == 25.0 and rolls.freeze == 75.0, "legacy shared rolls must be drawn in buff, miss, stun, freeze order")
	_expect(rolls.hits(50), "legacy accuracy equality must hit because only accuracy below the roll misses")
	_expect(not rolls.applies_stun(25) and rolls.applies_freeze(76), "legacy status chance uses a strict greater-than boundary")

func _test_type_chart_and_typed_damage() -> void:
	var chart := TypeChartDefinition.new()
	chart.id = &"base:type_chart/classic"
	chart.display_name = "Classic type chart"
	chart.multipliers = {
		"base:type/fire>base:type/ice": 1.5,
		"base:type/fire>base:type/dino": 1.5,
	}
	_expect(is_equal_approx(chart.combined_multiplier(&"base:type/fire", [&"base:type/ice", &"base:type/dino"]), 2.25), "dual defending types must multiply their effectiveness")
	_expect(is_equal_approx(chart.healing_multiplier(&"base:type/fire", &"base:type/ice"), 0.66666666667), "healing must reverse a damaging weakness")

	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var catalog_chart := pack.definitions.filter(func(definition): return definition is TypeChartDefinition)[0] as TypeChartDefinition
	catalog_chart.multipliers = chart.multipliers.duplicate(true)
	var fire_type := TypeDefinition.new()
	fire_type.id = &"base:type/fire"
	fire_type.display_name = "Fire"
	pack.definitions.append(fire_type)
	var strike := pack.definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/strike/tier1")[0] as MoveDefinition
	strike.type_id = &"base:type/fire"
	strike.target_mode = MoveDefinition.TargetMode.ALL
	strike.enemy_target_count = 2
	var damage := strike.effects[0]
	damage.amount = 30
	damage.random_bonus = 0
	damage.scaling = EffectDefinition.Scaling.ATTACK
	damage.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
	damage.uses_type_effectiveness = true
	damage.can_critical = true
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].level = 10
	setup.combatants[0].attack = 1000
	setup.combatants[0].type_ids = [&"base:type/fire"]
	setup.combatants[0].critical_chance = 0.0
	setup.combatants[1].max_health = 500
	setup.combatants[1].health = 500
	setup.combatants[1].type_ids = [&"base:type/ice", &"base:type/dino"]
	var second_enemy: Dictionary = setup.combatants[1].duplicate(true)
	second_enemy.instance_id = "enemy-2"
	setup.combatants.append(second_enemy)
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(1, [0, 0, 0, 0, 0, 999999, 999999]))
	_expect(start.accepted, "typed damage fixture must start with a valid catalog")
	var decision := engine.get_decision()
	engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [], int(decision.revision)))
	var healths: Array[int] = []
	for state in engine.snapshot().state.combatants:
		if int(state.team) == 1: healths.append(int(state.health))
	healths.sort()
	_expect(healths == [302, 302], "legacy damage must apply one shared base roll, STAB, and both defender types")
	_expect(int(engine.snapshot().rng.script_index) == 7, "shared damage power must consume one RNG draw while critical remains per target")

func _test_periodic_lifecycle() -> void:
	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var strike := pack.definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/strike/tier1")[0] as MoveDefinition
	var dot := EffectDefinition.new()
	dot.id = &"foundation:effect/test_dot"
	dot.display_name = "Test periodic damage"
	dot.kind = EffectDefinition.Kind.PERIODIC_DAMAGE
	dot.amount = 30
	dot.duration = 2
	dot.scaling = EffectDefinition.Scaling.ATTACK
	dot.roll_scope = EffectDefinition.RollScope.PERIODIC_TICK
	dot.uses_type_effectiveness = true
	dot.blocked_by_battle_mod_shield = true
	dot.executor = preload("res://src/domain/battle/periodic_effect_executor.gd")
	strike.effects = [dot]
	var wait_effect := EffectDefinition.new()
	wait_effect.id = &"foundation:effect/test_wait"
	wait_effect.display_name = "Test wait"
	wait_effect.kind = EffectDefinition.Kind.ENERGY
	wait_effect.target_scope = EffectDefinition.TargetScope.ACTOR
	wait_effect.phase = EffectDefinition.Phase.BEFORE_ACCURACY
	wait_effect.amount = 0
	wait_effect.executor = preload("res://src/domain/battle/energy_effect_executor.gd")
	var wait_move := MoveDefinition.new()
	wait_move.id = &"foundation:move/test_wait/tier1"
	wait_move.display_name = "Test wait"
	wait_move.family_id = &"foundation:move_family/test_wait"
	wait_move.type_id = &"base:type/none"
	wait_move.energy_cost = 0
	wait_move.target_side = MoveDefinition.TargetSide.SELF
	wait_move.effects = [wait_effect]
	pack.definitions.append(wait_move)
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].level = 10
	setup.combatants[0].attack = 1000
	setup.combatants[1].max_health = 200
	setup.combatants[1].health = 200
	setup.combatants[1].move_ids = [wait_move.id]
	var engine := BattleEngine.new()
	var response := engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(4))
	var decision := engine.get_decision()
	engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	decision = engine.get_decision()
	var first_round_end := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, wait_move.id, [&"enemy-1"], int(decision.revision)))
	var after_first := engine.snapshot()
	var enemy: Dictionary = after_first.state.combatants.filter(func(state): return state.instance_id == "enemy-1")[0]
	_expect(enemy.health == 120 and enemy.statuses.size() == 1 and enemy.statuses[0].turns == 1, "periodic payload must tick after all actors and retain its source for the configured duration")
	var first_tick_events := first_round_end.events.filter(func(event: BattleEvent): return event.kind == &"periodic_tick")
	_expect(not first_tick_events.is_empty() and first_tick_events.all(func(event: BattleEvent): return event.values.has("effectiveness")), "periodic tick events must carry their resolved type-effectiveness multiplier for presentation")
	decision = engine.get_decision()
	engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"foundation:move/mend/tier1", [&"player-1"], int(decision.revision)))
	decision = engine.get_decision()
	response = engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, wait_move.id, [&"enemy-1"], int(decision.revision)))
	enemy = engine.snapshot().state.combatants.filter(func(state): return state.instance_id == "enemy-1")[0]
	_expect(enemy.health == 40 and enemy.statuses.is_empty(), "periodic payload must reroll each tick and expire immediately after its final configured tick")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"periodic_expired"), "final periodic tick must emit explicit expiration playback data")

func _test_periodic_refresh_and_shield_block() -> void:
	var effect := EffectDefinition.new()
	effect.id = &"foundation:effect/refresh_dot"
	effect.display_name = "Refresh DOT"
	effect.kind = EffectDefinition.Kind.PERIODIC_DAMAGE
	effect.duration = 3
	effect.blocked_by_battle_mod_shield = true
	var move := MoveDefinition.new()
	move.id = &"foundation:move/refresh_dot/tier1"
	var first := CombatantState.from_setup({"instance_id": "source-a"})
	var second := CombatantState.from_setup({"instance_id": "source-b"})
	var target := CombatantState.from_setup({"instance_id": "target"})
	var executor := preload("res://src/domain/battle/periodic_effect_executor.gd").new()
	executor.execute(effect, {"actor": first, "target": target, "move": move, "emit": Callable(self, "_ignore_event")})
	target.statuses[0].turns = 2
	executor.execute(effect, {"actor": second, "target": target, "move": move, "emit": Callable(self, "_ignore_event")})
	_expect(target.statuses.size() == 1, "reapplying the same periodic move must refresh rather than stack")
	_expect(target.statuses[0].turns == 0 and target.statuses[0].source_id == &"source-b", "periodic refresh must reset duration and replace the source combatant")
	target.statuses.clear()
	target.battle_mod_shield_active = true
	executor.execute(effect, {"actor": first, "target": target, "move": move, "emit": Callable(self, "_ignore_event")})
	_expect(target.statuses.is_empty(), "battle-mod shield must prevent blocked periodic payload attachment")

func _test_armor_reflection_and_redirection_order() -> void:
	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var armor_effect := EffectDefinition.new()
	armor_effect.id = &"foundation:effect/test_armor"
	armor_effect.display_name = "Test armor"
	armor_effect.kind = EffectDefinition.Kind.ARMOR
	armor_effect.amount = 50
	var reflect_effect := EffectDefinition.new()
	reflect_effect.id = &"foundation:effect/test_reflect"
	reflect_effect.display_name = "Test reflect"
	reflect_effect.kind = EffectDefinition.Kind.REFLECT
	reflect_effect.amount = 50
	var payload_move := MoveDefinition.new()
	payload_move.id = &"foundation:move/test_defense/tier1"
	payload_move.display_name = "Test defense"
	payload_move.family_id = &"foundation:move_family/test_defense"
	payload_move.type_id = &"base:type/none"
	payload_move.effects = [armor_effect, reflect_effect]
	var redirect_effect := EffectDefinition.new()
	redirect_effect.id = &"foundation:effect/test_redirect"
	redirect_effect.display_name = "Test redirect"
	redirect_effect.kind = EffectDefinition.Kind.REDIRECT_DAMAGE
	redirect_effect.amount = 60
	var redirect_move := MoveDefinition.new()
	redirect_move.id = &"foundation:move/test_redirect/tier1"
	redirect_move.display_name = "Test redirect"
	redirect_move.family_id = &"foundation:move_family/test_redirect"
	redirect_move.type_id = &"base:type/none"
	redirect_move.is_passive = true
	redirect_move.effects = [redirect_effect]
	pack.definitions.append_array([payload_move, redirect_move])
	_expect(catalog.rebuild_index().is_empty(), "defensive modifier fixture must form valid content")
	var actor := CombatantState.from_setup({"instance_id": "actor", "team": 0, "max_health": 500, "health": 500, "attack": 0})
	var target := CombatantState.from_setup({"instance_id": "target", "team": 1, "slot_index": 0, "max_health": 500, "health": 500})
	target.statuses = [{"kind": &"periodic", "move_id": payload_move.id, "source_id": &"target", "turns": 0}]
	var redirect_a := CombatantState.from_setup({"instance_id": "redirect-a", "team": 1, "slot_index": 1, "max_health": 500, "health": 500, "move_ids": [redirect_move.id]})
	var redirect_b := CombatantState.from_setup({"instance_id": "redirect-b", "team": 1, "slot_index": 2, "max_health": 500, "health": 500, "move_ids": [redirect_move.id]})
	var damage_effect := EffectDefinition.new()
	damage_effect.id = &"foundation:effect/test_defensive_damage"
	damage_effect.amount = 100
	var attack_move := MoveDefinition.new()
	attack_move.id = &"foundation:move/test_attack/tier1"
	attack_move.type_id = &"base:type/none"
	var combatants := {actor.instance_id: actor, target.instance_id: target, redirect_a.instance_id: redirect_a, redirect_b.instance_id: redirect_b}
	var executor := preload("res://src/domain/battle/damage_effect_executor.gd").new()
	var shared: Dictionary = {}
	executor.execute(damage_effect, {"actor": actor, "target": target, "move": attack_move, "content": catalog, "combatants": combatants, "shared_amounts": shared, "rng": BattleRng.new(1), "emit": Callable(self, "_ignore_event")})
	_expect(target.health == 500 and redirect_a.health == 450 and redirect_b.health == 450, "120% redirection must normalize two 60% providers before target armor")
	_expect(actor.health == 450, "target reflection must apply separately to every redirected portion")
	executor.execute(damage_effect, {"actor": actor, "target": target, "move": attack_move, "content": catalog, "combatants": combatants, "shared_amounts": shared, "rng": BattleRng.new(1), "emit": Callable(self, "_ignore_event")})
	_expect(target.health == 500 and redirect_a.health == 390 and redirect_b.health == 390, "multi-target resolution must preserve the source's repeated redirection-divisor conversion")
	redirect_a.move_ids.clear()
	redirect_b.move_ids.clear()
	actor.health = 500
	target.health = 500
	executor.execute(damage_effect, {"actor": actor, "target": target, "move": attack_move, "content": catalog, "combatants": combatants, "shared_amounts": {}, "rng": BattleRng.new(1), "emit": Callable(self, "_ignore_event")})
	_expect(target.health == 450, "50% armor must halve the post-redirection damage received by the target")
	_expect(actor.health == 450, "50% reflection must damage the actor before target armor is applied")
	armor_effect.amount = 200
	reflect_effect.amount = 150
	var modifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")
	_expect(is_equal_approx(modifiers.armor_rate(target, catalog, combatants), 0.05), "stacked armor must clamp to the source's 5% minimum damage multiplier")
	_expect(is_equal_approx(modifiers.reflect_rate(target, catalog, combatants), 1.0), "stacked reflection must cap at the source's 100% maximum")

func _test_passive_stats_self_damage_and_shields() -> void:
	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var local_stat := EffectDefinition.new()
	local_stat.id = &"foundation:effect/local_attack_percent"
	local_stat.display_name = "Local attack percent"
	local_stat.kind = EffectDefinition.Kind.STAT_PERCENT
	local_stat.stat_type_id = &"base:stat/attack"
	local_stat.amount = 20
	var local_crit := EffectDefinition.new()
	local_crit.id = &"foundation:effect/local_crit"
	local_crit.display_name = "Local critical chance"
	local_crit.kind = EffectDefinition.Kind.CRITICAL_CHANCE
	local_crit.amount = 10
	var local_passive := MoveDefinition.new()
	local_passive.id = &"foundation:move/local_passive/tier1"
	local_passive.display_name = "Local passive"
	local_passive.family_id = &"foundation:move_family/local_passive"
	local_passive.type_id = &"base:type/none"
	local_passive.is_passive = true
	local_passive.effects = [local_stat, local_crit]
	var global_stat := EffectDefinition.new()
	global_stat.id = &"foundation:effect/global_attack_percent"
	global_stat.display_name = "Global attack percent"
	global_stat.kind = EffectDefinition.Kind.STAT_PERCENT
	global_stat.stat_type_id = &"base:stat/attack"
	global_stat.amount = 10
	var global_crit := EffectDefinition.new()
	global_crit.id = &"foundation:effect/global_crit"
	global_crit.display_name = "Global critical chance"
	global_crit.kind = EffectDefinition.Kind.CRITICAL_CHANCE
	global_crit.amount = 5
	var global_passive := MoveDefinition.new()
	global_passive.id = &"foundation:move/global_passive/tier1"
	global_passive.display_name = "Global passive"
	global_passive.family_id = &"foundation:move_family/global_passive"
	global_passive.type_id = &"base:type/none"
	global_passive.is_global_passive = true
	global_passive.effects = [global_stat, global_crit]
	pack.definitions.append_array([local_passive, global_passive])
	_expect(catalog.rebuild_index().is_empty(), "passive stat fixture must form valid content")
	var actor := CombatantState.from_setup({"instance_id": "actor", "team": 0, "level": 10, "max_health": 200, "health": 200, "attack": 100, "healing": 1000, "move_ids": [local_passive.id]})
	actor.stat_stages[&"base:stat/attack"] = 2
	var ally := CombatantState.from_setup({"instance_id": "ally", "team": 0, "move_ids": [global_passive.id]})
	var combatants := {actor.instance_id: actor, ally.instance_id: ally}
	var modifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")
	_expect(is_equal_approx(modifiers.effective_attack(actor, catalog, combatants), 292.5), "attack must preserve the source's squared stage multiplier and additive local/global passive percentage")
	_expect(is_equal_approx(modifiers.critical_chance(actor, catalog, combatants), 21.25), "critical chance must add the 6.25 base, owned passive, and unique living-team global passive")
	var shield_effect := EffectDefinition.new()
	shield_effect.kind = EffectDefinition.Kind.SHIELD
	shield_effect.amount = 30
	shield_effect.scaling = EffectDefinition.Scaling.HEALING
	var shield_executor := preload("res://src/domain/battle/shield_effect_executor.gd").new()
	shield_executor.execute(shield_effect, {"actor": actor, "target": actor, "content": catalog, "combatants": combatants, "rng": BattleRng.new(1, [0]), "emit": Callable(self, "_ignore_event")})
	_expect(actor.shield == 80 and actor.max_shield == 80, "shield amount must use legacy healing scaling and establish its maximum")
	shield_effect.amount = 20
	shield_executor.execute(shield_effect, {"actor": actor, "target": actor, "content": catalog, "combatants": combatants, "rng": BattleRng.new(1, [0]), "emit": Callable(self, "_ignore_event")})
	_expect(actor.shield == 80, "a smaller shield must not replace the source's current shield")
	var self_effect := EffectDefinition.new()
	self_effect.id = &"foundation:effect/self_damage_test"
	self_effect.kind = EffectDefinition.Kind.SELF_DAMAGE
	self_effect.amount = 30
	self_effect.scaling = EffectDefinition.Scaling.ATTACK
	var self_executor := preload("res://src/domain/battle/self_damage_effect_executor.gd").new()
	actor.shield = 10
	self_executor.execute(self_effect, {"actor": actor, "content": catalog, "combatants": combatants, "shared_amounts": {}, "rng": BattleRng.new(1, [0]), "emit": Callable(self, "_ignore_event")})
	_expect(actor.health == 186 and actor.shield == 0, "flat self-damage must use effective attack and pass through the actor's shield without armor or reflection")
	self_effect.kind = EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE
	self_effect.amount = 25
	self_executor.execute(self_effect, {"actor": actor, "content": catalog, "combatants": combatants, "shared_amounts": {}, "rng": BattleRng.new(1), "emit": Callable(self, "_ignore_event")})
	_expect(actor.health == 136 and actor.shield == 0, "percentage self-damage must use maximum health and integer AddToHealth semantics")

func _test_derived_health_and_energy_maxima() -> void:
	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var health_percent := EffectDefinition.new()
	health_percent.id = &"foundation:effect/derived_health_percent"
	health_percent.display_name = "Derived health percent"
	health_percent.kind = EffectDefinition.Kind.STAT_PERCENT
	health_percent.stat_type_id = &"base:stat/health"
	health_percent.amount = 20
	var energy_percent := EffectDefinition.new()
	energy_percent.id = &"foundation:effect/derived_energy_percent"
	energy_percent.display_name = "Derived energy percent"
	energy_percent.kind = EffectDefinition.Kind.STAT_PERCENT
	energy_percent.stat_type_id = &"base:stat/energy"
	energy_percent.amount = 10
	var passive := MoveDefinition.new()
	passive.id = &"foundation:move/derived_max_passive/tier1"
	passive.display_name = "Derived maximum passive"
	passive.family_id = &"foundation:move_family/derived_max_passive"
	passive.type_id = &"base:type/none"
	passive.is_passive = true
	passive.effects = [health_percent, energy_percent]
	pack.definitions.append(passive)
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].move_ids.append(passive.id)
	setup.combatants[0].base_max_health = 100
	setup.combatants[0].max_health = 100
	setup.combatants[0].health = 100
	setup.combatants[0].base_max_energy = 100
	setup.combatants[0].max_energy = 100
	setup.combatants[0].energy = 100
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(101))
	var actor := _state_for(engine, "player-1")
	_expect(start.accepted and actor.max_health == 120 and actor.health == 100, "health maximum must apply one stage/passive rate without percentage-scaling current health")
	_expect(actor.max_energy == 100, "a personal passive uses only its first stat-percentage entry, matching OwnedMinion")
	var modifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")
	var state := CombatantState.from_setup({"instance_id": "derived", "team": 0, "base_max_health": 100, "max_health": 100, "base_max_energy": 100, "max_energy": 100})
	state.stat_stages[&"base:stat/health"] = 2
	state.stat_stages[&"base:stat/energy"] = -1
	_expect(modifiers.effective_max_health(state, catalog, {state.instance_id: state}) == 150, "health maximum must use the recovered single positive stage multiplier")
	_expect(modifiers.effective_max_energy(state, catalog, {state.instance_id: state}) == 64, "energy maximum must preserve the recovered squared negative stage multiplier")

func _test_equal_speed_tie_preference() -> void:
	var setup := SampleFactory.battle_setup()
	setup.erase("tie_first_team")
	setup.combatants[0].speed = 10
	setup.combatants[1].speed = 10
	var engine := BattleEngine.new()
	engine.start(setup, SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(1, [500001]))
	_expect(engine.get_decision().team == 1, "a battle-activation tie roll above 50% must preserve the source's opponent-first insertion quirk")
	engine = BattleEngine.new()
	engine.start(setup, SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(1, [500000]))
	_expect(engine.get_decision().team == 0, "tie-roll equality must preserve the source's player-first strict boundary")

func _test_shield_and_resurrection_battle_modifiers() -> void:
	var catalog := SampleFactory.build_catalog()
	var strike := catalog.packs[0].definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/strike/tier1")[0] as MoveDefinition
	var damage := strike.effects[0] as EffectDefinition
	damage.amount = 300
	damage.random_bonus = 0
	damage.scaling = EffectDefinition.Scaling.ATTACK
	damage.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].level = 10
	setup.combatants[0].attack = 1000
	setup.combatants[0].speed = 30
	setup.combatants[1].slot_index = 0
	setup.combatants[1].max_health = 100
	setup.combatants[1].health = 100
	setup.combatants[1].speed = 10
	var second_enemy: Dictionary = setup.combatants[1].duplicate(true)
	second_enemy.instance_id = "enemy-2"
	second_enemy.slot_index = 1
	second_enemy.max_health = 500
	second_enemy.health = 500
	second_enemy.speed = 5
	setup.combatants.append(second_enemy)
	var rules := SampleFactory.build_rules()
	rules.configuration = {"battle_modifiers": {"shield": {"enemy": 1}}}
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, rules, BattleRng.new(401, [1, 0, 0, 0, 0, 0]))
	var decision := engine.get_decision()
	_expect(start.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_shields_assigned") and decision.legal_moves[0].target_ids == ["enemy-1"], "round shields must leave one enemy targetable and exclude the shielded slot from legal targets")
	var response := engine.submit(BattleCommand.new(&"player-1", BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_shield_removed" and event.target_id == &"enemy-2"), "the last living shielded enemy must lose its battle-mod shield after an action")
	_expect(engine.get_decision().actor_id == "enemy-2" and engine.get_decision().legal_moves[0].target_ids.has("player-1"), "an automatically unshielded survivor must continue the round normally")

	rules = SampleFactory.build_rules()
	rules.configuration = {"battle_modifiers": {"resurrection": {"team": 1, "turns": 1}}}
	engine = BattleEngine.new()
	engine.start(setup, catalog, rules, BattleRng.new(402, [0, 0, 0, 0, 0]))
	var afflicted := engine._state.combatants[&"enemy-1"] as CombatantState
	afflicted.statuses.append({"kind": &"periodic", "move_id": strike.id, "source_id": &"player-1", "turns": 0})
	afflicted.stat_stages[&"foundation:stat/attack"] = -1
	decision = engine.get_decision()
	response = engine.submit(BattleCommand.new(&"player-1", BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	var revived := _state_for(engine, "enemy-1")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_resurrected") and revived.health == 50 and not revived.defeated, "partial-team resurrection must clear defeat and halve health on the first revival")
	_expect(revived.statuses.is_empty() and revived.stat_stages.is_empty(), "resurrection must clear periodic effects and stat stages as source ClearBuffsAndDebuffs does")
	var revived_presentation := BattlePresentationState.apply_event({"statuses": [{"kind": &"periodic"}], "stat_stages": {"attack": -1}}, BattleEvent.new(0, &"battle_mod_resurrected", &"", &"enemy-1", {"health": 50}))
	_expect(revived_presentation.statuses.is_empty() and revived_presentation.stat_stages.is_empty(), "revival presentation must remove old effects immediately rather than at the next snapshot sync")
	_expect(engine.get_decision().actor_id == "enemy-1", "a faster resurrected minion that had not acted must re-enter the recalculated current-round order")

func _test_extra_minion_battle_modifier() -> void:
	var catalog := SampleFactory.build_catalog()
	var strike := catalog.packs[0].definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/strike/tier1")[0] as MoveDefinition
	var damage := strike.effects[0] as EffectDefinition
	damage.amount = 300
	damage.random_bonus = 0
	damage.scaling = EffectDefinition.Scaling.ATTACK
	damage.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].level = 10
	setup.combatants[0].attack = 1000
	setup.combatants[0].speed = 30
	setup.combatants[1].max_health = 100
	setup.combatants[1].health = 100
	var extra := {
		"instance_id": "enemy-extra-1", "definition_id": "foundation:minion/rival", "move_ids": ["foundation:move/strike/tier1"],
		"level": 10, "max_health": 240, "health": 240, "max_energy": 10, "energy": 10, "attack": 100, "speed": 8,
	}
	var rules := SampleFactory.build_rules()
	rules.configuration = {"battle_modifiers": {"extra_minions": {"enemy": {"count": 1, "templates": [extra]}}}}
	var engine := BattleEngine.new()
	engine.start(setup, catalog, rules, BattleRng.new(501, [0, 0, 0, 0, 0]))
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(&"player-1", BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	_expect(engine.get_result().is_empty() and response.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_extra_spawned" and event.target_id == &"enemy-extra-1"), "an available extra enemy must replace a defeated slot before the battle can end")
	var ids: Array = engine.snapshot().state.combatants.map(func(state): return state.instance_id)
	_expect("enemy-1" not in ids and "enemy-extra-1" in ids and _state_for(engine, "enemy-extra-1").slot_index == 0, "extra-minion replacement must preserve the dead slot without retaining a duplicate combatant")

func _test_move_timer_battle_modifier() -> void:
	var catalog := SampleFactory.build_catalog()
	var setup := SampleFactory.battle_setup()
	var timer_actor := {
		"instance_id": "timer-minion", "definition_id": "foundation:minion/rival", "team": 1,
		"move_ids": ["foundation:move/strike/tier1"], "level": 10, "max_health": 100, "health": 100,
		"max_energy": 100, "energy": 100, "attack": 0, "speed": 100,
	}
	var rules := SampleFactory.build_rules()
	rules.configuration = {"battle_modifiers": {"move_timer": {"interval": 1, "move_id": "foundation:move/strike/tier1", "actor": timer_actor}}}
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, rules, BattleRng.new(601))
	_expect(start.accepted and not start.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_timer_triggered"), "a move timer with interval one must allow the first normal selection")
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"foundation:move/strike/tier1", [&"enemy-1"], int(decision.revision)))
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_timer_triggered" and event.actor_id == &"timer-minion"), "the persistent hidden modifier minion must fire before the next normal actor at the configured interval")
	_expect(engine.get_decision().actor_id == "enemy-1" and "timer-minion" not in engine.snapshot().state.turn_order, "the move-timer minion must not consume a party turn or participate in normal ordering")
	var before := engine.snapshot()
	engine.restore(before)
	_expect(engine.snapshot() == before, "move-timer actor energy and counter state must round-trip through battle snapshots")

func _make_wait_move() -> MoveDefinition:
	var effect := EffectDefinition.new()
	effect.id = &"foundation:effect/lifecycle_wait"
	effect.display_name = "Lifecycle wait"
	effect.kind = EffectDefinition.Kind.ENERGY
	effect.target_scope = EffectDefinition.TargetScope.ACTOR
	effect.phase = EffectDefinition.Phase.BEFORE_ACCURACY
	effect.executor = preload("res://src/domain/battle/energy_effect_executor.gd")
	var move := MoveDefinition.new()
	move.id = &"foundation:move/lifecycle_wait/tier1"
	move.display_name = "Lifecycle wait"
	move.family_id = &"foundation:move_family/lifecycle_wait"
	move.type_id = &"base:type/none"
	move.energy_cost = 0
	move.target_side = MoveDefinition.TargetSide.SELF
	move.effects = [effect]
	return move

func _submit_current(engine: BattleEngine, move_id: StringName, target_id: StringName) -> BattleResponse:
	var decision := engine.get_decision()
	return engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, move_id, [target_id], int(decision.revision)))

func _state_for(engine: BattleEngine, instance_id: String) -> Dictionary:
	return engine.snapshot().state.combatants.filter(func(state): return state.instance_id == instance_id)[0]

func _test_charge_exhaust_and_cooldown_lifecycle() -> void:
	var catalog := SampleFactory.build_catalog()
	var pack := catalog.packs[0]
	var strike := pack.definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/strike/tier1")[0] as MoveDefinition
	strike.charge_turns = 2
	strike.exhaust_turns = 2
	strike.cooldown_turns = 1
	strike.energy_cost = 3
	var wait_move := _make_wait_move()
	pack.definitions.append(wait_move)
	var setup := SampleFactory.battle_setup()
	setup.combatants[1].move_ids = [wait_move.id]
	var engine := BattleEngine.new()
	engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(71))
	var response := _submit_current(engine, strike.id, &"enemy-1")
	var actor := _state_for(engine, "player-1")
	_expect(actor.energy == 10 and actor.current_charge == 1, "selecting a charged move must lock its targets without paying energy")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"charge_started"), "charged selection must emit playback state")
	response = _submit_current(engine, wait_move.id, &"enemy-1")
	actor = _state_for(engine, "player-1")
	_expect(actor.current_charge == 2 and actor.energy == 10 and engine.get_decision().actor_id == "enemy-1", "an incomplete charge turn must advance automatically without paying cost")
	response = _submit_current(engine, wait_move.id, &"enemy-1")
	actor = _state_for(engine, "player-1")
	_expect(actor.charge_move_id == "" and actor.energy == 7 and actor.current_exhaust == 2, "a completed charge must release automatically, pay cost, and establish exhaustion")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"charge_released"), "automatic charged release must remain visible in ordered events")
	_submit_current(engine, wait_move.id, &"enemy-1")
	actor = _state_for(engine, "player-1")
	_expect(actor.current_exhaust == 1 and int(actor.cooldowns.get(strike.id, 0)) == 1, "first exhausted turn must skip while a one-turn cooldown remains blocked")
	_submit_current(engine, wait_move.id, &"enemy-1")
	actor = _state_for(engine, "player-1")
	_expect(actor.current_exhaust == 0 and int(actor.cooldowns.get(strike.id, 0)) == 0, "second exhausted turn must skip and finish the cooldown elapsed-counter lifecycle")
	_submit_current(engine, wait_move.id, &"enemy-1")
	_expect(engine.get_decision().actor_id == "player-1", "actor must receive a decision after every configured exhaustion turn is consumed")

func _test_defeated_cooldowns_do_not_tick() -> void:
	var catalog := SampleFactory.build_catalog()
	var wait_move := _make_wait_move()
	catalog.packs[0].definitions.append(wait_move)
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].move_ids = [wait_move.id]
	setup.combatants[1].move_ids = [wait_move.id]
	var second_player: Dictionary = setup.combatants[0].duplicate(true)
	second_player.instance_id = "player-2"
	second_player.slot_index = 1
	second_player.speed = 5
	var second_enemy: Dictionary = setup.combatants[1].duplicate(true)
	second_enemy.instance_id = "enemy-2"
	second_enemy.slot_index = 1
	second_enemy.speed = 4
	setup.combatants.append(second_player)
	setup.combatants.append(second_enemy)
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(73))
	var defeated_actor := engine._state.combatants[StringName("player-2")] as CombatantState if start.accepted else null
	if defeated_actor != null:
		defeated_actor.health = 0
		defeated_actor.defeated = true
		defeated_actor.cooldowns[&"foundation:move/strike/tier1"] = 2
	var turns_accepted := true
	for _turn_index in 4:
		if engine._state.round_number >= 2: break
		var decision := engine.get_decision()
		if decision.is_empty():
			turns_accepted = false
			break
		var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, wait_move.id, [StringName(decision.actor_id)], int(decision.revision)))
		turns_accepted = turns_accepted and response.accepted
	_expect(start.accepted and defeated_actor != null and turns_accepted and engine._state.round_number == 2 and int(defeated_actor.cooldowns.get(&"foundation:move/strike/tier1", 0)) == 2, "cooldowns must decrement only at round start for living minions, preserving defeated minion cooldowns through later revival")

func _test_frozen_and_stunned_turn_activation() -> void:
	var catalog := SampleFactory.build_catalog()
	var wait_move := _make_wait_move()
	catalog.packs[0].definitions.append(wait_move)
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].frozen = true
	setup.combatants[1].move_ids = [wait_move.id]
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(9, [0, 0, 0, 0, 0, 0]))
	_expect(start.events.any(func(event: BattleEvent): return event.kind == &"frozen_turn_skipped") and engine.get_decision().actor_id == "enemy-1", "first frozen activation must always skip because the strict thaw boundary cannot pass")
	var response := _submit_current(engine, wait_move.id, &"enemy-1")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"thawed") and engine.get_decision().actor_id == "player-1", "a later frozen activation must reroll and can thaw into a decision")
	setup = SampleFactory.battle_setup()
	setup.combatants[0].stunned = true
	setup.combatants[1].move_ids = [wait_move.id]
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, SampleFactory.build_rules(), BattleRng.new(9, [500000, 0, 0, 0, 0, 499999]))
	_expect(start.events.any(func(event: BattleEvent): return event.kind == &"stunned_turn_skipped"), "stun equality at 50% must skip because recovery uses strict greater-than")
	response = _submit_current(engine, wait_move.id, &"enemy-1")
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"stun_resisted") and engine.get_decision().actor_id == "player-1", "stun must reroll each activation and permit a decision below 50% without clearing the status")

func _test_legacy_ai_selection_and_snapshot() -> void:
	var catalog := SampleFactory.build_catalog()
	var mend := catalog.packs[0].definitions.filter(func(definition): return definition is MoveDefinition and definition.id == &"foundation:move/mend/tier1")[0] as MoveDefinition
	var heal := mend.effects[0] as EffectDefinition
	heal.amount = 3000
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].speed = 5
	setup.combatants[1].speed = 20
	setup.combatants[1].health = 1
	setup.combatants[1].healing = 1000
	setup.combatants[1].move_ids = [&"foundation:move/strike/tier1", mend.id]
	var rules := SampleFactory.build_rules()
	rules.configuration = {"ai_teams": [1]}
	var engine := BattleEngine.new()
	var start := engine.start(setup, catalog, rules, BattleRng.new(301, [0, 0, 0, 0, 0]))
	_expect(start.accepted and engine.get_decision().actor_id == "enemy-1", "AI fixture must begin on the configured AI team")
	var before := engine.snapshot()
	var response := engine.submit_ai_turn()
	_expect(response.accepted and response.events.any(func(event: BattleEvent): return event.kind == &"move_used" and event.values.move_id == String(mend.id)), "legacy threat scoring must prefer a large useful heal over generic damage")
	var first_after := engine.snapshot()
	engine.restore(before)
	response = engine.submit_ai_turn()
	_expect(response.accepted and engine.snapshot() == first_after, "restoring battle, RNG, and persistent AI threat state must reproduce the same AI turn")
	var decision := engine.get_decision()
	var rejected := engine.submit_ai_turn()
	_expect(not rejected.accepted and rejected.error_code == &"not_ai_actor" and decision.team == 0, "AI submission must reject a player-controlled active actor without changing its decision")

	var unavailable := MoveDefinition.new()
	unavailable.id = &"foundation:move/unavailable_attack/tier1"
	unavailable.display_name = "Unavailable Attack"
	unavailable.family_id = &"foundation:move_family/unavailable_attack"
	unavailable.available = false
	unavailable.energy_cost = 0
	var unavailable_effect := EffectDefinition.new()
	unavailable_effect.id = &"foundation:effect/unavailable_attack_damage"
	unavailable_effect.display_name = "Unavailable attack damage"
	unavailable_effect.kind = EffectDefinition.Kind.DAMAGE
	unavailable_effect.amount = 1000
	unavailable_effect.executor = preload("res://src/domain/battle/damage_effect_executor.gd")
	unavailable.effects = [unavailable_effect]
	catalog.packs[0].definitions.append(unavailable_effect)
	catalog.packs[0].definitions.append(unavailable)
	var desperation := (load("res://content/imported/recovered-20260911/moves/base__move_desperation_tier1.tres") as MoveDefinition).duplicate(true) as MoveDefinition
	desperation.type_id = &"base:type/none"
	catalog.packs[0].definitions.append(desperation)
	catalog.rebuild_index()
	setup = SampleFactory.battle_setup()
	setup.combatants[0].speed = 5
	setup.combatants[1].speed = 20
	setup.combatants[1].move_ids = [unavailable.id, &"foundation:move/strike/tier1"]
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(302, [0, 0, 0, 0, 0]))
	response = engine.submit_ai_turn()
	_expect(start.accepted and response.accepted and response.events.any(func(event: BattleEvent): return event.kind == &"move_used" and event.values.move_id == "foundation:move/strike/tier1"), "AI must ignore unavailable source moves and fall back to a legal implemented move")

	setup = SampleFactory.battle_setup()
	setup.combatants[0].speed = 5
	setup.combatants[1].speed = 20
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(303, [0, 0, 0, 0, 0]))
	var desperate_actor := engine._state.combatants[&"enemy-1"] as CombatantState
	desperate_actor.energy = 0
	desperate_actor.cooldowns[&"foundation:move/strike/tier1"] = 1
	var desperation_decision := engine.get_decision()
	response = engine.submit_ai_turn()
	_expect(start.accepted and desperation_decision.legal_moves.any(func(legal_move: Dictionary): return StringName(legal_move.move_id) == &"base:move/desperation/tier1") and response.accepted and response.events.any(func(event: BattleEvent): return event.kind == &"move_used" and event.values.move_id == "base:move/desperation/tier1"), "when every learned move is unusable due to energy or cooldown, the AI must choose Desperation rather than skip")

	setup = SampleFactory.battle_setup()
	setup.combatants[0].speed = 5
	setup.combatants[1].speed = 20
	engine = BattleEngine.new()
	start = engine.start(setup, catalog, rules, BattleRng.new(303, [0, 0, 0, 0, 0]))
	for combatant in engine._state.combatants.values():
		if combatant.team == 0:
			(combatant as CombatantState).battle_mod_shield_active = true
	var shielded_decision := engine.get_decision()
	response = engine.submit_ai_turn()
	_expect(start.accepted and shielded_decision.legal_moves.size() == 1 and StringName(shielded_decision.legal_moves[0].move_id) == &"base:move/desperation/tier1" and shielded_decision.legal_moves[0].target_ids.is_empty() and response.accepted and response.events.any(func(event: BattleEvent): return event.kind == &"move_used" and event.values.move_id == "base:move/desperation/tier1") and not response.events.any(func(event: BattleEvent): return event.kind == &"turn_skipped"), "when all enemies are temporarily untargetable, desperation's self-cost effects still execute instead of skipping the AI turn")

func _test_miss_cost_restore_and_cooldown_order() -> void:
	var catalog := SampleFactory.build_catalog()
	catalog.rebuild_index()
	var strike := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	strike.accuracy_percent = 50
	strike.cooldown_turns = 3
	var restore := EffectDefinition.new()
	restore.id = &"foundation:effect/pre_miss_restore"
	restore.display_name = "Pre-miss energy restore"
	restore.kind = EffectDefinition.Kind.ENERGY
	restore.target_scope = EffectDefinition.TargetScope.ACTOR
	restore.phase = EffectDefinition.Phase.BEFORE_ACCURACY
	restore.scaling = EffectDefinition.Scaling.ENERGY_STAT_PERCENT
	restore.amount = 50
	restore.executor = preload("res://src/domain/battle/energy_effect_executor.gd")
	strike.effects.push_front(restore)
	var engine := BattleEngine.new()
	engine.start(SampleFactory.battle_setup(), catalog, SampleFactory.build_rules(), BattleRng.new(1, [0, 900000, 0, 0]))
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	var actor_state: Dictionary = {}
	for combatant in engine.snapshot().state.combatants:
		if combatant.instance_id == "player-1": actor_state = combatant
	_expect(response.events.any(func(event: BattleEvent): return event.kind == &"missed"), "scripted miss roll must emit a miss")
	_expect(actor_state.energy == 10, "energy percentage restoration must occur after cost and before a miss")
	_expect(not actor_state.cooldowns.has(strike.id), "a missed legacy move must not start its cooldown")

func _test_shared_stat_and_condition_rolls() -> void:
	var catalog := SampleFactory.build_catalog()
	catalog.rebuild_index()
	var strike := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	var debuff := EffectDefinition.new()
	debuff.id = &"foundation:effect/shared_attack_debuff"
	debuff.display_name = "Shared attack debuff"
	debuff.kind = EffectDefinition.Kind.STAT_STAGE
	debuff.target_scope = EffectDefinition.TargetScope.ENEMY_TARGETS
	debuff.phase = EffectDefinition.Phase.ENEMY_TARGET
	debuff.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
	debuff.amount = -2
	debuff.chance_percent = 50
	debuff.stat_type_id = &"base:stat/attack"
	debuff.executor = preload("res://src/domain/battle/stat_stage_effect_executor.gd")
	var stun := EffectDefinition.new()
	stun.id = &"foundation:effect/shared_stun"
	stun.display_name = "Shared stun"
	stun.kind = EffectDefinition.Kind.STUN
	stun.target_scope = EffectDefinition.TargetScope.ENEMY_TARGETS
	stun.phase = EffectDefinition.Phase.ENEMY_TARGET
	stun.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
	stun.chance_percent = 25
	stun.executor = preload("res://src/domain/battle/condition_effect_executor.gd")
	strike.effects.append(debuff)
	strike.effects.append(stun)
	var engine := BattleEngine.new()
	# buff=40 applies the 50% debuff; stun=20 applies the 25% stun.
	engine.start(SampleFactory.battle_setup(), catalog, SampleFactory.build_rules(), BattleRng.new(1, [400000, 0, 200000, 0, 0]))
	var decision := engine.get_decision()
	engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	var enemy_state: Dictionary = {}
	for combatant in engine.snapshot().state.combatants:
		if combatant.instance_id == "enemy-1": enemy_state = combatant
	_expect(int(enemy_state.stat_stages.get(&"base:stat/attack", 0)) == -2, "stat stages must use the one shared legacy buff/debuff roll")
	_expect(enemy_state.stunned, "stun must use the one shared legacy stun roll")

func _test_rejected_command_is_atomic() -> void:
	var engine := BattleEngine.new()
	engine.start(SampleFactory.battle_setup(), SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(9, [44]))
	var before := engine.snapshot()
	var rejected := engine.submit(BattleCommand.new(&"enemy-1", BattleCommand.Kind.USE_MOVE, &"foundation:move/strike/tier1", [&"player-1"], 0))
	_expect(not rejected.accepted and rejected.error_code == &"wrong_actor", "wrong actor command must be rejected structurally")
	_expect(before == engine.snapshot(), "rejected command must not change state, revision, sequence, or RNG")

func _test_state_isolation() -> void:
	var setup := SampleFactory.battle_setup()
	setup.combatants.append({"instance_id": "player-2", "definition_id": "foundation:minion/apprentice", "team": 0, "move_ids": ["foundation:move/strike/tier1"], "max_health": 32, "health": 5, "max_energy": 10, "attack": 2, "speed": 1})
	var engine := BattleEngine.new()
	engine.start(setup, SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(2))
	var snapshot := engine.snapshot()
	var states: Dictionary = {}
	for state in snapshot.state.combatants: states[state.instance_id] = state
	_expect(states["player-1"].health == 32 and states["player-2"].health == 5, "instances sharing a definition must not share health")

func _test_presenter_independence() -> void:
	var first := _run_battle()
	var logical_snapshot: Dictionary = first.snapshot.duplicate(true)
	var event_count: int = first.events.size()
	_expect(event_count > 0, "battle fixture must emit playback facts")
	_expect(first.snapshot == logical_snapshot, "reading playback events must not mutate logical state")

func _test_presenter_modes_are_equivalent() -> void:
	var immediate_run := _run_recovered_parity_battle()
	var animated_run := _run_recovered_parity_battle()
	_expect(immediate_run.commands == animated_run.commands, "immediate and animated presentation runs must submit the same player and AI commands")
	_expect(not immediate_run.result.is_empty(), "recovered battle parity fixture must reach a real victory or defeat result")
	_expect(immediate_run.event_records == animated_run.event_records and immediate_run.engine.snapshot() == animated_run.engine.snapshot(), "identical recovered battle setup and commands must produce identical engine events and outcomes")
	var immediate_snapshot: Dictionary = immediate_run.engine.snapshot().duplicate(true)
	var animated_snapshot: Dictionary = animated_run.engine.snapshot().duplicate(true)
	var immediate := BattlePresenter.new()
	add_child(immediate)
	immediate.seconds_per_event = 0.001
	await immediate.play(immediate_run.events, true)
	var animated := BattlePresenter.new()
	add_child(animated)
	animated.seconds_per_event = 0.001
	await animated.play(animated_run.events, false)
	_expect(immediate.visual_state == animated.visual_state, "immediate and animated presentation of the same real recovered battle must converge on identical event-derived visual state")
	_expect(immediate_run.engine.snapshot() == immediate_snapshot and animated_run.engine.snapshot() == animated_snapshot, "presenter playback modes must leave both recovered battle outcomes unchanged")
	immediate.queue_free()
	animated.queue_free()

func _run_recovered_parity_battle() -> Dictionary:
	var catalog := load("res://content/imported/recovered-20260911/catalog.tres") as ContentCatalog
	var rules := RuleSetDefinition.new()
	rules.id = &"base:rules/presentation-parity"
	rules.display_name = "Presentation parity fixture"
	rules.configuration = {"ai_teams": [1]}
	var setup := _recovered_setup(&"base:move/flare_up/tier1", [&"base:type/fire"])
	setup.combatants[1].move_ids = [&"base:move/burn/tier1"]
	var engine := BattleEngine.new()
	var response := engine.start(setup, catalog, rules, BattleRng.new(704, [0, 0, 0, 0, 0, 999999]))
	var events: Array[BattleEvent] = []
	var event_records: Array[Dictionary] = []
	events.append_array(response.events)
	for event in response.events: event_records.append(event.to_dict())
	var commands: Array[Dictionary] = []
	var steps := 0
	while engine.get_result().is_empty() and steps < 100:
		steps += 1
		var decision := engine.get_decision()
		if decision.is_empty(): break
		if int(decision.team) == 1:
			response = engine.submit_ai_turn()
			commands.append({"actor": decision.actor_id, "kind": "ai"})
		else:
			if decision.legal_moves.is_empty(): break
			var legal_move: Dictionary = decision.legal_moves[0]
			var targets: Array[StringName] = []
			if not legal_move.target_ids.is_empty(): targets.append(StringName(legal_move.target_ids[0]))
			commands.append({"actor": decision.actor_id, "move": legal_move.move_id, "targets": targets})
			response = engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(legal_move.move_id), targets, int(decision.revision)))
		if not response.accepted: break
		events.append_array(response.events)
		for event in response.events: event_records.append(event.to_dict())
	return {"engine": engine, "events": events, "event_records": event_records, "commands": commands, "result": engine.get_result().to_dictionary()}

func _test_snapshot_restore() -> void:
	var engine := BattleEngine.new()
	engine.start(SampleFactory.battle_setup(), SampleFactory.build_catalog(), SampleFactory.build_rules(), BattleRng.new(51, [0, 3]))
	var before := engine.snapshot()
	var decision := engine.get_decision()
	var command := BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"foundation:move/strike/tier1", [&"enemy-1"], int(decision.revision))
	var first := engine.submit(command)
	var first_events: Array[Dictionary] = []
	for event in first.events: first_events.append(event.to_dict())
	var first_after := engine.snapshot()
	engine.restore(before)
	var second := engine.submit(command)
	var second_events: Array[Dictionary] = []
	for event in second.events: second_events.append(event.to_dict())
	_expect(first_events == second_events, "snapshot restore must reproduce ordered events")
	_expect(first_after == engine.snapshot(), "snapshot restore must reproduce state and RNG")

func _test_save_validation() -> void:
	var repository := SaveRepository.new()
	var valid := {"schema_version": 1, "content_version": "test", "character": {}, "party": [], "storage": [], "progression": {}, "room_state": {}, "safe_location": {}, "active_mods": {}, "pending_mods": {}}
	_expect(repository.validate(valid).ok, "complete save payload must validate")
	var future := valid.duplicate(true)
	future.schema_version = 999
	_expect(repository.validate(future).code == "unsupported_schema", "newer save schemas must fail explicitly")
	var migration := repository.migrate_payload(valid)
	_expect(migration.ok and migration.state.schema_version == 2 and migration.state.has("pending_battle") and migration.state.applied_battle_ids.is_empty(), "schema 1 saves must migrate in memory to schema 2 campaign fields")
	_expect(repository.validate(migration.state).ok, "migrated schema 2 campaign save payloads must pass nested validation")
	var malformed_v2: Dictionary = migration.state.duplicate(true)
	malformed_v2.party = [{"instance_id": "duplicate"}, {"instance_id": "duplicate"}]
	_expect(not repository.validate(malformed_v2).ok, "schema 2 saves must reject incomplete or duplicate owned-minion instances")
	_expect(repository.delete_slot(0).code == "invalid_slot", "save deletion must reject out-of-range slots before accessing user data")

func _test_campaign_catalog_and_progression() -> void:
	var catalog := load("res://content/imported/recovered-20260911/catalog.tres").duplicate(true) as ContentCatalog
	var campaign_pack := load("res://content/base/packs/campaign_slice.tres") as ContentPackDefinition
	var floor_two_pack := load("res://content/base/packs/floor_2_slice.tres") as ContentPackDefinition
	var floor_three_pack := load("res://content/base/packs/floor_3_slice.tres") as ContentPackDefinition
	var floor_three_trainers_pack := load("res://content/base/packs/floor_3_trainers.tres") as ContentPackDefinition
	var floor_four_pack := load("res://content/base/packs/floor_4_slice.tres") as ContentPackDefinition
	var floor_four_trainers_pack := load("res://content/base/packs/floor_4_trainers.tres") as ContentPackDefinition
	var floor_five_pack := load("res://content/base/packs/floor_5_slice.tres") as ContentPackDefinition
	var floor_five_trainers_pack := load("res://content/base/packs/floor_5_trainers.tres") as ContentPackDefinition
	var has_campaign_pack := false
	var has_floor_two_pack := false
	var has_floor_three_pack := false
	var has_floor_three_trainers_pack := false
	var has_floor_four_pack := false
	var has_floor_four_trainers_pack := false
	var has_floor_five_pack := false
	var has_floor_five_trainers_pack := false
	for pack in catalog.packs:
		if pack != null and pack.id == campaign_pack.id:
			has_campaign_pack = true
		if pack != null and pack.id == floor_two_pack.id:
			has_floor_two_pack = true
		if pack != null and pack.id == floor_three_pack.id:
			has_floor_three_pack = true
		if pack != null and pack.id == floor_three_trainers_pack.id:
			has_floor_three_trainers_pack = true
		if pack != null and pack.id == floor_four_pack.id:
			has_floor_four_pack = true
		if pack != null and pack.id == floor_four_trainers_pack.id:
			has_floor_four_trainers_pack = true
		if pack != null and pack.id == floor_five_pack.id:
			has_floor_five_pack = true
		if pack != null and pack.id == floor_five_trainers_pack.id:
			has_floor_five_trainers_pack = true
	if not has_campaign_pack:
		catalog.packs.append(campaign_pack)
	if not has_floor_two_pack:
		catalog.packs.append(floor_two_pack)
	if not has_floor_three_pack:
		catalog.packs.append(floor_three_pack)
	if not has_floor_three_trainers_pack:
		catalog.packs.append(floor_three_trainers_pack)
	if not has_floor_four_pack:
		catalog.packs.append(floor_four_pack)
	if not has_floor_four_trainers_pack:
		catalog.packs.append(floor_four_trainers_pack)
	if not has_floor_five_pack:
		catalog.packs.append(floor_five_pack)
	if not has_floor_five_trainers_pack:
		catalog.packs.append(floor_five_trainers_pack)
	# The standard campaign now references both five-floor families. Match the
	# runtime's ten-floor pack set, rather than validating a five-floor fixture
	# against a ten-floor campaign definition.
	for floor_number in range(6, 11):
		for suffix in ["slice", "trainers"]:
			var extra_pack := load("res://content/base/packs/floor_%d_%s.tres" % [floor_number, suffix]) as ContentPackDefinition
			var already_loaded := false
			for existing_pack in catalog.packs:
				if existing_pack.id == extra_pack.id:
					already_loaded = true
					break
			if not already_loaded:
				catalog.packs.append(extra_pack)
	var catalog_errors := catalog.rebuild_index()
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var room_start := catalog.get_definition(&"base:room/level_1_1_entryhallway") as RoomDefinition
	var room_a := catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	var room_b := catalog.get_definition(&"base:room/level_1_1_b") as RoomDefinition
	var room_e := catalog.get_definition(&"base:room/level_1_1_e") as RoomDefinition
	var room_hall := catalog.get_definition(&"base:room/level_1_1_h0") as RoomDefinition
	var room_h2 := catalog.get_definition(&"base:room/level_1_1_h2") as RoomDefinition
	var room_courtyard := catalog.get_definition(&"base:room/level_1_1_courtyard") as RoomDefinition
	var room_eggery := catalog.get_definition(&"base:room/level_1_1_eggery") as RoomDefinition
	var floor_two_h1 := catalog.get_definition(&"base:room/level_1_2_h1") as RoomDefinition
	var floor_two_e := catalog.get_definition(&"base:room/level_1_2_e") as RoomDefinition
	var floor_two_eggery := catalog.get_definition(&"base:room/level_1_2_eggery") as RoomDefinition
	var floor_three_h1 := catalog.get_definition(&"base:room/level_1_3_h1") as RoomDefinition
	var floor_three_a := catalog.get_definition(&"base:room/level_1_3_a") as RoomDefinition
	var floor_three_b := catalog.get_definition(&"base:room/level_1_3_b") as RoomDefinition
	var floor_three_c := catalog.get_definition(&"base:room/level_1_3_c") as RoomDefinition
	var floor_three_d := catalog.get_definition(&"base:room/level_1_3_d") as RoomDefinition
	var floor_three_e := catalog.get_definition(&"base:room/level_1_3_e") as RoomDefinition
	var floor_three_eggery := catalog.get_definition(&"base:room/level_1_3_eggery") as RoomDefinition
	var floor_four_h1 := catalog.get_definition(&"base:room/level_1_4_h1") as RoomDefinition
	var floor_four_a := catalog.get_definition(&"base:room/level_1_4_a") as RoomDefinition
	var floor_four_b := catalog.get_definition(&"base:room/level_1_4_b") as RoomDefinition
	var floor_four_e := catalog.get_definition(&"base:room/level_1_4_e") as RoomDefinition
	var floor_four_c := catalog.get_definition(&"base:room/level_1_4_c") as RoomDefinition
	var floor_four_d := catalog.get_definition(&"base:room/level_1_4_d") as RoomDefinition
	var floor_four_f := catalog.get_definition(&"base:room/level_1_4_f") as RoomDefinition
	var floor_four_eggery := catalog.get_definition(&"base:room/level_1_4_eggery") as RoomDefinition
	var floor_five_gym := catalog.get_definition(&"base:room/level_1_gym") as RoomDefinition
	var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	var encounter_hard := catalog.get_definition(&"base:encounter/grass_floor1_room4_hard") as EncounterDefinition
	var encounter_boss := catalog.get_definition(&"base:encounter/grass_floor1_room6_boss") as EncounterDefinition
	var floor_two_trainer_one := catalog.get_definition(&"base:encounter/grass_floor2_trainer_1") as EncounterDefinition
	var floor_two_boss := catalog.get_definition(&"base:encounter/grass_floor2_trainer_6_boss") as EncounterDefinition
	var floor_three_trainer_one := catalog.get_definition(&"base:encounter/grass_floor3_trainer_1") as EncounterDefinition
	var floor_three_trainer_three := catalog.get_definition(&"base:encounter/grass_floor3_trainer_3") as EncounterDefinition
	var floor_three_hard := catalog.get_definition(&"base:encounter/grass_floor3_trainer_4_hard") as EncounterDefinition
	var floor_three_boss := catalog.get_definition(&"base:encounter/grass_floor3_trainer_6_boss") as EncounterDefinition
	var floor_four_trainer_one := catalog.get_definition(&"base:encounter/grass_floor4_trainer_1") as EncounterDefinition
	var floor_four_trainer_three := catalog.get_definition(&"base:encounter/grass_floor4_trainer_3") as EncounterDefinition
	var floor_four_hard := catalog.get_definition(&"base:encounter/grass_floor4_trainer_4_hard") as EncounterDefinition
	var floor_four_expert := catalog.get_definition(&"base:encounter/grass_floor4_trainer_5_expert") as EncounterDefinition
	var floor_four_boss := catalog.get_definition(&"base:encounter/grass_floor4_trainer_6_boss") as EncounterDefinition
	var grass_sage := catalog.get_definition(&"base:encounter/grass_floor5_sage") as EncounterDefinition
	_expect(catalog_errors.is_empty(), "source-backed campaign resources through the Fire Sage gym must resolve their stable references: %s" % "; ".join(catalog_errors))
	_expect(campaign != null and campaign.floors.size() >= 10, "campaign fixture must include the complete ten-floor runtime slice")
	_expect(campaign != null and campaign.starting_room_id == &"base:room/level_1_1_entryhallway" and campaign.floors.size() >= 5 and campaign.floors[0].get("room_ids", []).size() == 14 and campaign.floors[1].get("room_ids", []).size() == 11 and campaign.floors[2].get("room_ids", []).size() == 10 and campaign.floors[3].get("room_ids", []).size() == 12 and campaign.floors[4].get("room_ids", []).size() == 1 and room_start != null and room_a != null and room_b != null and room_e != null and room_hall != null and room_h2 != null and room_courtyard != null and room_eggery != null and encounter != null and encounter_hard != null and encounter_boss != null and floor_two_h1 != null and floor_two_e != null and floor_two_eggery != null and floor_two_trainer_one != null and floor_two_boss != null and floor_three_h1 != null and floor_three_a != null and floor_three_b != null and floor_three_c != null and floor_three_d != null and floor_three_e != null and floor_three_eggery != null and floor_three_trainer_one != null and floor_three_trainer_three != null and floor_three_hard != null and floor_three_boss != null and floor_four_h1 != null and floor_four_a != null and floor_four_b != null and floor_four_e != null and floor_four_c != null and floor_four_d != null and floor_four_f != null and floor_four_eggery != null and floor_four_trainer_one != null and floor_four_trainer_three != null and floor_four_hard != null and floor_four_expert != null and floor_four_boss != null and floor_five_gym != null and grass_sage != null, "standard tower slice must register the source-backed Floors 1–4 routes including expert rooms and the frontier Grass Sage gym")
	if campaign == null or campaign.floors.size() < 5 or room_start == null or room_a == null or room_b == null or room_e == null or room_hall == null or room_h2 == null or room_courtyard == null or room_eggery == null or encounter == null or encounter_hard == null or encounter_boss == null or floor_two_h1 == null or floor_two_e == null or floor_two_eggery == null or floor_two_trainer_one == null or floor_two_boss == null or floor_three_h1 == null or floor_three_a == null or floor_three_b == null or floor_three_c == null or floor_three_d == null or floor_three_e == null or floor_three_eggery == null or floor_three_trainer_one == null or floor_three_trainer_three == null or floor_three_hard == null or floor_three_boss == null or floor_four_h1 == null or floor_four_a == null or floor_four_b == null or floor_four_e == null or floor_four_c == null or floor_four_d == null or floor_four_f == null or floor_four_eggery == null or floor_four_trainer_one == null or floor_four_trainer_three == null or floor_four_hard == null or floor_four_expert == null or floor_four_boss == null or floor_five_gym == null or grass_sage == null:
		return
	_expect(room_start.spawn_positions.get("start", Vector2.ZERO) == Vector2(397.0, 670.0) and room_start.spawn_positions.get("entry-0", Vector2.ZERO) == Vector2(397.0, 670.0) and room_start.spawn_ids.has(&"start"), "fresh campaigns must resolve their start spawn from source entryObject0_up using the original x−15/y−66 actor offset")
	var spawn_migration_session := CampaignSessionScript.new()
	spawn_migration_session.catalog = catalog
	var legacy_spawn_state = CampaignStateScript.new()
	legacy_spawn_state.campaign_id = campaign.id
	legacy_spawn_state.current_room_id = room_start.id
	legacy_spawn_state.progression["currency"] = 123
	legacy_spawn_state.safe_location = {"room_id": String(room_start.id), "spawn_id": "start", "position": "(412, 736)"}
	var did_repair_legacy_spawn: bool = spawn_migration_session._repair_legacy_start_spawn(legacy_spawn_state, campaign)
	_expect(did_repair_legacy_spawn and legacy_spawn_state.safe_location.position == Vector2(397.0, 670.0) and int(legacy_spawn_state.progression.currency) == 123, "the startup save migration must repair the old blocked entry spawn without changing campaign progression")
	legacy_spawn_state.safe_location["position"] = Vector2.ONE
	_expect(spawn_migration_session._repair_legacy_start_spawn(legacy_spawn_state, campaign) and legacy_spawn_state.safe_location.position == Vector2(397.0, 670.0), "the startup migration must also repair saves previously moved to the invalid top-left fallback")
	_expect(room_a.spawn_positions.get("entry-1", Vector2.ZERO) == Vector2(402.0, 606.0) and room_hall.spawn_positions.get("entry-1", Vector2.ZERO).is_equal_approx(Vector2(315.3, 115.35)), "numbered source entry markers must route to the original Flash actor destination, including its x−15/y−66 offset")
	_expect(room_a.exits.size() == 2 and room_b.exits.size() == 3 and room_b.exits.any(func(route: Dictionary) -> bool: return int(route.get("transition_id", -1)) == 99 and String(route.get("requires_tower_mode", "")) == "hard" and StringName(route.get("target_room_id", "")) == &"base:room/floor_1_expert_room_grass") and room_h2.exits.size() == 3 and StringName(room_h2.exits[2].get("requires_progression_flag", "")) == &"boss_door_unlocked" and StringName(room_e.exits[1].get("requires_progression_flag", "")) == &"eggery_door_unlocked", "room-transition IDs must connect their matching numbered entries and preserve the two key-gated doors")
	_expect(room_h2.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("kind", "")) == &"heal_party" and bool(interaction.get("trigger_on_enter", false))) and room_eggery.interactions.size() == 9 and room_eggery.spawn_positions.has("entry-10"), "Floor 1 passage heal stones and all nine source hatchery egg zones must be authored into the route")
	_expect(floor_two_h1.spawn_ids.has(&"entry-0") and floor_two_h1.external_transitions.any(func(route: Dictionary): return int(route.get("transition_id", -1)) == 101 and String(route.get("target_route", "")) == "lobby") and floor_two_eggery.external_transitions.any(func(route: Dictionary): return int(route.get("transition_id", -1)) == 100 and String(route.get("target_route", "")) == "lobby"), "Floor 2 must start at its numbered entry and return through both recovered Lobby transition markers")
	_expect(floor_two_e.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("kind", "")) == &"map_station" and String(interaction.get("requires_tower_mode", "")) == "standard") and floor_two_e.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("kind", "")) == &"trainer" and String(interaction.get("requires_tower_mode", "")) == "hard"), "Floor 2 E must retain its standard map station and hard-mode trainer as mutually mode-gated interactions")
	_expect(int(floor_two_trainer_one.rewards.get("first_clear", {}).get("floor_keys", 0)) == 1 and int(floor_two_boss.rewards.get("first_clear", {}).get("eggery_keys", 0)) == 1 and not floor_two_boss.rewards.get("first_clear", {}).has("sage_seals"), "Floor 2 normal and boss reward records must distinguish floor keys, Eggery keys, and actual Sage Seals")
	_expect(floor_three_h1.spawn_ids.has(&"entry-0") and floor_three_a.encounter_ids.has(floor_three_trainer_one.id) and floor_three_b.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == &"base:encounter/grass_floor3_trainer_2") and floor_three_e.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_three_trainer_three.id), "Floor 3 must start at its source entry and attach its three standard trainers to A, B, and E")
	_expect(floor_three_c.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_three_hard.id and String(interaction.get("requires_tower_mode", "")) == "hard") and floor_three_d.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_three_boss.id) and floor_three_eggery.interactions.size() == 9 and int(campaign.floors[2].get("eggery_minion_base_level", 0)) == 13, "Floor 3 must retain its hard-only C trainer, standard boss in D, all nine egg slots, and source Eggery minion level")
	_expect(floor_four_h1.spawn_ids.has(&"entry-0") and floor_four_a.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_four_trainer_one.id) and floor_four_b.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == &"base:encounter/grass_floor4_trainer_2") and floor_four_e.encounter_ids.has(floor_four_trainer_three.id) and floor_four_e.interactions.is_empty(), "Floor 4 must start at source entry 0, bind trainers 1–2 to source zones, and retain trainer 3 as an explicitly unresolved source binding in E")
	_expect(floor_four_c.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_four_hard.id and String(interaction.get("requires_tower_mode", "")) == "hard") and floor_four_d.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == floor_four_boss.id) and floor_four_eggery.interactions.size() == 9 and int(campaign.floors[3].get("eggery_minion_base_level", 0)) == 22 and floor_four_expert.team_entries.size() == 5, "Floor 4 must retain the hard trainer in C, boss in D, nine Eggery slots, source level 22, and source expert roster")
	_expect(is_equal_approx(float(floor_four_expert.team_entries[0].get("level", 0)), 22.0) and floor_four_d.interactions[0].get("first_visit_text", "").contains("true strength"), "Floor 4 trainer resources must preserve the expert base level and boss source dialogue")
	_expect(floor_five_gym.spawn_ids.has(&"entry-0") and floor_five_gym.encounter_ids.has(grass_sage.id) and floor_five_gym.interactions.any(func(interaction: Dictionary): return StringName(interaction.get("encounter_id", "")) == grass_sage.id) and int(campaign.floors[4].get("eggery_minion_base_level", 0)) == 15 and grass_sage.source_trainer_type == &"TrainerType.TRAINER_GYM_1" and int(grass_sage.rewards.get("first_clear", {}).get("sage_seals", 0)) == 1, "The source-frontier Floor 5 gym must enter at its numbered door and resolve the Grass Sage battle and seal reward")
	_expect(CampaignProgressionService._trainer_unlocks_floor(grass_sage.source_trainer_type) and not CampaignProgressionService._trainer_unlocks_floor(floor_four_trainer_one.source_trainer_type), "Gym trainers must trigger the source floor-unlock path while ordinary trainers do not")
	var hard_reward_probe := CampaignStateScript.new()
	hard_reward_probe.progression["star_upgrades"] = {"money": 2}
	var hard_rewards := CampaignProgressionService._grant_first_clear_rewards(hard_reward_probe, floor_three_hard)
	var hard_basis := float(floor_three_hard.rewards.get("first_clear", {}).get("floor_money_basis", 0.0))
	_expect(int(hard_rewards.get("money", -1)) == int(hard_basis / 6.0 * 4.0) and int(hard_rewards.get("eggery_keys", 0)) == 1, "Floor 3 hard trainer must get the source integer upgrade-only money formula and Eggery key, without the normal-trainer one-third bonus")
	_expect(encounter_hard.team_entries.size() == 3 and encounter_boss.team_entries.size() == 2 and encounter_boss.team_entries[0].get("move_ids", []).size() == 5 and encounter_boss.team_entries[1].get("move_ids", []).size() == 7, "hard and boss trainer teams must retain their source rosters and explicit move overrides")
	var state = CampaignStateScript.new()
	state.campaign_id = campaign.id
	state.current_room_id = room_a.id
	state.safe_location = {"room_id": String(room_a.id), "spawn_id": "start", "position": room_a.spawn_positions.get("start", Vector2.ZERO)}
	var owned := OwnedMinionState.new()
	owned.instance_id = &"owned-campaign-test"
	owned.definition_id = &"base:minion/raptor_1"
	owned.level = 4
	owned.experience = 4990
	owned.learned_move_ids.assign((catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
	state.party.append(owned)
	var state_roundtrip = CampaignStateScript.new()
	state_roundtrip.load_dictionary(state.to_dictionary(catalog.content_version))
	owned.stat_bonus = &"attack"
	state_roundtrip.load_dictionary(state.to_dictionary(catalog.content_version))
	_expect(state_roundtrip.party.size() == 1 and state_roundtrip.party[0].instance_id == owned.instance_id and state_roundtrip.party[0].persistent_energy == -1 and state_roundtrip.party[0].stat_bonus == &"attack", "campaign serialization must round-trip ordered minions, persistent resources, and the Grand Sage's starting stat gift")
	var prepared := CampaignProgressionService.prepare_battle(state, encounter)
	var setup_result := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
	var setup: Dictionary = setup_result if setup_result.get("ok", false) else {}
	_expect(prepared.ok and prepared.battle_id == "base:campaign/standard_tower/battle/1" and setup_result.get("ok", false), "campaign encounter start must persist a unique sequence ID and build battle setup from its owned party")
	_expect(setup.get("combatants", []).size() == 3 and int(setup.combatants[1].level) == 4 and int(setup.combatants[2].level) == 4, "floor-one source trainer setup must resolve two grass snakes at trainer level 7 minus the source -3 offset")
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"elimination"
	result.participants = [
		{"instance_id": "owned-campaign-test", "team": 0, "persistent_changes": {"health": 7, "energy": 12}},
		{"instance_id": "enemy-0-grasssnake_1", "team": 1, "persistent_changes": {"health": 0, "energy": 0}},
		{"instance_id": "unowned-replacement", "team": 0, "persistent_changes": {"health": 1, "energy": 1}},
	]
	var applied := CampaignProgressionService.apply_battle_result(state, result, encounter, catalog)
	var duplicate := CampaignProgressionService.apply_battle_result(state, result, encounter, catalog)
	_expect(applied.ok and not applied.already_applied and duplicate.ok and duplicate.already_applied, "a campaign battle result must apply once and safely ignore re-delivery")
	var level_award: Dictionary = applied.get("experience_awards", {}).get(String(owned.instance_id), {})
	_expect(int(level_award.get("new_level", 0)) > int(level_award.get("old_level", 0)) and owned.persistent_health == 7 + int(level_award.get("health_increase", 0)) and owned.persistent_energy == 12 and applied.updated_party_members == 1, "battle XP must level the owned minion and raise current health by the earned health-stat delta")
	_expect(state.progression.currency is int and state.progression.currency == 2 and state.progression.floor_keys == 1 and state.progression.completed_encounters.has(String(encounter.id)), "the source normal trainer's first clear must grant one floor key and floor-zero money once")
	_expect(state.pending_battle.is_empty() and state.applied_battle_ids.size() == 1, "committing a result must clear pending context and store an applied-battle id")
	_test_campaign_talent_progression(catalog)
	var defeat_state = CampaignStateScript.new()
	defeat_state.load_dictionary(state_roundtrip.to_dictionary(catalog.content_version))
	defeat_state.campaign_id = campaign.id
	defeat_state.current_room_id = room_hall.id
	defeat_state.safe_location = {"room_id": String(room_a.id), "spawn_id": "start"}
	var defeat_prepare := CampaignProgressionService.prepare_battle(defeat_state, encounter)
	var defeat_result := BattleResult.new()
	defeat_result.battle_id = StringName(defeat_prepare.battle_id)
	defeat_result.winning_team = 1
	defeat_result.reason = &"elimination"
	defeat_result.participants = [{"instance_id": "owned-campaign-test", "team": 0, "persistent_changes": {"health": 0, "energy": 0}}]
	var defeat_settlement := CampaignProgressionService.apply_battle_result(defeat_state, defeat_result, encounter, catalog)
	var owned_definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	var restored_stats := LegacyMinionStats.current_stats(owned_definition, owned.level)
	_expect(bool(defeat_settlement.get("show_first_defeat_tutorial", false)) and bool(defeat_state.progression.get("death_exp_tutorial_seen", false)), "the first campaign loss must persist and request the source experience tutorial")
	var tutorial_round_trip := CampaignStateScript.new()
	tutorial_round_trip.load_dictionary(defeat_state.to_dictionary(catalog.content_version))
	_expect(bool(tutorial_round_trip.progression.get("death_exp_tutorial_seen", false)), "the one-time defeat tutorial flag must survive campaign save serialization")
	_expect(defeat_state.current_room_id == room_hall.id and not defeat_state.pending_defeat_return.is_empty(), "loss settlement must preserve battle resources and room until the finish sequence returns")
	_expect(int(defeat_settlement.get("experience_awards", {}).get(String(owned.instance_id), {}).get("experience", 0)) > 0, "an elimination defeat must award the source-reduced 75% battle experience")
	var defeat_return := CampaignProgressionService.complete_defeat_return(defeat_state, catalog)
	_expect(defeat_return.ok and defeat_state.pending_defeat_return.is_empty() and defeat_state.current_room_id == room_a.id and defeat_state.party[0].persistent_health == int(restored_stats.health) and defeat_state.party[0].persistent_energy == int(restored_stats.energy), "post-finish defeat recovery must restore the safe room and heal party health and energy")
	var forfeit_prepare := CampaignProgressionService.prepare_battle(defeat_state, encounter)
	var forfeit_result := BattleResult.new()
	forfeit_result.battle_id = StringName(forfeit_prepare.battle_id)
	forfeit_result.winning_team = 1
	forfeit_result.reason = &"forfeit"
	forfeit_result.participants = [{"instance_id": "owned-campaign-test", "team": 0, "persistent_changes": {"health": 4, "energy": 5}}]
	var experience_before_forfeit: int = defeat_state.party[0].experience
	var forfeit_settlement := CampaignProgressionService.apply_battle_result(defeat_state, forfeit_result, encounter, catalog)
	_expect(forfeit_settlement.get("experience_awards", {}).is_empty() and not bool(forfeit_settlement.get("show_first_defeat_tutorial", false)) and defeat_state.party[0].experience == experience_before_forfeit, "forfeiting must restore the party without tutorial or battle experience")

func _test_campaign_talent_progression(catalog: ContentCatalog) -> void:
	var definition := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var owned := OwnedMinionState.new()
	owned.instance_id = &"talent-progression-test"
	owned.definition_id = definition.id
	owned.level = 6
	owned.experience = 6000
	owned.learned_move_ids.assign(definition.initial_move_ids)
	_expect(CampaignProgressionService.maximum_talent_points(6) == 1 and CampaignProgressionService.maximum_talent_points(60) == 17, "talent point totals must follow the original three-level, then four-level cadence through level sixty")
	var choices := CampaignProgressionService.talent_choices(owned, definition, catalog)
	_expect(choices.size() == 3 and choices.all(func(choice: Dictionary): return StringName(choice.get("kind", "")) == &"specialization"), "the first earned point must offer all three source specialization moves")
	if choices.is_empty():
		return
	var specialization_id := StringName(choices[0].move_id)
	var specialization_purchase := CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, specialization_id)
	_expect(specialization_purchase.ok and specialization_id in owned.learned_move_ids and CampaignProgressionService.available_talent_points(owned, definition) == 0, "buying specialization must persist the selected move and spend the point")
	owned.level = 9
	owned.experience = 9000
	choices = CampaignProgressionService.talent_choices(owned, definition, catalog)
	_expect(choices.size() == 3, "after specialization all three parallel starting branches must be purchasable with the next point")
	for branch in choices:
		var branch_owned := owned.duplicate_state()
		var branch_purchase := CampaignProgressionService.purchase_talent_choice(branch_owned, definition, catalog, StringName(branch.move_id))
		_expect(branch_purchase.ok and CampaignProgressionService.available_talent_points(branch_owned, definition) == 0, "each starting branch must accept the point independently, rather than being gated by its column")
	_expect(not choices.is_empty() and choices.all(func(choice: Dictionary): return StringName(choice.get("kind", "")) == &"talent" and int(choice.get("tree_index", -1)) == int(choices[0].get("tree_index", -2))), "after specialization, source tree gating must offer legal moves only from the chosen specialization")
	if not choices.is_empty():
		var talent_id := StringName(choices[0].move_id)
		var talent_purchase := CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, talent_id)
		_expect(talent_purchase.ok and CampaignProgressionService.available_talent_points(owned, definition) == 0, "buying an available tree move must consume exactly one earned point")
		var restored_owned := OwnedMinionState.from_dictionary(owned.to_dictionary())
		_expect(restored_owned.learned_move_ids == owned.learned_move_ids and restored_owned.talent_node_ids == owned.talent_node_ids, "specialization and talent purchases must survive owned-minion serialization")
	var move_ranks := CampaignProgressionService.highest_tier_move_ids([&"base:move/claw/tier1", &"base:move/claw/tier2", &"base:move/burn/tier1"], catalog)
	var reset_owned := owned.duplicate_state()
	var reset_result := CampaignProgressionService.reset_talents(reset_owned, definition)
	_expect(reset_result.ok and reset_owned.learned_move_ids == definition.initial_move_ids and reset_owned.talent_node_ids.is_empty() and CampaignProgressionService.available_talent_points(reset_owned, definition) == 2 and CampaignProgressionService.talent_choices(reset_owned, definition, catalog).size() == 3, "reset must restore default moves, refund both points, and allow choosing another specialization")
	_expect(move_ranks == [&"base:move/claw/tier2", &"base:move/burn/tier1"], "battle setup must expose only the highest owned rank from each move family")
	owned.level = 9
	owned.definition_id = definition.id
	owned.persistent_health = 17
	owned.persistent_energy = 12
	var early_evolution := CampaignProgressionService.evolve_owned_minion(owned, catalog)
	_expect(not early_evolution.ok and StringName(early_evolution.get("code", "")) == &"evolution_locked", "a campaign minion must not evolve before its authored level threshold")
	owned.level = 10
	var evolution := CampaignProgressionService.evolve_owned_minion(owned, catalog)
	_expect(evolution.ok and owned.definition_id == &"base:minion/fire_pig_2" and owned.persistent_health == 17 and owned.persistent_energy == 12, "reaching the authored level must evolve the owned minion and preserve valid absolute health and energy")
