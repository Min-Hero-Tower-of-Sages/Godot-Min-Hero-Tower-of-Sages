extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	assert(catalog.ensure_index().is_empty())
	var chart := catalog.get_type_chart()
	var move := MoveDefinition.new()
	move.type_id = &"base:type/fire"
	var effect := EffectDefinition.new()
	effect.kind = EffectDefinition.Kind.DAMAGE
	effect.amount = 10
	effect.uses_type_effectiveness = true
	move.effects = [effect]
	var target := {"instance_id": "enemy", "team": 1, "type_ids": [&"base:type/plant"]}
	var rows := TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart)
	assert(rows.size() == 1 and is_equal_approx(rows[0].multiplier, 1.5))
	assert(rows[0].text.contains("Super effective"))
	assert(rows[0].compact == "↑ ×1.5")
	target.type_ids = [&"base:type/plant", &"base:type/ice"]
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart)[0].text.contains("2.25"))
	target.type_ids = [&"base:type/plant", &"base:type/water"]
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart)[0].text == "Normal · ×1")
	target.type_ids = [&"base:type/fire", &"base:type/water"]
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart)[0].text.contains("0.44"))
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart, false)[0].text == "Unknown matchup")
	effect.kind = EffectDefinition.Kind.PERIODIC_DAMAGE
	assert(not TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart).is_empty())
	effect.kind = EffectDefinition.Kind.SHIELD
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart).is_empty())
	var spark := catalog.get_definition(&"base:move/spark/tier2") as MoveDefinition
	var caster := {"instance_id": "actor", "team": 0, "type_ids": [&"base:type/energy"]}
	assert(TypeEffectivenessPreview.hints(spark, &"actor", 0, caster, chart).is_empty(), "Offensive Spark never previews its caster")
	var same_type_enemy := {"instance_id": "enemy", "team": 1, "type_ids": [&"base:type/energy"]}
	assert(TypeEffectivenessPreview.hints(spark, &"actor", 0, same_type_enemy, chart)[0].compact == "↓ ×0.67", "Same-type enemy resistance is real")
	effect.kind = EffectDefinition.Kind.HEAL
	effect.target_scope = EffectDefinition.TargetScope.ALLY_TARGETS
	target.team = 0
	target.type_ids = [&"base:type/plant"]
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart)[0].text.contains("Healing reduced"))
	effect.uses_type_effectiveness = false
	assert(TypeEffectivenessPreview.hints(move, &"actor", 0, target, chart).is_empty())
	var guide := TypeGuideView.new()
	guide.configure(catalog)
	root.add_child(guide)
	await process_frame
	assert(guide._types.size() == 15 and guide._type_buttons.size() == 15)
	assert(root.get_visible_rect().encloses(guide._panel.get_global_rect()))
	guide._select_type(&"base:type/water")
	guide._healing_tab.pressed.emit()
	assert(guide.healing and guide.selected_type == &"base:type/water")
	# Every supported type and both directions can build without fixed tables.
	for type in guide._types:
		guide._select_type(type.id)
		guide._set_healing(false)
		guide._set_healing(true)
	guide._select_type(&"base:type/fire")
	guide._set_healing(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/type-guide-preview.png")
	guide.queue_free()
	await process_frame
	var pedia := CampaignMinionPediaView.new()
	root.add_child(pedia)
	pedia.configure(catalog, CampaignState.new())
	var selection := pedia._selected
	pedia._open_type_guide()
	assert(not pedia._panel.visible, "No doubled frames behind nested guide")
	var pedia_guide := pedia.get_node("TypeGuide") as TypeGuideView
	assert(pedia_guide != null)
	pedia_guide.closed.emit()
	assert(pedia.get_node_or_null("TypeGuide") == null and pedia._selected == selection and pedia._panel.visible)
	var entry := pedia.find_child("TypeGuideEntry", true, false) as Button
	assert(entry.get_theme_stylebox("normal") is StyleBoxTexture)
	var portrait_frame := pedia._panel.get_node("MinionPortraitFrame") as TextureRect
	assert(entry.position.y >= 30, "Header clears the outer and inset frame rims")
	assert(portrait_frame.position.y - entry.get_rect().end.y >= 12, "Header and portrait have a real gap")
	assert(portrait_frame.get_rect().end.y <= 288, "Details/footer are not pushed down")
	var entry_caption := entry.get_node("Caption") as Label
	assert(entry.text.is_empty() and entry_caption.vertical_alignment == VERTICAL_ALIGNMENT_TOP)
	assert(entry_caption.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png("res://build/type-guide-pedia-preview.png")
		var source_to_pixels := Vector2(capture.get_width(), capture.get_height()) / root.get_visible_rect().size
		var button_rect := entry.get_global_rect()
		var button_capture := capture.get_region(Rect2i(button_rect.position * source_to_pixels, button_rect.size * source_to_pixels))
		_check_caption_clearance(button_capture)
		var caption_area := entry.get_global_rect().grow(4)
		var closeup := capture.get_region(Rect2i(caption_area.position * source_to_pixels, caption_area.size * source_to_pixels))
		closeup.resize(closeup.get_width() * 3, closeup.get_height() * 3, Image.INTERPOLATE_NEAREST)
		closeup.save_png("res://build/type-guide-entry-closeup.png")
	pedia.queue_free()
	await process_frame
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	main.catalog = catalog
	main.start_overlay.visible = false
	main.result_overlay.visible = false
	main.forfeit_confirmation.visible = false
	var setup := {"tie_first_team": 0, "combatants": [
		{"instance_id": "player-1", "definition_id": "base:minion/fire_pig_1", "team": 0, "slot_index": 0, "level": 10, "speed": 100, "max_health": 200, "max_energy": 100, "move_ids": ["base:move/burn/tier1", "base:move/spark/tier2"]},
		{"instance_id": "enemy-1", "definition_id": "base:minion/grassgorilla_1", "team": 1, "slot_index": 0, "level": 10, "speed": 2, "max_health": 200, "type_ids": ["base:type/plant"], "move_ids": ["base:move/claw/tier1"]},
		{"instance_id": "enemy-2", "definition_id": "base:minion/fire_frog_1", "team": 1, "slot_index": 1, "level": 10, "speed": 1, "max_health": 200, "type_ids": ["base:type/fire"], "move_ids": ["base:move/claw/tier1"]},
	]}
	assert(main.controller.start(setup, catalog, RuleSetDefinition.new(), BattleRng.new(1)).accepted)
	main._sync_from_engine()
	main.busy = false
	main._build_move_buttons(main.controller.engine.get_decision())
	await create_timer(1.5).timeout
	var previous_state = runtime.session.state
	var discovery := CampaignState.new()
	discovery.progression.seen_minion_ids = ["base:minion/grassgorilla_1"]
	runtime.session.state = discovery
	main.settings_service.effectiveness_hints_enabled = true
	var enemy_view: BattleCombatantView = main.combatant_views["enemy-1"]
	enemy_view.state_cache.type_ids = [&"base:type/energy"]
	main._show_move_tooltip(spark)
	main._refresh_effectiveness_hints()
	assert(not main._effectiveness_badges.has("player-1"))
	var spark_badge: PanelContainer = main._effectiveness_badges["enemy-1"]
	assert(spark_badge.get_child(0).get_child(0).text == "↓ ×0.67")
	var bar_bounds := enemy_view.health_background_sprite.get_global_transform_with_canvas() * enemy_view.health_background_sprite.get_rect()
	assert(spark_badge.size.x <= 70 and is_equal_approx(spark_badge.get_global_rect().end.x, bar_bounds.end.x))
	var pinned := spark_badge.position
	main.move_tooltip.position = spark_badge.position
	main._layout_effectiveness_hints()
	assert(spark_badge.position == pinned, "Tooltip/selector cannot push an enemy hint over its caster")
	enemy_view.state_cache.type_ids = [&"base:type/plant"]
	main._clear_effectiveness_hints()
	main._refresh_effectiveness_hints()
	assert(not main._effectiveness_badges.has("enemy-1"), "Neutral matchups add no HUD clutter")
	var burn := catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	main._show_move_tooltip(burn)
	main._refresh_effectiveness_hints()
	assert(main._effectiveness_badges.size() == 2)
	var known_badge: PanelContainer = main._effectiveness_badges["enemy-1"]
	var unknown_badge: PanelContainer = main._effectiveness_badges["enemy-2"]
	assert(known_badge.get_child(0).get_child(0).text.contains("1.5"))
	assert(unknown_badge.get_child(0).get_child(0).text == "?")
	assert(known_badge.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	main._hide_move_tooltip()
	main._refresh_effectiveness_hints()
	assert(main._effectiveness_badges.is_empty())
	var legal: Dictionary = main.controller.engine.get_decision().legal_moves[0]
	main._choose_move(legal)
	main._refresh_effectiveness_hints()
	assert(not main.pending_move.is_empty() and main._effectiveness_badges.size() == 2)
	# State-cache engine teams must not confuse hints in a mirrored network POV.
	for view in main.combatant_views.values(): view.state_cache.team = 1 - view.team
	main._clear_effectiveness_hints()
	main._refresh_effectiveness_hints()
	assert(main._effectiveness_badges.size() == 2)
	var before: Dictionary = main.controller.engine.snapshot()
	var pending: Dictionary = main.pending_move.duplicate(true)
	main._open_type_guide()
	assert(is_instance_valid(main.type_guide) and main._effectiveness_badges.is_empty())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = main.combatant_views["enemy-1"].minion_sprite.global_position
	main._input(click)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main.type_guide._input(escape)
	assert(not is_instance_valid(main.type_guide))
	assert(main.pending_move == pending and main.controller.engine.snapshot() == before)
	main._refresh_effectiveness_hints()
	main.settings_service.effectiveness_hints_enabled = false
	main._refresh_effectiveness_hints()
	assert(main._effectiveness_badges.is_empty())
	main.settings_service.effectiveness_hints_enabled = true
	main._refresh_effectiveness_hints()
	if DisplayServer.get_name() != "headless":
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/type-hints-preview.png")
	main.busy = true
	main._refresh_effectiveness_hints()
	assert(main._effectiveness_badges.is_empty())
	var settings: CampaignSettingsService = main.settings_service
	var settings_view := CampaignSettingsView.new()
	root.add_child(settings_view)
	settings_view.configure(settings)
	assert(settings_view.find_child("EffectivenessHintsToggle", true, false) != null)
	settings_view._toggle_setting("type_hints")
	assert(not settings.effectiveness_hints_enabled)
	assert(not CampaignSettingsService.new().effectiveness_hints_enabled)
	settings_view._toggle_setting("type_hints")
	assert(settings.effectiveness_hints_enabled and CampaignSettingsService.new().effectiveness_hints_enabled)
	main.visible = false
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/type-hints-settings-preview.png")
	settings_view.queue_free()
	runtime.session.state = previous_state
	main.queue_free()
	await process_frame
	print("PASS: chart math, dual types, healing/DOT/utility, discovery, hover/target lifecycle, mirrored teams, guide/Pedia modal, bounds and persistent hint setting")
	quit()

func _check_caption_clearance(capture: Image) -> void:
	# Measure actual bright glyph pixels against the flat button face, not
	# the Font's line box (which includes substantial invisible top leading).
	var face_color := capture.get_pixel(int(capture.get_width() * 0.15), capture.get_height() / 2)
	var face_top := capture.get_height()
	var face_bottom := -1
	var ink_top := capture.get_height()
	var ink_bottom := -1
	for y in capture.get_height():
		var face := capture.get_pixel(int(capture.get_width() * 0.15), y)
		if absf(face.r - face_color.r) + absf(face.g - face_color.g) + absf(face.b - face_color.b) < 0.04:
			face_top = mini(face_top, y)
			face_bottom = maxi(face_bottom, y)
		for x in range(6, capture.get_width() - 6):
			var pixel := capture.get_pixel(x, y)
			if pixel.r > 0.9 and pixel.g > 0.9 and pixel.b > 0.9:
				ink_top = mini(ink_top, y)
				ink_bottom = maxi(ink_bottom, y)
	var top_gap := ink_top - face_top
	var bottom_gap := face_bottom - ink_bottom
	print("Caption clearances (rendered pixels): top ", top_gap, ", bottom ", bottom_gap)
	assert(top_gap >= 3 and bottom_gap >= 3, "Full glyphs stay clear of both bevels")
	assert(absi(top_gap - bottom_gap) <= 2, "Visible glyphs have balanced top/bottom clearance")
