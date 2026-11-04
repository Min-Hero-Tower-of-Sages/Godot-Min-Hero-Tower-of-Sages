extends SceneTree

## The "Piercing Over-Time" save mod: DOT/HOT ticks skip the type chart while
## direct hits keep it. Off (the recovered Flash behavior), a Burn tick on a
## fire minion is resisted, exactly like OwnedMinion.TickDotsAndHots.
## godot --headless --path . --script res://tests/piercing_over_time_smoke.gd

var catalog: ContentCatalog = preload("res://content/imported/recovered-20260911/catalog.tres")

func _initialize() -> void:
	assert(catalog.ensure_index().is_empty())
	var resisted := _burn_tick(false)
	var pierced := _burn_tick(true)
	assert(resisted.effectiveness < 0.99, "Default Burn ticks are resisted by fire minions (source behavior)")
	assert(is_equal_approx(pierced.effectiveness, 1.0), "Piercing Over-Time ticks ignore the target's types")
	assert(pierced.amount > resisted.amount, "Piercing ticks deal more to a resistant type")

	# The rule is part of the battle snapshot, so resumed and replayed battles keep it.
	var engine := _engine(true)
	var restored := BattleEngine.new()
	assert(restored.start(_setup(false), catalog, RuleSetDefinition.new(), BattleRng.new(1)).accepted)
	restored.restore(engine.snapshot())
	assert(restored.periodic_ignores_types(), "Snapshot restore keeps the over-time rule")

	# Save mod plumbing: a known, toggleable Gameplay Tweaks option.
	assert(CampaignModService.option_index("piercing_over_time") >= 0)
	assert(CampaignModService.normalize({"piercing_over_time": true}).get("piercing_over_time", false))
	var gameplay: Dictionary = CampaignModService.CATEGORIES.filter(func(category: Dictionary) -> bool: return category.id == "gameplay")[0]
	assert("piercing_over_time" in gameplay.groups)

	# Battle hints drop the over-time part of a matchup when the rule is on.
	var dot_only := MoveDefinition.new()
	dot_only.type_id = &"base:type/fire"
	var tick := EffectDefinition.new()
	tick.kind = EffectDefinition.Kind.PERIODIC_DAMAGE
	tick.amount = 5
	tick.uses_type_effectiveness = true
	tick.target_scope = EffectDefinition.TargetScope.ENEMY_TARGETS
	dot_only.effects = [tick]
	var target := {"instance_id": "enemy", "team": 1, "type_ids": [&"base:type/fire"]}
	assert(not TypeEffectivenessPreview.hints(dot_only, &"caster", 0, target, catalog.get_type_chart()).is_empty())
	assert(TypeEffectivenessPreview.hints(dot_only, &"caster", 0, target, catalog.get_type_chart(), true, false).is_empty())
	print("PASS: Piercing Over-Time ticks, default source resistance, snapshot restore, mod registration and battle hints")
	quit()

func _setup(pierce: bool) -> Dictionary:
	return {"tie_first_team": 0, "periodic_ignores_types": pierce, "combatants": [
		{"instance_id": "caster", "definition_id": "base:minion/fire_pig_1", "team": 0, "speed": 100, "level": 30, "max_health": 300, "max_energy": 200, "energy": 120, "attack": 60, "max_attack_stat": 120.0, "move_ids": ["base:move/burn/tier1"]},
		{"instance_id": "enemy", "definition_id": "base:minion/fire_frog_1", "type_ids": ["base:type/fire"], "team": 1, "speed": 1, "level": 30, "max_health": 300, "max_energy": 80, "move_ids": ["base:move/claw/tier1"]}]}

func _engine(pierce: bool) -> BattleEngine:
	var engine := BattleEngine.new()
	assert(engine.start(_setup(pierce), catalog, RuleSetDefinition.new(), BattleRng.new(1)).accepted)
	return engine

func _burn_tick(pierce: bool) -> Dictionary:
	var engine := _engine(pierce)
	assert(engine.periodic_ignores_types() == pierce)
	var enemy: CombatantState = engine._state.combatants[&"enemy"]
	enemy.statuses.append({"kind": "periodic", "move_id": "base:move/burn/tier1", "source_id": "caster", "turns": 0})
	engine._current_events = []
	engine._tick_periodic_effects()
	for event in engine._current_events:
		if event.kind == &"periodic_tick": return {"effectiveness": float(event.values.effectiveness), "amount": int(event.values.amount)}
	assert(false, "Burn ticked")
	return {}
