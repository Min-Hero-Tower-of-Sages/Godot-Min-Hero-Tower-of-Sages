class_name CampaignProgressionService
extends RefCounted

const CampaignStateScript = preload("res://src/domain/campaign_state.gd")
const GemEquipmentService = preload("res://src/application/campaign_gem_equipment_service.gd")
const TITAN_1_ID: StringName = &"base:minion/titan_1"
const TITAN_2_ID: StringName = &"base:minion/titan_2"

static func lobby_titan_status(state) -> Dictionary:
	if state == null:
		return {"ok": false, "code": "no_campaign", "message": "there is no active campaign"}
	var owned_titan_1 := false
	var owned_titan_2 := false
	for owned in state.party + state.storage:
		owned_titan_1 = owned_titan_1 or owned.definition_id == TITAN_1_ID
		owned_titan_2 = owned_titan_2 or owned.definition_id == TITAN_2_ID
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0])
	var highest_floor := int(state.progression.get("highest_beaten_floor", -1))
	if highest_floor < 0:
		# Older converted saves have no explicit beaten-floor marker. Treat their
		# unlocked frontier conservatively as the highest completed floor; adding
		# one here would make Titan 1 available as soon as Floor 31 was unlocked.
		highest_floor = 0
		for floor_index in unlocked:
			highest_floor = maxi(highest_floor, int(floor_index))
	# highest_beaten_floor is a one-based completed floor, whereas source
	# GetHighestFloor() is the one-based unlocked frontier (32 after Grand Sage).
	# Completing Floor 31 therefore qualifies immediately, not after Hard Floor 1.
	var eligible := highest_floor >= 31
	var all_titans_owned := owned_titan_1 and owned_titan_2
	var can_claim_titans := eligible and not all_titans_owned
	var message := "I need the six sage seals and to defeat the Grand Sage."
	var guard_message := "Titan minions are very powerful, you'll need all six sage seals and you'll need to defeat the Grand Sage before you're ready to have these minions."
	if all_titans_owned:
		message = "I already have the titans."
		guard_message = "You're amazing and you did it!"
	elif can_claim_titans:
		message = "You've received the Titans."
		guard_message = "These titans belong to you now, go get them!"
	return {
		"ok": true,
		"highest_floor": highest_floor,
		"eligible": eligible,
		"has_titan_1": owned_titan_1,
		"has_titan_2": owned_titan_2,
		"all_titans_owned": all_titans_owned,
		"can_claim_titans": can_claim_titans,
		"message": message,
		"guard_message": guard_message,
	}

static func create_lobby_titan(state, catalog: ContentCatalog, definition_id: StringName, instance_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("invalid_context", "campaign state and catalog are required")
	var definition := catalog.get_definition(definition_id) as MinionDefinition
	if definition == null or not definition.type_ids.has(&"base:type/titan"):
		return _error("missing_titan", "lobby reward references missing Titan %s" % definition_id)
	var owned := OwnedMinionState.new()
	owned.instance_id = instance_id
	owned.definition_id = definition.id
	owned.level = 60
	owned.experience = 60000
	owned.learned_move_ids.assign(definition.initial_move_ids)
	var stats := owned_display_stats(owned, definition, catalog, state)
	owned.persistent_health = int(stats.get("health", definition.base_health))
	owned.persistent_energy = int(stats.get("energy", definition.base_energy))
	return {"ok": true, "minion": owned, "definition": definition, "level": owned.level}

static func prepare_battle(state, encounter: EncounterDefinition) -> Dictionary:
	if state == null or encounter == null:
		return _error("invalid_context", "campaign state and encounter are required")
	if not state.pending_battle.is_empty():
		return _error("battle_pending", "a campaign battle is already pending")
	if not state.pending_defeat_return.is_empty():
		return _error("defeat_return_pending", "finish the checkpoint return before starting another battle")
	state.battle_sequence += 1
	state.runtime_trainer_bonus_move_ids.clear()
	var timer: Dictionary = encounter.battle_modifier_configuration.get("move_timer", {})
	var timer_bonus := StringName(timer.get("buff_move_id", timer.get("passive_move_id", "")))
	if not timer_bonus.is_empty(): state.runtime_trainer_bonus_move_ids.append(timer_bonus)
	var battle_id := "%s/battle/%d" % [String(state.campaign_id), state.battle_sequence]
	state.pending_battle = {
		"battle_id": battle_id,
		"encounter_id": String(encounter.id),
		"room_id": String(state.current_room_id),
		"sequence": state.battle_sequence,
	}
	return {"ok": true, "battle_id": battle_id, "context": state.pending_battle.duplicate(true)}

const STARTERS := [
	{"id": &"base:minion/fire_pig_1", "instance": "starter-zapig", "level": 4, "experience": 4350},
	{"id": &"base:minion/tiger_1", "instance": "starter-ticub", "level": 5, "experience": 5300},
]

## The new-campaign party; instance IDs are `id_prefix` + the starter name.
## Definitions missing from the catalog are skipped (callers check the size).
static func starter_party(catalog: ContentCatalog, id_prefix: String) -> Array[OwnedMinionState]:
	var party: Array[OwnedMinionState] = []
	for starter in STARTERS:
		var definition := catalog.get_definition(starter.id) as MinionDefinition
		if definition == null:
			continue
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName(id_prefix + String(starter.instance))
		owned.definition_id = definition.id
		owned.level = int(starter.level)
		owned.experience = int(starter.experience)
		owned.learned_move_ids.assign(definition.initial_move_ids)
		party.append(owned)
	return party

## Battle combatant entries for the owned party (team 0), with the same gem,
## star-upgrade and IV stat math as a campaign trainer battle.
static func party_setup_combatants(state, catalog: ContentCatalog) -> Dictionary:
	var setup_combatants: Array[Dictionary] = []
	for index in state.party.size():
		var owned: OwnedMinionState = state.party[index]
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		if definition == null:
			return _error("missing_minion", "party references missing minion %s" % owned.definition_id)
		var stats := owned_stats(owned, definition, -1, state.owned_gems, state.progression.get("star_upgrades", {}))
		var raw_stats := owned_stats(owned, definition, -1, state.owned_gems, state.progression.get("star_upgrades", {}), false)
		var persistent_maxima := owned_display_stats(owned, definition, catalog, state)
		var move_ids := owned.learned_move_ids.duplicate()
		if move_ids.is_empty():
			move_ids = definition.initial_move_ids.duplicate()
		move_ids = highest_tier_move_ids(move_ids, catalog)
		var attack_bonus_multiplier := 1.05 if owned.stat_bonus == &"attack" else 1.0
		var healing_bonus_multiplier := 1.05 if owned.stat_bonus == &"healing" else 1.0
		var attack_iv := float(owned.ivs.get("attack", owned.ivs.get(&"attack", 0.0)))
		var healing_iv := float(owned.ivs.get("healing", owned.ivs.get(&"healing", 0.0)))
		setup_combatants.append({
			"instance_id": String(owned.instance_id),
			"definition_id": String(owned.definition_id),
			"team": 0,
			"slot_index": index,
			"level": owned.level,
			"type_ids": definition.type_ids.duplicate(),
			"move_ids": move_ids,
			"source_raw_stats": raw_stats.merged({"max_attack_stat": (LegacyMinionStats.max_attack_stat(definition, attack_iv, attack_bonus_multiplier) + float(GemEquipmentService.gem_stat_bonus(owned, &"attack", state.owned_gems)) * attack_bonus_multiplier) * _star_stat_multiplier(state, &"attack"), "max_healing_stat": (LegacyMinionStats.max_healing_stat(definition, healing_iv, healing_bonus_multiplier) + float(GemEquipmentService.gem_stat_bonus(owned, &"healing", state.owned_gems)) * healing_bonus_multiplier) * _star_stat_multiplier(state, &"healing")}),
			"base_max_health": int(stats.health),
			"max_health": int(stats.health),
			"health": int(persistent_maxima.health) if owned.persistent_health < 0 else maxi(0, owned.persistent_health),
			"base_max_energy": int(stats.energy),
			"max_energy": int(stats.energy),
			"energy": int(persistent_maxima.energy) if owned.persistent_energy < 0 else clampi(owned.persistent_energy, 0, int(persistent_maxima.energy)),
			"attack": int(stats.attack),
			"healing": int(stats.healing),
			"speed": int(stats.speed),
			"max_attack_stat": (LegacyMinionStats.max_attack_stat(definition, attack_iv, attack_bonus_multiplier) + float(GemEquipmentService.gem_stat_bonus(owned, &"attack", state.owned_gems)) * attack_bonus_multiplier) * _star_stat_multiplier(state, &"attack"),
			"max_healing_stat": (LegacyMinionStats.max_healing_stat(definition, healing_iv, healing_bonus_multiplier) + float(GemEquipmentService.gem_stat_bonus(owned, &"healing", state.owned_gems)) * healing_bonus_multiplier) * _star_stat_multiplier(state, &"healing"),
		})
	return {"ok": true, "combatants": setup_combatants}

static func build_battle_setup(state, catalog: ContentCatalog, encounter: EncounterDefinition) -> Dictionary:
	if state == null or catalog == null or encounter == null:
		return _error("invalid_context", "campaign state, catalog, and encounter are required")
	if state.pending_battle.is_empty() or String(state.pending_battle.get("encounter_id", "")) != String(encounter.id):
		return _error("battle_not_prepared", "prepare this encounter before building its battle setup")
	refresh_minion_pedia(state)
	var seen_minions: Array = state.progression.get("seen_minion_ids", []).duplicate()
	# Species met for the first time in this fight: the battle keeps their
	# name and types hidden until the next time they are faced.
	var first_seen: Array = []
	for enemy_entry in encounter.team_entries:
		var enemy_id := StringName(enemy_entry.get("definition_id", ""))
		if not seen_minions.has(enemy_id) and not seen_minions.has(String(enemy_id)) and not first_seen.has(String(enemy_id)):
			first_seen.append(String(enemy_id))
		_append_unique_id(seen_minions, enemy_id)
	state.pending_battle["first_seen_minion_ids"] = first_seen
	state.progression["seen_minion_ids"] = seen_minions
	var party_setup := party_setup_combatants(state, catalog)
	if not party_setup.ok:
		return party_setup
	var setup_combatants: Array[Dictionary] = []
	setup_combatants.assign(party_setup.combatants)
	var source_trainer := String(encounter.source_trainer_id).begins_with("base:trainer/standard/") or String(encounter.source_trainer_id).begins_with("base:trainer/hard/")
	# Rebuilding the same pending encounter (including a rejected save retry)
	# must not reroll its enemy talents or constructor stat bonus.
	var trainer_rng := BattleRng.new(hash("trainer/%s/%s" % [state.pending_battle.battle_id, encounter.id]))
	var stat_ids := ["health", "energy", "attack", "healing", "speed"]
	for entry in encounter.team_entries:
		var definition_id := StringName(entry.get("definition_id", ""))
		var definition := catalog.get_definition(definition_id) as MinionDefinition
		if definition == null:
			return _error("missing_encounter_minion", "encounter references missing minion %s" % definition_id)
		var offset := int(entry.get("source_level_offset", encounter.source_level_offset))
		if source_trainer and encounter.source_floor_index >= 31:
			offset = 0 # TrainerSystem.LoadTrianer ignores extraMinionLevels in hard mode.
		var level := maxi(1, int(entry.get("level", 1)) + offset)
		var stats := LegacyMinionStats.current_stats(definition, level)
		var raw_stats: Dictionary = {}
		if source_trainer:
			var bonus: String = stat_ids[int(trainer_rng.next_unit() * 5.0)]
			stats = LegacyMinionStats.enemy_stats(definition, level, encounter.source_floor_index, bonus)
			raw_stats = LegacyMinionStats.constructor_stats(definition, level, encounter.source_floor_index, bonus, null, false)
		var enemy_slot := int(entry.get("slot_index", setup_combatants.size()))
		var enemy_move_ids: Array[StringName] = []
		enemy_move_ids.assign(entry.get("move_ids", [] if source_trainer else definition.initial_move_ids))
		if enemy_move_ids.is_empty() and not source_trainer:
			enemy_move_ids = definition.initial_move_ids.duplicate()
		if source_trainer:
			enemy_move_ids = preload("res://src/domain/battle/legacy_minion_autobuilder.gd").new().build(definition, level, enemy_move_ids, catalog, trainer_rng)
		else:
			enemy_move_ids = highest_tier_move_ids(enemy_move_ids, catalog)
		setup_combatants.append({
			"instance_id": "enemy-%d-%s" % [enemy_slot, String(definition_id).get_file()],
			"definition_id": definition_id,
			"team": 1,
			"slot_index": enemy_slot,
			"level": level,
			"type_ids": definition.type_ids.duplicate(),
			"move_ids": enemy_move_ids,
			"source_raw_stats": raw_stats,
			"base_max_health": int(stats.health),
			"max_health": int(stats.health),
			"health": int(stats.health),
			"base_max_energy": int(stats.energy),
			"max_energy": int(stats.energy),
			"energy": int(stats.energy),
			"attack": int(stats.attack),
			"healing": int(stats.healing),
			"speed": int(stats.speed),
			"max_attack_stat": stats.get("max_attack_stat", LegacyMinionStats.max_attack_stat(definition)),
			"max_healing_stat": stats.get("max_healing_stat", LegacyMinionStats.max_healing_stat(definition)),
		})
	return {
		"ok": true,
		"battle_id": String(state.pending_battle.battle_id),
		"tie_first_team": 0,
		"combatants": setup_combatants,
		"campaign_encounter_id": String(encounter.id),
		"source_stat_context": {"floor_index": encounter.source_floor_index, "player_stars": state.progression.get("star_upgrades", {}).duplicate(true)} if source_trainer else {},
	}

static func apply_battle_result(state, result: BattleResult, encounter: EncounterDefinition, catalog: ContentCatalog = null) -> Dictionary:
	if state == null or result == null or encounter == null or result.is_empty():
		return _error("invalid_result", "completed battle result and encounter context are required")
	var battle_id := String(result.battle_id)
	if battle_id in state.applied_battle_ids:
		return {"ok": true, "already_applied": true, "battle_id": battle_id}
	if state.pending_battle.is_empty() or battle_id != String(state.pending_battle.get("battle_id", "")):
		return _error("unexpected_result", "battle result does not match the pending campaign battle")
	if String(state.pending_battle.get("encounter_id", "")) != String(encounter.id):
		return _error("encounter_mismatch", "battle result encounter differs from its prepared context")
	var owned_by_id: Dictionary = {}
	for owned in state.party:
		owned_by_id[String(owned.instance_id)] = owned
	var updated_participants := 0
	# Copy final health for every owned participant first. Global providers must
	# reflect the final roster before any synthetic/legacy energy cap is derived.
	# Reading source m_currHealth does not clamp after a maximum recalculation.
	for participant in result.participants:
		if int(participant.get("team", -1)) != 0: continue
		var owned := owned_by_id.get(String(participant.get("instance_id", ""))) as OwnedMinionState
		var changes: Dictionary = participant.get("persistent_changes", {})
		if owned != null and changes.has("health"):
			owned.persistent_health = maxi(0, int(changes.health))
	for participant in result.participants:
		if int(participant.get("team", -1)) != 0:
			continue
		var owned := owned_by_id.get(String(participant.get("instance_id", ""))) as OwnedMinionState
		if owned == null:
			continue
		var persistent_changes := participant.get("persistent_changes", {}) as Dictionary
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition if catalog != null else null
		var maximums := owned_display_stats(owned, definition, catalog, state) if definition != null else {}
		if persistent_changes.has("energy"):
			var energy_limit := int(participant.get("max_energy", maximums.get("energy", maxi(0, int(persistent_changes.energy)))))
			owned.persistent_energy = clampi(int(persistent_changes.energy), 0, maxi(0, energy_limit))
		updated_participants += 1
	var forfeited := result.reason == &"forfeit"
	var finish_stat_context := battle_finish_stat_context(state, result) if not forfeited else {}
	var stars_earned := _battle_star_rating(state, result) if result.winning_team == 0 and not forfeited else 0
	var stars_added := _record_encounter_stars(state, encounter, stars_earned) if result.winning_team == 0 and not forfeited else 0
	var experience_awards := _award_experience(state, encounter, catalog, result.winning_team == 0, result, finish_stat_context) if catalog != null and not forfeited else {}
	var completed_before_battle: Dictionary = state.progression.get("completed_encounters", {})
	var is_first_clear := not bool(completed_before_battle.get(String(encounter.id), false))
	var completion_awards := _grant_first_clear_rewards(state, encounter) if result.winning_team == 0 else {}
	var show_first_defeat_tutorial := false
	if result.winning_team == 0:
		state.progression["deaths_since_victory"] = 0
		if is_first_clear and _trainer_unlocks_floor(encounter.source_trainer_type) and catalog != null:
			state.progression["highest_beaten_floor"] = maxi(int(state.progression.get("highest_beaten_floor", 0)), int(state.progression.get("floor_index", 0)) + 1)
			_unlock_next_tower_floor(state, catalog)
		var completed: Dictionary = state.progression.get("completed_encounters", {}).duplicate(true)
		completed[String(encounter.id)] = true
		state.progression["completed_encounters"] = completed
	elif catalog != null:
		if not forfeited:
			state.progression["deaths_since_victory"] = int(state.progression.get("deaths_since_victory", 0)) + 1
		# The source shows its experience tip on the first loss screen, before
		# returning to exploration. Forfeits bypass that screen in this port.
		if not forfeited and not bool(state.progression.get("death_exp_tutorial_seen", false)):
			state.progression["death_exp_tutorial_seen"] = true
			show_first_defeat_tutorial = true
		# LoseScreen heals only after XP/level-up UI and its 3s blackout.
		# ForfeitYesButtonPressed instead performs this return immediately.
		state.pending_defeat_return = {"battle_id": battle_id, "checkpoint": state.safe_location.duplicate(true)}
		if forfeited:
			var recovered := complete_defeat_return(state, catalog)
			if not recovered.ok: return recovered
	state.applied_battle_ids.append(battle_id)
	state.last_battle_result = result.to_dictionary()
	state.pending_battle.clear()
	return {"ok": true, "already_applied": false, "battle_id": battle_id, "updated_party_members": updated_participants, "experience_awards": experience_awards, "finish_stat_context": finish_stat_context, "first_clear_rewards": completion_awards, "stars_earned": stars_earned, "stars_added": stars_added, "available_stars": available_stars(state), "show_first_defeat_tutorial": show_first_defeat_tutorial}

static func complete_defeat_return(state, catalog: ContentCatalog) -> Dictionary:
	if state == null or catalog == null:
		return _error("invalid_context", "campaign state and catalog are required")
	if state.pending_defeat_return.is_empty():
		return {"ok": true, "already_returned": true}
	var checkpoint: Dictionary = state.pending_defeat_return.get("checkpoint", state.safe_location)
	var safe_room_id := StringName(checkpoint.get("room_id", ""))
	# ReFillHealthAndEnergy clears stages before calculating/refilling. Keep
	# the current trainer aura, and revive global providers in source slot order.
	var rested := rest_party(state, catalog)
	if not rested.ok: return rested
	if not safe_room_id.is_empty() and catalog.get_definition(safe_room_id) is RoomDefinition:
		state.current_room_id = safe_room_id
		state.room_state["current_room_id"] = String(safe_room_id)
		state.room_state["current_location"] = checkpoint.duplicate(true)
	state.pending_defeat_return.clear()
	return {"ok": true, "already_returned": false}

## BattleScreen.DeActivate clears stages only AFTER finish/level-up UI. Keep
## that context in the settlement response, not on OwnedMinionState/progression.
## Restored originals use their retired record, never the replacement's stages.
static func battle_finish_stat_context(state, result: BattleResult) -> Dictionary:
	var owned_ids: Dictionary = {}
	for owned in state.party: owned_ids[String(owned.instance_id)] = true
	var stages: Dictionary = {}
	var bonus_ids: Array[StringName] = state.runtime_trainer_bonus_move_ids.duplicate()
	for participant in result.participants:
		if int(participant.get("team", -1)) != 0: continue
		var id := String(participant.get("instance_id", ""))
		if owned_ids.has(id) and participant.has("stat_stages"):
			stages[id] = participant.stat_stages.duplicate(true)
		for raw_id in participant.get("battle_bonus_global_move_ids", []):
			var bonus_id := StringName(raw_id)
			if bonus_id not in bonus_ids: bonus_ids.append(bonus_id)
	return {"stat_stages_by_id": stages, "battle_bonus_global_move_ids": bonus_ids}

static func star_upgrade_keys() -> Array[StringName]:
	return [&"health", &"energy", &"attack", &"healing", &"speed", &"movement_speed", &"experience", &"money"]

static func room_tutorial_id(state, room: RoomDefinition) -> String:
	if state == null or room == null or bool(state.progression.get("in_tower_lobby", false)):
		return ""
	var progression: Dictionary = state.progression
	var floor_index := int(progression.get("floor_index", 0))
	var deaths := int(progression.get("deaths_since_victory", 0))
	if floor_index == 0 and int(room.minimap_metadata.get("room_index", -1)) == 11 and not bool(progression.get("key_keepers_tutorial_seen", false)):
		return "key_keepers"
	if floor_index > 7 and deaths > 0 and not bool(progression.get("tank_tutorial_seen", false)):
		return "tank"
	if deaths == 2 and not bool(progression.get("reset_talents_first_tutorial_seen", false)):
		return "reset_talents_first"
	if deaths == 5 and not bool(progression.get("reset_talents_second_tutorial_seen", false)):
		return "reset_talents_second"
	return ""

static func star_upgrade_cost(rank: int) -> int:
	return 10 + maxi(0, rank) * 2

static func total_earned_stars(state) -> int:
	if state == null:
		return 0
	var ratings: Dictionary = state.progression.get("encounter_star_ratings", {})
	var total := 0
	for rating in ratings.values():
		total += clampi(int(rating), 0, 3)
	return total

static func spent_stars(state) -> int:
	if state == null:
		return 0
	var upgrades: Dictionary = state.progression.get("star_upgrades", {})
	var spent := 0
	for key in star_upgrade_keys():
		var rank := maxi(0, int(upgrades.get(String(key), 0)))
		for purchase in rank:
			spent += star_upgrade_cost(purchase)
	return spent

static func available_stars(state) -> int:
	return maxi(0, total_earned_stars(state) - spent_stars(state))

static func refresh_minion_pedia(state) -> void:
	if state == null:
		return
	var owned_ids: Array = state.progression.get("owned_minion_ids", []).duplicate()
	var seen_ids: Array = state.progression.get("seen_minion_ids", []).duplicate()
	for owned in state.party + state.storage:
		_append_unique_id(owned_ids, owned.definition_id)
		_append_unique_id(seen_ids, owned.definition_id)
	state.progression["owned_minion_ids"] = owned_ids
	state.progression["seen_minion_ids"] = seen_ids

static func purchase_star_upgrade(state, upgrade_index: int) -> Dictionary:
	if state == null or upgrade_index < 0 or upgrade_index >= star_upgrade_keys().size():
		return _error("invalid_star_upgrade", "star upgrade index must be between 0 and 7")
	var key := String(star_upgrade_keys()[upgrade_index])
	var upgrades: Dictionary = state.progression.get("star_upgrades", {}).duplicate(true)
	var rank := maxi(0, int(upgrades.get(key, 0)))
	var cost := star_upgrade_cost(rank)
	var available := available_stars(state)
	if available < cost:
		return _error("insufficient_stars", "upgrade costs %d stars; only %d are available" % [cost, available])
	upgrades[key] = rank + 1
	state.progression["star_upgrades"] = upgrades
	return {"ok": true, "kind": &"star_upgrade_purchased", "upgrade": StringName(key), "rank": rank + 1, "cost": cost, "available_stars": available_stars(state)}

static func reset_star_upgrades(state) -> Dictionary:
	if state == null:
		return _error("invalid_context", "campaign state is required")
	state.progression["star_upgrades"] = {}
	return {"ok": true, "kind": &"star_upgrades_reset", "available_stars": available_stars(state)}

static func _battle_star_rating(state, result: BattleResult) -> int:
	var living := 0
	var participant_health: Dictionary = {}
	for participant in result.participants:
		if int(participant.get("team", -1)) != 0:
			continue
		var changes: Dictionary = participant.get("persistent_changes", {})
		participant_health[String(participant.get("instance_id", ""))] = int(changes.get("health", 0))
	for owned in state.party:
		if int(participant_health.get(String(owned.instance_id), 1)) > 0:
			living += 1
	var fallen: int = state.party.size() - living
	if fallen <= 1:
		return 3
	if fallen == 2:
		return 2
	if fallen <= 4:
		return 1
	return 0

static func _record_encounter_stars(state, encounter: EncounterDefinition, earned: int) -> int:
	var ratings: Dictionary = state.progression.get("encounter_star_ratings", {}).duplicate(true)
	var key := String(encounter.id)
	var previous := clampi(int(ratings.get(key, 0)), 0, 3)
	var best := maxi(previous, clampi(earned, 0, 3))
	ratings[key] = best
	state.progression["encounter_star_ratings"] = ratings
	return best - previous

static func _append_unique_id(values: Array, value: StringName) -> void:
	if value.is_empty():
		return
	var text_value := String(value)
	if text_value not in values:
		values.append(text_value)

static func _star_stat_multiplier(state, stat_id: StringName) -> float:
	return _star_stat_multiplier_from(state.progression.get("star_upgrades", {}), stat_id) if state != null else 1.0

static func _star_stat_multiplier_from(upgrades: Dictionary, stat_id: StringName) -> float:
	var percentage_per_rank := 4.0 if stat_id == &"healing" else 2.0
	return 1.0 + float(maxi(0, int(upgrades.get(String(stat_id), 0)))) * percentage_per_rank / 100.0

static func rest_party(state, catalog: ContentCatalog) -> Dictionary:
	if state == null or catalog == null:
		return _error("invalid_context", "campaign state and catalog are required")
	for owned in state.party:
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		if definition == null:
			return _error("missing_minion", "party references missing minion %s" % owned.definition_id)
		# Heal in party-slot order, as DynamicData.HealAllOfAPlayersInPartyMinions
		# does. A provider revived here contributes to later slots' calculations.
		var stats := owned_display_stats(owned, definition, catalog, state)
		owned.persistent_health = int(stats.health)
		owned.persistent_energy = int(stats.energy)
	return {"ok": true, "rested": state.party.size()}

static func maximum_talent_points(level: int) -> int:
	var points := float(level - 3) / 3.0 if level < 31 else float(level - 30) / 4.0 + 9.0
	if level == 60:
		points += 1.0
	return int(points)

static func owned_stats(owned: OwnedMinionState, definition: MinionDefinition, level: int = -1, owned_gems: Array[Dictionary] = [], star_upgrades: Dictionary = {}, round_values: bool = true) -> Dictionary:
	var gem_bonuses: Dictionary = {}
	for stat_id in GemEquipmentService.STAT_IDS:
		gem_bonuses[String(stat_id)] = GemEquipmentService.gem_stat_bonus(owned, stat_id, owned_gems)
	var stats := LegacyMinionStats.raw_stats(definition, owned.level if level < 1 else level, owned.ivs, gem_bonuses)
	var bonus := String(owned.stat_bonus)
	for stat_id in GemEquipmentService.STAT_IDS:
		var stat_name := String(stat_id)
		if not stats.has(stat_name):
			continue
		var stat_value := float(stats[stat_name]) * _star_stat_multiplier_from(star_upgrades, stat_id)
		stats[stat_name] = stat_value * (1.05 if bonus == stat_name else 1.0)
		if round_values: stats[stat_name] = int(stats[stat_name])
	return stats

## Menus include local passives and unique global moves from living party
## members, just like OwnedMinion.Calculate*. Battle setup deliberately uses
## unmodified raw values because its engine applies these bonuses dynamically.
static func owned_display_stats(owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog, state, level: int = -1, battle_context: Dictionary = {}) -> Dictionary:
	# Standalone level cards can be created before begin_sequence supplies a
	# catalog. They still have valid base/IV/gem stats, but no resolvable passives.
	if catalog == null:
		return owned_stats(owned, definition, level, state.owned_gems, state.progression.get("star_upgrades", {}))
	var stats := owned_stats(owned, definition, level, state.owned_gems, state.progression.get("star_upgrades", {}), false)
	var members: Dictionary = {}
	for teammate in state.party:
		var member := CombatantState.new()
		member.instance_id = teammate.instance_id
		member.team = 0
		member.battle_bonus_global_move_ids.assign(battle_context.get("battle_bonus_global_move_ids", state.runtime_trainer_bonus_move_ids))
		member.defeated = teammate.persistent_health == 0
		var species := catalog.get_definition(teammate.definition_id) as MinionDefinition
		if species == null: continue
		member.move_ids = highest_tier_move_ids(teammate.learned_move_ids if not teammate.learned_move_ids.is_empty() else species.initial_move_ids, catalog)
		members[member.instance_id] = member
	var selected := CombatantState.new()
	selected.team = 0
	selected.move_ids = highest_tier_move_ids(owned.learned_move_ids if not owned.learned_move_ids.is_empty() else definition.initial_move_ids, catalog)
	for stat in stats:
		var stat_id := StringName("base:stat/%s" % stat)
		var stage_values: Dictionary = battle_context.get("stat_stages_by_id", {}).get(String(owned.instance_id), {})
		var stage := LegacyCombatModifiers.stat_stage_rate(int(stage_values.get(stat_id, stage_values.get(String(stat_id), 0))))
		stats[stat] = int(float(stats[stat]) * stage * (1.0 if stat == "health" else stage) * LegacyCombatModifiers._passive_stat_rate(selected, stat_id, catalog, members))
	return stats

static func available_talent_points(owned: OwnedMinionState, definition: MinionDefinition) -> int:
	if owned == null or definition == null:
		return 0
	var known_moves := owned.learned_move_ids.size()
	if owned.learned_move_ids.is_empty():
		known_moves = definition.initial_move_ids.size()
	var spent_points := maxi(0, known_moves - definition.initial_move_ids.size())
	return maximum_talent_points(owned.level) - spent_points

static func talent_choices(owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	if owned == null or definition == null or catalog == null or available_talent_points(owned, definition) <= 0:
		return choices
	var known_moves: Array[StringName] = owned.learned_move_ids.duplicate()
	if known_moves.is_empty():
		known_moves = definition.initial_move_ids.duplicate()
	var specialization_index := _specialization_index(known_moves, definition)
	if specialization_index < 0 and not definition.specialization_move_ids.is_empty():
		for index in definition.specialization_move_ids.size():
			var move_id := definition.specialization_move_ids[index]
			var move := catalog.get_definition(move_id) as MoveDefinition
			if move == null or not move.available or move_id in known_moves:
				continue
			choices.append({"kind": &"specialization", "tree_index": index, "move_id": move_id, "move": move})
		return choices
	if specialization_index < 0:
		specialization_index = 0
	var spent_points := maximum_talent_points(owned.level) - available_talent_points(owned, definition)
	for tree_index in definition.talent_tree_ids.size():
		var tree := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition
		if tree == null or tree.nodes.is_empty():
			continue
		if tree_index != specialization_index and spent_points < 11:
			continue
		var points_in_tree := 0
		for node in tree.nodes:
			points_in_tree += _owned_node_rank(node, known_moves)
		var node_index := 0
		while node_index < tree.nodes.size():
			var node: Dictionary = tree.nodes[node_index]
			var moves: Array = node.get("move_ids", [])
			if moves.is_empty():
				node_index += 1
				continue
			var next_move_index := 0
			for move_index in moves.size():
				if StringName(moves[move_index]) in known_moves:
					next_move_index = move_index + 1
			# Source gates depth (row) by points spent in this tree. Columns are
			# parallel branches and their first nodes are all available immediately.
			if next_move_index >= moves.size() or int(node.get("row", 0)) * 3 > points_in_tree:
				node_index += 1
				continue
			var dependencies_ready := true
			for prerequisite_id in node.get("prerequisite_node_ids", []):
				var prerequisite := _find_talent_node(tree, StringName(prerequisite_id))
				if prerequisite.is_empty():
					dependencies_ready = false
					break
				for prerequisite_move in prerequisite.get("move_ids", []):
					if StringName(prerequisite_move) not in known_moves:
						dependencies_ready = false
						break
				if not dependencies_ready:
					break
			if not dependencies_ready:
				node_index += 1
				continue
			var move_id := StringName(moves[next_move_index])
			var move := catalog.get_definition(move_id) as MoveDefinition
			if move != null and move.available:
				choices.append({"kind": &"talent", "tree_index": tree_index, "tree_id": tree.id, "node_id": StringName(node.get("id", "")), "move_id": move_id, "move": move})
			node_index += 1
	return choices

static func talent_specialization_index(owned: OwnedMinionState, definition: MinionDefinition) -> int:
	if owned == null or definition == null:
		return -1
	return _specialization_index(owned.learned_move_ids, definition)

static func talent_node_looks_active(owned: OwnedMinionState, definition: MinionDefinition, tree: TalentTreeDefinition, tree_index: int, node: Dictionary) -> bool:
	# TalentTreeNode.SetIfTheNodeLooksActive checks access, not affordability
	# or whether this node is already maxed. Those only block its click handler.
	var specialization := talent_specialization_index(owned, definition)
	var spent := maximum_talent_points(owned.level) - available_talent_points(owned, definition)
	if tree_index != specialization and spent < 11:
		return false
	var points_in_tree := 0
	for candidate in tree.nodes:
		points_in_tree += _owned_node_rank(candidate, owned.learned_move_ids)
	if points_in_tree < int(node.get("row", 0)) * 3:
		return false
	for prerequisite_id in node.get("prerequisite_node_ids", []):
		var prerequisite := _find_talent_node(tree, StringName(prerequisite_id))
		if prerequisite.is_empty() or _owned_node_rank(prerequisite, owned.learned_move_ids) < prerequisite.get("move_ids", []).size():
			return false
	return true

static func reset_talents(owned: OwnedMinionState, definition: MinionDefinition) -> Dictionary:
	if owned == null or definition == null:
		return _error("invalid_context", "owned minion and definition are required")
	owned.learned_move_ids.assign(definition.initial_move_ids)
	owned.talent_node_ids.clear()
	return {"ok": true, "available_points": available_talent_points(owned, definition)}

static func _owned_node_rank(node: Dictionary, known_moves: Array[StringName]) -> int:
	var rank := 0
	var move_ids: Array = node.get("move_ids", [])
	for index in move_ids.size():
		if StringName(move_ids[index]) in known_moves:
			rank = index + 1
	return rank

static func purchase_talent_choice(owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog, requested_move_id: StringName) -> Dictionary:
	if owned == null or definition == null or catalog == null:
		return _error("invalid_context", "owned minion, definition, and catalog are required")
	if owned.learned_move_ids.is_empty():
		owned.learned_move_ids.assign(definition.initial_move_ids)
	for choice in talent_choices(owned, definition, catalog):
		if StringName(choice.get("move_id", "")) != requested_move_id:
			continue
		if requested_move_id in owned.learned_move_ids:
			return _error("talent_already_owned", "minion already knows %s" % requested_move_id)
		owned.learned_move_ids.append(requested_move_id)
		var node_id := StringName(choice.get("node_id", ""))
		if not node_id.is_empty() and node_id not in owned.talent_node_ids:
			owned.talent_node_ids.append(node_id)
		return {"ok": true, "choice": choice, "available_points": available_talent_points(owned, definition)}
	return _error("talent_not_available", "move %s is not currently a legal talent choice" % requested_move_id)

static func evolve_owned_minion(owned: OwnedMinionState, catalog: ContentCatalog, owned_gems: Array[Dictionary] = [], star_upgrades: Dictionary = {}, state = null, battle_context: Dictionary = {}) -> Dictionary:
	if owned == null or catalog == null:
		return _error("invalid_context", "owned minion and catalog are required")
	var old_definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	if old_definition == null or old_definition.evolution_id.is_empty():
		return _error("no_evolution", "minion has no configured evolution")
	if owned.level < old_definition.evolution_level:
		return _error("evolution_locked", "%s evolves at level %d" % [old_definition.display_name, old_definition.evolution_level])
	var new_definition := catalog.get_definition(old_definition.evolution_id) as MinionDefinition
	if new_definition == null:
		return _error("missing_evolution", "evolution %s is missing" % old_definition.evolution_id)
	var old_health := owned.persistent_health
	var old_energy := owned.persistent_energy
	owned.definition_id = new_definition.id
	if owned.nickname == old_definition.display_name:
		owned.nickname = new_definition.display_name
	var new_stats := owned_display_stats(owned, new_definition, catalog, state, -1, battle_context) if state != null else owned_stats(owned, new_definition, -1, owned_gems, star_upgrades)
	if old_health >= 0:
		owned.persistent_health = clampi(old_health, 0, int(new_stats.health))
	if old_energy >= 0:
		owned.persistent_energy = clampi(old_energy, 0, int(new_stats.energy))
	return {"ok": true, "old_definition": old_definition, "new_definition": new_definition, "stats": new_stats}

static func highest_tier_move_ids(move_ids: Array[StringName], catalog: ContentCatalog) -> Array[StringName]:
	var result: Array[StringName] = []
	var family_positions: Dictionary = {}
	for move_id in move_ids:
		var move := catalog.get_definition(move_id) as MoveDefinition
		if move == null:
			continue
		var family_key := String(move.family_id)
		if not family_positions.has(family_key):
			family_positions[family_key] = result.size()
			result.append(move_id)
			continue
		var position := int(family_positions[family_key])
		var current := catalog.get_definition(result[position]) as MoveDefinition
		if current != null and move.tier > current.tier:
			result[position] = move_id
	return result

static func _specialization_index(known_moves: Array[StringName], definition: MinionDefinition) -> int:
	for index in definition.specialization_move_ids.size():
		if definition.specialization_move_ids[index] in known_moves:
			return index
	return -1

static func _find_talent_node(tree: TalentTreeDefinition, node_id: StringName) -> Dictionary:
	for node in tree.nodes:
		if StringName(node.get("id", "")) == node_id:
			return node
	return {}

static func _grant_first_clear_rewards(state, encounter: EncounterDefinition) -> Dictionary:
	var completed: Dictionary = state.progression.get("completed_encounters", {})
	if bool(completed.get(String(encounter.id), false)):
		return {"money": 0, "floor_keys": 0, "eggery_keys": 0, "sage_seals": 0}
	var first_clear: Dictionary = encounter.rewards.get("first_clear", {})
	var star_upgrades: Dictionary = state.progression.get("star_upgrades", {})
	var money_upgrade_level := int(star_upgrades.get("money", 0))
	var floor_money_basis := float(first_clear.get("floor_money_basis", 0.0))
	var money := int(first_clear.get("money", 0))
	if first_clear.has("floor_money_basis"):
		# Source assigns two separate += results to an int balance. Truncate
		# each award separately, not the sum of their fractional intermediates.
		money = int(floor_money_basis / 6.0 * money_upgrade_level * money_upgrade_level)
		if encounter.source_trainer_type == &"TrainerType.NORMAL_TRAINER":
			money += int(floor_money_basis / 3.0)
	var keys := int(first_clear.get("floor_keys", 0))
	var eggery_keys := int(first_clear.get("eggery_keys", 0))
	var sage_seals := int(first_clear.get("sage_seals", 0))
	if sage_seals > 0 and String(encounter.source_trainer_type).begins_with("TrainerType.TRAINER_GYM_"):
		# BattleScreen.AddSageSeal sets the earned seal frontier to this family's
		# number. It neither duplicates an existing seal nor assumes prior Gyms
		# were all cleared in order.
		var family := int(String(encounter.source_trainer_type).trim_prefix("TrainerType.TRAINER_GYM_"))
		sage_seals = maxi(0, family - int(state.progression.get("sage_seals", 0)))
	var seal_pieces := 0
	if encounter.source_trainer_type == &"TrainerType.BOSS_TRAINER" and encounter.source_floor_index < 31:
		var unlocked: Array = state.progression.get("unlocked_floor_indices", [0])
		var highest := 0
		for floor_index in unlocked:
			highest = maxi(highest, int(floor_index))
		if encounter.source_floor_index >= highest:
			seal_pieces = 1
	state.progression["currency"] = int(state.progression.get("currency", 0)) + money
	state.progression["floor_keys"] = int(state.progression.get("floor_keys", 0)) + keys
	state.progression["eggery_keys"] = int(state.progression.get("eggery_keys", 0)) + eggery_keys
	state.progression["sage_seals"] = int(state.progression.get("sage_seals", 0)) + sage_seals
	var gems: Array[Dictionary] = []
	# BattleScreen grants one gem for a first hard/expert clear. These rewards
	# were authored in encounter data but previously dropped during settlement.
	if encounter.source_trainer_type in [&"TrainerType.HARD_TRAINER", &"TrainerType.EXPERT_TRAINER"]:
		var tier := CampaignGemFactory.tier_for_floor(int(state.progression.get("floor_index", 0)))
		gems.append(CampaignGemFactory.grant(state, tier, String(encounter.id)))
	elif encounter.source_trainer_type == &"TrainerType.TRAINER_GYM_5" and sage_seals > 0:
		# BattleScreen.AddSageSeal(5) grants a tier-10 gem only when this
		# seal raises the frontier. Its second source argument is unused.
		gems.append(CampaignGemFactory.grant(state, 10, String(encounter.id)))
	return {"money": money, "floor_keys": keys, "eggery_keys": eggery_keys, "sage_seals": sage_seals, "sage_seal_pieces": seal_pieces, "gems": gems, "source_trainer_type": String(encounter.source_trainer_type)}

static func _unlock_next_tower_floor(state, catalog: ContentCatalog) -> void:
	var campaign := catalog.get_definition(state.campaign_id) as CampaignDefinition
	if campaign == null:
		return
	var current_floor := int(state.progression.get("floor_index", 0))
	var hard_mode := CampaignTowerModeService.mode_for_global_floor(current_floor) == &"hard"
	var floor_limit := CampaignTowerModeService.TOTAL_TOWER_FLOORS if hard_mode else CampaignTowerModeService.STANDARD_FLOOR_COUNT
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0]).duplicate()
	var highest_unlocked_floor := -1
	for unlocked_floor in unlocked:
		highest_unlocked_floor = maxi(highest_unlocked_floor, int(unlocked_floor))
	# Source sets the new-seal/unlock flag only when this boss is at the frontier:
	# currFloor + 2 must be greater than GetHighestFloor() (highest index + 1).
	if current_floor < highest_unlocked_floor:
		return
	# Utility.UnlockNextFloor restocks BEFORE unlocking the next floor, using
	# GetHighestFloor's one-based frontier rather than the room being replayed.
	CampaignGemEconomyService.refresh_shop(state, mini(61, highest_unlocked_floor + 1))
	var floors_to_unlock: Array[int] = []
	if hard_mode:
		# Hard floors follow the source's ordinary sequential path; standard-only
		# milestone jumps do not repeat in the second range.
		floors_to_unlock.append(current_floor + 1)
	elif current_floor in [2, 7, 12, 17]:
		floors_to_unlock.append(current_floor + 2)
	elif current_floor in [6, 11, 16, 21]:
		floors_to_unlock.append(current_floor - 3)
		floors_to_unlock.append(current_floor + 1)
	else:
		floors_to_unlock.append(current_floor + 1)
	for floor_index in floors_to_unlock:
		# Standard Floor 31 unlocks the first hard-mode slot (global index 31).
		var is_hard_entry := not hard_mode and current_floor == CampaignTowerModeService.STANDARD_FLOOR_COUNT - 1 and floor_index == CampaignTowerModeService.STANDARD_FLOOR_COUNT
		if floor_index < 0 or floor_index >= floor_limit and not is_hard_entry:
			continue
		if floor_index not in unlocked:
			unlocked.append(floor_index)
			if not hard_mode and floor_index in [3, 8, 13, 18]:
				var pending: Array = state.progression.get("pending_optional_floor_reveals", []).duplicate()
				if floor_index not in pending:
					pending.append(floor_index)
				state.progression["pending_optional_floor_reveals"] = pending
	unlocked.sort()
	state.progression["unlocked_floor_indices"] = unlocked

static func _trainer_unlocks_floor(source_trainer_type: StringName) -> bool:
	var trainer_type := String(source_trainer_type)
	return trainer_type == "TrainerType.BOSS_TRAINER" or trainer_type.begins_with("TrainerType.TRAINER_GYM_") or trainer_type == "TrainerType.TRAINER_GRAND_SAGE"

static func _award_experience(state, encounter: EncounterDefinition, catalog: ContentCatalog, battle_won: bool, result: BattleResult = null, finish_stat_context: Dictionary = {}) -> Dictionary:
	var enemy_entries: Array = encounter.team_entries
	if result != null:
		var final_enemies: Array[Dictionary] = []
		for participant in result.participants:
			if int(participant.get("team", -1)) != 1 or bool(participant.get("retired", false)) or not participant.has("level"):
				continue
			final_enemies.append(participant)
		if not final_enemies.is_empty():
			final_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("slot_index", 0)) < int(b.get("slot_index", 0)))
			enemy_entries = final_enemies
	if enemy_entries.is_empty():
		return {}
	var first_enemy_level := 1
	var has_first_enemy_level := false
	var base_experience := 850
	for enemy_entry in enemy_entries:
		var enemy_definition := catalog.get_definition(StringName(enemy_entry.get("definition_id", ""))) as MinionDefinition
		if enemy_definition == null:
			continue
		# Native result levels are already effective; authored fallback entries
		# still require TrainerSystem's encounter/per-minion offset.
		var source_hard := String(encounter.source_trainer_id).begins_with("base:trainer/hard/") and encounter.source_floor_index >= 31
		var enemy_level := maxi(1, int(enemy_entry.get("level", 1)) + (0 if enemy_entry.has("retired") or source_hard else int(enemy_entry.get("source_level_offset", encounter.source_level_offset))))
		if not has_first_enemy_level:
			first_enemy_level = enemy_level
			has_first_enemy_level = true
		base_experience += _extra_experience_value(enemy_definition.experience_gain_rate)
	var star_upgrades: Dictionary = state.progression.get("star_upgrades", {})
	var experience_star_level := int(star_upgrades.get("experience", 0))
	var awards: Dictionary = {}
	var source_jitter := String(encounter.source_trainer_id).begins_with("base:trainer/") and encounter.source_floor_index > 0
	var experience_rng := BattleRng.new(hash("experience/%s" % state.pending_battle.get("battle_id", "")))
	for raw_owned in state.party:
		var owned: OwnedMinionState = raw_owned
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		if definition == null:
			continue
		var gained := base_experience
		var level_difference := owned.level - first_enemy_level
		if source_jitter:
			# Utility.AddExpToMinions rolls once for each occupied party slot,
			# before halving/under-level bonuses; Floor 1 deliberately has no roll.
			level_difference += int(experience_rng.next_unit() * 3.0) - 1
		if level_difference > 0:
			for _index in level_difference:
				gained = int(float(gained) / 2.0)
			if gained < 50:
				gained = 50
		elif level_difference < 0:
			gained += int(float(level_difference) * (float(base_experience) / 3.0) * -1.0)
		gained = int(float(gained) * _experience_rate_multiplier(definition.experience_gain_rate))
		gained = int(float(gained) * (1.0 + float(experience_star_level) * 0.05))
		if not battle_won:
			gained = int(float(gained) * 0.75)
		var old_level := owned.level
		var old_experience := owned.experience
		owned.experience += maxi(gained, 0)
		owned.level = clampi(int(owned.experience / 1000.0), 1, 60)
		var old_max_health := int(owned_display_stats(owned, definition, catalog, state, old_level, finish_stat_context).health)
		var new_max_health := int(owned_display_stats(owned, definition, catalog, state, owned.level, finish_stat_context).health)
		var health_increase := maxi(0, new_max_health - old_max_health)
		if owned.persistent_health >= 0 and health_increase > 0:
			owned.persistent_health = mini(new_max_health, owned.persistent_health + health_increase)
		awards[String(owned.instance_id)] = {
			"experience": gained,
			"old_experience": old_experience,
			"new_experience": owned.experience,
			"old_level": old_level,
			"new_level": owned.level,
			"health_increase": health_increase,
		}
	return awards

## Multiplayer double battle, partner side: the partner's minions (prefixed
## `ally_prefix` in the battle) keep their final health/energy and earn XP from
## the duplicated trainer team. World effects (completion, stars, rewards,
## keys) belong to the player who started the fight, so none happen here. A
## loss heals the party in place instead of returning to a checkpoint.
static func apply_ally_battle_result(state, result: BattleResult, encounter: EncounterDefinition, catalog: ContentCatalog, ally_prefix: String) -> Dictionary:
	if state == null or result == null or encounter == null or result.is_empty():
		return _error("invalid_result", "completed battle result and encounter are required")
	var battle_id := "ally:%s" % String(result.battle_id)
	if battle_id in state.applied_battle_ids:
		return {"ok": true, "already_applied": true, "battle_id": battle_id}
	var owned_by_id: Dictionary = {}
	for owned in state.party:
		owned_by_id[ally_prefix + String(owned.instance_id)] = owned
	for participant in result.participants:
		var owned := owned_by_id.get(String(participant.get("instance_id", ""))) as OwnedMinionState
		if owned == null or int(participant.get("team", -1)) != 0:
			continue
		var changes: Dictionary = participant.get("persistent_changes", {})
		if changes.has("health"):
			owned.persistent_health = maxi(0, int(changes.health))
		if changes.has("energy"):
			owned.persistent_energy = maxi(0, int(changes.energy))
	var won := result.winning_team == 0
	var forfeited := result.reason == &"forfeit"
	var awards: Dictionary = {}
	if not forfeited and catalog != null:
		# The XP roll is seeded from the pending battle ID; use this battle's.
		var pending: Dictionary = state.pending_battle
		state.pending_battle = {"battle_id": battle_id}
		awards = _award_experience(state, encounter, catalog, won, result)
		state.pending_battle = pending
	if not won and catalog != null:
		var rested := rest_party(state, catalog)
		if not rested.ok:
			return rested
	state.applied_battle_ids.append(battle_id)
	return {"ok": true, "already_applied": false, "battle_id": battle_id, "experience_awards": awards, "won": won}

static func _extra_experience_value(rate: int) -> int:
	match rate:
		0: return -70
		1: return -35
		3: return 35
		4: return 70
		_: return 0

static func _experience_rate_multiplier(rate: int) -> float:
	match rate:
		0: return 1.2
		1: return 1.1
		3: return 0.9
		4: return 0.8
		_: return 1.0

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
