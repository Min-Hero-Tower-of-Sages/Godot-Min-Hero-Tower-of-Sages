extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower")
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.progression = {"floor_index": 0}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_show_campaign_menu")
	await create_timer(1.1).timeout
	var old_root: Control = shell.interaction_dialog
	var old_canvas: CanvasLayer = shell.interaction_dialog_canvas
	var old_visuals := SourceMenuTransition.visual_group(old_root)
	shell.call("_show_settings_menu")
	var settings: Control = shell.interaction_dialog
	var new_visuals := SourceMenuTransition.visual_group(settings)
	assert(is_instance_valid(old_canvas) and not old_canvas.is_queued_for_deletion())
	assert(old_canvas in shell._retiring_menu_canvases and old_root != settings)
	assert(is_equal_approx(old_visuals.modulate.a, 1.0) and is_zero_approx(new_visuals.modulate.a))
	_check_disabled(old_root)
	await create_timer(0.3).timeout
	assert(old_visuals.modulate.a > 0.0 and old_visuals.modulate.a < 1.0)
	assert(new_visuals.modulate.a > 0.0 and new_visuals.modulate.a < 1.0)
	assert(is_equal_approx(shell._menu_backdrop.shade.color.a, 0.65))
	await create_timer(0.4).timeout
	assert(not is_instance_valid(old_canvas) and shell._retiring_menu_canvases.is_empty())
	# A Return signal must overlap exits/entrances instead of waiting .6s first.
	var settings_canvas: CanvasLayer = shell.interaction_dialog_canvas
	settings.closed.emit()
	assert(shell.interaction_dialog != settings and settings_canvas in shell._retiring_menu_canvases)
	assert(not settings.is_processing_unhandled_key_input())
	await create_timer(0.7).timeout
	# Rapid page changes keep old input inactive and release every old canvas.
	for route in ["_show_you_menu", "_show_minion_pedia", "_save_from_menu", "_show_settings_menu"]:
		shell.call(route)
		await create_timer(0.12).timeout
	assert(shell._retiring_menu_canvases.size() >= 2)
	for canvas in shell._retiring_menu_canvases:
		_check_disabled(canvas.get_child(0))
	await create_timer(0.7).timeout
	assert(shell._retiring_menu_canvases.is_empty())
	# The active Settings consumes Escape; its retired version cannot steal the
	# next Escape from the root menu.
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key)
	await process_frame
	var new_root: Control = shell.interaction_dialog
	assert(not new_root is CampaignSettingsView)
	var second_key := InputEventKey.new()
	second_key.keycode = KEY_ESCAPE
	second_key.pressed = true
	root.push_input(second_key)
	await process_frame
	assert(shell._menu_navigation_active, "Retired Settings stole the root menu's close shortcut")
	await create_timer(0.7).timeout
	assert(shell.interaction_dialog == null and shell.current_room._controls_enabled)
	# Scene cleanup must immediately retire all fading canvases.
	shell.call("_show_campaign_menu")
	shell.call("_show_you_menu")
	assert(not shell._retiring_menu_canvases.is_empty())
	var lingering: CanvasLayer = shell._retiring_menu_canvases[0]
	shell.call("_clear_game_screen")
	assert(shell._retiring_menu_canvases.is_empty() and lingering.is_queued_for_deletion())
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: overlapping source popup exits/entrances, world opacity, outgoing input/focus isolation, Return, rapid navigation, keyboard handoff and scene cleanup")
	quit()

func _check_disabled(node: Node) -> void:
	assert(not node.is_processing_unhandled_key_input())
	if node is BaseButton:
		assert(node.disabled)
	for child in node.get_children():
		_check_disabled(child)
