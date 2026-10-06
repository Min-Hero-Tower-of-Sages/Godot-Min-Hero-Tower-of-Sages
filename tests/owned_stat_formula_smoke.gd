extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var ids := ["health", "energy", "attack", "healing", "speed"]
	var bases := [species.base_health, species.base_energy, species.base_attack, species.base_healing, species.base_speed]
	var ranks := {"health": 3, "energy": 2, "attack": 4, "healing": 5, "speed": 1}
	var gems: Array[Dictionary] = []
	var owned := OwnedMinionState.new()
	owned.instance_id = &"owned-formula-fixture"
	owned.definition_id = species.id
	for index in 5:
		owned.ivs[ids[index]] = index + 1
		var gem_id := StringName("fixture-gem-%d" % index)
		owned.equipment_ids.append(gem_id)
		gems.append({"instance_id": String(gem_id), "stat_id": ids[index], "stat_value": index + 3})
	var checked := 0
	for level in range(1, 61):
		owned.level = level
		owned.experience = level * 1000
		for bonus in ids:
			owned.stat_bonus = StringName(bonus)
			var calculated := CampaignProgressionService.owned_stats(owned, species, -1, gems, ranks)
			for index in 5:
				var divisor := maxf(10.0, 20.0 - (level - 15) / 45.0 * 12.0) if level > 14 and index == 0 else 20.0
				var value: float = (bases[index] + index + 1) * level / divisor + 5.0 + index + 3
				if bonus == ids[index]: value *= 1.05
				value *= 1.0 + ranks[ids[index]] * (0.04 if index == 3 else 0.02)
				if index == 1: value *= 1.5
				assert(calculated[ids[index]] == int(value), "Owned stat diverges from Calculate* at level %d (%s)" % [level, ids[index]])
				checked += 1
	# Production setup must consume the corrected values, not just the menu.
	var campaign := CampaignState.new()
	campaign.party.append(owned)
	campaign.owned_gems.assign(gems)
	campaign.progression["star_upgrades"] = ranks
	var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	campaign.pending_battle = {"battle_id": "owned-stat-setup", "encounter_id": String(encounter.id)}
	var setup := CampaignProgressionService.build_battle_setup(campaign, catalog, encounter)
	assert(setup.ok)
	var stats := CampaignProgressionService.owned_stats(owned, species, -1, gems, ranks)
	assert(setup.combatants[0].max_health == stats.health and setup.combatants[0].max_energy == stats.energy)
	for stat in ["attack", "healing", "speed"]: assert(setup.combatants[0][stat] == stats[stat])
	print("PASS: %d owned stat formulas across levels 1–60, all constructor bonuses, saved IVs, gem/star ordering and production battle setup" % checked)
	quit()
