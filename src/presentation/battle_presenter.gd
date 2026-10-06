class_name BattlePresenter
extends Node

const PresentationState = preload("res://src/presentation/battle_presentation_state.gd")

signal playback_finished
signal event_presented(event: BattleEvent)

@export var seconds_per_event: float = 0.12
var visual_state: Dictionary = {}

func play(events: Array[BattleEvent], immediate := false) -> void:
	for event in events:
		_apply(event)
		event_presented.emit(event)
		if not immediate and seconds_per_event > 0.0:
			await get_tree().create_timer(seconds_per_event).timeout
	playback_finished.emit()

func _apply(event: BattleEvent) -> void:
	if event.kind == &"battle_started": visual_state.clear()
	if not event.target_id.is_empty():
		var target: Dictionary = visual_state.get(event.target_id, {})
		visual_state[event.target_id] = PresentationState.apply_event(target, event)
	if event.kind == &"battle_completed": visual_state.result = event.values.duplicate(true)
