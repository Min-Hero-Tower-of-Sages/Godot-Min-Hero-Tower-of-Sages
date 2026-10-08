extends "res://tests/battle_replay_smoke.gd"

## Battle input through Godot's whole input pipeline (mouse hover, GUI, focus),
## which headless tests cannot exercise. Needs a window:
##   godot --path . --script res://tests/battle_real_input_probe.gd
## Health bars open stats during move selection; ground (also on the enemy
## side) closes the selector; moves sliding in under a still mouse do not pop
## tooltips; a trainer's Yes/No question has the source's arrow pointer
## (starting on No), moved by UP/W and DOWN/S and confirmed by Space/Enter.

var battle: Node

func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p
func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _to_window(p); m.global_position = m.position
	Input.parse_input_event(m)
	await process_frame
	await process_frame
func _click(p: Vector2) -> void:
	await _move(p)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT; b.pressed = pressed
		b.position = _to_window(p); b.global_position = b.position
		Input.parse_input_event(b)
		await process_frame
	await process_frame
func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.load_campaign(1)
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	runtime.session.state.current_room_id = &"base:room/level_1_1_a"
	runtime.prepare_trainer_battle(&"base:encounter/grass_floor1_room1_normal", Vector2.ZERO)
	var shell: Control = load("res://scenes/application_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell._clear_game_screen()
	battle = load("res://scenes/main.tscn").instantiate()
	shell.screen_host.add_child(battle)
	battle.call("begin_campaign_battle")
	var deadline := Time.get_ticks_msec() + 20000
	while not (battle.move_panel.visible and not battle.busy) and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.5).timeout
	var decision: Dictionary = battle.controller.engine.get_decision()
	var actor: BattleCombatantView = battle.combatant_views[String(decision.actor_id)]
	for view in battle.combatant_views.values():
		var bar: Sprite2D = view.health_background_sprite
		await _click(bar.get_global_transform_with_canvas() * (bar.texture.get_size() * 0.5))
		if view.team == 0:
			_expect(battle.stats_panel.visible, "your health bar opens stats while choosing (%s)" % view.instance_id)
		battle.stats_panel.close()
	# Cursor: a hand wherever a click does something.
	for button in battle.move_buttons.get_children():
		if button is Button and (button as Button).pressed.get_connections().size() > 0:
			await _move((button as Control).get_global_rect().get_center())
			await create_timer(0.1).timeout
			_expect(DisplayServer.cursor_get_shape() == DisplayServer.CURSOR_POINTING_HAND, "a choosable move shows the hand cursor")
			break
	var own_bar: Sprite2D = actor.health_background_sprite
	await _move(Vector2(600, 470))
	await _move(own_bar.get_global_transform_with_canvas() * (own_bar.texture.get_size() * 0.5))
	await create_timer(0.1).timeout
	_expect(DisplayServer.cursor_get_shape() == DisplayServer.CURSOR_POINTING_HAND, "your health bar shows the hand cursor (on the bar itself)")
	await _click(Vector2(600, 470))
	await create_timer(1.5).timeout
	_expect(not battle.move_panel.visible and not battle.battle_grey_layer.visible, "a click on the enemy side's ground closes the selector")
	await _move(actor.minion_sprite.get_global_transform_with_canvas().origin)
	await create_timer(0.2).timeout
	_expect(DisplayServer.cursor_get_shape() == DisplayServer.CURSOR_POINTING_HAND, "hovering your acting minion with the selector closed shows the hand cursor")
	await _move(Vector2(600, 470))
	await create_timer(0.2).timeout
	_expect(DisplayServer.cursor_get_shape() == DisplayServer.CURSOR_ARROW, "and the arrow is back over the ground")
	for view in battle.combatant_views.values():
		if view.team == 1:
			await _move(view.minion_sprite.get_global_transform_with_canvas().origin)
			await create_timer(0.1).timeout
			_expect(DisplayServer.cursor_get_shape() == DisplayServer.CURSOR_ARROW, "an enemy minion's body keeps the arrow")
			break
	# Reopen with the mouse resting where a move will land.
	var landing: Vector2 = battle.move_panel.get_global_transform_with_canvas() * Vector2(41.0 + 27.0, -45.0 + 26.0)
	await _click(actor.minion_sprite.get_global_transform_with_canvas().origin)
	await _move(landing)
	await create_timer(0.6).timeout
	_expect(not battle.move_tooltip.visible, "moves sliding in under the mouse show no tooltip")
	await create_timer(1.0).timeout
	await _move(landing + Vector2(2, 2))
	await create_timer(0.1).timeout
	_expect(battle.move_tooltip.visible, "once a move has arrived, hovering it shows its tooltip")
	# A trainer's Yes/No question in exploration (StandardChatBox).
	battle.queue_free()
	shell._show_room_from_state()
	await create_timer(1.5).timeout
	var answers: Array[String] = []
	for expected in ["no", "yes", "yes-key"]:
		shell._show_source_dialogue({"on_yes": func() -> void: answers.append("yes"), "on_no": func() -> void: answers.append("no")}, "Trainer", "You already beat me! Retry for three stars?")
		await create_timer(1.2).timeout
		var arrow: TextureRect = shell._source_dialogue_arrow
		_expect(arrow != null and arrow.visible and is_equal_approx(arrow.rotation_degrees, 270.0), "the arrow turns into the Yes/No pointer (%s)" % expected)
		var no_y: float = arrow.position.y
		if expected == "no":
			await _key(KEY_SPACE)
		elif expected == "yes":
			await _key(KEY_UP)
			_expect(arrow.position.y < no_y, "UP moves the pointer to Yes")
			await _key(KEY_DOWN)
			_expect(is_equal_approx(arrow.position.y, no_y), "DOWN moves it back to No")
			await _key(KEY_W)
			await _key(KEY_ENTER)
		else:
			await _key(KEY_Y)
		await create_timer(0.5).timeout
	_expect(answers == ["no", "yes", "yes"], "Space picks No by default, UP/W then Enter picks Yes, Y answers Yes (%s)" % [answers])
	if failures.is_empty():
		print("battle_real_input_probe: %d checks passed" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("battle_real_input_probe: %d of %d checks failed" % [failures.size(), checks])
		quit(1)
