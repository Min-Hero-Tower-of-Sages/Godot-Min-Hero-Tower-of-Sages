extends SceneTree

var CATALOG: ContentCatalog = preload("res://content/imported/recovered-20260911/catalog.tres")
var checks := 0
var failures: Array[String] = []
var emitted: Array[BattleEvent] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(CATALOG.ensure_index().is_empty(), "catalog remains valid")
	var policy_count := 0
	for definition in CATALOG._by_id.values():
		if not definition is MoveDefinition: continue
		for effect in definition.effects:
			if effect.kind != EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS: continue
			policy_count += 1
			var expected := EffectDefinition.RemovalPolicy.DEBUFFS_ONLY if effect.target_scope == EffectDefinition.TargetScope.ALLY_TARGETS else EffectDefinition.RemovalPolicy.BUFFS_ONLY
			_check(effect.removal_policy == expected, "content policy for %s" % effect.id)
	_check(policy_count == 42, "all 21 move definitions have both target policies")
	var mixed := MoveDefinition.new()
	mixed.id = &"test:move/mixed"
	for kind in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL, EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT]:
		var component := EffectDefinition.new()
		component.id = StringName("test:effect/%d" % kind)
		component.kind = kind
		component.amount = 10
		component.duration = 3
		mixed.effects.append(component)
	CATALOG._by_id[mixed.id] = mixed
	var actor := CombatantState.from_setup({"instance_id": "caster", "max_health": 200, "attack": 10, "healing": 10})
	var target := _target(mixed.id)
	var before := target.to_dict()
	_cast(actor, target, EffectDefinition.RemovalPolicy.DEBUFFS_ONLY)
	_check(target.stat_stages == {&"base:stat/attack": 2}, "cleanse preserves positive stages")
	_check(not target.frozen and not target.stunned and target.turns_frozen == 0, "cleanse removes stun/freeze")
	_check(target.statuses.size() == 2, "mixed beneficial components and unknown status survive")
	_check(not ConditionEffectExecutor.is_effect_active(target.statuses[0], mixed.effects[0]), "DOT component suppressed")
	_check(ConditionEffectExecutor.is_effect_active(target.statuses[0], mixed.effects[1]), "HOT component remains")
	_check(is_equal_approx(LegacyCombatModifiers.armor_rate(target, CATALOG, {}), 0.9), "armor remains effective")
	_check(is_equal_approx(LegacyCombatModifiers.reflect_rate(target, CATALOG, {}), 0.1), "reflect remains effective")
	_check(target.shield == 7 and target.current_exhaust == 2 and target.cooldowns == {&"test:move/cooldown": 3}, "shield/exhaust/cooldowns untouched")
	var visible := BattlePresentationState.apply_event(before, emitted.back())
	_check(visible.statuses == target.statuses and visible.stat_stages == target.stat_stages and not visible.frozen, "presentation uses selective impact state")
	var roundtrip := CombatantState.from_snapshot(JSON.parse_string(JSON.stringify(target.to_dict())))
	_check(not ConditionEffectExecutor.is_effect_active(roundtrip.statuses[0], mixed.effects[0]), "suppression survives JSON snapshot")
	var engine := BattleEngine.new()
	engine._content = CATALOG
	engine._rng = BattleRng.new(1)
	engine._state.combatants = {actor.instance_id: actor, target.instance_id: target}
	engine._tick_periodic_effects()
	_check(target.health > 100, "cleansed mixed status ticks healing, not damage")
	_check(int(target.statuses[0].turns) == 1, "remaining effects retain duration progression")
	target = _target(mixed.id)
	before = target.to_dict()
	_cast(actor, target, EffectDefinition.RemovalPolicy.BUFFS_ONLY)
	_check(target.stat_stages == {&"base:stat/speed": -2}, "dispel preserves negative stages")
	_check(target.frozen and target.stunned and target.turns_frozen == 2, "dispel preserves stun/freeze")
	_check(ConditionEffectExecutor.is_effect_active(target.statuses[0], mixed.effects[0]) and not ConditionEffectExecutor.is_effect_active(target.statuses[0], mixed.effects[1]), "dispel removes HOT, keeps DOT")
	_check(is_equal_approx(LegacyCombatModifiers.armor_rate(target, CATALOG, {}), 1.0) and is_zero_approx(LegacyCombatModifiers.reflect_rate(target, CATALOG, {})), "dispel suppresses armor and reflect")
	visible = BattlePresentationState.apply_event(before, emitted.back())
	_check(visible.frozen and visible.stunned and visible.statuses == target.statuses, "display preserves enemy debuffs")
	var periodic_context := {"actor": actor, "target": target, "move": mixed, "emit": _capture}
	PeriodicEffectExecutor.new().execute(mixed.effects[0], periodic_context)
	_check(not target.statuses[0].has("suppressed_effect_ids") and target.statuses[0].turns == 0, "reapplication restores source components")
	_cast(actor, target, EffectDefinition.RemovalPolicy.BOTH)
	_check(target.statuses.is_empty() and target.stat_stages.is_empty() and not target.frozen and not target.stunned, "explicit full-clear remains supported")
	visible = BattlePresentationState.apply_event(before, BattleEvent.new(0, &"buffs_debuffs_cleared"))
	_check(visible.statuses.is_empty() and visible.stat_stages.is_empty(), "legacy full-clear events remain supported")
	var tooltip := BattleMoveTooltip.new()
	root.add_child(tooltip)
	tooltip.show_move(CATALOG.get_definition(&"base:move/cleansing_heal/tier1"))
	_check(tooltip.details.text.contains("Cleanse Ally Debuffs") and not tooltip.details.text.contains("Remove Enemy Buffs") and tooltip.details.text.contains("20%"), "Cleansing Heal tooltip shows only active target and unchanged chance")
	tooltip.show_move(CATALOG.get_definition(&"base:move/blow_by/tier1"))
	_check(tooltip.details.text.contains("Remove Enemy Buffs") and not tooltip.details.text.contains("Cleanse Ally Debuffs"), "Blow By does not gain allied cleansing")
	tooltip.free()
	_check_live_casts()
	CATALOG._by_id.erase(mixed.id)
	for failure in failures: push_error(failure)
	print("%s: selective cleansing (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _target(move_id: StringName) -> CombatantState:
	var target := CombatantState.from_setup({"instance_id": "target", "max_health": 200, "health": 100})
	target.statuses = [{"kind": &"periodic", "move_id": move_id, "source_id": &"caster", "turns": 0}, {"kind": &"unknown_extension"}]
	target.stat_stages = {&"base:stat/attack": 2, &"base:stat/speed": -2}
	target.stunned = true
	target.frozen = true
	target.turns_frozen = 2
	target.shield = 7
	target.current_exhaust = 2
	target.cooldowns = {&"test:move/cooldown": 3}
	return target

func _cast(actor: CombatantState, target: CombatantState, policy: EffectDefinition.RemovalPolicy) -> void:
	var effect := EffectDefinition.new()
	effect.kind = EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS
	effect.removal_policy = policy
	ConditionEffectExecutor.new().execute(effect, {"actor": actor, "target": target, "content": CATALOG, "emit": _capture})

func _capture(kind: StringName, actor_id: StringName, target_id: StringName, values: Dictionary) -> void:
	emitted.append(BattleEvent.new(emitted.size(), kind, actor_id, target_id, values))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _check_live_casts() -> void:
	for move_id in [&"base:move/blow_by/tier1", &"base:move/cleansing_heal/tier1"]:
		var is_cleanse: bool = String(move_id).contains("cleansing_heal")
		var found_success := false
		for seed in range(1, 30):
			var engine := BattleEngine.new()
			var rules := RuleSetDefinition.new()
			var setup := {"tie_first_team": 0, "combatants": [
				{"instance_id": "caster", "definition_id": "base:minion/fire_pig_1", "team": 0, "speed": 100, "max_health": 200, "max_energy": 100, "move_ids": [move_id]},
				{"instance_id": "ally", "definition_id": "base:minion/fire_pig_1", "team": 0, "speed": 2, "max_health": 200, "move_ids": ["base:move/claw/tier1"]},
				{"instance_id": "enemy", "definition_id": "base:minion/fire_pig_1", "team": 1, "speed": 1, "max_health": 200, "move_ids": ["base:move/claw/tier1"]}]}
			var started := engine.start(setup, CATALOG, rules, BattleRng.new(seed))
			_check(started.accepted, "live cast setup accepted")
			if not started.accepted: break
			var target_id: StringName = &"ally" if is_cleanse else &"enemy"
			var target: CombatantState = engine._state.combatants[target_id]
			target.stat_stages = {&"base:stat/attack": 2, &"base:stat/speed": -2}
			target.health = 100
			var command := BattleCommand.new(&"caster", BattleCommand.Kind.USE_MOVE, move_id, [target_id], engine._state.revision)
			var twin := BattleEngine.new()
			twin.start(setup, CATALOG, rules, BattleRng.new(seed))
			twin.restore(JSON.parse_string(JSON.stringify(engine.snapshot())))
			var response := engine.submit(command)
			var twin_response := twin.submit(command)
			_check(response.accepted and twin_response.accepted, "live command accepted")
			# JSON turns dictionary integers into floats; compare normalized facts,
			# not the spelling of 2 versus 2.0 in the serialized text.
			_check(JSON.parse_string(JSON.stringify(engine.snapshot())) == JSON.parse_string(JSON.stringify(twin.snapshot())), "snapshot-restored command resolves identically")
			for event in response.events:
				if event.kind != &"buffs_debuffs_cleared": continue
				found_success = true
				_check(event.target_id == target_id, "clear event stays on chosen target")
				_check(event.values.stat_stages == {&"base:stat/attack": 2} if is_cleanse else event.values.stat_stages == {&"base:stat/speed": -2}, "live move preserves the opposite polarity")
			if found_success: break
		_check(found_success, "original clearing chance can succeed for %s" % move_id)
