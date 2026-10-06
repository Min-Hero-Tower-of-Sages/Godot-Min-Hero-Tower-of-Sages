extends RefCounted

const GEM_TOOLTIP := preload("res://src/presentation/source_gem_tooltip.gd")

## MinionDetailsMinionGemsObject is shared by party and storage in the source.
static func build(page: Control, tooltip_parent: Control, owned: OwnedMinionState, definition: MinionDefinition, state: CampaignState, request: Callable) -> void:
	if definition == null:
		return
	var tooltip := GEM_TOOLTIP.new()
	tooltip.name = "SourceEquippedGemTooltip"
	tooltip_parent.add_child(tooltip)
	for index in 4:
		var at := Vector2(22 + (index % 2) * 150, 63 + floori(float(index) / 2.0) * 90)
		var empty := SourceMenuArt.image(page, "menus_emptyGemSocket", at)
		if empty != null:
			empty.name = "EmptyGemSocket%d" % index
		var gem: Dictionary = {}
		if index < owned.equipment_ids.size() and not owned.equipment_ids[index].is_empty():
			gem = CampaignGemEquipmentService._find_gem(state, owned.equipment_ids[index])
		if not gem.is_empty():
			if empty != null:
				empty.hide()
			var portrait := CampaignGemPortrait.new()
			portrait.name = "EquippedGem%d" % index
			portrait.position = at
			page.add_child(portrait)
			portrait.configure(gem)
		var available := index < definition.gem_slots
		var locked := index >= definition.gem_slots and index < definition.gem_slots + definition.locked_gem_slots
		var symbol := "menus_changeButton" if available else "menus_gemLockedButton" if locked else "menus_gemPremiumButton"
		var action := SourceMenuArt.button(page, symbol, at + Vector2(65, 15), request.bind(owned.instance_id, index))
		if action != null:
			action.name = "GemSlotAction%d" % index
			action.disabled = not available
			action.tooltip_text = "Change gem" if available else "Gem slot locked" if locked else "Additional gem slot unavailable"
		if available:
			var hit := Button.new()
			hit.name = "GemSocketHit%d" % index
			hit.position = at
			var texture := SourceMenuArt.texture("menus_emptyGemSocket")
			hit.size = texture.get_size() if texture != null else Vector2(48, 48)
			hit.flat = true
			hit.focus_mode = Control.FOCUS_NONE
			hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for style in ["normal", "hover", "pressed", "focus"]:
				hit.add_theme_stylebox_override(style, StyleBoxEmpty.new())
			page.add_child(hit)
			preload("res://src/presentation/source_menu_button_audio.gd").bind_button(hit)
			hit.pressed.connect(request.bind(owned.instance_id, index))
			if not gem.is_empty():
				hit.mouse_entered.connect(tooltip.show_gem.bind(gem))
				hit.mouse_exited.connect(tooltip.hide)
