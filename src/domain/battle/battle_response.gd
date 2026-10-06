class_name BattleResponse
extends RefCounted

var accepted: bool
var error_code: StringName
var message: String
var revision: int
var events: Array[BattleEvent]

static func success(p_revision: int, p_events: Array[BattleEvent]) -> BattleResponse:
	var response := BattleResponse.new()
	response.accepted = true
	response.revision = p_revision
	response.events = p_events
	return response

static func rejected(p_revision: int, code: StringName, p_message: String) -> BattleResponse:
	var response := BattleResponse.new()
	response.accepted = false
	response.revision = p_revision
	response.error_code = code
	response.message = p_message
	return response
