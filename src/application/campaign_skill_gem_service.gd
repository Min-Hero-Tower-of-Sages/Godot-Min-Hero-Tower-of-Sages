class_name CampaignSkillGemService
extends RefCounted

## Skill gems reference catalog moves; they never spend points or alter talents.
const FLAG := "skill_gems"
const COLOR_TYPES := ["fire", "undead", "dino", "energy", "water"] # Electric is named energy in the recovered catalog.
const COLOR_NAMES := ["Red", "Purple", "Orange", "Yellow", "Blue"]
const RECIPES := {
	"0,3,4": "plant", "0,1,2": "demonic", "0,1,3": "earth",
	"0,1,4": "robot", "0,2,4": "normal", "1,2,3": "holy",
	"1,2,4": "flying", "1,3,4": "titan", "2,3,4": "ice",
}
const SUPPORT_KINDS := [EffectDefinition.Kind.STAT_PERCENT, EffectDefinition.Kind.STAT_STAGE,
	EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.SHIELD, EffectDefinition.Kind.REFLECT,
	EffectDefinition.Kind.REDIRECT_DAMAGE, EffectDefinition.Kind.CRITICAL_CHANCE]

static func is_skill(gem: Dictionary) -> bool:
	return gem.get("kind", "") == "skill"

static func level_for_tier(tier: int) -> int:
	if tier <= 3: return 1
	if tier <= 5: return 2
	if tier <= 7: return 3
	if tier <= 9: return 4
	return 5

static func forge_unlocked(state) -> bool:
	# Also works for older/imported saves that already defeated Talo.
	return CampaignModService.enabled(state, FLAG) and (bool(state.progression.get("random_forge_unlocked", false)) or int(state.progression.get("sage_seals", 0)) >= 5)

static func universal(move: MoveDefinition) -> bool:
	if move == null or move.effects.is_empty(): return false
	for effect in move.effects:
		if not move.is_passive and not move.is_global_passive:
			if effect.target_scope == EffectDefinition.TargetScope.ENEMY_TARGETS and move.enemy_target_count == 0: continue
			if effect.target_scope == EffectDefinition.TargetScope.ALLY_TARGETS and move.ally_target_count == 0: continue
		if effect.kind not in SUPPORT_KINDS or effect.amount < 0: return false
		if effect.target_scope in [EffectDefinition.TargetScope.ENEMY_TARGETS, EffectDefinition.TargetScope.BOTH_TARGET_GROUPS]: return false
	return true

static func can_equip(state, catalog: ContentCatalog, gem: Dictionary, definition: MinionDefinition) -> Dictionary:
	if not is_skill(gem): return {"ok": true}
	if not CampaignModService.enabled(state, FLAG): return _error("Enable Skill Gems in Gameplay Tweaks to equip this gem.")
	var move := catalog.get_definition(StringName(gem.get("move_id", ""))) as MoveDefinition
	if move == null or not move.available: return _error("This skill gem references an unavailable move.")
	if universal(move): return {"ok": true}
	var chart := catalog.get_type_chart()
	if chart != null and chart.combined_multiplier(move.type_id, definition.type_ids) > 1.00001:
		return _error("%s is weak to %s and cannot equip this skill gem." % [definition.display_name, type_label(move.type_id)])
	return {"ok": true}

static func equipped_moves(state, catalog: ContentCatalog, owned: OwnedMinionState) -> Array[StringName]:
	var moves: Array[StringName] = []
	if not CampaignModService.enabled(state, FLAG): return moves
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	if definition == null: return moves
	for gem in state.owned_gems:
		if is_skill(gem) and StringName(gem.get("instance_id", "")) in owned.equipment_ids and can_equip(state, catalog, gem, definition).ok:
			moves.append(StringName(gem.move_id))
	return moves

static func candidates(catalog: ContentCatalog, requested_level: int, type_id: StringName = &"", support_only: bool = false) -> Array[MoveDefinition]:
	# One roll per family, not one per rank. Rank-limited moves remain in the
	# pool and cap at their highest available rank (including one-rank skills).
	var families: Dictionary = {}
	for definition in catalog._by_id.values():
		if not definition is MoveDefinition: continue
		var move: MoveDefinition = definition
		if not move.available or move.effects.is_empty() or move.family_id == &"base:move_family/desperation": continue
		if not type_id.is_empty() and move.type_id != type_id: continue
		if support_only:
			# Non-elemental recipes include defensive support as well as stats:
			# armor, reflection and damage redirection (Taunt/Torment).
			if not universal(move) or move.type_id != &"base:type/none": continue
		if move.tier > requested_level: continue
		var previous := families.get(move.family_id) as MoveDefinition
		if previous == null or move.tier > previous.tier: families[move.family_id] = move
	var result: Array[MoveDefinition] = []
	for move in families.values(): result.append(move)
	result.sort_custom(func(a: MoveDefinition, b: MoveDefinition) -> bool: return String(a.id) < String(b.id))
	return result

static func create(catalog: ContentCatalog, requested_level: int, type_id: StringName = &"", rng: RandomNumberGenerator = null, tier: int = 1, colors: Array = [], support_only: bool = false) -> Dictionary:
	var pool := candidates(catalog, clampi(requested_level, 1, 5), type_id, support_only)
	if pool.is_empty(): return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var move: MoveDefinition = pool[rng.randi_range(0, pool.size() - 1)]
	var gem := CampaignGemFactory.create_random(clampi(tier, 1, 10))
	gem.merge({"kind": "skill", "move_id": String(move.id), "skill_level": move.tier,
		"type_id": String(move.type_id), "skill_name": move.display_name,
		"skill_icon": String(move.buff_icon_name), "universal": universal(move),
		"stat_id": "", "stat_label": "", "stat_value": 0}, true)
	var raw: Array[float] = [0, 0, 0, 0, 0]
	var selected_colors := colors.duplicate()
	if selected_colors.is_empty():
		var color_index := COLOR_TYPES.find(String(move.type_id).get_file())
		if color_index >= 0: selected_colors.append(color_index)
		else:
			for recipe in RECIPES:
				if RECIPES[recipe] == String(move.type_id).get_file():
					for value in recipe.split(","): selected_colors.append(int(value))
					break
		if selected_colors.is_empty(): selected_colors = [0, 1, 2, 3, 4]
	for index in selected_colors: raw[int(index)] = 1.0
	gem["raw_stats"] = raw
	return gem

static func grant(state, catalog: ContentCatalog, level: int, origin: String) -> Dictionary:
	var gem := create(catalog, level, &"", null, 6 if level == 3 else 1)
	if gem.is_empty(): return gem
	append_owned(state, gem, origin)
	return gem

static func append_owned(state, gem: Dictionary, origin: String) -> void:
	gem["instance_id"] = CampaignGemEconomyService._new_gem_id(state, origin)
	state.owned_gems.append(gem)

static func field_gem(state, catalog: ContentCatalog, room_id: StringName, source_index: int, tier: int) -> Dictionary:
	if CampaignModService.enabled(state, FLAG):
		# Stable per chest/campaign, so reopening a room doesn't reroll its kind.
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(hash("skill:%s:%d:%d" % [room_id, source_index, int(state.progression.get("chest_seed", 0))]))
		if rng.randi_range(0, 7) == 0:
			return create(catalog, rng.randi_range(1, 2), &"", rng, tier)
	return CampaignGemFactory.create_random(tier)

static func forge_preview(state, catalog: ContentCatalog, gems: Array[Dictionary]) -> Dictionary:
	if not forge_unlocked(state): return _error("Defeat the Talo Sage to unlock Random Forge.")
	if gems.size() != 3: return _error("Select three stat gems of the same tier.")
	var tier := int(gems[0].get("tier", 0))
	if tier < 1 or tier > 10: return _error("Random Forge accepts tiers 1–10.")
	var unique: Dictionary = {}
	var colors: Array[int] = []
	var combined_raw: Array[float] = [0, 0, 0, 0, 0]
	for gem in gems:
		if is_skill(gem): return _error("Skill gems cannot be combined or used in Random Forge.")
		if int(gem.get("tier", 0)) != tier: return _error("Gems need to be of the same tier")
		var id := String(gem.get("instance_id", ""))
		if id.is_empty() or unique.has(id): return _error("Select three different stat gems.")
		unique[id] = true
		var raw: Array = gem.get("raw_stats", [])
		if raw.size() != 5: return _error("This stat gem has invalid color data.")
		for index in 5:
			combined_raw[index] += float(raw[index])
			if float(raw[index]) > 0.0 and index not in colors: colors.append(index)
	colors.sort()
	var color_keys := PackedStringArray()
	for color in colors: color_keys.append(str(color))
	var element := String(COLOR_TYPES[colors[0]]) if colors.size() == 1 else String(RECIPES.get(",".join(color_keys), "none"))
	var type_id := StringName("base:type/%s" % element)
	var level := level_for_tier(tier)
	if candidates(catalog, level, type_id, element == "none").is_empty(): return _error("No available skills match this recipe.")
	# No move is rolled or revealed by previewing the recipe.
	return {"ok": true, "cost": int(CampaignGemEconomyService.COMBINE_COSTS[mini(tier, 9)]),
		"gem": {"kind": "skill", "tier": tier, "skill_level": level, "type_id": String(type_id), "raw_stats": combined_raw}, "colors": colors}

static func label(gem: Dictionary) -> String:
	if not is_skill(gem): return "Gem (tier %d): +%d %s" % [int(gem.get("tier", 1)), int(gem.get("stat_value", 0)), String(gem.get("stat_label", ""))]
	var skill_name := String(gem.get("skill_name", "Skill"))
	var rank_suffix := skill_name.to_lower().find("lv.")
	if rank_suffix >= 0: skill_name = skill_name.left(rank_suffix).strip_edges()
	return "%s Gem · Lv.%d" % [skill_name, int(gem.get("skill_level", 1))]

static func type_label(type_id: StringName) -> String:
	if type_id == &"base:type/none": return "Non-elemental"
	return "Electric" if type_id == &"base:type/energy" else String(type_id).get_file().capitalize()

static func _error(message: String) -> Dictionary:
	return {"ok": false, "code": "skill_gem_unavailable", "message": message}
