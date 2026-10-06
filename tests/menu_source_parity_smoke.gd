extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var session := MemorySession.new()
	session.catalog = catalog
	session.state = CampaignState.new()
	for index in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("menu-parity-%d" % index)
		owned.definition_id = &"base:minion/fire_pig_1" if index == 0 else &"base:minion/tiger_1"
		owned.level = 5
		owned.experience = 5350
		session.state.party.append(owned)
	var storage := CampaignStorageMenuView.new()
	root.add_child(storage)
	storage.configure(session, Callable())
	var viewport_size := storage.get_viewport_rect().size
	var source_scale := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	assert(storage._menu.scale.is_equal_approx(Vector2.ONE * source_scale), "Storage must scale with the source stage, not fit its panel")
	assert(storage._menu.position.is_equal_approx((viewport_size - Vector2(700, 525) * source_scale) * 0.5), "Storage must fade at source stage origin")
	var first := storage._menu.get_node("StorageMinion0") as Control
	var portrait := first.get_node("SourceStoragePortrait") as Sprite2D
	assert(portrait.scale == Vector2(0.4, 0.4))
	assert((first.position + Vector2(first.size.x * 0.5, first.size.y)).is_equal_approx(Vector2(59, 132)), "Storage bitmap is not bottom-centered on the source grid")
	storage.call("_slot_pressed", &"menu-parity-0")
	storage.call("_change_box", 1)
	assert(storage._selected_id == &"menu-parity-0", "Ordinary page navigation must retain details selection")
	assert(storage._menu.has_node("StorageDetails"))
	storage.call("_change_box", 0)
	storage.call("_toggle_swap")
	assert(storage._swap_first_id == &"menu-parity-0" and storage._selected_id.is_empty(), "Entering swap mode must keep the current selection")
	assert(not storage._menu.has_node("StorageDetails"))
	storage.call("_toggle_swap")
	assert(storage._selected_id == &"menu-parity-0" and storage._swap_first_id.is_empty(), "Leaving swap mode must restore details for its selection")
	storage.call("_toggle_swap")
	storage.call("_slot_pressed", &"menu-parity-1")
	assert(storage._swap_animating, "Same-page swap does not animate")
	var menu_during_swap := storage._menu
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	storage.call("_unhandled_key_input", escape)
	storage.call("_toggle_swap")
	assert(storage._menu == menu_during_swap and storage._swap_animating, "Escape/toggling must not rebuild live swap targets")
	await create_timer(0.6).timeout
	assert(session.state.party[0].instance_id == &"menu-parity-1", "Party-to-party swap was silently ignored")
	assert(session.saves == 1 and not storage._swap_animating)
	storage.call("_slot_pressed", &"menu-parity-1")
	storage.call("_change_box", 1)
	assert(storage._swap_first_id == &"menu-parity-1", "Changing boxes loses the first swap selection")
	storage.call("_toggle_swap")
	assert(storage._selected_id == &"menu-parity-1", "Off-page swap selection must return to ordinary details")
	storage.call("_change_detail_tab", 1)
	var moves_page := Control.new()
	root.add_child(moves_page)
	storage.call("_build_moves", moves_page, session.state.party[0])
	assert(_art_count(moves_page, "menus_scrollButton_up") == 0 and _art_count(moves_page, "menus_scrollButton_down") == 0, "A single move page must not show paging arrows")
	var families := {}
	for definition in catalog._by_id.values():
		if definition is MoveDefinition and definition.available and not definition.is_passive and not families.has(definition.family_id):
			families[definition.family_id] = true
			session.state.party[0].learned_move_ids.append(definition.id)
			if session.state.party[0].learned_move_ids.size() >= 9:
				break
	storage.call("_build_moves", moves_page, session.state.party[0])
	assert(_art_count(moves_page, "menus_scrollButton_up") == 1 and _art_count(moves_page, "menus_scrollButton_down") == 1, "First page needs one active arrow and one source down-state bitmap")
	for child in moves_page.get_children():
		moves_page.remove_child(child)
		child.queue_free()
	storage._move_page = 1
	storage.call("_build_moves", moves_page, session.state.party[0])
	assert(_art_count(moves_page, "menus_scrollButton_up") == 2 and _art_count(moves_page, "menus_scrollButton_down") == 2, "Middle page must retain both source underlay bitmaps")
	for child in moves_page.get_children():
		if child is Label:
			assert(child.size.x == 250 and child.autowrap_mode == TextServer.AUTOWRAP_OFF, "Move names must use source single-line width")
	moves_page.queue_free()
	var pedia := CampaignMinionPediaView.new()
	root.add_child(pedia)
	pedia.configure(catalog, session.state)
	assert(pedia._panel.position == Vector2(5, 13), "Pedia is not at the source menu origin")
	var known_index := -1
	var unknown_index := -1
	for index in pedia._minions.size():
		if pedia._minions[index].id == &"base:minion/fire_pig_1":
			known_index = index
		elif not pedia._seen.has(String(pedia._minions[index].id)):
			unknown_index = index
	assert(known_index >= 0 and unknown_index >= 0)
	pedia.call("_select", known_index)
	var pedia_portrait := pedia._description.get_node("SourcePediaPortrait") as Sprite2D
	assert(pedia_portrait.position + Vector2(pedia_portrait.texture.get_width() * 0.5, pedia_portrait.texture.get_height()) == Vector2(174, 247))
	assert(not pedia._found_floors.is_empty(), "Pedia did not resolve campaign hatchery acquisition tables")
	pedia.call("_select", unknown_index)
	assert(pedia._description.get_node("SourcePediaPortrait").texture == SourceMenuArt.texture("unknownMinion"))
	pedia.call("_scroll_by", 3)
	await create_timer(0.6).timeout
	assert(is_equal_approx(pedia._list_holder.position.y, 19.0 - pedia._list_holder.size.y / 20.0 * 3))
	var tooltip := BattleMoveTooltip.new()
	root.add_child(tooltip)
	var move := MoveDefinition.new()
	move.display_name = "Tooltip fixture"
	move.type_id = &"base:type/ice"
	move.charge_turns = 1
	move.exhaust_turns = 2
	move.enemy_target_count = 3
	move.random_targets = true
	var stun := EffectDefinition.new()
	stun.kind = EffectDefinition.Kind.STUN
	stun.chance_percent = 35
	move.effects.append(stun)
	tooltip.show_move(move)
	var text := tooltip.details.get_parsed_text()
	assert(text.contains("Stun Chance: 35%") and text.contains("Enemies Hit: 3 random"))
	assert(text.contains("Charge: 1 turn") and text.contains("Exhaustion: 2 turns"))
	assert(tooltip.type_icon.visible and tooltip.type_icon.texture != null)
	assert(tooltip.type_icon.get_parent() == tooltip.details, "Type badge must overlay the source footer, not add an entire layout row")
	var paired := MoveDefinition.new()
	paired.display_name = "Combined debuff fixture"
	paired.type_id = &"base:type/fire"
	paired.enemy_target_count = 2
	# Execution order is deliberately unlike the source description order.
	for scope in [EffectDefinition.TargetScope.ACTOR, EffectDefinition.TargetScope.ENEMY_TARGETS]:
		var debuff := EffectDefinition.new()
		debuff.kind = EffectDefinition.Kind.STAT_STAGE
		debuff.amount = -1
		debuff.stat_type_id = &"base:stat/speed"
		debuff.chance_percent = 40
		debuff.target_scope = scope
		paired.effects.append(debuff)
	var damage := EffectDefinition.new()
	damage.kind = EffectDefinition.Kind.DAMAGE
	damage.amount = 30
	paired.effects.append(damage)
	tooltip.show_move(paired)
	text = tooltip.details.get_parsed_text()
	assert(text.begins_with("Damage: 30\nEnemies Hit: 2\nReduces target/your speed:"), text)
	assert(text.count("Reduces") == 1, "Paired self/target debuff must not duplicate the source description")
	assert(tooltip.details.text.contains("[color=#ffbd7c] (Chance 40%)"), "Debuff chance must use the source orange, not buff green")
	assert(paired.effects[0].target_scope == EffectDefinition.TargetScope.ACTOR, "Tooltip ordering must never reorder gameplay effects")
	var redirect := EffectDefinition.new()
	redirect.kind = EffectDefinition.Kind.REDIRECT_DAMAGE
	redirect.amount = 50
	paired.effects.append(redirect)
	tooltip.show_move(paired)
	assert(tooltip.details.get_parsed_text() == "Redirects 50% of damage to this minion", "Source redirection replaces the ordinary move description")
	await process_frame
	await process_frame
	assert(is_equal_approx(tooltip.type_icon.position.y, tooltip.details.get_content_height() - 11.0))
	storage.queue_free()
	pedia.queue_free()
	tooltip.queue_free()
	await process_frame
	await process_frame
	print("PASS: source storage stage geometry/selection continuity/guarded animated swap, Pedia layout/art/scroll and full tooltip fields")
	quit(0)

func _art_count(parent: Node, symbol: String) -> int:
	var expected := SourceMenuArt.texture(symbol)
	var count := 0
	for child in parent.get_children():
		if child is TextureRect and child.texture == expected:
			count += 1
		elif child is TextureButton and child.texture_normal == expected:
			count += 1
	return count
