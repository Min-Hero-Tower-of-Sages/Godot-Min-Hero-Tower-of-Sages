class_name CampaignDebugService
extends RefCounted

const OPTIONS := [
	{"id": "unlimited_money", "name": "Unlimited Money", "description": "Purchases and gem combining are free. Your actual money balance is preserved."},
	{"id": "max_party_levels", "name": "Max Party Levels", "description": "Raise party minions to level 60 and refill them. Granted levels cannot be undone by switching this off."},
	{"id": "force_shiny", "name": "100% Shiny", "description": "All newly acquired minions are shiny, even with the normal Shinies mod off. Existing minions stay unchanged."},
	{"id": "unlimited_stars", "name": "Unlimited Stars", "description": "Star upgrades are free without changing earned ratings. Granted upgrades remain after disabling; Reset still works."},
	{"id": "full_keys", "name": "Full Keys", "description": "Keeps floor-door and hatchery keys topped up for this floor, including both three-key rings in Hard Mode."},
]

static func available(state) -> bool:
	return CampaignModService.enabled(state, "debug_mode")

static func enabled(state, option: String) -> bool:
	return available(state) and bool(state.progression.get("debug_options", {}).get(option, false))

static func can_afford(state, cost: int) -> bool:
	return cost >= 0 and (enabled(state, "unlimited_money") or int(state.progression.get("currency", 0)) >= cost)

static func charged_cost(state, cost: int) -> int:
	return 0 if enabled(state, "unlimited_money") else cost

static func apply_party_levels(state, catalog: ContentCatalog) -> void:
	if not enabled(state, "max_party_levels"): return
	for owned in state.party:
		if owned.level >= 60: continue
		owned.level = 60
		owned.experience = maxi(60000, owned.experience)
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		if definition == null: continue
		var stats := CampaignProgressionService.owned_display_stats(owned, definition, catalog, state)
		owned.persistent_health = int(stats.health)
		owned.persistent_energy = int(stats.energy)

static func apply_keys(state) -> void:
	if not enabled(state, "full_keys") or bool(state.progression.get("in_tower_lobby", false)): return
	state.progression["floor_keys"] = maxi(3, int(state.progression.get("floor_keys", 0)))
	var hatchery_keys := 3 if int(state.progression.get("floor_index", 0)) >= CampaignTowerModeService.STANDARD_FLOOR_COUNT else 1
	state.progression["eggery_keys"] = maxi(hatchery_keys, int(state.progression.get("eggery_keys", 0)))
