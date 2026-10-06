extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings := CampaignSettingsService.new()
	var audio := BattleAudioController.new()
	audio.add_to_group("source_menu_audio")
	root.add_child(audio)
	var played: Array[Dictionary] = []
	audio.child_entered_tree.connect(func(node: Node) -> void:
		if node is AudioStreamPlayer and (node as AudioStreamPlayer).stream != null and (node as AudioStreamPlayer).stream.resource_path.get_file().begins_with("menu_"):
			played.append({"name": (node as AudioStreamPlayer).stream.resource_path.get_file().get_basename(), "volume": db_to_linear((node as AudioStreamPlayer).volume_db), "bus": (node as AudioStreamPlayer).bus, "stream": (node as AudioStreamPlayer).stream})
	)
	var view := Control.new()
	root.add_child(view)
	var bindings := preload("res://src/presentation/source_menu_button_audio.gd")
	bindings.bind_tree(view)
	bindings.bind_tree(view)
	var clicks := [0]
	var button := SourceMenuArt.button(view, "menus_returnButton", Vector2.ZERO, func() -> void: clicks[0] += 1)
	assert(button != null)
	button.mouse_entered.emit()
	button.pressed.emit()
	assert(played.size() == 2 and clicks[0] == 1, "Source menu signals missing or double-bound")
	assert(played[0].name == "menu_tickSound" and is_equal_approx(played[0].volume, 0.5))
	assert(played[1].name == "menu_onPress" and is_equal_approx(played[1].volume, 0.65))
	assert(played.all(func(item: Dictionary) -> bool: return item.bus == &"SFX" and item.stream != null))
	button.disabled = true
	button.mouse_entered.emit()
	assert(played.size() == 2, "Disabled control played hover sound")
	button.disabled = false
	view.hide()
	button.mouse_entered.emit()
	assert(played.size() == 2, "Hidden menu played hover sound")
	view.show()
	# Rebuilt descendants bind through the retained view's child hook.
	var rebuilt := Control.new()
	view.add_child(rebuilt)
	var refreshed_button := SourceMenuArt.button(rebuilt, "menus_exitButton", Vector2.ZERO, func() -> void: rebuilt.queue_free())
	refreshed_button.pressed.emit()
	assert(played.size() == 3, "Rebuilt menu missed its click cue or duplicate hooks replayed it")
	var service_bus := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(service_bus, true)
	button.pressed.emit()
	assert(played.size() == 4 and AudioServer.is_bus_mute(service_bus), "Menu cue bypassed the Sound setting bus")
	# Settings controls use their own constructor rather than SourceMenuArt.
	var settings_view := CampaignSettingsView.new()
	root.add_child(settings_view)
	settings_view.configure(settings)
	settings_view._toggle_buttons["sound"].mouse_entered.emit()
	assert(played.size() == 5, "Custom Settings control lacks native hover cue")
	view.queue_free()
	settings_view.queue_free()
	audio.queue_free()
	await process_frame
	print("PASS: source hover/click sound IDs/volumes, single bindings, rebuilt descendants, disabled/hidden guards, SFX mute and custom Settings controls")
	quit()
