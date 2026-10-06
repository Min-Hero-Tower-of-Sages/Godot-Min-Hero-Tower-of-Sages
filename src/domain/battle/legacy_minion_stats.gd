class_name LegacyMinionStats
extends RefCounted

const BASE_HEALTH_STAT := 5.0
const BASE_OTHER_STAT := 5.0
const STAT_DIVISOR := 20.0
const BASE_HEALTH_DIVISOR := 20.0
const MIN_HEALTH_DIVISOR := 10.0
const ENERGY_MULTIPLIER := 1.5

# StaticData.SetupEnemyStatModificationValues. Values multiply the species'
# usable gem sockets, not equipped gems or locked sockets. Floors 7–20 retain
# the initial energy coefficient (0.05 * 1.1), unlike explicit overrides.
const ENEMY_FLOOR_COEFFICIENTS := [
	0.0, 0.0, 0.0, 0.05, 0.05, 0.05, 0.05,
	0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05,
	0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05,
	0.05, 0.052, 0.054, 0.056, 0.06, 0.065, 0.067, 0.07, 0.075, 0.08,
	0.1, 0.12, 0.11, 0.12, 0.1, 0.25, 0.2, 0.25, 0.27, 0.27,
	0.27, 0.27, 0.32, 0.27, 0.27, 0.29, 0.32, 0.33, 0.34,
	0.35, 0.35, 0.35, 0.35, 0.35, 0.37, 0.37, 0.37, 0.37, 0.37, 0.4, 0.4,
]

static func enemy_stat_multiplier(definition: MinionDefinition, floor_index: int, stat: String) -> float:
	var floor_id := clampi(floor_index, 0, ENEMY_FLOOR_COEFFICIENTS.size() - 1)
	var coefficient: float = ENEMY_FLOOR_COEFFICIENTS[floor_id]
	if floor_id == 31 and stat in ["attack", "healing"]:
		coefficient = 0.12
	elif stat == "energy" and floor_id != 31 and floor_id != 32:
		coefficient *= 1.1 if floor_id >= 7 and floor_id <= 20 else 1.3
	return 1.0 + coefficient * definition.gem_slots

## Enemy OwnedMinion constructors have zero IVs, empty gems and exactly one
## random 5% stat bonus. Keep the raw formula until its final integer cast.
## Learned/global passives are applied separately by LegacyCombatModifiers.
static func enemy_stats(definition: MinionDefinition, level: int, floor_index: int, bonus: String) -> Dictionary:
	return constructor_stats(definition, level, floor_index, bonus)

## Temporary player replacements are new owned minions: no inherited gems/IVs,
## but the player's saved star upgrades apply instead of enemy floor scaling.
static func constructor_stats(definition: MinionDefinition, level: int, floor_index: int, bonus: String, player_stars: Variant = null, round_values: bool = true) -> Dictionary:
	var stats := raw_stats(definition, level)
	for stat in stats:
		stats[stat] = float(stats[stat]) * _constructor_multiplier(definition, floor_index, stat, player_stars) * (1.05 if bonus == stat else 1.0)
	stats["max_attack_stat"] = max_attack_stat(definition) * _constructor_multiplier(definition, floor_index, "attack", player_stars) * (1.05 if bonus == "attack" else 1.0)
	stats["max_healing_stat"] = max_healing_stat(definition) * _constructor_multiplier(definition, floor_index, "healing", player_stars) * (1.05 if bonus == "healing" else 1.0)
	if round_values:
		for stat in stats: stats[stat] = int(stats[stat])
	return stats

static func _constructor_multiplier(definition: MinionDefinition, floor_index: int, stat: String, player_stars: Variant) -> float:
	if player_stars == null: return enemy_stat_multiplier(definition, floor_index, stat)
	return 1.0 + maxi(0, int(player_stars.get(stat, 0))) * (0.04 if stat == "healing" else 0.02)

static func current_stats(definition: MinionDefinition, level: int) -> Dictionary:
	var stats := raw_stats(definition, level)
	for stat in stats: stats[stat] = int(stats[stat])
	return stats

## OwnedMinion.Calculate* keeps fractional base/IV arithmetic until the final
## cast. Energy gem bonuses are added BEFORE the final 1.5 multiplier.
static func raw_stats(definition: MinionDefinition, level: int, ivs: Dictionary = {}, gem_bonuses: Dictionary = {}) -> Dictionary:
	var safe_level := maxi(1, level)
	var bases := {"health": definition.base_health, "energy": definition.base_energy, "attack": definition.base_attack, "healing": definition.base_healing, "speed": definition.base_speed}
	var stats: Dictionary = {}
	for stat in bases:
		var divisor := _health_divisor(safe_level) if stat == "health" else STAT_DIVISOR
		var value := (float(bases[stat]) + float(ivs.get(stat, ivs.get(StringName(stat), 0)))) * safe_level / divisor + BASE_OTHER_STAT + float(gem_bonuses.get(stat, 0))
		stats[stat] = value * (ENERGY_MULTIPLIER if stat == "energy" else 1.0)
	return stats

## The legacy battle formula uses m_maxAttackStat/m_maxHealingStat for move
## power even when a minion is below level 60. These are its level-60 stats,
## not the current-level stats returned by current_stats().
static func max_attack_stat(definition: MinionDefinition, iv: float = 0.0, multiplier: float = 1.0) -> float:
	if definition == null:
		return 0.0
	return ((float(definition.base_attack) + iv) * 60.0 / STAT_DIVISOR + BASE_OTHER_STAT) * multiplier

static func max_healing_stat(definition: MinionDefinition, iv: float = 0.0, multiplier: float = 1.0) -> float:
	if definition == null:
		return 0.0
	return ((float(definition.base_healing) + iv) * 60.0 / STAT_DIVISOR + BASE_OTHER_STAT) * multiplier

static func _health_divisor(level: int) -> float:
	if level <= 14:
		return BASE_HEALTH_DIVISOR
	return maxf(MIN_HEALTH_DIVISOR, BASE_HEALTH_DIVISOR - float(level - 15) / 45.0 * 12.0)
