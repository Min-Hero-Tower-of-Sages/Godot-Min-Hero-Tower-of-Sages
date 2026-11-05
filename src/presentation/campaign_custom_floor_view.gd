class_name CampaignCustomFloorView
extends Control

signal floor_selected(floor_id: StringName)
signal closed

func configure(floors: Array[CustomFloorDefinition], room_state: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ModWorkshopForm.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.08, 0.64)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(488, 128 + clampi(floors.size(), 1, 3) * 112)
	center.add_child(panel)
	var form := ModWorkshopForm.new()
	panel.add_child(form)
	var title := form.note("CUSTOM FLOORS", ModWorkshopForm.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var rows := ModWorkshopForm.new()
	list.add_child(rows)
	if floors.is_empty():
		var empty := rows.card("No custom floors enabled")
		empty.note("Enable Ice Content or a player mod with a floor in Settings → Mod Menu.")
	for floor in floors:
		var row := rows.card()
		var line := row.row("")
		var icon := SourceMenuArt.texture("iFloorIcon" if floor.id == CustomFloorBuilder.ICE_ID else "roomSelect_plantRoom")
		var thumbnail := ModWorkshopForm.picture(icon, Vector2(91, 54), line)
		thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var details := ModWorkshopForm.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(details)
		var name_label := details.note(floor.display_name, ModWorkshopForm.GOLD)
		name_label.add_theme_font_size_override("font_size", 17)
		var summary := "%d rooms" % floor.room_ids.size()
		if bool(room_state.get(String(floor.id), {}).get("reward_spent", false)):
			summary += "  •  Egg claimed"
		details.note(summary)
		if not floor.description.is_empty():
			details.note(floor.description, ModWorkshopForm.INK)
		var go := _art_button("roomSelect_roomInformationGoButton", line, func() -> void: floor_selected.emit(floor.id))
		go.name = "CustomFloorGo"
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.tooltip_text = "Enter %s" % floor.display_name
	var back := _art_button("menus_returnButton", form, func() -> void: closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.tooltip_text = "Return to the Side Hall"
	focus_mode = Control.FOCUS_ALL
	grab_focus()

func _art_button(symbol: String, parent: Control, action: Callable) -> TextureButton:
	var art := SourceMenuArt.texture(symbol)
	var button := TextureButton.new()
	button.texture_normal = art
	button.custom_minimum_size = art.get_size()
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
