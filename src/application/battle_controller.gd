class_name BattleController
extends RefCounted

signal events_produced(events: Array[BattleEvent])
signal battle_finished(result)

var engine := BattleEngine.new()
var _result_emitted := false

func start(setup: Dictionary, content: ContentCatalog, rules: RuleSetDefinition, rng: BattleRng) -> BattleResponse:
	_result_emitted = false
	var response := engine.start(setup, content, rules, rng)
	if response.accepted: events_produced.emit(response.events)
	return response

func submit(command: BattleCommand) -> BattleResponse:
	var response := engine.submit(command)
	if response.accepted:
		events_produced.emit(response.events)
		var result = engine.get_result()
		if not result.is_empty() and not _result_emitted:
			_result_emitted = true
			battle_finished.emit(result)
	return response

func submit_ai_turn() -> BattleResponse:
	var response := engine.submit_ai_turn()
	if response.accepted:
		events_produced.emit(response.events)
		var result = engine.get_result()
		if not result.is_empty() and not _result_emitted:
			_result_emitted = true
			battle_finished.emit(result)
	return response

func consume_result_once(campaign_state: Dictionary) -> bool:
	var result = engine.get_result()
	if result.is_empty(): return false
	if String(campaign_state.get("last_applied_battle", "")) == String(result.battle_id): return false
	campaign_state["last_applied_battle"] = String(result.battle_id)
	campaign_state["last_battle_result"] = result.to_dictionary()
	return true
