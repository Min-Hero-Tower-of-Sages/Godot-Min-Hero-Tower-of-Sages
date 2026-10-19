class_name TypeEffectivenessPreview
extends RefCounted

const GOOD := Color8(130, 222, 118)
const WEAK := Color8(255, 183, 109)
const NORMAL := Color8(235, 234, 235)

static func multiplier_text(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix(".") if not is_equal_approx(value, roundf(value)) else str(int(roundf(value)))

static func applicable_kinds(move: MoveDefinition, actor_id: StringName, actor_team: int, target: Dictionary) -> Array[bool]:
	var result: Array[bool] = [] # false: damage, true: healing
	for effect in move.effects:
		if effect == null or not effect.uses_type_effectiveness or (effect.amount == 0 and effect.random_bonus == 0): continue
		if not effect.kind in [EffectDefinition.Kind.DAMAGE, EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.HEAL, EffectDefinition.Kind.PERIODIC_HEAL]: continue
		var allied := int(target.get("team", -1)) == actor_team
		match effect.target_scope:
			EffectDefinition.TargetScope.ACTOR:
				if StringName(target.get("instance_id", "")) != actor_id: continue
			EffectDefinition.TargetScope.ENEMY_TARGETS:
				if allied: continue
			EffectDefinition.TargetScope.ALLY_TARGETS, EffectDefinition.TargetScope.ALLIED_TEAM:
				if not allied: continue
		var healing := effect.kind in [EffectDefinition.Kind.HEAL, EffectDefinition.Kind.PERIODIC_HEAL]
		if healing not in result: result.append(healing)
	return result

static func hints(move: MoveDefinition, actor_id: StringName, actor_team: int, target: Dictionary, chart: TypeChartDefinition, known: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kinds := applicable_kinds(move, actor_id, actor_team, target)
	if kinds.is_empty() or chart == null: return result
	if not known: return [{"text": "Unknown matchup", "compact": "?", "color": NORMAL}]
	var types: Array[StringName] = []
	types.assign(target.get("type_ids", []))
	for healing in kinds:
		var value := chart.combined_multiplier(move.type_id, types, healing)
		var strong := value > 1.00001
		var weak := value < 0.99999
		var caption: String
		if healing: caption = "Healing boosted" if strong else "Healing reduced" if weak else "Normal healing"
		else: caption = "Super effective" if strong else "Not very effective" if weak else "Normal"
		var compact := ("♥" if healing else "") + ("↑" if strong else "↓" if weak else "") + " ×" + multiplier_text(value)
		result.append({"text": "%s · ×%s" % [caption, multiplier_text(value)], "compact": compact.strip_edges(), "color": GOOD if strong else WEAK if weak else NORMAL, "multiplier": value, "healing": healing})
	return result
