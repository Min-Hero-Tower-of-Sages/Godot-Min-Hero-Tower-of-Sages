extends SceneTree

class MemorySession extends CampaignSession:
	var reject := false
	func _save_candidate(candidate) -> Dictionary:
		assert(candidate.validation_errors(catalog).is_empty())
		var validation := save_repository.validate(candidate.to_dictionary(catalog.content_version))
		if not validation.ok: return validation
		return {"ok": false, "message": "Fixture rejection"} if reject else {"ok": true}

var catalog: ContentCatalog
var session: MemorySession
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run() -> void:
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	session = MemorySession.new()
	session.catalog = catalog
	session.state = CampaignState.new()
	session.state.campaign_id = &"base:campaign/standard_tower"
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.active_mods = {"skill_gems": true}
	session.state.progression.currency = 100000
	session.state.progression.sage_seals = 5
	session.state.party = CampaignProgressionService.starter_party(catalog, "skill-fixture-")
	for owned in session.state.party: owned.level = 60
	_check(CampaignModService.normalize({"skill_gems": true}).get("skill_gems", false), "Mod flag survives normalization")
	_check_recipes()
	_check_neutral_support_pool()
	_check_acquisition()
	_check_equipment()
	_check_transactions()
	await _check_ui()
	if failures.is_empty(): print("PASS: skill-gem recipes/ranks, field drops, Hard rewards/Talo, elemental restrictions, active/passive battle grants, JSON/toggle/unequip, forge transactions and rendered menus")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _stat(id: String, tier: int, colors: Array) -> Dictionary:
	var gem := CampaignGemFactory.create_random(tier)
	gem.instance_id = id
	gem.raw_stats = [0.0, 0.0, 0.0, 0.0, 0.0]
	for color in colors: gem.raw_stats[int(color)] = pow(3.0, tier)
	return gem

func _gems(colors: Array, tier: int = 6) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in 3: result.append(_stat("material-%d" % index, tier, [colors[index % colors.size()]]))
	return result

func _skill(move_id: StringName, id: String) -> Dictionary:
	var move := catalog.get_definition(move_id) as MoveDefinition
	assert(move != null)
	var gem := CampaignGemFactory.create_random(6)
	gem.merge({"instance_id": id, "kind": "skill", "move_id": String(move.id), "skill_level": move.tier,
		"skill_name": move.display_name, "skill_icon": String(move.buff_icon_name), "type_id": String(move.type_id), "stat_id": "", "stat_value": 0,
		"raw_stats": [1.0, 0.0, 0.0, 0.0, 0.0]}, true)
	return gem

func _check_recipes() -> void:
	for tier in range(1, 11):
		var level: int = [1, 1, 1, 2, 2, 3, 3, 4, 4, 5][tier - 1]
		_check(CampaignSkillGemService.level_for_tier(tier) == level, "Refined tier table %d" % tier)
		for color in 5:
			var preview := CampaignSkillGemService.forge_preview(session.state, catalog, _gems([color], tier))
			if not preview.get("ok", false):
				_check(false, "Recipe failed for tier %d color %d: %s" % [tier, color, preview])
				return
			_check(preview.get("ok", false) and preview.gem.type_id == "base:type/%s" % CampaignSkillGemService.COLOR_TYPES[color], "Single-color recipe")
			_check(preview.gem.skill_level == level and not preview.gem.has("move_id"), "Preview hides the random skill")
	for recipe in CampaignSkillGemService.RECIPES:
		var colors: Array[int] = []
		for value in recipe.split(","): colors.append(int(value))
		var preview := CampaignSkillGemService.forge_preview(session.state, catalog, _gems(colors))
		_check(preview.ok and preview.gem.type_id == "base:type/%s" % CampaignSkillGemService.RECIPES[recipe], "Triple-color recipe %s" % recipe)
		colors.reverse()
		_check(CampaignSkillGemService.forge_preview(session.state, catalog, _gems(colors)).gem.type_id == preview.gem.type_id, "Recipe is order-independent")
	_check(CampaignSkillGemService.forge_preview(session.state, catalog, _gems([0, 2, 3])).gem.type_id == "base:type/none", "Unlisted triple is non-elemental")
	_check(CampaignSkillGemService.forge_preview(session.state, catalog, _gems([0, 0, 1])).gem.type_id == "base:type/none", "Mixed duplicate colors are non-elemental")
	var mixed: Array[Dictionary] = [_stat("mix-a", 10, [0, 2]), _stat("mix-b", 10, [2]), _stat("mix-c", 10, [4])]
	_check(CampaignSkillGemService.forge_preview(session.state, catalog, mixed).gem.type_id == "base:type/normal", "Combined stat gems contribute all their colors")
	_check(not CampaignGemEconomyService.combine_preview(_gems([0], 10)).ok, "Stat combining still caps at tier 10")
	for level in range(1, 6):
		var pool := CampaignSkillGemService.candidates(catalog, level)
		var families: Dictionary = {}
		for move in pool:
			_check(move.tier <= level and not families.has(move.family_id), "One candidate per family, capped at requested rank")
			families[move.family_id] = true
		for family in [&"base:move_family/purge", &"base:move_family/stun"]:
			var capped := pool.filter(func(move: MoveDefinition) -> bool: return move.family_id == family)
			_check(capped.size() == 1 and capped[0].tier == 1, "%s stays available at rank 1 even for high-tier inputs" % family)
	session.state.progression.sage_seals = 4
	_check(not CampaignSkillGemService.forge_preview(session.state, catalog, _gems([0])).ok, "Forge requires Talo")
	session.state.progression.sage_seals = 5

func _check_neutral_support_pool() -> void:
	for tier in [1, 4, 6, 8, 10]:
		var preview := CampaignSkillGemService.forge_preview(session.state, catalog, _gems([0, 0, 1], tier))
		_check(preview.ok and preview.gem.type_id == "base:type/none", "Red/Red/Purple selects non-elemental support")
		var rank := CampaignSkillGemService.level_for_tier(tier)
		var pool := CampaignSkillGemService.candidates(catalog, rank, StringName(preview.gem.type_id), true)
		for family in ["taunt", "diamond_skin", "rock_skin", "mirror_skin", "mirror_coating"]:
			var expected := StringName("base:move/%s/tier%d" % [family, rank])
			_check(pool.any(func(move: MoveDefinition) -> bool: return move.id == expected), "Non-elemental forge can roll %s at its requested rank" % expected)
		for move in pool:
			_check(move.type_id == &"base:type/none" and CampaignSkillGemService.universal(move), "Non-elemental pool excludes attacks, negative effects and elemental moves")
	var strongest := CampaignSkillGemService.candidates(catalog, 5, &"base:type/none", true)
	_check(strongest.any(func(move: MoveDefinition) -> bool: return move.display_name == "Torment"), "Tier-10 inputs offer Torment rather than a lower-rank Taunt")
	var normal := CampaignSkillGemService.candidates(catalog, 5, &"base:type/normal")
	_check(normal.any(func(move: MoveDefinition) -> bool: return move.id == &"base:move/reflect_damage/tier5"), "Normal-type active Diamond Skin keeps its separate elemental recipe")

func _check_acquisition() -> void:
	var fields := 0
	for index in 4096:
		var gem := CampaignSkillGemService.field_gem(session.state, catalog, &"base:room/level_1_1_a", index, 5)
		if CampaignSkillGemService.is_skill(gem):
			fields += 1
			_check(int(gem.skill_level) <= 2, "Field skill gems cap at rank 2")
			_check(gem.move_id == CampaignSkillGemService.field_gem(session.state, catalog, &"base:room/level_1_1_a", index, 5).move_id, "Field roll stable for the same chest")
	_check(fields >= 400 and fields <= 630, "About one in eight field gem finds is a skill gem: %d/4096" % fields)
	print("Field skill-gem rate: ", fields, "/4096")
	for trainer_type in [&"TrainerType.HARD_TRAINER", &"TrainerType.EXPERT_TRAINER"]:
		var encounter := EncounterDefinition.new()
		encounter.id = StringName("fixture:%s" % trainer_type)
		encounter.source_trainer_type = trainer_type
		var state := CampaignState.new()
		state.active_mods = {"skill_gems": true}
		state.progression.floor_index = 31
		var rewards := CampaignProgressionService._grant_first_clear_rewards(state, encounter, catalog)
		_check(rewards.gems.size() == 1 and CampaignSkillGemService.is_skill(rewards.gems[0]) and rewards.gems[0].skill_level <= 3, "Hard map/extra trainers grant rank-3-roll skill gems")
		state.progression.completed_encounters = {String(encounter.id): true}
		_check(CampaignProgressionService._grant_first_clear_rewards(state, encounter, catalog).get("gems", []).is_empty(), "No duplicated trainer rewards on replay")
		state.progression.completed_encounters = {}
		state.progression.floor_index = 0
		_check(not CampaignSkillGemService.is_skill(CampaignProgressionService._grant_first_clear_rewards(state, encounter, catalog).gems[0]), "Standard expert rewards remain stat gems")
	var talo := EncounterDefinition.new()
	talo.id = &"fixture:talo"
	talo.source_trainer_type = &"TrainerType.TRAINER_GYM_5"
	talo.rewards = {"first_clear": {"sage_seals": 1}}
	var state := CampaignState.new()
	state.active_mods = {"skill_gems": true}
	state.progression.sage_seals = 4
	_check(CampaignProgressionService._grant_first_clear_rewards(state, talo, catalog).gems.is_empty() and CampaignSkillGemService.forge_unlocked(state), "Talo unlocks Forge instead of a stat gem")
	state.active_mods.clear()
	state.progression.sage_seals = 4
	_check(CampaignProgressionService._grant_first_clear_rewards(state, talo, catalog).gems[0].tier == 10, "Vanilla Talo reward remains tier 10")
	_check(not CampaignSkillGemService.is_skill(CampaignSkillGemService.field_gem(state, catalog, &"fixture:room", 0, 5)), "Disabled mod keeps field drops vanilla")
	var actual_talo := catalog.get_definition(&"base:encounter/floor25_trainer_0") as EncounterDefinition
	_check(actual_talo != null, "Actual Talo encounter is present")
	if actual_talo != null:
		state.active_mods.skill_gems = true
		_check(preload("res://src/application/source_trainer_dialogue.gd").for_encounter(actual_talo, state).after_win_text.contains("Random Forge"), "Talo explains the mod reward")
		_check(not preload("res://src/application/source_trainer_dialogue.gd").for_encounter(actual_talo).after_win_text.contains("Random Forge"), "Dialogue overlay leaves vanilla source data unchanged")

func _check_equipment() -> void:
	var holder: OwnedMinionState = session.state.party[0]
	var ally: OwnedMinionState = session.state.party[1]
	var original_moves := holder.learned_move_ids.duplicate()
	var original_points := CampaignProgressionService.available_talent_points(holder, catalog.get_definition(holder.definition_id))
	var active := _skill(&"base:move/fire_ram/tier3", "active-gem")
	var aura := _skill(&"base:move/hulk_inspiration/tier3", "aura-gem")
	session.state.owned_gems.assign([active, aura])
	_check(session.equip_gem(&"active-gem", holder.instance_id, 0).ok, "Active skill equips")
	_check(session.equip_gem(&"aura-gem", holder.instance_id, 1).ok, "Party passive equips")
	holder = session.state.party[0]
	_check(CampaignProgressionService.effective_move_ids(holder, catalog, session.state).has(&"base:move/fire_ram/tier3"), "Equipped skill is available")
	_check(holder.learned_move_ids == original_moves and CampaignProgressionService.available_talent_points(holder, catalog.get_definition(holder.definition_id)) == original_points, "Gems do not spend talent points or alter learned moves")
	for stat in CampaignGemFactory.STAT_IDS: _check(CampaignGemEquipmentService.gem_stat_bonus(holder, stat, session.state.owned_gems) == 0, "Skill gem artwork grants no raw stats")
	var entries: Array = CampaignProgressionService.party_setup_combatants(session.state, catalog).combatants
	_check(&"base:move/fire_ram/tier3" in entries[0].move_ids, "Battle setup includes the granted move")
	_check_battle_use(entries)
	var combatants: Dictionary = {}
	for entry in entries: combatants[StringName(entry.instance_id)] = CombatantState.from_setup(entry)
	var target: CombatantState = combatants[ally.instance_id]
	var baseline := int(entries[1].base_max_health)
	_check(LegacyCombatModifiers.effective_max_health(target, catalog, combatants) > baseline, "Living holder provides the party HP aura")
	combatants[holder.instance_id].defeated = true
	_check(LegacyCombatModifiers.effective_max_health(target, catalog, combatants) == baseline, "Aura ends when the holder dies")
	var falcona := catalog.get_definition(&"base:minion/waterbird_3") as MinionDefinition
	var cern := _skill(&"base:move/overload/tier5", "cern")
	_check(not CampaignSkillGemService.can_equip(session.state, catalog, cern, falcona).ok, "Falcona cannot equip Electric Cern Reaction")
	_check(CampaignSkillGemService.can_equip(session.state, catalog, aura, falcona).ok, "Universal stat aura ignores elemental restrictions")
	_check(CampaignSkillGemService.universal(catalog.get_definition(&"base:move/reflect_damage/tier5")), "Ally reflection ignores inactive enemy-effect entries")
	var encoded := JSON.parse_string(JSON.stringify(session.state.to_dictionary())) as Dictionary
	var reloaded := CampaignState.new()
	reloaded.load_dictionary(encoded)
	_check(CampaignProgressionService.effective_move_ids(reloaded.party[0], catalog, reloaded).has(&"base:move/fire_ram/tier3"), "Skill gems survive JSON reload")
	reloaded.active_mods.skill_gems = false
	_check(not CampaignProgressionService.effective_move_ids(reloaded.party[0], catalog, reloaded).has(&"base:move/fire_ram/tier3"), "Disabling mod suspends equipped skills")
	_check(CampaignGemEquipmentService.unequip_gem(reloaded, catalog, holder.instance_id, 0).ok, "Disabled skill gems remain removable")
	reloaded.active_mods.skill_gems = true
	reloaded.party[0].learned_move_ids.append(&"base:move/fire_ram/tier4")
	var stronger := _skill(&"base:move/fire_ram/tier5", "stronger-gem")
	reloaded.owned_gems.append(stronger)
	_check(CampaignGemEquipmentService.equip_gem(reloaded, catalog, &"stronger-gem", holder.instance_id, 0).ok, "A stronger gem can replace a lower-rank grant")
	var effective := CampaignProgressionService.effective_move_ids(reloaded.party[0], catalog, reloaded)
	_check(effective.has(&"base:move/fire_ram/tier5") and not effective.has(&"base:move/fire_ram/tier4"), "Only the highest family rank is exposed")
	CampaignGemEquipmentService.unequip_gem(reloaded, catalog, holder.instance_id, 0)
	_check(CampaignProgressionService.effective_move_ids(reloaded.party[0], catalog, reloaded).has(&"base:move/fire_ram/tier4"), "Unequipping restores the permanent lower rank")
	_check(session.unequip_gem(holder.instance_id, 0).ok and not CampaignProgressionService.effective_move_ids(session.state.party[0], catalog, session.state).has(&"base:move/fire_ram/tier3"), "Unequipping removes the grant")
	_check(not CampaignGemEconomyService.combine_preview([active, active, active]).ok, "Skill gems cannot enter normal combining")
	_check(not CampaignSkillGemService.forge_preview(session.state, catalog, [active, active, active]).ok, "Skill gems cannot enter Forge")
	_check(session.sell_gem(&"active-gem").ok, "Unequipped skill gems can be sold")

func _check_battle_use(entries: Array) -> void:
	var actor: Dictionary = entries[0].duplicate(true)
	actor.speed = 9999
	actor.source_raw_stats.speed = 9999
	var enemy: Dictionary = entries[1].duplicate(true)
	enemy.instance_id = "skill-gem-target"
	enemy.team = 1
	enemy.speed = 1
	enemy.source_raw_stats.speed = 1
	enemy.health = 1000000
	enemy.base_max_health = 1000000
	enemy.max_health = 1000000
	enemy.source_raw_stats.health = 1000000
	var engine := BattleEngine.new()
	var rules := RuleSetDefinition.new()
	var started := engine.start({"battle_id": "skill-gem-use", "tie_first_team": 0, "combatants": [actor, enemy]}, catalog, rules, BattleRng.new(8))
	_check(started.accepted, "Battle engine accepts a party equipped with skill gems")
	var decision := engine.get_decision()
	_check(decision.actor_id == actor.instance_id and decision.legal_moves.any(func(move: Dictionary) -> bool: return move.move_id == "base:move/fire_ram/tier3"), "Granted Fire Ram is offered as a legal battle action")
	var response := engine.submit(BattleCommand.new(StringName(actor.instance_id), BattleCommand.Kind.USE_MOVE, &"base:move/fire_ram/tier3", [], int(decision.revision)))
	_check(response.accepted, "Granted Fire Ram can be cast by its equipper")

func _check_transactions() -> void:
	for owned in session.state.party: owned.equipment_ids.clear()
	session.state.owned_gems.assign(_gems([0], 6))
	var ids: Array[StringName] = [&"material-0", &"material-1", &"material-2"]
	var before: Dictionary = session.state.to_dictionary()
	session.reject = true
	_check(not session.combine_gems(ids, 2, true).ok and session.state.to_dictionary() == before, "Rejected forge saves preserve materials and currency")
	session.reject = false
	var forged := session.combine_gems(ids, 2, true)
	_check(forged.ok and forged.gem.type_id == "base:type/fire" and forged.gem.skill_level <= 3, "Forge produces the previewed type/rank cap")
	_check(CampaignGemEquipmentService.inventory_slots(session.state)[30] == forged.gem.instance_id, "Forge result enters the displayed inventory page")
	_check(session.state.owned_gems.size() == 1 and int(session.state.progression.currency) == int(before.progression.currency) - forged.cost, "Forge consumes exactly three materials and its cost")

func _check_ui() -> void:
	root.size = Vector2i(1050, 787)
	session.state.owned_gems.assign(_gems([0, 2, 4], 10))
	var view := CampaignGemMerchantView.new()
	root.add_child(view)
	session.state.progression.sage_seals = 4
	view.configure_merchant(session, &"combine")
	_check(view._panel.get_node_or_null("SkillGemTab") != null, "Combiner has a Random Forge tab")
	_check(view._panel.get_node("SkillGemTab").disabled, "Forge tab is locked before Talo")
	view._set_forge(true)
	_check(not view._skill_forge, "Locked tab cannot activate Forge")
	session.state.progression.sage_seals = 5
	view._set_forge(true)
	for id in [&"material-0", &"material-1", &"material-2"]: view._select_gem(id)
	_check(not view._panel.get_node("MerchantAction_Forge").disabled, "Tier-10 materials enable Forge")
	view._show_tooltip(CampaignSkillGemService.forge_preview(session.state, catalog, _gems([0, 2, 4], 10)).gem)
	view._tooltip.set_process(false)
	await process_frame
	await process_frame
	view._tooltip._place_at_canvas_point(Vector2(650, 390))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-forge-preview.png")
	view._show_recipes()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-forge-recipes.png")
	view._close_recipes()
	view._combine()
	var gem: Dictionary = session.state.owned_gems[0]
	_check(CampaignSkillGemService.is_skill(gem) and gem.skill_level <= 5, "Forge button produces a skill gem")
	view._select_gem(StringName(gem.instance_id))
	_check(view._materials.is_empty(), "Skill gem selection is refused as a crafting material")
	view._show_tooltip(gem)
	view._tooltip.set_process(false)
	await process_frame
	await process_frame
	view._tooltip._place_at_canvas_point(Vector2(650, 390))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-forge-result.png")
	view.free()
	await _check_party_ui()

func _check_party_ui() -> void:
	var holder: OwnedMinionState = session.state.party[0]
	session.state.owned_gems.assign([_skill(&"base:move/fire_ram/tier3", "ui-active"), _skill(&"base:move/hulk_inspiration/tier3", "ui-aura")])
	holder.equipment_ids.assign([&"ui-active", &"ui-aura"])
	var shell = load("res://src/application/application_shell.gd").new()
	shell.runtime = {"catalog": catalog, "session": session}
	var party := CampaignPartyMenuView.new()
	party._selected = 0
	party._showing_details = true
	party._tab = 1
	root.add_child(party)
	party.configure(session, Callable(shell, "_build_party_menu_row"))
	_check(party.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text.contains("Fire Ram")), "Party Moves tab displays the equipped skill")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-gem-party-moves.png")
	party._choose_tab(2)
	var page := party._detail.get_node("DetailPage")
	page.get_node("GemSocketHit0").mouse_entered.emit()
	var tooltip = party._source_root.get_node("SourceEquippedGemTooltip")
	_check(tooltip._skill_details.title.text.contains("Fire Ram Gem"), "Equipped gem tooltip resolves the actual move")
	tooltip.set_process(false)
	await process_frame
	await process_frame
	tooltip._place_at_canvas_point(Vector2(495, 290))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-gem-party-sockets.png")
	party.free()
	shell.free()
	# An incompatible skill is visible but its equip action is disabled.
	session.state.party[1].definition_id = &"base:minion/waterbird_3"
	session.state.owned_gems.append(_skill(&"base:move/overload/tier5", "ui-cern"))
	var inventory := CampaignGemMenuView.new()
	root.add_child(inventory)
	inventory.configure(session, session.state.party[1].instance_id, 0)
	inventory._selected_gem = &"ui-cern"
	inventory._refresh()
	_check(inventory._panel.get_node("GemEquip").disabled, "Falcona's equip button rejects the Electric gem")
	inventory.free()
