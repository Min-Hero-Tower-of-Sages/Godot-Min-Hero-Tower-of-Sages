extends Node

const INTRO := preload("res://src/presentation/source_new_campaign_intro.gd")
var _completed_count := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://development")
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	add_child(shell)
	await get_tree().create_timer(5.5).timeout
	assert(shell.current_screen.get_node("TitlePlayButton").mouse_filter == Control.MOUSE_FILTER_STOP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://development/title-menu-parity.png")
	shell.call("_show_save_slots")
	await get_tree().create_timer(1.4).timeout
	assert(shell.current_screen.get_node("TitleSaveSlots").get_child_count() == 3)
	shell.call("_show_character_creation")
	await get_tree().create_timer(1.5).timeout
	shell.call("_set_gender", "female")
	assert(shell.selected_gender == "female")
	shell.call("_show_save_slots")
	await get_tree().create_timer(0.7).timeout
	assert(shell.current_screen.get_node_or_null("CharacterCreationLayer") == null)
	assert(shell.current_screen.get_node("TitleMusicToggle").mouse_filter == Control.MOUSE_FILTER_STOP)
	# Exercise full playback and skip independently, without creating/deleting
	# any real save. Accelerate the cinematic clock, not the actual menu timing.
	shell.current_screen.hide()
	var intro := INTRO.new()
	add_child(intro)
	intro.completed.connect(func() -> void: _completed_count += 1)
	intro.start(shell._campaign_audio)
	assert(intro._story_words.size() == 30 and intro._story_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	assert(not (intro.FONT as FontFile).multichannel_signed_distance_field, "Intro must not change the shared UI font")
	Engine.time_scale = 8.0
	await get_tree().create_timer(12.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://development/new-save-intro-door.png")
	await get_tree().create_timer(14.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://development/new-save-intro-story.png")
	await get_tree().create_timer(16.0).timeout
	assert(_completed_count == 1 and intro._finished)
	intro.finish()
	assert(_completed_count == 1, "Intro completion must be idempotent")
	intro.queue_free()
	await get_tree().process_frame
	var skipped := INTRO.new()
	add_child(skipped)
	skipped.completed.connect(func() -> void: _completed_count += 1)
	skipped.start(shell._campaign_audio)
	assert(skipped._skip.disabled)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	skipped._input(click)
	assert(skipped._skip.disabled, "The reveal click must not also activate Skip")
	await get_tree().create_timer(0.6).timeout
	assert(not skipped._skip.disabled)
	skipped._skip.pressed.emit()
	assert(_completed_count == 2 and skipped._timelines.is_empty())
	await get_tree().create_timer(42.0).timeout
	assert(_completed_count == 2, "Skipped intro must not complete again later")
	Engine.time_scale = 1.0
	skipped.queue_free()
	# The shell handoff uses an in-memory campaign, never start_new_campaign.
	var runtime := get_node("/root/CampaignRuntime")
	var session := CampaignSession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower")
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.progression = {"floor_index": 0}
	runtime.session = session
	shell.current_screen.show()
	shell.call("_start_new_campaign_intro")
	var integrated_intro: Control = shell.current_screen.get_node("NewCampaignIntro")
	assert(shell._room_transition_active)
	integrated_intro.finish()
	await get_tree().create_timer(1.4).timeout
	assert(is_instance_valid(shell.current_room) and not shell._room_transition_active)
	assert(shell.current_room._controls_enabled and not shell.room_transition_curtain.visible)
	runtime.session = null
	print("PASS: title entrance, three save cards, creation return/toggles, full intro, source glow shader, click-to-reveal Skip and cancelled callbacks; no saves modified")
	get_tree().quit()
