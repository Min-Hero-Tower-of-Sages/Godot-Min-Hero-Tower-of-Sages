extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selector := CampaignModSelector.new()
	selector.position = Vector2(20, 20)
	root.add_child(selector)
	await process_frame
	assert(selector._category_buttons.size() == CampaignModService.CATEGORIES.size())
	for category_index in CampaignModService.CATEGORIES.size():
		selector._category_buttons[category_index].pressed.emit()
		assert(selector._category == category_index)
		await process_frame
		for button_index in selector._buttons.size():
			selector._buttons[button_index].pressed.emit()
			var option: Dictionary = CampaignModService.OPTIONS[selector._option_indices[button_index]]
			for flag in option.flags: assert(selector.flags[flag])
			await process_frame
			assert(selector._description.get_visible_line_count() == selector._description.get_line_count(), "Every description line fits within panel")
			assert(selector._buttons[button_index].position.x + selector._buttons[button_index].size.x <= 185, "Toggle fits within row")
		var back := selector._body.get_child(0) as Button
		back.pressed.emit()
		assert(selector._category == -1)
		var category: Dictionary = CampaignModService.CATEGORIES[category_index]
		assert(selector._category_buttons[category_index].text.contains("%d/%d" % [category.groups.size(), category.groups.size()]))
		await process_frame
	assert(CampaignModService.normalize(selector.flags) == selector.flags)
	_check_restored_skills()
	# All original egg-table combinations retain the same bit identities.
	var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CampaignModService.EGG_TABLE_PATH))
	for mask in range(1, 16):
		var state := CampaignState.new()
		for flag in CampaignModService.EGG_POOL_BITS:
			state.active_mods[flag] = (mask & int(CampaignModService.EGG_POOL_BITS[flag])) != 0
		for floor_key in tables[str(mask)]:
			assert(CampaignModService.egg_pool(state, int(floor_key), {}) == tables[str(mask)][floor_key])
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1050, 787)
		selector._show_categories()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-categories.png")
		selector._open_category(0)
		selector._describe(CampaignModService.OPTIONS[3].description)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-minions-submenu.png")
		selector._open_category(2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-experimental-submenu.png")
		selector._open_category(3)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-skills-submenu.png")
		selector._show_categories()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-categories.png")
		selector._open_category(3)
		selector._describe(CampaignModService.OPTIONS.back().description)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mod-shinies-submenu.png")
	print("PASS: category navigation, flags/counts/bounds, 15 egg-pool masks and restored skill gates/purchases/isolation")
	quit()

func _check_restored_skills() -> void:
	var catalog: ContentCatalog = load("res://content/imported/recovered-20260911/catalog.tres")
	assert(catalog.ensure_index().is_empty())
	var state := CampaignState.new()
	state.active_mods = {"restored_martyr": true, "restored_righteous_fate": true}
	for entry in [
		["base:minion/holymantris_1", 1, "martyr"],
		["base:minion/healinghorse_1", 1, "martyr"],
		["arkvian:minion/holybird1", 0, "righteous_fate"],
		["arkvian:minion/holybird2", 0, "righteous_fate"]]:
		var definition := catalog.get_definition(StringName(entry[0])) as MinionDefinition
		var tree_index: int = entry[1]
		var family: String = entry[2]
		var original := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition
		var overlay := CampaignModService.talent_tree(state, definition, tree_index, catalog)
		assert(overlay.nodes.size() == original.nodes.size() + 1 and overlay.validation_errors().is_empty())
		var cells: Dictionary = {}
		for node in overlay.nodes:
			var cell := Vector2(int(node.column), int(node.row))
			assert(not cells.has(cell), "Restored talent occupies a free slot")
			cells[cell] = true
		assert(CampaignModService.talent_tree(null, definition, tree_index, catalog) == original)
		var owned := OwnedMinionState.new()
		owned.definition_id = definition.id
		owned.level = 60
		owned.learned_move_ids.assign(definition.initial_move_ids)
		owned.learned_move_ids.append(definition.specialization_move_ids[tree_index])
		var tier1 := StringName("base:move/%s/tier1" % family)
		assert(not CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, tier1, state).ok, "Normal row gates still apply")
		# Spend legally in the original branch until its added node is unlocked.
		for point in 9:
			var choices := CampaignProgressionService.talent_choices(owned, definition, catalog, state)
			var purchased := false
			for choice in choices:
				if choice.tree_index != tree_index or String(choice.move_id).contains("/%s/" % family): continue
				assert(CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, choice.move_id, state).ok)
				purchased = true
				break
			assert(purchased)
		var before := CampaignProgressionService.available_talent_points(owned, definition)
		for tier in range(1, 6):
			var move_id := StringName("base:move/%s/tier%d" % [family, tier])
			assert(not CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, move_id).ok, "Disabled option cannot be purchased")
			assert(CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, move_id, state).ok)
		assert(CampaignProgressionService.available_talent_points(owned, definition) == before - 5)
		var roundtrip := OwnedMinionState.from_dictionary(JSON.parse_string(JSON.stringify(owned.to_dictionary())))
		assert(roundtrip.learned_move_ids == owned.learned_move_ids)
		assert(original.nodes.size() + 1 == overlay.nodes.size(), "Shared catalog remains unchanged")
	# Enabling both options cannot give Martyr to the bird sharing its Holy tree.
	var bird := catalog.get_definition(&"arkvian:minion/holybird1") as MinionDefinition
	var bird_tree := CampaignModService.talent_tree(state, bird, 0, catalog)
	assert(String(bird_tree.nodes.back().move_ids[0]).contains("/righteous_fate/"))
