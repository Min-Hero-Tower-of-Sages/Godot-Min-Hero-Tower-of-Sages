extends SceneTree

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	var reject := false
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		if reject: return {"ok": false, "message": "Rejected fixture save"}
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var session := CampaignSession.new()
	session.catalog = catalog
	var repository := MemoryRepository.new()
	session.save_repository = repository
	assert(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "debug-")).ok)
	assert(not session.set_debug_option("unlimited_money", true).ok)
	var settings := CampaignSettingsService.new()
	var view := CampaignSettingsView.new()
	root.add_child(view)
	view.configure(settings, session)
	assert(view.find_child("DebugMenuButton", true, false) == null)
	session.state.active_mods.debug_mode = true
	view.configure(settings, session)
	assert(view.find_child("DebugMenuButton", true, false) != null)
	view._open_debug()
	for option in CampaignDebugService.OPTIONS:
		assert(view.find_child("DebugToggle_%s" % option.id, true, false) != null)
	var before: Dictionary = session.state.to_dictionary(catalog.content_version, true)
	repository.reject = true
	assert(not session.set_debug_option("max_party_levels", true).ok)
	assert(session.state.to_dictionary(catalog.content_version, true) == before)
	repository.reject = false
	assert(session.set_debug_option("max_party_levels", true).ok)
	for owned in session.state.party: assert(owned.level == 60 and owned.experience >= 60000)
	assert(session.set_debug_option("max_party_levels", false).ok)
	assert(session.state.party[0].level == 60, "Disabling does not remove granted levels")
	assert(session.set_debug_option("unlimited_money", true).ok)
	session.state.progression.currency = 0
	CampaignGemEconomyService.refresh_shop(session.state, 1)
	assert(CampaignGemEconomyService.buy_shop_gem(session.state, 0).ok)
	assert(session.state.progression.currency == 0, "Free purchase preserves balance")
	assert(session.set_debug_option("unlimited_money", false).ok)
	assert(not CampaignGemEconomyService.buy_shop_gem(session.state, 1).ok)
	assert(session.set_debug_option("unlimited_stars", true).ok)
	var earned := CampaignProgressionService.total_earned_stars(session.state)
	var available := CampaignProgressionService.available_stars(session.state)
	assert(session.purchase_star_upgrade(0).ok)
	assert(CampaignProgressionService.total_earned_stars(session.state) == earned)
	assert(CampaignProgressionService.available_stars(session.state) == available)
	assert(session.set_debug_option("unlimited_stars", false).ok)
	assert(CampaignProgressionService.available_stars(session.state) == available)
	assert(not session.purchase_star_upgrade(0).ok)
	assert(session.reset_star_upgrades().ok and not session.state.progression.has("debug_free_star_cost"))
	assert(session.set_debug_option("full_keys", true).ok)
	assert(session.state.progression.floor_keys >= 3 and session.state.progression.eggery_keys >= 1)
	session.state.progression.floor_index = 31
	session.state.progression.floor_keys = 0
	session.state.progression.eggery_keys = 0
	assert(session.save().ok)
	assert(session.state.progression.floor_keys >= 3 and session.state.progression.eggery_keys >= 3)
	assert(session.set_debug_option("full_keys", false).ok)
	session.state.progression.floor_keys = 0
	session.state.progression.eggery_keys = 0
	assert(session.save().ok and session.state.progression.floor_keys == 0)
	assert(session.set_debug_option("force_shiny", true).ok)
	var new_minion := OwnedMinionState.new()
	new_minion.definition_id = &"base:minion/tiger_1"
	CampaignShinyService.initialize_new(new_minion, session.state, catalog, 511)
	assert(new_minion.is_shiny, "Force shiny works without regular Shinies mod")
	assert(not session.state.party[0].is_shiny, "Existing party stays unchanged")
	assert(session.load(1).ok and CampaignDebugService.enabled(session.state, "force_shiny"))
	session.state.active_mods.erase("debug_mode")
	assert(not CampaignDebugService.enabled(session.state, "force_shiny"))
	view.configure(settings, session)
	assert(view.find_child("DebugMenuButton", true, false) == null)
	# Restore gate only for isolated preview rendering.
	session.state.active_mods.debug_mode = true
	view.configure(settings, session)
	view._open_debug()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1050, 787)
		view._build_view()
		await process_frame
		var description := view.find_child("DebugDescription", true, false) as Label
		assert(description.size.x <= 290, "Debug text stays inside panel")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/debug-settings-preview.png")
	view.queue_free()
	print("PASS: gated debug UI, atomic saves, level60 party, free purchases/star upgrades, full normal/hard keys and forced shinies")
	quit()
