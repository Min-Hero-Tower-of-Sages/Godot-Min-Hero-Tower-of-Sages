extends SceneTree

var catalog: ContentCatalog
const MOD := {"gem_affinity": true}
const GEM_VALUES := [7, 11, 13, 17, 19]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	if not user_root.contains("/build/gem-affinity-profile/"):
		push_error("Use isolated build/gem-affinity-profile; this fixture writes saves.")
		quit(2)
		return
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	assert(_check_formulas())
	assert(await _check_saved_toggle())
	print("PASS: all five gem affinities, fractional bonuses, corrected Energy gem scaling, legacy/off parity, battle power/passives, real save/reload, atomic toggles and party/storage clamping")
	quit()

func _gem(id: String) -> Dictionary:
	var gem := CampaignGemFactory.create_random(1)
	gem.instance_id = id
	gem.raw_stats = GEM_VALUES.duplicate()
	return gem

func _check_formulas() -> bool:
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var owned := OwnedMinionState.new()
	owned.instance_id = &"affinity-formula"
	owned.definition_id = species.id
	owned.level = 20
	owned.ivs = {"health": 1, "energy": 2, "attack": 3, "healing": 4, "speed": 5}
	owned.learned_move_ids.assign(species.initial_move_ids)
	owned.equipment_ids.assign([&"mixed-gem"])
	var gems: Array[Dictionary] = [_gem("mixed-gem")]
	var stars := {"health": 1, "energy": 2, "attack": 3, "healing": 4, "speed": 5}
	var state := CampaignState.new()
	state.party.assign([owned])
	state.owned_gems.assign(gems)
	state.active_mods = MOD.duplicate()
	state.progression.star_upgrades = stars
	for affinity in CampaignGemFactory.STAT_IDS:
		owned.stat_bonus = affinity
		var no_gems := CampaignProgressionService.owned_stats(owned, species, -1, [], stars, false)
		var mod_no_gems := CampaignProgressionService.owned_stats(owned, species, -1, [], stars, false, MOD)
		assert(no_gems == mod_no_gems, "Base/IV Energy scaling must stay unchanged without gems")
		var legacy := CampaignProgressionService.owned_stats(owned, species, -1, gems, stars, false)
		assert(legacy == CampaignProgressionService.owned_stats(owned, species, -1, gems, stars, false, {"gem_affinity": false}))
		var changed := CampaignProgressionService.owned_stats(owned, species, -1, gems, stars, false, MOD)
		for index in 5:
			var stat_id: StringName = CampaignGemFactory.STAT_IDS[index]
			var stat := String(stat_id)
			var star_rate := 1.0 + int(stars[stat]) * (0.04 if stat == "healing" else 0.02)
			var affinity_rate := 1.05 if affinity == stat_id else 1.0
			var expected := float(GEM_VALUES[index]) * (1.2 if affinity == stat_id else 1.0) * star_rate * affinity_rate
			assert(is_equal_approx(changed[stat] - no_gems[stat], expected), "Incorrect modded gem contribution: %s / %s" % [affinity, stat])
			var old_expected := float(GEM_VALUES[index]) * star_rate * affinity_rate * (1.5 if stat == "energy" else 1.0)
			assert(is_equal_approx(legacy[stat] - no_gems[stat], old_expected), "Mod off changed legacy gem math")
		var setup := CampaignProgressionService.party_setup_combatants(state, catalog)
		assert(setup.ok)
		var combatant: Dictionary = setup.combatants[0]
		assert(combatant.max_health == int(changed.health) and combatant.max_energy == int(changed.energy))
		for stat in ["attack", "healing", "speed"]: assert(combatant[stat] == int(changed[stat]))
		var display := CampaignProgressionService.owned_display_stats(owned, species, catalog, state)
		for stat in changed: assert(display[stat] == int(changed[stat]))
		for pair in [["attack", "max_attack_stat"], ["healing", "max_healing_stat"]]:
			var stat: String = pair[0]
			var base: float = LegacyMinionStats.max_attack_stat(species, 3.0) if stat == "attack" else LegacyMinionStats.max_healing_stat(species, 4.0)
			var amount: float = GEM_VALUES[2] if stat == "attack" else GEM_VALUES[3]
			var expected := (base + amount * (1.2 if String(affinity) == stat else 1.0)) * (1.05 if String(affinity) == stat else 1.0) * (1.0 + int(stars[stat]) * (0.04 if stat == "healing" else 0.02))
			assert(is_equal_approx(combatant[pair[1]], expected), "Move power did not use boosted gem stats")
			assert(is_equal_approx(combatant.source_raw_stats[pair[1]], expected))
	owned.stat_bonus = &"health"
	var aura := catalog.get_definition(&"base:move/hulk_inspiration/tier1") as MoveDefinition
	owned.learned_move_ids.append(aura.id)
	var health_before: float = CampaignProgressionService.owned_stats(owned, species, -1, gems, stars, false, MOD).health
	assert(CampaignProgressionService.owned_display_stats(owned, species, catalog, state).health > int(health_before))
	var skill := CampaignSkillGemService.create(catalog, 1)
	skill.instance_id = "skill-only"
	owned.equipment_ids.assign([&"skill-only"])
	assert(CampaignProgressionService.effective_gem_stat_bonus(owned, &"health", [skill], MOD) == 0.0)
	return true

func _check_saved_toggle() -> bool:
	var repository := SaveRepository.new()
	assert(repository.delete_slot(1).ok)
	var session := CampaignSession.new()
	session.catalog = catalog
	session.save_repository = repository
	assert(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "affinity-disk-"), {}, 1).ok)
	assert(not CampaignModService.enabled(session.state, "gem_affinity"))
	var owned: OwnedMinionState = session.state.party[0]
	owned.level = 20
	owned.experience = 20000
	owned.stat_bonus = &"energy"
	owned.equipment_ids.assign([&"affinity-owned"])
	session.state.owned_gems.assign([_gem("affinity-owned")])
	var species := catalog.get_definition(owned.definition_id) as MinionDefinition
	owned.persistent_energy = CampaignProgressionService.owned_display_stats(owned, species, catalog, session.state).energy
	var old_energy := owned.persistent_energy
	assert(session.save().ok)
	assert(session.set_mod_option("gem_affinity", true).ok)
	owned = session.state.party[0]
	var corrected := CampaignProgressionService.owned_display_stats(owned, species, catalog, session.state)
	assert(owned.persistent_energy == int(corrected.energy) and owned.persistent_energy < old_energy)
	var loaded := CampaignSession.new()
	loaded.catalog = catalog
	loaded.save_repository = repository
	assert(loaded.load(1).ok and loaded.state.active_mods.gem_affinity)
	assert(CampaignProgressionService.owned_display_stats(loaded.state.party[0], species, catalog, loaded.state) == corrected)
	var before: Dictionary = loaded.state.to_dictionary()
	loaded.save_redirect = func(_data: Dictionary) -> Dictionary: return {"ok": false, "message": "Fixture rejected toggle"}
	assert(not loaded.set_mod_option("gem_affinity", false).ok and loaded.state.to_dictionary() == before)
	loaded.save_redirect = Callable()
	var energy: int = loaded.state.party[0].persistent_energy
	assert(loaded.set_mod_option("gem_affinity", false).ok and loaded.state.party[0].persistent_energy == energy)
	assert(loaded.set_mod_option("gem_affinity", true).ok and loaded.state.party[0].persistent_energy == energy, "Switching cannot refill Energy")
	# Health-affinity gains do not heal, and storage obeys the same caps.
	var stored: OwnedMinionState = loaded.state.party.pop_at(0)
	stored.stat_bonus = &"health"
	loaded.state.storage.append(stored)
	assert(loaded.set_mod_option("gem_affinity", false).ok)
	stored = loaded.state.storage[0]
	var legacy_health: int = CampaignProgressionService.owned_display_stats(stored, species, catalog, loaded.state).health
	stored.persistent_health = legacy_health
	assert(loaded.set_mod_option("gem_affinity", true).ok and loaded.state.storage[0].persistent_health == legacy_health)
	stored = loaded.state.storage[0]
	stored.persistent_health = CampaignProgressionService.owned_display_stats(stored, species, catalog, loaded.state).health
	assert(loaded.set_mod_option("gem_affinity", false).ok and loaded.state.storage[0].persistent_health == legacy_health)
	var menu := CampaignModMenuView.new()
	root.add_child(menu)
	menu.configure(loaded)
	menu._open_category(3)
	menu._describe("gem_affinity")
	assert(menu._toggles.has("gem_affinity") and menu._description.text.contains("20%") and menu._description.text.contains("50%"))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/gem-affinity-menu.png")
	menu.free()
	return true
