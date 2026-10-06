class_name BattleEngine
extends RefCounted

const LegacyRolls = preload("res://src/domain/battle/legacy_move_rolls.gd")
const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyModifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")
const LegacyAi = preload("res://src/domain/battle/legacy_ai_planner.gd")
const BATTLE_RESULT_SCRIPT = preload("res://src/domain/battle/battle_result.gd")
const RULE_MODULE_CONTEXT_SCRIPT = preload("res://src/domain/battle/battle_rule_context.gd")

var _content: ContentCatalog
var _rules: RuleSetDefinition
var _rng: BattleRng
var _type_chart: TypeChartDefinition
var _shared_amounts: Dictionary = {}
var _state := BattleState.new()
var _event_sequence: int = 0
var _current_events: Array[BattleEvent] = []
var _ai := LegacyAi.new()
var _timer_actor: CombatantState = null
var _rule_modules: Array[BattleRuleModule] = []
var _source_stat_context: Dictionary = {}

func start(setup: Dictionary, content: ContentCatalog, rules: RuleSetDefinition, rng: BattleRng) -> BattleResponse:
	_content = content
	_rules = rules
	_rng = rng
	_state = BattleState.new()
	_current_events = []
	_ai.reset()
	_timer_actor = null
	_rule_modules.clear()
	_source_stat_context = setup.get("source_stat_context", {}).duplicate(true)
	if _rules == null:
		return BattleResponse.rejected(0, &"invalid_rules", "ruleset is missing")
	for index in _rules.rule_modules.size():
		var resource := _rules.rule_modules[index]
		if resource == null:
			return BattleResponse.rejected(0, &"invalid_rules", "ruleset module at index %d is null" % index)
		if not resource is BattleRuleModule:
			return BattleResponse.rejected(0, &"invalid_rules", "ruleset module at index %d (%s) must extend BattleRuleModule" % [index, resource.get_class()])
		# Ruleset definitions are shared catalog resources; each battle gets its
		# own module instance so extension state cannot leak into later battles.
		var battle_module := resource.duplicate(true) as BattleRuleModule
		if battle_module == null:
			return BattleResponse.rejected(0, &"invalid_rules", "ruleset module at index %d could not be duplicated" % index)
		_rule_modules.append(battle_module)
	_state.battle_id = StringName(setup.get("battle_id", "battle"))
	# BattleScreen names this flag "ties go to player", but its actual insertion
	# order puts opponents first when the activation roll is above 50%.
	_state.tie_first_team = int(setup.tie_first_team) if setup.has("tie_first_team") else (1 if _rng.next_percent_value() > 50.0 else 0)
	var errors := _content.ensure_index()
	if not errors.is_empty():
		return BattleResponse.rejected(0, &"invalid_content", "\n".join(errors))
	_type_chart = _content.get_type_chart()
	for entry in setup.get("combatants", []):
		var combatant := CombatantState.from_setup(entry)
		if combatant.instance_id.is_empty() or _state.combatants.has(combatant.instance_id):
			return BattleResponse.rejected(0, &"invalid_setup", "combatant IDs must be non-empty and unique")
		if not _content.has_definition(combatant.definition_id):
			return BattleResponse.rejected(0, &"invalid_setup", "missing minion definition %s" % combatant.definition_id)
		for move_id in combatant.move_ids:
			if not _content.get_definition(move_id) is MoveDefinition:
				return BattleResponse.rejected(0, &"invalid_setup", "missing move definition %s" % move_id)
		_state.combatants[combatant.instance_id] = combatant
	if _state.living_team_members(0).is_empty() or _state.living_team_members(1).is_empty():
		return BattleResponse.rejected(0, &"invalid_setup", "both teams require a living combatant")
	_emit(&"battle_started", &"", &"", {"battle_id": String(_state.battle_id), "round": 1})
	_initialize_modifier_state()
	var module_context := RULE_MODULE_CONTEXT_SCRIPT.new(_state, _content, _rules.configuration) as BattleRuleContext
	for module in _rule_modules:
		module.on_battle_started(module_context)
	var modifier_error := _validate_modifier_state()
	if not modifier_error.is_empty(): return BattleResponse.rejected(0, &"invalid_setup", modifier_error)
	_refresh_derived_maxima()
	if bool(_rules.configuration.get("refill_on_activation", false)):
		# BattleScreen.StartActivate heals after the trainer's global stone buff
		# is available. Campaign setup's pre-aura maxima are not the final maxima.
		for member in _state.combatants.values():
			member.health = member.max_health
			member.energy = member.max_energy
	_apply_round_shields()
	_build_turn_order()
	_state.phase = BattleState.Phase.DECISION
	_activate_next_actor()
	return BattleResponse.success(_state.revision, _current_events)

func get_decision() -> Dictionary:
	if _state.phase != BattleState.Phase.DECISION: return {}
	var actor := _state.combatants[_state.active_actor_id] as CombatantState
	var legal_moves: Array[Dictionary] = []
	for move_id in _usable_move_ids(actor):
		var move := _content.get_definition(move_id) as MoveDefinition
		if move == null or not move.available or actor.energy < move.energy_cost or int(actor.cooldowns.get(move_id, 0)) > 0: continue
		var targets := _legal_targets(actor, move)
		if targets.is_empty() and move_id != LegacyAi.DESPERATION_ID: continue
		legal_moves.append({"move_id": String(move_id), "target_ids": targets.map(func(target: CombatantState): return String(target.instance_id))})
	return {"revision": _state.revision, "actor_id": String(actor.instance_id), "team": actor.team, "legal_moves": legal_moves, "can_forfeit": true}

func submit_ai_turn() -> BattleResponse:
	if _state.phase != BattleState.Phase.DECISION:
		return BattleResponse.rejected(_state.revision, &"not_awaiting_command", "battle is not awaiting a command")
	var actor := _state.combatants[_state.active_actor_id] as CombatantState
	var ai_teams: Array = _rules.configuration.get("ai_teams", [1])
	if actor.team not in ai_teams:
		return BattleResponse.rejected(_state.revision, &"not_ai_actor", "active actor is not controlled by AI")
	var decision := get_decision()
	var legal_moves: Array = decision.get("legal_moves", [])
	if legal_moves.is_empty():
		return _skip_ai_turn(actor, &"no_legal_move")
	var normal_legal_moves: Array = legal_moves.filter(func(legal_move: Dictionary): return StringName(legal_move.get("move_id", "")) != LegacyAi.DESPERATION_ID)
	var desperation_legal_moves: Array = legal_moves.filter(func(legal_move: Dictionary): return StringName(legal_move.get("move_id", "")) == LegacyAi.DESPERATION_ID)
	var choice := _fallback_ai_choice(desperation_legal_moves) if normal_legal_moves.is_empty() and not desperation_legal_moves.is_empty() else _ai.choose(actor, _state, _content, _type_chart, _rules.configuration.get("ai_difficulty", {}), _rng)
	if not _ai_choice_is_legal(choice, legal_moves):
		choice = _fallback_ai_choice(legal_moves)
	if choice.is_empty():
		return _skip_ai_turn(actor, &"no_legal_move")
	var response := submit(BattleCommand.new(actor.instance_id, BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), choice.target_ids, _state.revision))
	if not response.accepted:
		# A bad planner result must never send the UI into a retry loop on the
		# same decision. This should only be reachable if state changed between
		# planning and submission, so preserve the reason in the turn event.
		return _skip_ai_turn(actor, response.error_code)
	return response

func _ai_choice_is_legal(choice: Dictionary, legal_moves: Array) -> bool:
	if choice.is_empty(): return false
	for legal_move in legal_moves:
		if StringName(legal_move.get("move_id", "")) != StringName(choice.get("move_id", "")): continue
		var move := _content.get_definition(StringName(legal_move.move_id)) as MoveDefinition
		if move == null: return false
		if move.target_mode != MoveDefinition.TargetMode.CHOSEN: return true
		var legal_targets: Array = legal_move.get("target_ids", [])
		var chosen_targets: Array = choice.get("target_ids", [])
		if chosen_targets.size() != mini(move.target_count, legal_targets.size()): return false
		var unique: Dictionary = {}
		for target_id in chosen_targets:
			if target_id not in legal_targets or unique.has(target_id): return false
			unique[target_id] = true
		return true
	return false

func _fallback_ai_choice(legal_moves: Array) -> Dictionary:
	if legal_moves.is_empty(): return {}
	var fallback: Dictionary = legal_moves[0]
	var move := _content.get_definition(StringName(fallback.get("move_id", ""))) as MoveDefinition
	if move == null: return {}
	var target_ids: Array[StringName] = []
	if move.target_mode == MoveDefinition.TargetMode.CHOSEN:
		var legal_targets: Array = fallback.get("target_ids", [])
		for index in mini(move.target_count, legal_targets.size()):
			target_ids.append(StringName(legal_targets[index]))
	return {"move_id": move.id, "target_ids": target_ids}

func _skip_ai_turn(actor: CombatantState, reason: StringName) -> BattleResponse:
	if _state.phase != BattleState.Phase.DECISION or _state.active_actor_id != actor.instance_id:
		return BattleResponse.rejected(_state.revision, &"not_awaiting_command", "AI actor is no longer awaiting a decision")
	_current_events = []
	_emit(&"turn_skipped", actor.instance_id, actor.instance_id, {"reason": String(reason)})
	_advance_turn()
	_state.revision += 1
	return BattleResponse.success(_state.revision, _current_events)

func submit(command: BattleCommand) -> BattleResponse:
	var error := _validate(command)
	if not error.is_empty(): return BattleResponse.rejected(_state.revision, StringName(error.code), String(error.message))
	_current_events = []
	var actor := _state.combatants[command.actor_id] as CombatantState
	if command.kind == BattleCommand.Kind.FORFEIT:
		_finish(1 - actor.team, &"forfeit")
	else:
		var move := _content.get_definition(command.move_id) as MoveDefinition
		if move.charge_turns > 0:
			var locked_targets := _resolve_targets(actor, move, command.target_ids)
			actor.charge_move_id = move.id
			actor.charge_target_ids.assign(locked_targets.map(func(target: CombatantState): return target.instance_id))
			actor.current_charge = 1
			_emit(&"charge_started", actor.instance_id, actor.instance_id, {"move_id": String(move.id), "charge": 1, "required": move.charge_turns})
			_advance_turn()
		else:
			_perform_move(actor, move, command.target_ids)
	_state.revision += 1
	return BattleResponse.success(_state.revision, _current_events)

func _perform_move(actor: CombatantState, move: MoveDefinition, target_ids: Array[StringName], locked_targets: bool = false, advance_after: bool = true) -> void:
	_shared_amounts.clear()
	actor.energy -= move.energy_cost
	_emit(&"cost_paid", actor.instance_id, actor.instance_id, {"move_id": String(move.id), "energy_cost": move.energy_cost, "energy": actor.energy})
	# Source selects/locks recipients before LoadUpTheQueue draws accuracy.
	# Miss playback still needs those recipients, including random targets.
	var targets := _resolve_locked_targets(target_ids) if locked_targets else _resolve_targets(actor, move, target_ids)
	var legacy_rolls := LegacyRolls.draw(_rng)
	_execute_before_accuracy(actor, move)
	var hit := legacy_rolls.hits(move.accuracy_percent)
	_emit(&"move_used", actor.instance_id, &"", {"move_id": String(move.id), "hit": hit, "target_ids": targets.map(func(target: CombatantState): return String(target.instance_id)), "visual_callouts": _source_visual_callouts(actor, move, targets, legacy_rolls) if hit else {}, "stat_callouts": _source_stat_callouts(actor, move, targets, legacy_rolls) if hit else [], "redirection_callouts": _source_redirection_callouts(actor, move) if hit else []})
	if not hit:
		_emit(&"missed", actor.instance_id, targets[0].instance_id if not targets.is_empty() else &"", {"move_id": String(move.id), "target_ids": targets.map(func(target: CombatantState): return String(target.instance_id))})
	else:
		actor.current_exhaust = move.exhaust_turns
		_execute_target_phase(EffectDefinition.Phase.ENEMY_TARGET, actor, move, targets, legacy_rolls)
		_execute_target_phase(EffectDefinition.Phase.ALLY_TARGET, actor, move, targets, legacy_rolls)
		_execute_actor_after_targets(actor, move, targets, legacy_rolls)
		if move.cooldown_turns > 0: actor.cooldowns[move.id] = move.cooldown_turns + 1
	_refresh_derived_maxima()
	if advance_after:
		_advance_turn()
	elif not _process_post_action_modifiers():
		_refresh_derived_maxima()
		_build_turn_order()
		_activate_next_actor()

func _source_redirection_callouts(actor: CombatantState, move: MoveDefinition) -> Array[String]:
	var ids: Array[String] = []
	if not move.effects.any(func(effect: EffectDefinition) -> bool: return effect != null and effect.kind == EffectDefinition.Kind.DAMAGE and (effect.amount > 0 or effect.random_bonus > 0)):
		return ids
	# ApplyEffects visits living opposing redirectors once, in source slot order,
	# before looping damage recipients (even when redirected damage rounds to 0).
	var redirectors: Array[CombatantState] = []
	for combatant in _state.combatants.values():
		if combatant.team != actor.team and combatant.health > 0 and not combatant.defeated and LegacyModifiers.redirect_percent(combatant, _content) > 0.0:
			redirectors.append(combatant)
	redirectors.sort_custom(func(left: CombatantState, right: CombatantState) -> bool: return left.slot_index < right.slot_index if left.slot_index != right.slot_index else String(left.instance_id) < String(right.instance_id))
	for redirector in redirectors:
		ids.append(String(redirector.instance_id))
	return ids

func _source_visual_callouts(actor: CombatantState, move: MoveDefinition, targets: Array[CombatantState], rolls: LegacyMoveRolls) -> Dictionary:
	var result: Dictionary = {}
	for target in targets:
		if target.team == actor.team:
			continue
		var kinds: Array[String] = []
		for kind in [EffectDefinition.Kind.STUN, EffectDefinition.Kind.FREEZE]:
			for effect in move.effects:
				if effect != null and effect.kind == kind and effect.roll_scope == EffectDefinition.RollScope.SHARED_MOVE and effect.target_scope in [EffectDefinition.TargetScope.ENEMY_TARGETS, EffectDefinition.TargetScope.BOTH_TARGET_GROUPS] and _effect_applies(effect, rolls):
					kinds.append("stunned" if kind == EffectDefinition.Kind.STUN else "frozen")
					break
		if LegacyModifiers.reflect_rate(target, _content, _state.combatants) > 0.0:
			kinds.append("reflection")
		if not kinds.is_empty():
			result[String(target.instance_id)] = kinds
	return result

func _source_stat_callouts(actor: CombatantState, move: MoveDefinition, targets: Array[CombatantState], rolls: LegacyMoveRolls) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# BaseMoveSystem: self buffs, self debuffs, target buffs, target debuffs.
	for self_group in [true, false]:
		for positive in [true, false]:
			var effects: Array[EffectDefinition] = []
			for effect in move.effects:
				if effect == null or effect.kind != EffectDefinition.Kind.STAT_STAGE or effect.roll_scope != EffectDefinition.RollScope.SHARED_MOVE:
					continue
				if (effect.target_scope == EffectDefinition.TargetScope.ACTOR) != self_group or (effect.amount > 0) != positive or effect.amount == 0:
					continue
				if rolls.applies_buff(effect.chance_percent): effects.append(effect)
			var recipients: Array[CombatantState] = []
			if self_group:
				recipients.append(actor)
			else:
				recipients = _targets_for_scope(actor, move, targets, EffectDefinition.TargetScope.BOTH_TARGET_GROUPS)
			# Source's target loops visit allies before enemies, preserving the
			# selected order within each group.
			var ordered: Array[CombatantState] = []
			for allied in [true, false]:
				for recipient in recipients:
					if (recipient.team == actor.team) == allied: ordered.append(recipient)
			for recipient in ordered:
				for effect in effects:
					if not self_group and recipient not in _targets_for_scope(actor, move, targets, effect.target_scope): continue
					result.append({"target_id": String(recipient.instance_id), "stat_type_id": String(effect.stat_type_id), "amount": effect.amount, "lead_seconds": 0.1 if self_group or positive and recipient.team == actor.team else 0.0})
	return result

func _execute_before_accuracy(actor: CombatantState, move: MoveDefinition) -> void:
	for effect in move.effects:
		if effect == null or effect.phase != EffectDefinition.Phase.BEFORE_ACCURACY: continue
		if effect.chance_percent < 100 and not _rng.roll_percent(effect.chance_percent): continue
		var executor := effect.executor.new() as EffectExecutor if effect.executor != null else null
		if executor == null:
			push_error("Effect %s executor does not extend EffectExecutor" % effect.id)
			continue
		executor.execute(effect, {"actor": actor, "target": actor, "move": move, "content": _content, "combatants": _state.combatants, "type_chart": _type_chart, "shared_amounts": _shared_amounts, "rng": _rng, "emit": Callable(self, "_emit")})

func _execute_target_phase(phase: EffectDefinition.Phase, actor: CombatantState, move: MoveDefinition, selected: Array[CombatantState], rolls: LegacyMoveRolls) -> void:
	var scope := EffectDefinition.TargetScope.ENEMY_TARGETS if phase == EffectDefinition.Phase.ENEMY_TARGET else EffectDefinition.TargetScope.ALLY_TARGETS
	var targets := _targets_for_scope(actor, move, selected, scope)
	for target in targets:
		for effect in move.effects:
			if effect == null or effect.phase != phase: continue
			if not _effect_applies(effect, rolls): continue
			_execute_effect(effect, actor, target, move, rolls)

func _execute_actor_after_targets(actor: CombatantState, move: MoveDefinition, selected: Array[CombatantState], rolls: LegacyMoveRolls) -> void:
	for effect in move.effects:
		if effect == null or effect.phase != EffectDefinition.Phase.ACTOR_AFTER_TARGETS: continue
		if not _effect_applies(effect, rolls): continue
		for target in _targets_for_scope(actor, move, selected, effect.target_scope):
			_execute_effect(effect, actor, target, move, rolls)

func _execute_effect(effect: EffectDefinition, actor: CombatantState, target: CombatantState, move: MoveDefinition, rolls: LegacyMoveRolls) -> void:
	var executor := effect.executor.new() as EffectExecutor if effect.executor != null else null
	if executor == null:
		push_error("Effect %s executor does not extend EffectExecutor" % effect.id)
		return
	executor.execute(effect, {"actor": actor, "target": target, "move": move, "content": _content, "combatants": _state.combatants, "type_chart": _type_chart, "shared_amounts": _shared_amounts, "rng": _rng, "legacy_rolls": rolls, "emit": Callable(self, "_emit")})

func _effect_applies(effect: EffectDefinition, rolls: LegacyMoveRolls) -> bool:
	match effect.roll_scope:
		EffectDefinition.RollScope.SHARED_MOVE:
			match effect.kind:
				EffectDefinition.Kind.STUN: return rolls.applies_stun(effect.chance_percent)
				EffectDefinition.Kind.FREEZE: return rolls.applies_freeze(effect.chance_percent)
				EffectDefinition.Kind.STAT_STAGE: return rolls.applies_buff(effect.chance_percent)
				_: return true
		EffectDefinition.RollScope.PER_TARGET, EffectDefinition.RollScope.PER_EFFECT_TARGET:
			return float(effect.chance_percent) > _rng.next_percent_value()
		_: return true

func _targets_for_scope(actor: CombatantState, move: MoveDefinition, selected: Array[CombatantState], scope: EffectDefinition.TargetScope) -> Array[CombatantState]:
	if scope == EffectDefinition.TargetScope.ACTOR: return [actor]
	var result: Array[CombatantState] = []
	if scope in [EffectDefinition.TargetScope.ALLY_TARGETS, EffectDefinition.TargetScope.BOTH_TARGET_GROUPS]:
		for target in selected:
			if target.team == actor.team: result.append(target)
		if result.is_empty():
			var allies := _state.living_team_members(actor.team)
			for index in mini(move.ally_target_count, allies.size()): result.append(allies[index])
	if scope in [EffectDefinition.TargetScope.ENEMY_TARGETS, EffectDefinition.TargetScope.BOTH_TARGET_GROUPS]:
		var found_enemy := false
		for target in selected:
			if target.team != actor.team:
				result.append(target)
				found_enemy = true
		if not found_enemy:
			var enemies := _state.living_team_members(1 - actor.team)
			for index in mini(move.enemy_target_count, enemies.size()): result.append(enemies[index])
	if scope == EffectDefinition.TargetScope.ALLIED_TEAM: return _state.living_team_members(actor.team)
	return result

func snapshot() -> Dictionary:
	return {"state": _state.snapshot(), "rng": _rng.snapshot(), "event_sequence": _event_sequence, "ai": _ai.snapshot(), "timer_actor": _timer_actor.to_dict() if _timer_actor != null else {}, "source_stat_context": _source_stat_context.duplicate(true)}

func restore(data: Dictionary) -> void:
	_state.restore(data.state)
	_rng.restore(data.rng)
	_event_sequence = int(data.event_sequence)
	_ai.restore(data.get("ai", {}))
	_source_stat_context = data.get("source_stat_context", _source_stat_context).duplicate(true)
	var timer_data := data.get("timer_actor", {}) as Dictionary
	_timer_actor = CombatantState.from_snapshot(timer_data) if not timer_data.is_empty() else null

func get_result():
	var result = BATTLE_RESULT_SCRIPT.new()
	if _state.phase == BattleState.Phase.COMPLETE:
		result.battle_id = StringName(_state.result.get("battle_id", ""))
		result.winning_team = int(_state.result.get("winning_team", -1))
		result.reason = StringName(_state.result.get("reason", ""))
		result.rounds = int(_state.result.get("rounds", 0))
		result.participants.assign(_state.result.get("participants", []))
	return result

func _validate(command: BattleCommand) -> Dictionary:
	if _state.phase != BattleState.Phase.DECISION: return {"code": "not_awaiting_command", "message": "battle is not awaiting a command"}
	if command.expected_revision != _state.revision: return {"code": "stale_revision", "message": "expected revision does not match"}
	if command.actor_id != _state.active_actor_id: return {"code": "wrong_actor", "message": "command actor is not active"}
	var actor := _state.combatants.get(command.actor_id) as CombatantState
	if actor == null or actor.defeated: return {"code": "invalid_actor", "message": "actor is unavailable"}
	if command.kind == BattleCommand.Kind.FORFEIT: return {}
	if not command.move_id in _usable_move_ids(actor): return {"code": "unknown_move", "message": "actor does not know that move"}
	var move := _content.get_definition(command.move_id) as MoveDefinition
	if move == null: return {"code": "unknown_move", "message": "move is not registered"}
	if not move.available: return {"code": "unavailable_move", "message": "move is declared by the source but has no constructed implementation"}
	if actor.energy < move.energy_cost: return {"code": "insufficient_energy", "message": "actor cannot pay the move cost"}
	if int(actor.cooldowns.get(move.id, 0)) > 0: return {"code": "cooldown", "message": "move is on cooldown"}
	var legal := _legal_targets(actor, move)
	if move.target_mode == MoveDefinition.TargetMode.CHOSEN:
		# The source commits a chosen move once every remaining legal target has
		# been selected, even when fewer than the move's normal target count live.
		if command.target_ids.size() != mini(move.target_count, legal.size()): return {"code": "invalid_targets", "message": "wrong target count"}
		var unique: Dictionary = {}
		for target_id in command.target_ids:
			if unique.has(target_id): return {"code": "invalid_targets", "message": "duplicate target"}
			unique[target_id] = true
			if not legal.any(func(target: CombatantState): return target.instance_id == target_id): return {"code": "invalid_targets", "message": "target is not legal"}
	return {}

func _usable_move_ids(actor: CombatantState) -> Array[StringName]:
	var ids: Array[StringName] = []
	for move_id in actor.move_ids:
		var move := _content.get_definition(move_id) as MoveDefinition
		if move != null and (move.is_passive or move.is_global_passive):
			continue
		ids.append(move_id)
	var desperation_id := LegacyAi.DESPERATION_ID
	if _content.get_definition(desperation_id) is MoveDefinition and desperation_id not in ids: ids.append(desperation_id)
	return ids

func _legal_targets(actor: CombatantState, move: MoveDefinition) -> Array[CombatantState]:
	if move.target_side == MoveDefinition.TargetSide.SELF: return [actor]
	var team := actor.team if move.target_side == MoveDefinition.TargetSide.ALLY else 1 - actor.team
	var result := _state.living_team_members(team)
	if move.target_side == MoveDefinition.TargetSide.ENEMY:
		result = result.filter(func(target: CombatantState): return not target.battle_mod_shield_active)
	return result

func _resolve_targets(actor: CombatantState, move: MoveDefinition, chosen: Array[StringName]) -> Array[CombatantState]:
	var legal := _legal_targets(actor, move)
	if move.target_mode == MoveDefinition.TargetMode.ALL: return legal
	if move.target_mode == MoveDefinition.TargetMode.RANDOM:
		var picked: Array[CombatantState] = []
		while not legal.is_empty() and picked.size() < move.target_count:
			picked.append(legal.pop_at(_rng.next_int(legal.size())))
		return picked
	var selected: Array[CombatantState] = []
	for id in chosen: selected.append(_state.combatants[id] as CombatantState)
	return selected

func _resolve_locked_targets(ids: Array[StringName]) -> Array[CombatantState]:
	var result: Array[CombatantState] = []
	for id in ids:
		var target := _state.combatants.get(id) as CombatantState
		if target != null: result.append(target)
	return result

func _advance_turn() -> void:
	var remaining := _remaining_actors()
	if not remaining.is_empty():
		if _process_post_action_modifiers(): return
		_refresh_derived_maxima()
		_build_turn_order()
		remaining = _remaining_actors()
		if not remaining.is_empty():
			_activate_next_actor()
			return
	_tick_periodic_effects()
	_state.round_number += 1
	_state.turn_index = 0
	_state.acted_ids.clear()
	for combatant in _state.combatants.values():
		if combatant.defeated or combatant.health <= 0: continue
		for move_id in combatant.cooldowns.keys(): combatant.cooldowns[move_id] = maxi(0, int(combatant.cooldowns[move_id]) - 1)
	_apply_round_shields()
	if _process_post_action_modifiers(): return
	_refresh_derived_maxima()
	_build_turn_order()
	_emit(&"round_started", &"", &"", {"round": _state.round_number})
	_activate_next_actor()

func _activate_next_actor() -> void:
	if _state.phase == BattleState.Phase.COMPLETE: return
	if _maybe_run_move_timer(): return
	var remaining := _remaining_actors()
	if remaining.is_empty(): return
	_state.active_actor_id = remaining[0].instance_id
	_state.turn_index = _state.turn_order.find(_state.active_actor_id)
	_prepare_active_actor()

func _prepare_active_actor() -> void:
	if _state.phase == BattleState.Phase.COMPLETE: return
	var actor := _state.combatants[_state.active_actor_id] as CombatantState
	if actor.instance_id not in _state.acted_ids: _state.acted_ids.append(actor.instance_id)
	if actor.frozen:
		actor.turns_frozen += 1
		var thawed := float(actor.turns_frozen) > 1.0 + _rng.next_unit() * 3.0
		if thawed:
			actor.frozen = false
			_emit(&"thawed", actor.instance_id, actor.instance_id, {"turns_frozen": actor.turns_frozen})
			_emit(&"decision_requested", actor.instance_id, &"", {})
		else:
			_emit(&"frozen_turn_skipped", actor.instance_id, actor.instance_id, {"turns_frozen": actor.turns_frozen})
			_advance_turn()
		return
	if actor.stunned:
		if 50.0 > _rng.next_percent_value():
			_emit(&"stun_resisted", actor.instance_id, actor.instance_id, {})
			_emit(&"decision_requested", actor.instance_id, &"", {})
		else:
			_emit(&"stunned_turn_skipped", actor.instance_id, actor.instance_id, {})
			_advance_turn()
		return
	if not actor.charge_move_id.is_empty():
		var move := _content.get_definition(actor.charge_move_id) as MoveDefinition
		if move == null:
			actor.charge_move_id = &""
			actor.charge_target_ids.clear()
			actor.current_charge = 0
			_emit(&"charge_cancelled", actor.instance_id, actor.instance_id, {"reason": "missing_move"})
			_emit(&"decision_requested", actor.instance_id, &"", {})
		elif actor.current_charge == move.charge_turns:
			var targets := actor.charge_target_ids.duplicate()
			actor.charge_move_id = &""
			actor.charge_target_ids.clear()
			actor.current_charge = 0
			_emit(&"charge_released", actor.instance_id, actor.instance_id, {"move_id": String(move.id)})
			_perform_move(actor, move, targets, true)
		else:
			actor.current_charge += 1
			_emit(&"charge_progressed", actor.instance_id, actor.instance_id, {"move_id": String(move.id), "charge": actor.current_charge, "required": move.charge_turns})
			_advance_turn()
		return
	if actor.current_exhaust > 0:
		actor.current_exhaust -= 1
		_emit(&"exhausted_turn_skipped", actor.instance_id, actor.instance_id, {"remaining": actor.current_exhaust})
		_advance_turn()
		return
	_emit(&"decision_requested", actor.instance_id, &"", {})

func _tick_periodic_effects() -> void:
	var ordered: Array[CombatantState] = []
	for combatant in _state.combatants.values():
		if not combatant.defeated: ordered.append(combatant)
	ordered.sort_custom(func(left: CombatantState, right: CombatantState):
		if left.slot_index != right.slot_index: return left.slot_index < right.slot_index
		if left.team != right.team: return left.team > right.team
		return String(left.instance_id) < String(right.instance_id))
	for target in ordered:
		var net_health := 0.0
		for status_index in range(target.statuses.size() - 1, -1, -1):
			var status: Dictionary = target.statuses[status_index]
			if StringName(status.get("kind", "")) != &"periodic": continue
			var move := _content.get_definition(StringName(status.get("move_id", ""))) as MoveDefinition
			var source := _periodic_source(StringName(status.get("source_id", "")))
			if move == null or source == null:
				target.statuses.remove_at(status_index)
				continue
			var duration := 0
			for effect in move.effects:
				if effect == null or effect.kind not in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL, EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT]: continue
				duration = maxi(duration, effect.duration)
				if effect.kind not in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL]: continue
				var stat := LegacyModifiers.effective_attack(source, _content, _state.combatants) if effect.kind == EffectDefinition.Kind.PERIODIC_DAMAGE else LegacyModifiers.effective_healing(source, _content, _state.combatants)
				var amount := float(LegacyMath.calculate_scaled_amount(effect.amount, effect.random_bonus, stat, source.level, _rng.next_unit()))
				var effectiveness := 1.0
				if effect.uses_type_effectiveness and _type_chart != null:
					effectiveness = _type_chart.combined_multiplier(move.type_id, target.type_ids, effect.kind == EffectDefinition.Kind.PERIODIC_HEAL)
					amount *= effectiveness
				net_health += amount if effect.kind == EffectDefinition.Kind.PERIODIC_HEAL else -amount
				_emit(&"periodic_tick", source.instance_id, target.instance_id, {"move_id": String(move.id), "kind": effect.kind, "amount": int(amount), "effectiveness": effectiveness})
			status.turns = int(status.get("turns", 0)) + 1
			if int(status.turns) >= duration:
				target.statuses.remove_at(status_index)
				_emit(&"periodic_expired", source.instance_id, target.instance_id, {"move_id": String(move.id)})
			else:
				target.statuses[status_index] = status
		_apply_periodic_net(target, int(net_health))

func _periodic_source(instance_id: StringName) -> CombatantState:
	var active := _state.combatants.get(instance_id) as CombatantState
	if active != null: return active
	# Source DOT/HOT arrays retain their OwnedMinion reference. A hidden timer
	# caster or retired original is not a party slot, but remains a valid source.
	if _timer_actor != null and _timer_actor.instance_id == instance_id:
		return _timer_actor
	for retired in _state.retired_combatants:
		if StringName(retired.get("instance_id", "")) == instance_id:
			return CombatantState.from_snapshot(retired)
	return null

func _apply_periodic_net(target: CombatantState, net_health: int) -> void:
	if net_health < 0 and target.battle_mod_shield_active: return
	var applied := net_health
	if net_health < 0 and target.shield > 0:
		target.shield += net_health
		if target.shield > 0:
			applied = 0
		else:
			applied = target.shield
			target.shield = 0
	target.health = clampi(target.health + applied, 0, target.max_health)
	if target.health <= 0: target.defeated = true
	_emit(&"periodic_health_applied", &"", target.instance_id, {"net": net_health, "applied": applied, "health": target.health, "shield": target.shield})

func _build_turn_order() -> void:
	_state.turn_order.clear()
	for combatant in _state.combatants.values():
		if not combatant.defeated: _state.turn_order.append(combatant.instance_id)
	_state.turn_order.sort_custom(func(a: StringName, b: StringName):
		var left := _state.combatants[a] as CombatantState
		var right := _state.combatants[b] as CombatantState
		var left_speed := LegacyModifiers.effective_speed(left, _content, _state.combatants)
		var right_speed := LegacyModifiers.effective_speed(right, _content, _state.combatants)
		if left_speed != right_speed: return left_speed > right_speed
		if left.slot_index != right.slot_index: return left.slot_index < right.slot_index
		if left.team != right.team: return left.team == _state.tie_first_team
		return String(a) < String(b))

func _remaining_actors() -> Array[CombatantState]:
	var result: Array[CombatantState] = []
	for id in _state.turn_order:
		var combatant := _state.combatants.get(id) as CombatantState
		if combatant != null and not combatant.defeated and combatant.instance_id not in _state.acted_ids: result.append(combatant)
	return result

func _refresh_derived_maxima() -> void:
	for combatant in _state.combatants.values():
		combatant.max_health = LegacyModifiers.effective_max_health(combatant, _content, _state.combatants)
		combatant.max_energy = LegacyModifiers.effective_max_energy(combatant, _content, _state.combatants)
		# OwnedMinion.m_currEnergy clamps whenever read or assigned after a maximum
		# change. Health does not clamp merely because CalculateCurrStats ran.
		combatant.energy = mini(combatant.energy, combatant.max_energy)

func _initialize_modifier_state() -> void:
	var resurrection := _rules.configuration.get("battle_modifiers", {}).get("resurrection", {}) as Dictionary
	var counters: Dictionary = {}
	var revives: Dictionary = {}
	for combatant in _state.combatants.values():
		counters[String(combatant.instance_id)] = 0
		revives[String(combatant.instance_id)] = 0
	_state.modifier_state = {
		"resurrection_team": int(resurrection.get("team", 1)),
		"resurrection_turns": int(resurrection.get("turns", 0)),
		"resurrection_counters": counters,
		"resurrection_counts": revives,
		"extra_minions_used": {0: 0, 1: 0},
		"move_timer_counter": 0,
	}
	var timer := _rules.configuration.get("battle_modifiers", {}).get("move_timer", {}) as Dictionary
	if not timer.is_empty():
		var bonus_id := StringName(timer.get("buff_move_id", timer.get("passive_move_id", "")))
		if not bonus_id.is_empty():
			for member in _state.combatants.values():
				if member.team == 0 and bonus_id not in member.battle_bonus_global_move_ids:
					member.battle_bonus_global_move_ids.append(bonus_id)
		var actor_data := (timer.get("actor", {}) as Dictionary).duplicate(true)
		actor_data.instance_id = String(actor_data.get("instance_id", "battle-mod-timer"))
		actor_data.team = int(actor_data.get("team", 1))
		# BattleScreen uses a hidden BMod at the first enemy's effective level.
		if timer.has("source_power"):
			var enemies := _state.living_team_members(1)
			_sort_by_slot(enemies)
			if not enemies.is_empty(): actor_data.level = enemies[0].level
		var definition := _content.get_definition(StringName(actor_data.get("definition_id", ""))) as MinionDefinition
		if definition != null:
			var stats := LegacyMinionStats.current_stats(definition, int(actor_data.get("level", 1)))
			var defaults := {"type_ids": definition.type_ids.duplicate(), "max_health": stats.health, "max_energy": stats.energy, "attack": stats.attack, "healing": stats.healing, "speed": stats.speed, "max_attack_stat": LegacyMinionStats.max_attack_stat(definition), "max_healing_stat": LegacyMinionStats.max_healing_stat(definition)}
			for key in defaults:
				if not actor_data.has(key): actor_data[key] = defaults[key]
			var original: Dictionary = timer.get("actor", {})
			if original.has("attack") and not original.has("max_attack_stat"): actor_data.max_attack_stat = original.attack
			if original.has("healing") and not original.has("max_healing_stat"): actor_data.max_healing_stat = original.healing
		_timer_actor = CombatantState.from_setup(actor_data)

func _validate_modifier_state() -> String:
	var timer := _rules.configuration.get("battle_modifiers", {}).get("move_timer", {}) as Dictionary
	if timer.is_empty(): return ""
	if int(timer.get("interval", 0)) < 0: return "move timer interval cannot be negative"
	var bonus_id := StringName(timer.get("buff_move_id", timer.get("passive_move_id", "")))
	if not bonus_id.is_empty():
		var bonus := _content.get_definition(bonus_id) as MoveDefinition
		if bonus == null or not bonus.is_global_passive: return "move timer bonus requires a global passive move"
	var move := _content.get_definition(StringName(timer.get("move_id", ""))) as MoveDefinition
	if move == null or move.is_passive or move.is_global_passive: return "move timer requires an active move"
	if _timer_actor == null or _timer_actor.instance_id.is_empty() or not _content.has_definition(_timer_actor.definition_id): return "move timer requires a valid modifier actor"
	return ""

func _maybe_run_move_timer() -> bool:
	var timer := _rules.configuration.get("battle_modifiers", {}).get("move_timer", {}) as Dictionary
	if timer.is_empty(): return false
	var interval := int(timer.get("interval", 0))
	var counter := int(_state.modifier_state.get("move_timer_counter", 0))
	if interval - counter != 0:
		_state.modifier_state.move_timer_counter = counter + 1
		return false
	_state.modifier_state.move_timer_counter = 0
	var move := _content.get_definition(StringName(timer.move_id)) as MoveDefinition
	var targets := _random_timer_targets(_timer_actor, move)
	_emit(&"battle_mod_timer_triggered", _timer_actor.instance_id, &"", {"move_id": String(move.id), "interval": interval})
	_perform_move(_timer_actor, move, targets, true, false)
	return true

func _random_timer_targets(actor: CombatantState, move: MoveDefinition) -> Array[StringName]:
	var result: Array[StringName] = []
	var enemies := _state.living_team_members(1 - actor.team).filter(func(target: CombatantState): return not target.battle_mod_shield_active)
	var allies := _state.living_team_members(actor.team)
	for count_and_pool in [[move.enemy_target_count, enemies], [move.ally_target_count, allies]]:
		var count := int(count_and_pool[0])
		var pool: Array = (count_and_pool[1] as Array).duplicate()
		while not pool.is_empty() and count > 0:
			var target := pool.pop_at(_rng.next_int(pool.size())) as CombatantState
			result.append(target.instance_id)
			count -= 1
	return result

func _apply_round_shields() -> void:
	var shield := _rules.configuration.get("battle_modifiers", {}).get("shield", {}) as Dictionary
	if shield.is_empty(): return
	for team in [0, 1]:
		var members := _state.living_team_members(team)
		for member in members: member.battle_mod_shield_active = false
		var requested := int(shield.get("player" if team == 0 else "enemy", 0))
		var count := mini(requested, maxi(0, members.size() - 1))
		var selected: Dictionary = {}
		while selected.size() < count:
			var slot := _rng.next_int(5)
			var candidate := _living_at_slot(team, slot)
			if candidate != null: selected[candidate.instance_id] = candidate
		for member in selected.values(): member.battle_mod_shield_active = true
		_emit(&"battle_mod_shields_assigned", &"", &"", {"team": team, "target_ids": selected.keys().map(func(id): return String(id))})

func _process_post_action_modifiers() -> bool:
	_inject_extra_minions()
	if _state.living_team_members(0).is_empty():
		_finish(1, &"defeat")
		return true
	if _state.living_team_members(1).is_empty():
		_finish(0, &"victory")
		return true
	_release_last_shields()
	_process_resurrection()
	return false

func _release_last_shields() -> void:
	var shield := _rules.configuration.get("battle_modifiers", {}).get("shield", {}) as Dictionary
	if shield.is_empty(): return
	for team in [0, 1]:
		var living := _state.living_team_members(team)
		if living.any(func(member: CombatantState): return not member.battle_mod_shield_active): continue
		var chosen: CombatantState = null
		_sort_by_slot(living)
		for member in living:
			if not member.battle_mod_shield_active: continue
			if chosen == null or _rng.next_percent_value() > 50.0: chosen = member
		if chosen != null:
			chosen.battle_mod_shield_active = false
			_emit(&"battle_mod_shield_removed", &"", chosen.instance_id, {"team": team})

func _process_resurrection() -> void:
	var turns := int(_state.modifier_state.get("resurrection_turns", 0))
	if turns <= 0: return
	var team := int(_state.modifier_state.get("resurrection_team", 1))
	if _state.living_team_members(team).is_empty(): return
	var counters := _state.modifier_state.resurrection_counters as Dictionary
	var counts := _state.modifier_state.resurrection_counts as Dictionary
	var dead: Array[CombatantState] = []
	for combatant in _state.combatants.values():
		if combatant.team == team and combatant.defeated: dead.append(combatant)
	_sort_by_slot(dead)
	for combatant in dead:
		var key := String(combatant.instance_id)
		var elapsed := int(counters.get(key, 0)) + 1
		if elapsed >= turns:
			var revive_count := int(counts.get(key, 0))
			combatant.statuses.clear()
			combatant.stat_stages.clear()
			combatant.frozen = false
			combatant.turns_frozen = 0
			combatant.stunned = false
			combatant.health = maxi(1, int(float(combatant.max_health) / pow(2.0, revive_count + 1)))
			combatant.defeated = false
			counters[key] = 0
			counts[key] = revive_count + 1
			_emit(&"battle_mod_resurrected", &"", combatant.instance_id, {"health": combatant.health, "revive_count": revive_count + 1})
		else:
			counters[key] = elapsed
			_emit(&"battle_mod_resurrection_progressed", &"", combatant.instance_id, {"elapsed": elapsed, "required": turns})
	_state.modifier_state.resurrection_counters = counters
	_state.modifier_state.resurrection_counts = counts

func _inject_extra_minions() -> void:
	var config := _rules.configuration.get("battle_modifiers", {}).get("extra_minions", {}) as Dictionary
	if config.is_empty(): return
	var used := _state.modifier_state.extra_minions_used as Dictionary
	for raw_team in [0, 1]:
		var team_index: int = int(raw_team)
		var team_key: String = "player" if team_index == 0 else "enemy"
		var team_config := config.get(team_key, {}) as Dictionary
		var templates := team_config.get("templates", []) as Array
		var allowed := int(team_config.get("count", templates.size()))
		var team_used := int(used.get(team_index, 0))
		if team_used >= allowed or templates.is_empty(): continue
		var dead: Array[CombatantState] = []
		for combatant in _state.combatants.values():
			if combatant.team == team_index and combatant.defeated: dead.append(combatant)
		_sort_by_slot(dead)
		for defeated in dead:
			if team_used >= allowed: break
			var template := (templates[mini(team_used, templates.size() - 1)] as Dictionary).duplicate(true)
			var old_id := defeated.instance_id
			var new_id := StringName(template.get("instance_id", "battle-mod-extra-%d-%d" % [team_index, team_used + 1]))
			template.instance_id = String(new_id)
			template.team = team_index
			template["battle_bonus_global_move_ids"] = defeated.battle_bonus_global_move_ids.duplicate()
			template.slot_index = defeated.slot_index
			# Source extra-minion records describe a species/level, not explicit
			# combat stats. Keep extension templates with explicit stats unchanged.
			if bool(template.get("source_derive_stats", false)):
				var definition := _content.get_definition(StringName(template.get("definition_id", ""))) as MinionDefinition
				if definition == null:
					_emit(&"battle_mod_extra_rejected", &"", old_id, {"reason": "invalid_content"})
					break
				var bonus: String = ["health", "energy", "attack", "healing", "speed"][int(_rng.next_unit() * 5.0)]
				var floor_index := int(_source_stat_context.get("floor_index", _rules.configuration.get("ai_difficulty", {}).get("floor_index", 0)))
				var player_stars: Variant = _source_stat_context.get("player_stars", {}) if team_index == 0 else null
				var stats := LegacyMinionStats.constructor_stats(definition, int(template.get("level", 1)), floor_index, bonus, player_stars)
				template["source_raw_stats"] = LegacyMinionStats.constructor_stats(definition, int(template.get("level", 1)), floor_index, bonus, player_stars, false)
				template.merge({"type_ids": definition.type_ids.duplicate(), "max_health": stats.health, "health": stats.health, "max_energy": stats.energy, "energy": stats.energy, "attack": stats.attack, "healing": stats.healing, "speed": stats.speed, "max_attack_stat": stats.max_attack_stat, "max_healing_stat": stats.max_healing_stat}, true)
				var autobuilder := preload("res://src/domain/battle/legacy_minion_autobuilder.gd").new()
				template.move_ids = autobuilder.build(definition, int(template.get("level", 1)), template.get("move_ids", []), _content, _rng)
			var replacement := CombatantState.from_setup(template)
			if replacement.instance_id.is_empty() or _state.combatants.has(replacement.instance_id) and replacement.instance_id != old_id:
				_emit(&"battle_mod_extra_rejected", &"", old_id, {"reason": "duplicate_instance_id"})
				break
			if not _content.has_definition(replacement.definition_id) or replacement.move_ids.any(func(id): return not _content.get_definition(id) is MoveDefinition):
				_emit(&"battle_mod_extra_rejected", &"", old_id, {"reason": "invalid_content"})
				break
			_state.retired_combatants.append(defeated.to_dict())
			_state.combatants.erase(old_id)
			_state.acted_ids.erase(old_id)
			_state.turn_order.erase(old_id)
			_state.combatants[replacement.instance_id] = replacement
			if bool(template.get("source_derive_stats", false)):
				replacement.max_health = LegacyModifiers.effective_max_health(replacement, _content, _state.combatants)
				replacement.max_energy = LegacyModifiers.effective_max_energy(replacement, _content, _state.combatants)
				replacement.health = replacement.max_health
				replacement.energy = replacement.max_energy
			_state.modifier_state.resurrection_counters.erase(String(old_id))
			_state.modifier_state.resurrection_counts.erase(String(old_id))
			_state.modifier_state.resurrection_counters[String(replacement.instance_id)] = 0
			_state.modifier_state.resurrection_counts[String(replacement.instance_id)] = 0
			team_used += 1
			used[team_index] = team_used
			_emit(&"battle_mod_extra_spawned", &"", replacement.instance_id, {"team": team_index, "slot": replacement.slot_index, "replaced_id": String(old_id), "remaining": allowed - team_used, "combatant": replacement.to_dict()})
	_state.modifier_state.extra_minions_used = used

func _living_at_slot(team: int, slot: int) -> CombatantState:
	for combatant in _state.combatants.values():
		if combatant.team == team and combatant.slot_index == slot and not combatant.defeated: return combatant
	return null

func _sort_by_slot(combatants: Array[CombatantState]) -> void:
	combatants.sort_custom(func(a: CombatantState, b: CombatantState):
		return a.slot_index < b.slot_index if a.slot_index != b.slot_index else String(a.instance_id) < String(b.instance_id))

func _finish(winning_team: int, reason: StringName) -> void:
	_state.phase = BattleState.Phase.COMPLETE
	_state.active_actor_id = &""
	var participant_states: Array[CombatantState] = []
	for combatant in _state.combatants.values(): participant_states.append(combatant as CombatantState)
	for retired_data in _state.retired_combatants: participant_states.append(CombatantState.from_snapshot(retired_data))
	participant_states.sort_custom(func(left: CombatantState, right: CombatantState) -> bool:
		if left.team != right.team: return left.team < right.team
		if left.slot_index != right.slot_index: return left.slot_index < right.slot_index
		return String(left.instance_id) < String(right.instance_id)
	)
	var participant_results: Array[Dictionary] = []
	for combatant in participant_states:
		participant_results.append({
			"instance_id": String(combatant.instance_id),
			"definition_id": String(combatant.definition_id),
			"team": combatant.team,
			"slot_index": combatant.slot_index,
			"level": combatant.level,
			"retired": _state.combatants.get(combatant.instance_id) != combatant,
			"stat_stages": combatant.stat_stages.duplicate(true),
			"battle_bonus_global_move_ids": combatant.battle_bonus_global_move_ids.duplicate(),
			"survived": not combatant.defeated,
			"defeated": combatant.defeated,
			"remaining_health": combatant.health,
			"max_health": combatant.max_health,
			"remaining_energy": combatant.energy,
			"max_energy": combatant.max_energy,
			"persistent_changes": {"health": combatant.health, "energy": combatant.energy},
		})
	var result = BATTLE_RESULT_SCRIPT.new()
	result.battle_id = _state.battle_id
	result.winning_team = winning_team
	result.reason = reason
	result.rounds = _state.round_number
	result.participants = participant_results
	_state.result = result.to_dictionary()
	_emit(&"battle_completed", &"", &"", _state.result)

func _emit(kind: StringName, actor_id: StringName, target_id: StringName, values: Dictionary) -> void:
	if kind in [&"decision_requested", &"battle_mod_timer_triggered"]:
		# The UI must display the order at this handoff, not the final order
		# after a later automatic action in the same response has changed it.
		values = values.duplicate(true)
		values["turn_order"] = _state.turn_order.duplicate()
	_event_sequence += 1
	_current_events.append(BattleEvent.new(_event_sequence, kind, actor_id, target_id, values))
