extends SceneTree

var saves := 0

func _initialize() -> void:
	_run.call_deferred()

func _save() -> Dictionary:
	saves += 1
	return {"ok": true}

func _node_button(parent: Node, move_id: StringName) -> TextureButton:
	for child in parent.find_children("*", "TextureButton", true, false):
		if child.get_meta("move_id", &"") == move_id:
			return child
	return null

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	var definition := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var owned := OwnedMinionState.new()
	owned.instance_id = &"talent-flow-fixture"
	owned.definition_id = definition.id
	owned.level = 9
	owned.learned_move_ids.assign(definition.initial_move_ids)
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	presenter.show_campaign_talents(owned, catalog, _save)
	await create_timer(0.7).timeout
	var modal := presenter.get_node("TalentTreeModal") as Control
	var panel := modal.get_node("TalentTreePanel") as Control
	var viewport_size := presenter.get_viewport_rect().size
	var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	assert(panel.scale.is_equal_approx(Vector2.ONE * factor))
	assert(panel.position.is_equal_approx((viewport_size - Vector2(700, 525) * factor) * 0.5 + CampaignPartyMenuView.SOURCE_SETTLED_PANEL_POSITION * factor))
	assert(panel.has_node("CloseButton") and modal.color == Color(0, 0, 0, 0.65))
	assert(panel.get_node("TalentPoints").position == Vector2(66, 312))
	for move_id in definition.specialization_move_ids:
		var button := _node_button(panel, move_id)
		assert(button != null and button.get_meta("purchasable") and button.get_meta("visually_active"))
	_node_button(panel, definition.specialization_move_ids[1]).pressed.emit()
	await process_frame
	modal = presenter.get_node("TalentTreeModal")
	panel = modal.get_node("TalentTreePanel")
	assert(CampaignProgressionService.talent_specialization_index(owned, definition) == 1 and saves == 1)
	var tree := panel.get_node("TalentTree1") as Control
	assert(tree.visible and panel.get_node("TreeTabLabel1").get_theme_font_size("font_size") == 20)
	assert(panel.get_node("TreeTabLabel1").vertical_alignment == VERTICAL_ALIGNMENT_TOP)
	panel.get_node("TreeTabButton0").pressed.emit()
	assert(panel.get_node("TalentTree0").visible and not tree.visible)
	assert(panel.get_node("TalentPoints").text == "Reset to fire to add points here")
	panel.get_node("TreeTabButton1").pressed.emit()
	var first_move := &"base:move/spark/tier1"
	_node_button(tree, first_move).pressed.emit()
	await process_frame
	modal = presenter.get_node("TalentTreeModal")
	panel = modal.get_node("TalentTreePanel")
	tree = panel.get_node("TalentTree1")
	assert(first_move in owned.learned_move_ids and saves == 2)
	assert(CampaignProgressionService.available_talent_points(owned, definition) == 0)
	var next_tier := _node_button(tree, &"base:move/spark/tier2")
	assert(next_tier != null and not next_tier.get_meta("purchasable") and next_tier.get_meta("visually_active"), "Accessible nodes remain colored when points run out")
	assert(is_equal_approx(next_tier.material.get_shader_parameter("saturation"), 1.0))
	panel.get_node("ResetTalentsButton").pressed.emit()
	await process_frame
	assert(owned.learned_move_ids == definition.initial_move_ids and saves == 3)
	modal = presenter.get_node("TalentTreeModal")
	panel = modal.get_node("TalentTreePanel")
	assert(_node_button(panel, definition.specialization_move_ids[0]) != null)
	# Inspect every imported passive stat tooltip, not only one speed move.
	var tooltip := BattleMoveTooltip.new()
	root.add_child(tooltip)
	var passive_stat_moves := 0
	for content in catalog._by_id.values():
		if not content is MoveDefinition or not (content.is_passive or content.is_global_passive):
			continue
		for effect in content.effects:
			if effect.kind != EffectDefinition.Kind.STAT_PERCENT:
				continue
			tooltip.show_move(content)
			assert(tooltip.details.get_parsed_text().contains("%s by %d%%" % [String(effect.stat_type_id).get_file(), effect.amount]))
			passive_stat_moves += 1
	assert(passive_stat_moves > 20)
	tooltip.show_move(catalog.get_definition(&"base:move/burn/tier1"))
	assert(tooltip.type_icon.texture == SourceMenuArt.texture("moveDescription_type_fire"))
	tooltip.hide()
	if "--capture-talents" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://development/talent_specialization_current.png")
	_node_button(panel, definition.specialization_move_ids[1]).pressed.emit()
	await process_frame
	modal = presenter.get_node("TalentTreeModal")
	panel = modal.get_node("TalentTreePanel")
	_node_button(panel, &"base:move/spark/tier1").mouse_entered.emit()
	assert(presenter._active_talent_tooltip.visible)
	if "--capture-talents" in OS.get_cmdline_user_args():
		presenter.set_process(false)
		presenter._active_talent_tooltip.follow_mouse(panel.position + Vector2(100, 210) * factor, Vector2(root.size))
		await create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://development/talent_advanced_current.png")
	panel.get_node("CloseButton").pressed.emit()
	await process_frame
	assert(not presenter._sequence_active)
	tooltip.queue_free()
	presenter.queue_free()
	await process_frame
	print("PASS: campaign talent scaling, specialization, branch switching, atomic refresh names, reset, access-vs-purchase visuals, close and %d passive stat tooltip descriptions" % passive_stat_moves)
	quit()
