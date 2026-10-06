extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var session := CampaignSession.new()
	session.catalog = root.get_node("CampaignRuntime").catalog
	session.state = CampaignState.new()
	var owned := OwnedMinionState.new()
	owned.instance_id = &"gem-panel-fixture"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 5
	owned.experience = 5000
	owned.equipment_ids.assign([&"gem-panel-equipped"])
	session.state.party.append(owned)
	var gem := {"instance_id": "gem-panel-equipped", "tier": 2, "raw_stats": [9.0, 3.0, 0.0, 0.0, 0.0]}
	session.state.owned_gems.append(gem)
	var definition := MinionDefinition.new()
	definition.gem_slots = 1
	definition.locked_gem_slots = 1
	var before: Dictionary = session.state.to_dictionary()
	var storage := CampaignStorageMenuView.new()
	root.add_child(storage)
	storage.configure(session, Callable())
	var party := CampaignPartyMenuView.new()
	root.add_child(party)
	party.configure(session, func(_parent, _owned, _action) -> void: pass)
	for view in [storage, party]:
		var tooltip_parent: Control = view._menu if view == storage else view._source_root
		var page := Control.new()
		tooltip_parent.add_child(page)
		if view == storage:
			view._build_gems(page, owned, definition)
		else:
			view._gems(page, owned, definition)
		assert(not page.get_node("EmptyGemSocket0").visible, "Occupied socket must hide its empty artwork")
		assert(page.get_node("EquippedGem0").position == Vector2(22, 63))
		var native_size := SourceMenuArt.texture("menus_emptyGemSocket").get_size()
		assert(page.get_node("EmptyGemSocket1").size == native_size, "Empty sockets must keep their original bitmap dimensions")
		assert(page.get_node("EmptyGemSocket1").visible)
		assert(page.get_node("GemSlotAction0").texture_normal == SourceMenuArt.texture("menus_changeButton"))
		assert(page.get_node("GemSlotAction1").texture_normal == SourceMenuArt.texture("menus_gemLockedButton"))
		assert(page.get_node("GemSlotAction2").texture_normal == SourceMenuArt.texture("menus_gemPremiumButton"))
		assert(page.get_node("GemSlotAction1").disabled and page.get_node("GemSlotAction2").disabled)
		assert(page.get_node_or_null("GemSocketHit1") == null, "Locked socket must not open equipment selection")
		var hit := page.get_node("GemSocketHit0") as Button
		assert(hit.position == Vector2(22, 63) and hit.size == native_size)
		var requests: Array = []
		view.gems_requested.connect(func(id, socket) -> void: requests.append([id, socket]))
		hit.pressed.emit()
		assert(requests == [[&"gem-panel-fixture", 0]], "Socket artwork must route the exact minion/socket pair")
		hit.mouse_entered.emit()
		var tooltip := tooltip_parent.get_node("SourceEquippedGemTooltip") as PanelContainer
		assert(tooltip.visible)
		var title := tooltip.get_child(0).get_node("Title") as Label
		var description := tooltip.get_child(0).get_node("Description") as RichTextLabel
		assert(title.text == "Gem  (tier 2)")
		assert(description.get_parsed_text() == "+5 Health\n+2 Energy")
		assert(description.text.contains("#fc7979") and description.text.contains("#ca8ada"))
		hit.mouse_exited.emit()
		assert(not tooltip.visible)
	var inventory := CampaignGemMenuView.new()
	root.add_child(inventory)
	inventory.configure(session)
	inventory._show_tooltip(gem)
	assert(inventory._tooltip.get_script() == preload("res://src/presentation/source_gem_tooltip.gd"), "Inventory must use the same source gem tooltip as minion details")
	assert(inventory._tooltip.get_child(0).get_node("Description").get_parsed_text() == "+5 Health\n+2 Energy")
	assert(session.state.to_dictionary() == before, "Presentation checks must not alter equipment or currency")
	storage.queue_free()
	party.queue_free()
	inventory.queue_free()
	await process_frame
	await process_frame
	print("PASS: shared party/storage native sockets, occupied artwork, locked/premium distinctions, socket selection, colored gem stats and inventory tooltip reuse")
	quit(0)
