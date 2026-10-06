extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var base := LegacyMinionStats.constructor_stats(species, 30, 40, "health", {})
	var upgraded := LegacyMinionStats.constructor_stats(species, 30, 40, "health", {"health": 3, "energy": 2, "attack": 4, "healing": 5, "speed": 2})
	assert(upgraded.health == int((species.base_health * 30.0 / 16.0 + 5.0) * 1.05 * 1.06))
	assert(upgraded.energy == int((species.base_energy * 30.0 / 20.0 + 5.0) * 1.5 * 1.04))
	assert(upgraded.max_attack_stat == int((species.base_attack * 3.0 + 5.0) * 1.08))
	assert(upgraded.max_healing_stat == int((species.base_healing * 3.0 + 5.0) * 1.2))
	assert(upgraded.health > base.health)
	var state := CampaignState.new()
	var owned := OwnedMinionState.new()
	owned.instance_id = &"replacement-stats-original"
	owned.definition_id = species.id
	owned.level = 30
	owned.experience = 30000
	state.party.append(owned)
	state.progression["star_upgrades"] = {"health": 3, "energy": 2, "attack": 4, "healing": 5, "speed": 2}
	var encounter := EncounterDefinition.new()
	encounter.id = &"fixture:source/replacement-stats"
	encounter.source_trainer_id = &"base:trainer/standard/4/1"
	encounter.source_floor_index = 40
	encounter.team_entries = [{"definition_id": species.id, "level": 30, "slot_index": 0}]
	state.pending_battle = {"battle_id": "replacement-stats", "encounter_id": String(encounter.id)}
	var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
	assert(setup.ok)
	var template := {"definition_id": species.id, "level": 30, "source_derive_stats": true, "move_ids": []}
	var rules := RuleSetDefinition.new()
	rules.configuration = {"ai_teams": [], "battle_modifiers": {"extra_minions": {"player": {"count": 1, "templates": [template]}, "enemy": {"count": 1, "templates": [template]}}}}
	var engine := BattleEngine.new()
	assert(engine.start(setup, catalog, rules, BattleRng.new(71)).accepted)
	var saved := engine.snapshot()
	engine._source_stat_context.clear()
	engine.restore(saved)
	assert(engine._source_stat_context.player_stars.health == 3, "Snapshot lost source scaling context")
	for team in [0, 1]:
		var original := engine._state.living_team_members(team)[0] as CombatantState
		original.health = 0
		original.defeated = true
		engine._rng = BattleRng.new(71, [0]) # constructor selects health bonus
		engine._inject_extra_minions()
		var replacement := engine._living_at_slot(team, original.slot_index)
		assert(replacement != null and replacement.instance_id != original.instance_id)
		var expected := LegacyMinionStats.constructor_stats(species, 30, 40, "health", state.progression.star_upgrades if team == 0 else null)
		assert(replacement.base_max_health == expected.health and replacement.base_max_energy == expected.energy)
		assert(replacement.max_attack_stat == expected.max_attack_stat and replacement.max_healing_stat == expected.max_healing_stat)
		assert(replacement.health == LegacyCombatModifiers.effective_max_health(replacement, catalog, engine._state.combatants))
		assert(replacement.energy == LegacyCombatModifiers.effective_max_energy(replacement, catalog, engine._state.combatants))
	var checked := 0
	var rolls_seen: Dictionary = {}
	for floor_id in [0, 1, 31]:
		for battle_index in 12:
			for won in [true, false]:
				var xp_state := CampaignState.new()
				xp_state.pending_battle = {"battle_id": "xp/%d" % battle_index}
				xp_state.progression["star_upgrades"] = {"experience": 2}
				var xp_encounter := EncounterDefinition.new()
				xp_encounter.source_trainer_id = &"base:trainer/hard/1/room/1" if floor_id == 31 else &"base:trainer/standard/1/1"
				xp_encounter.source_floor_index = floor_id
				xp_encounter.source_level_offset = 3 if floor_id == 31 else 0
				xp_encounter.team_entries = [{"definition_id": species.id, "level": 10}]
				var rng := BattleRng.new(hash("experience/%s" % xp_state.pending_battle.battle_id))
				var expected_awards: Dictionary = {}
				for slot in 5:
					var recipient := OwnedMinionState.new()
					recipient.instance_id = StringName("xp-slot-%d" % slot)
					recipient.definition_id = species.id
					recipient.level = 8 + slot
					recipient.experience = recipient.level * 1000
					xp_state.party.append(recipient)
					var jitter := int(rng.next_unit() * 3.0) - 1 if floor_id > 0 else 0
					if floor_id > 0: rolls_seen[jitter] = true
					var difference := recipient.level - 10 + jitter
					var gained: int = 850 + [-70, -35, 0, 35, 70][species.experience_gain_rate]
					var basis: int = gained
					if difference > 0:
						for iteration in difference: gained = int(gained / 2.0)
						gained = maxi(50, gained)
					elif difference < 0:
						gained += int(-difference * basis / 3.0)
					gained = int(gained * [1.2, 1.1, 1.0, 0.9, 0.8][species.experience_gain_rate])
					gained = int(gained * 1.1)
					if not won: gained = int(gained * 0.75)
					expected_awards[String(recipient.instance_id)] = gained
				var retry := CampaignState.new()
				retry.load_dictionary(xp_state.to_dictionary())
				var awarded := CampaignProgressionService._award_experience(xp_state, xp_encounter, catalog, won)
				assert(awarded == CampaignProgressionService._award_experience(retry, xp_encounter, catalog, won), "XP retry rerolled awards")
				for id in expected_awards:
					assert(awarded[id].experience == expected_awards[id], "Source XP formula mismatch")
				checked += 5
	assert(rolls_seen.size() == 3, "Fixture did not exercise all XP jitter values")
	print("PASS: native player/enemy replacement constructor bonuses, star/floor scaling, power stats, passive refill and snapshot context; %d source XP awards across first/later/hard floors, win/loss, every jitter and deterministic retries" % checked)
	quit()
