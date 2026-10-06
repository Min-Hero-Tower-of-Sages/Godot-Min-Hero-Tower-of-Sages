extends SceneTree

class MemorySession extends CampaignSession:
	var reject := false
	func _save_candidate(candidate) -> Dictionary:
		assert(candidate.validation_errors(catalog).is_empty())
		return {"ok": false, "message": "Fixture rejection"} if reject else {"ok": true}

class RecordingAudio extends BattleAudioController:
	var sounds: Array[Dictionary] = []
	func play_sound(sound_id: String, volume: float = 1.0) -> bool:
		sounds.append({"id": sound_id, "volume": volume})
		return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var session := MemorySession.new()
	session.catalog = catalog
	session.state = CampaignState.new()
	session.state.campaign_id = &"base:campaign/standard_tower"
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.character = {"gender": "female"}
	session.state.progression.currency = 100.0
	var owned := OwnedMinionState.new()
	owned.instance_id = &"merchant-fixture"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 6
	session.state.party.append(owned)
	for id in ["a", "b", "c", "d", "other"]:
		var gem := CampaignGemFactory.create_random(2 if id == "other" else 1)
		gem.instance_id = id
		session.state.owned_gems.append(gem)
	assert(session.move_gem_to_slot(&"b", 45).ok)
	assert(session.refresh_gem_shop().ok)
	var audio := RecordingAudio.new()
	root.add_child(audio)
	var shop := CampaignGemMerchantView.new()
	root.add_child(shop)
	shop.configure_merchant(session, &"shop", audio)
	assert(shop.get_children().filter(func(child: Node) -> bool: return child is ColorRect).is_empty(), "NPC services do not invent a dimmed world")
	var buy := shop._panel.get_node("MerchantAction_Buy") as TextureButton
	assert(buy.disabled and is_equal_approx(buy.modulate.a, 0.3))
	assert(buy.get_child(0) is Label and buy.get_child(0).position == Vector2(-17, 8), "Caption shares its button's dimming and Flash inset")
	shop._page = 3
	shop._select_stock(0)
	var before: Dictionary = session.state.to_dictionary()
	session.reject = true
	shop._buy()
	assert(session.state.to_dictionary() == before and audio.sounds.is_empty())
	session.reject = false
	shop._buy()
	assert(shop._page == 3 and shop._stock_selection == -1)
	var inventory := CampaignGemEquipmentService.inventory_slots(session.state)
	assert(not inventory[46].is_empty() and inventory[45] == "b", "Purchase fills the first free slot at or after the displayed page")
	assert(audio.sounds.back().id == "menu_buyingItem" and is_equal_approx(audio.sounds.back().volume, 0.6))
	shop._select_stock(1)
	shop._refresh_stock()
	assert(shop._stock_selection == 1, "Refreshing preserves the selected shop position")
	shop._select_gem(StringName(inventory[46]))
	shop._sell()
	assert(shop._page == 0 and shop._selected_gem.is_empty() and audio.sounds.back().id == "tower_moneyPickup")
	shop.queue_free()
	await process_frame
	var combiner := CampaignGemMerchantView.new()
	root.add_child(combiner)
	combiner.configure_merchant(session, &"combine", audio)
	combiner._page = 3
	combiner._select_gem(&"b")
	combiner._select_gem(&"other")
	assert(combiner._materials == [&"b"])
	var warning := combiner._panel.get_node("SameTierWarning") as Label
	assert(warning.position == Vector2(336, 285) and warning.get_theme_color("font_color") == Color.hex(0xf42b2bff))
	combiner._select_gem(&"b")
	assert(combiner._materials.size() == 1, "A material cannot be selected twice")
	combiner._select_gem(&"c")
	combiner._select_gem(&"d")
	session.state.progression.currency = 0
	combiner._refresh()
	assert(combiner._panel.get_node("MoneyWarning").position == Vector2(487, 371))
	assert(combiner._panel.get_node("MerchantAction_Combine").disabled)
	session.state.progression.currency = 100
	combiner._refresh()
	assert(combiner._panel.get_node("MerchantAction_Combine").get_child(0).text == "Combine($3)")
	before = session.state.to_dictionary()
	session.reject = true
	combiner._combine()
	assert(session.state.to_dictionary() == before and combiner._materials.size() == 3)
	session.reject = false
	if "--capture-merchant" in OS.get_cmdline_user_args():
		combiner._message = ""
		combiner._refresh()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://development/merchant_combiner_current.png")
	combiner._combine()
	inventory = CampaignGemEquipmentService.inventory_slots(session.state)
	assert(combiner._page == 3 and combiner._materials.is_empty())
	assert(inventory[45].begins_with("slot-gem-combined-"))
	assert(session.state.owned_gems.size() == 3 and audio.sounds.back().id == "menu_buyingItem")
	assert(session.move_gem_to_slot(&"a", 90).ok)
	combiner._page = 6
	combiner._select_gem(&"a")
	before = session.state.to_dictionary()
	session.reject = true
	assert(not combiner._reset_materials() and session.state.to_dictionary() == before and combiner._materials == [&"a"])
	session.reject = false
	assert(combiner._reset_materials() and combiner._page == 0 and combiner._materials.is_empty())
	assert(CampaignGemEquipmentService.inventory_slots(session.state)[0] == "a")
	var closed_count := [0]
	combiner.closed.connect(func() -> void: closed_count[0] += 1)
	combiner._select_gem(&"a")
	combiner._return_from_merchant()
	assert(closed_count[0] == 1 and combiner._materials.is_empty() and CampaignGemEquipmentService.inventory_slots(session.state)[0] == "a")
	# Full tail: reject without spending money or losing the purchased gem.
	var tail_state := CampaignState.new()
	var last_gem := CampaignGemFactory.create_random(1)
	last_gem.instance_id = "tail-gem"
	tail_state.owned_gems.append(last_gem)
	var tail_slots: Array[String] = []
	tail_slots.resize(CampaignGemEquipmentService.INVENTORY_CAPACITY)
	for index in range(98 * 15, tail_slots.size()):
		var gem := CampaignGemFactory.create_random(1)
		gem.instance_id = "tail-%d" % index
		tail_state.owned_gems.append(gem)
		tail_slots[index] = gem.instance_id
	tail_slots[0] = "tail-gem"
	tail_state.progression.gem_inventory_slots = tail_slots
	assert(not CampaignGemEquipmentService.place_gem_from_page(tail_state, &"tail-gem", 98).ok)
	assert(tail_state.progression.gem_inventory_slots == tail_slots)
	combiner.queue_free()
	audio.queue_free()
	await process_frame
	print("PASS: source merchant captions/warnings, shop and combine page placement, sounds, selection/reset, rejected saves and full-tail preservation")
	quit()
