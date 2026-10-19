extends SceneTree

const SHINIES := preload("res://src/application/campaign_shiny_service.gd")

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var runtime := root.get_node("CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	assert(catalog.ensure_index().is_empty())
	var state := CampaignState.new()
	state.active_mods = {"shinies": true}
	assert(CampaignModService.normalize(state.active_mods) == state.active_mods)
	var owned := OwnedMinionState.new()
	owned.instance_id = &"shiny-fixture"
	owned.definition_id = &"base:minion/tiger_1"
	owned.level = 60
	owned.experience = 60000
	owned.learned_move_ids = [&"base:move/claw/tier1"]
	SHINIES.initialize_new(owned, state, catalog, 0)
	assert(owned.is_shiny and owned.shiny_line_id == owned.definition_id)
	state.party.append(owned)
	var restored := OwnedMinionState.from_dictionary(JSON.parse_string(JSON.stringify(owned.to_dictionary())))
	assert(restored.is_shiny and restored.shiny_line_id == owned.shiny_line_id)
	assert(owned.duplicate_state().is_shiny)
	var normal := OwnedMinionState.from_dictionary({"instance_id": "old", "definition_id": "base:minion/tiger_1"})
	assert(not normal.is_shiny, "Old saves/import fields default to normal")
	SHINIES.initialize_new(normal, state, catalog, 511)
	assert(not normal.is_shiny)
	var disabled := CampaignState.new()
	SHINIES.initialize_new(normal, disabled, catalog, 0)
	assert(not normal.is_shiny)
	var setup := CampaignProgressionService.party_setup_combatants(state, catalog)
	assert(setup.ok and setup.combatants[0].is_shiny and setup.combatants[0].shiny_line_id == String(owned.shiny_line_id))
	var original_line := owned.shiny_line_id
	assert(CampaignProgressionService.evolve_owned_minion(owned, catalog).ok)
	assert(owned.is_shiny and owned.shiny_line_id == original_line)
	var view := BattleCombatantView.new()
	root.add_child(view)
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	var texture := load("res://content/base/art/battle/minions/normalTiger2.png") as Texture2D
	view.setup(setup.combatants[0], definition, texture, catalog)
	assert(view.minion_sprite.material.shader == MinionPaletteService.SHADER)
	view.play_source_condition_tint(&"poison")
	assert(view.minion_sprite.material.get_shader_parameter("hue_shift") == 0.5, "Status tint doesn't replace shiny palette")
	view.queue_free()
	var session := CampaignSession.new()
	session.catalog = catalog
	session.save_repository = MemoryRepository.new()
	var party: Array[OwnedMinionState] = [owned]
	assert(session.start_new(&"base:campaign/standard_tower", party, {}, 1, false, {"shinies": true}).ok)
	# Isolated room exercises the real egg transaction without depending on
	# the historical source graph's room names.
	var eggery := RoomDefinition.new()
	eggery.id = &"test:room/shiny_eggery"
	eggery.interactions = [{"kind": &"egg_pick", "source_zone_id": 0, "candidates": ["base:minion/tiger_1"], "weights": [100]}]
	catalog._by_id[eggery.id] = eggery
	session.state.current_room_id = eggery.id
	session.state.room_state.current_room_id = String(eggery.id)
	session.state.room_state.erase("current_location")
	session.state.progression.eggery_picks_remaining = 1
	session.state.progression.eggery_taken_slots = []
	var egg: Dictionary = {}
	for interaction in eggery.interactions:
		if StringName(interaction.get("kind", "")) == &"egg_pick":
			egg = interaction
			break
	# A saved winning roll must survive an interrupted preview and acceptance.
	session.state.room_state[String(eggery.id)] = {"eggery_shiny_slots": {str(egg.source_zone_id): true}}
	var preview := session._pick_egg(egg)
	assert(preview.ok and preview.minion.is_shiny)
	assert(session.load(1).ok)
	assert(session.state.room_state[String(eggery.id)].eggery_shiny_slots[str(egg.source_zone_id)])
	preview = session._pick_egg(egg)
	assert(preview.ok and preview.minion.is_shiny)
	assert(session.finish_egg_selection(preview.minion.instance_id).ok)
	assert(session.load(1).ok and session.state.party.back().is_shiny)
	catalog._by_id.erase(eggery.id)
	print("PASS: 1/512 boundaries, defaults, save/clone/evolution identity, campaign battle setup and condition-compatible shiny material")
	quit()
