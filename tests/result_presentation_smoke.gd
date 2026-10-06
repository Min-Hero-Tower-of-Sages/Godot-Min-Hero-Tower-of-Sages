extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	var main := MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	call_deferred("_run_result_flows", main)

func _run_result_flows(main: Control) -> void:
	await process_frame
	var victory := BattleResult.new()
	victory.winning_team = 0
	for slot in 5:
		victory.participants.append({"team": 0, "slot_index": slot, "instance_id": "player-%d" % (slot + 1), "survived": true})
	main._show_result(victory)
	_check(main.result_overlay.visible and main.victory_popup.visible and main._source_victory_star_count(victory) == 3, "victory card must open and use the source three-star result")
	_check(main.victory_background.modulate.a == 0.0, "victory background must start transparent")
	await create_timer(0.5).timeout
	_check(main.victory_background.modulate.a > 0.0 and main.victory_background.modulate.a < 1.0, "victory background must be fading in, not appear instantly")
	await create_timer(0.45).timeout
	_check(main.victory_background.modulate.a > 0.99 and (main.victory_stars[0] as TextureRect).modulate.a > 0.0, "victory card and first star must follow their delayed source fades")
	await create_timer(2.5).timeout
	_check(not main.victory_popup.visible, "victory card must close after the source hold/fade sequence")
	main.result_overlay.visible = false
	main._battle_result_presented = false # A new battle normally resets this in _start_battle().
	var defeat := BattleResult.new()
	defeat.winning_team = 1
	main._show_result(defeat)
	_check(main.defeat_transition_layer.visible and main.defeat_message.visible and not main.result_overlay.visible, "defeat must show the source blackout/message before the practice restart panel")
	await create_timer(3.6).timeout
	_check(not main.defeat_transition_layer.visible and main.result_overlay.visible, "defeat aftermath must reveal the practice restart only after the source 3.5-second transition")
	main.result_overlay.visible = false
	main.campaign_mode = true
	main.campaign_defeat_return_requested.connect(_record_campaign_return.bind(main))
	main._play_defeat_presentation()
	await create_timer(3.6).timeout
	_check(not main.result_overlay.visible and main.defeat_transition_layer.visible and main.defeat_black.modulate.a > 0.99 and int(main.get_meta("campaign_return_count", 0)) == 1, "campaign defeat must hand off under an opaque blackout without opening the practice restart panel")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: result presentation (7 checks)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of 7 result presentation checks" % failures.size())
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _record_campaign_return(main: Control) -> void:
	main.set_meta("campaign_return_count", int(main.get_meta("campaign_return_count", 0)) + 1)
