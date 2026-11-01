extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(candidate) -> Dictionary:
		var errors: PackedStringArray = candidate.validation_errors(catalog)
		if reject_save or not errors.is_empty(): return {"ok": false, "message": "Fixture save rejected"}
		return save_repository.validate(candidate.to_dictionary(catalog.content_version))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	if not user_root.contains("/build/prompt-settings-profile/"):
		push_error("Use the isolated build/prompt-settings-profile; this fixture writes preferences.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument == "--verify-export":
			assert(not ResourceLoader.exists("res://tests/test_runner.tscn"), "Expected exported game resources")
		if argument.begins_with("--expect-version="):
			assert(ProjectSettings.get_setting("application/config/version") == argument.trim_prefix("--expect-version="))
	root.size = Vector2i(1050, 787)
	var old_config := ConfigFile.new()
	old_config.set_value("settings", "tips_enabled", false)
	assert(old_config.save(CampaignSettingsService.SETTINGS_PATH) == OK)
	var settings := CampaignSettingsService.new()
	assert(not settings.tips_enabled and settings.confirm_floor_exit, "Older preferences preserve Tips and default exit confirmation on")
	settings.set_confirm_floor_exit(false)
	settings.set_tips_enabled(true)
	assert(CampaignSettingsService.new().tips_enabled and not CampaignSettingsService.new().confirm_floor_exit)
	settings.set_confirm_floor_exit(true)
	var runtime := root.get_node("CampaignRuntime")
	var original_session: CampaignSession = runtime.session
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = &"base:room/main_tower_lobby"
	session.state.character = {"name": "Prompt fixture", "gender": "male"}
	session.state.active_mods = {"debug_mode": true}
	session.state.progression.unlocked_floor_indices = [0, 1, 3]
	session.state.progression.in_tower_lobby = true
	session.state.party = CampaignProgressionService.starter_party(session.catalog, "prompt-")
	runtime.session = session
	assert(await _settings_ui(settings, session))
	assert(await _disabled_tutorials(settings, session))
	assert(await _optional_reveal(settings, session))
	assert(await _lobby_flow(settings, session))
	settings.set_tips_enabled(true)
	settings.set_confirm_floor_exit(true)
	runtime.session = original_session
	print("PASS: preference migration/persistence, independent tutorial/exit controls, suppressed battle/room/bonus/defeat help, save-retry preservation and source-timed lobby picker transitions")
	quit()

func _settings_ui(settings: CampaignSettingsService, session: CampaignSession) -> bool:
	var view := CampaignSettingsView.new()
	root.add_child(view)
	view.configure(settings, session)
	assert(view.find_child("TutorialPromptsToggle", true, false) != null)
	assert(view.find_child("ConfirmFloorExitToggle", true, false) != null)
	assert(view.find_child("SavedModMenuButton", true, false) != null and view.find_child("DebugMenuButton", true, false) != null)
	view._toggle_setting("tips")
	assert(not settings.tips_enabled and settings.confirm_floor_exit, "Disabling tutorials must keep the exit confirmation")
	view._toggle_setting("confirm_exit")
	assert(not settings.tips_enabled and not settings.confirm_floor_exit)
	view._toggle_setting("confirm_exit")
	assert(not CampaignSettingsService.new().tips_enabled and CampaignSettingsService.new().confirm_floor_exit)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/prompt-settings.png")
	view.free()
	return true

func _disabled_tutorials(settings: CampaignSettingsService, session: CampaignSession) -> bool:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settings_service = settings
	root.add_child(main)
	main.catalog = session.catalog
	main.campaign_mode = true
	assert(main._campaign_intro_tutorial_id(session).is_empty())
	session.state.progression.floor_keys = 1
	assert(main._decision_tutorial_id(session, {"actor_id": "unused"}).is_empty())
	main._show_move_selection_hint()
	assert(not is_instance_valid(main._move_selection_hint))
	assert(not session.state.progression.get("battle_basics_tutorial_seen", false), "The setting does not rewrite tutorial history")
	main.free()
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	var finished: Array[bool] = [false]
	presenter.sequence_finished.connect(func() -> void: finished[0] = true)
	presenter.begin_sequence([], {}, session.catalog, {}, false, null, Callable(), true)
	await process_frame
	assert(presenter.get_node_or_null("FirstDefeatTutorial") == null)
	await create_timer(1.5).timeout
	assert(finished[0], "Disabling the first-defeat tip must not block result progression")
	presenter.free()
	return true

func _optional_reveal(settings: CampaignSettingsService, session: CampaignSession) -> bool:
	session.state.progression.pending_optional_floor_reveals = [3]
	var picker := CampaignFloorSelectView.new()
	root.add_child(picker)
	picker.configure(session, null, settings)
	session.reject_save = true
	picker._finish_optional_floor_insertion()
	assert(is_instance_valid(picker._tutorial) and picker._tutorial.name == "BonusFloorSaveRetry", "Save failures still offer retry with tutorials disabled")
	assert(3 in session.state.progression.pending_optional_floor_reveals)
	session.reject_save = false
	(picker._tutorial.find_child("BonusTutorialOK", true, false) as TextureButton).pressed.emit()
	await create_timer(0.6).timeout
	assert(session.state.progression.pending_optional_floor_reveals.is_empty() and not picker._insertion_active)
	assert(not session.state.progression.get("bonus_floor_tutorial_seen", false))
	picker.free()
	return true

func _lobby_flow(settings: CampaignSettingsService, session: CampaignSession) -> bool:
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell._settings = settings
	shell._show_room_from_state()
	var progression_before: Dictionary = session.state.progression.duplicate(true)
	var room_before: StringName = session.state.current_room_id
	shell._show_floor_picker()
	assert(shell._room_transition_active and shell.interaction_dialog == null and not shell.current_room._controls_enabled)
	await create_timer(0.25).timeout
	assert(shell.room_transition_curtain.visible and shell.room_transition_curtain.color.a > 0.05 and shell.room_transition_curtain.color.a < 0.99)
	assert(shell.interaction_dialog == null, "Do not swap to the picker before black")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/lobby-picker-fade.png")
	await create_timer(0.35).timeout
	var picker: CampaignFloorSelectView = shell.interaction_dialog
	assert(picker != null and shell._room_transition_active and shell.room_transition_curtain.color.a > 0.95)
	shell._select_tower_floor(1)
	picker.closed.emit()
	assert(session.state.progression == progression_before and session.state.current_room_id == room_before and shell.interaction_dialog == picker, "Transition input must not select a floor or close the opening picker")
	await create_timer(0.7).timeout
	assert(not shell._room_transition_active and not shell.room_transition_curtain.visible and not shell.current_room._controls_enabled)
	picker.closed.emit()
	assert(shell._room_transition_active and shell.interaction_dialog == picker)
	await create_timer(0.3).timeout
	assert(shell.interaction_dialog == picker, "Return keeps the picker until opaque")
	await create_timer(1.0).timeout
	assert(shell.interaction_dialog == null and not shell._room_transition_active and shell.current_room._controls_enabled)
	# The guide opened through the real shell/Pedia shares its settings instance.
	shell._show_minion_pedia()
	var pedia: CampaignMinionPediaView = shell.interaction_dialog
	pedia._open_type_guide()
	var guide := pedia.get_node("TypeGuide") as TypeGuideView
	assert(guide.settings == settings)
	var hints_before := settings.effectiveness_hints_enabled
	guide._hints_toggle.pressed.emit()
	assert(settings.effectiveness_hints_enabled != hints_before)
	guide._hints_toggle.pressed.emit()
	shell._clear_dialog(true)
	# Three-key and context-room tutorials must not appear later from timers.
	session.state.progression.in_tower_lobby = false
	session.state.progression.floor_keys = 3
	for definition in session.catalog._by_id.values():
		if definition is RoomDefinition and int(definition.minimap_metadata.get("floor_index", -1)) == 0 and int(definition.minimap_metadata.get("room_index", -1)) == 11:
			session.state.current_room_id = definition.id
			break
	shell._show_room_from_state()
	shell._present_return_rewards({})
	await create_timer(3.1).timeout
	assert(shell.interaction_dialog == null and shell.current_room._controls_enabled)
	assert(not session.state.progression.get("boss_room_tutorial_seen", false))
	# Returning from a hatchery keeps its own confirmation even with Tutorials off.
	session.state.current_room_id = &"base:room/level_1_1_eggery"
	shell._show_room_from_state()
	shell._on_room_transition_requested({"target_route": "lobby"})
	assert(shell.interaction_dialog != null and not shell._room_transition_active)
	assert(not session.state.progression.in_tower_lobby)
	shell._cancel_lobby_exit()
	assert(shell.interaction_dialog == null and shell.current_room._controls_enabled)
	settings.set_confirm_floor_exit(false)
	shell._on_room_transition_requested({"target_route": "lobby"})
	assert(shell._room_transition_active and shell.interaction_dialog == null)
	await create_timer(1.3).timeout
	assert(session.state.progression.in_tower_lobby and not shell._room_transition_active)
	shell.free()
	return true
