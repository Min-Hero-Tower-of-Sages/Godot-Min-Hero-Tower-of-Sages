class_name CampaignGemFactory
extends RefCounted

const STAT_IDS := [&"health", &"energy", &"attack", &"healing", &"speed"]
const STAT_LABELS := ["Health", "Energy", "Attack", "Healing", "Speed"]

static func tier_for_floor(floor_index: int) -> int:
	# StaticData's authored standard/hard tower tier table.
	if floor_index < 5:
		return 1
	if floor_index < 10:
		return 2
	if floor_index < 15:
		return 3
	if floor_index < 20:
		return 4
	return 5 if floor_index < 30 else 6

static func create_random(tier: int) -> Dictionary:
	# OwnedGem.CreateRandomGemWithTier / GetRandomGemMod / GetExtraStat.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stat_index := rng.randi_range(0, STAT_IDS.size() - 1)
	var modifier := 1.0 + (rng.randf() * 95.0 - 40.0) / 100.0
	var raw_stats: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	raw_stats[stat_index] = pow(3.0, tier) * modifier
	var slots: Array[int] = []
	for index in range(12):
		slots.append(index)
	var facets: Array[int] = []
	while not slots.is_empty():
		facets.append(slots.pop_at(rng.randi_range(0, slots.size() - 1)) * 30)
	var tier_base := 3
	for value in range(2, tier + 1):
		tier_base += value
	return {
		"tier": tier,
		"stat_id": String(STAT_IDS[stat_index]),
		"stat_label": STAT_LABELS[stat_index],
		"stat_value": ceili(float(tier_base) * modifier),
		"raw_stats": raw_stats,
		"facet_positions": facets,
	}

static func grant(state, tier: int, origin: String) -> Dictionary:
	var gem := create_random(tier)
	# Inventory size is monotonic until a gem management/selling flow exists.
	gem["instance_id"] = "%s-gem-%d" % [origin, state.owned_gems.size() + 1]
	state.owned_gems.append(gem)
	return gem
