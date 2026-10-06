extends SceneTree

# The runtime already validated this immutable snapshot. Avoid re-reading
# hundreds of room payloads for every encounter in this content sweep.
class ImmutableCatalog extends ContentCatalog:
	func rebuild_index() -> PackedStringArray:
		return PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var validated: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var catalog := ImmutableCatalog.new()
	catalog.packs.assign(validated.packs)
	catalog._by_id = validated._by_id.duplicate()
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var encounters := 0
	var modifiers := 0
	for floor_data in campaign.floors:
		if int(floor_data.floor_index) < 10: continue
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
				var state := CampaignState.new()
				state.campaign_id = campaign.id
				state.current_room_id = room.id
				state.progression["floor_index"] = int(floor_data.floor_index)
				var owned := OwnedMinionState.new()
				owned.instance_id = &"extended-setup-starter"
				owned.definition_id = &"base:minion/fire_pig_1"
				owned.level = 40
				owned.experience = 40000
				owned.learned_move_ids.assign((catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
				state.party.append(owned)
				var prepared := CampaignProgressionService.prepare_battle(state, encounter)
				assert(prepared.ok, str(prepared))
				var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
				assert(setup.ok, str(setup))
				var rules := RuleSetDefinition.new()
				rules.configuration = {"ai_teams": [], "refill_on_activation": true, "battle_modifiers": encounter.battle_modifier_configuration.duplicate(true)}
				var engine := BattleEngine.new()
				var response := engine.start(setup, catalog, rules, BattleRng.new(123))
				assert(response.accepted, "%s: %s" % [encounter.id, response.message])
				if not encounter.battle_modifier_configuration.is_empty(): modifiers += 1
				var extra: Dictionary = encounter.battle_modifier_configuration.get("extra_minions", {})
				for side in ["player", "enemy"]:
					if not extra.has(side): continue
					var team := 0 if side == "player" else 1
					var dead := engine._state.living_team_members(team)[0] as CombatantState
					dead.health = 0
					dead.defeated = true
					engine._inject_extra_minions()
					var replacement := engine._living_at_slot(team, dead.slot_index)
					assert(replacement != null and replacement.instance_id != dead.instance_id, "Replacement did not spawn")
					assert(replacement.max_health > 1 and replacement.max_energy > 0 and replacement.health == replacement.max_health and replacement.energy == replacement.max_energy, "Replacement stats/refill missing")
				encounters += 1
	print("PASS: %d extended-floor battle setups, %d modifier encounters; source replacement stats and full refill" % [encounters, modifiers])
	quit()
