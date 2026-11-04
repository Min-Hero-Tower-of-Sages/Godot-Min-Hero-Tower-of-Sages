class_name ModWorkshopController
extends Node

## Shell glue for the Mod Workshop: opens it over the title screen and runs a
## test battle with the edited mod active, then comes back to the same mod.
## The Workshop always edits against the unmodded catalog, so "change a minion"
## starts from the real values rather than another save's mods.

const VIEW := preload("res://src/presentation/mod_workshop/mod_workshop_view.gd")
const BATTLE_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AUTOBUILDER := preload("res://src/domain/battle/legacy_minion_autobuilder.gd")

var shell: Control

func show_workshop(resume: Dictionary = {}) -> void:
	if shell.runtime == null: return
	UserModService.deactivate(shell.runtime.catalog)
	shell._clear_dialog(true)
	var view: Control = VIEW.new()
	view.name = "ModWorkshop"
	view.catalog = shell.runtime.catalog
	shell.interaction_dialog = view
	shell._attach_interaction_dialog()
	view.closed.connect(func() -> void: shell._clear_dialog())
	view.test_battle_requested.connect(_test_battle)
	view.open(resume)

func _test_battle(mod_id: String, spec: Dictionary) -> void:
	if shell._room_transition_active or shell.current_battle != null: return
	var catalog: ContentCatalog = shell.runtime.catalog
	var activated := UserModService.activate(catalog, [{"id": mod_id}])
	var view: Control = shell.interaction_dialog
	if not activated.ok:
		view.show_message("The mod could not be loaded:\n%s" % activated.message)
		return
	var setup := sandbox_setup(catalog, spec)
	if not setup.ok:
		UserModService.deactivate(catalog)
		view.show_message(setup.message)
		return
	shell._clear_dialog(true)
	shell._room_transition_active = true
	var battle: Node = BATTLE_SCENE.instantiate()
	battle.settings_service = shell._settings
	battle.visible = false
	battle.audio_controller.music_owner = shell._campaign_audio
	battle.sandbox_finished.connect(_on_test_finished.bind(battle, mod_id), CONNECT_ONE_SHOT)
	shell._campaign_audio.fade_music_to(0.0, 0.5)
	await shell._fade_campaign_screen_out()
	shell._clear_game_screen()
	shell.current_battle = battle
	shell.screen_host.add_child(battle)
	battle.call("begin_sandbox_battle", {"setup": setup.setup, "encounter_id": String(spec.get("encounter_id", ""))})
	battle.visible = true
	await shell._finish_campaign_screen_transition()

func _on_test_finished(battle: Node, mod_id: String) -> void:
	while shell._room_transition_active:
		await get_tree().process_frame
	shell._room_transition_active = true
	await shell._fade_campaign_screen_out()
	if is_instance_valid(battle): battle.queue_free()
	shell.current_battle = null
	shell._campaign_audio.play_music("titleTrack", 1.0, 1.0)
	shell._build_title_screen(true)
	shell._show_save_slots()
	await shell._finish_campaign_screen_transition()
	show_workshop({"mod_id": mod_id, "tab": "Test"})

## Both teams for a sandbox battle. `spec`: {"player": [{minion, level,
## moves}], "encounter_id": trainer to fight, or "enemy": [...] instead}.
static func sandbox_setup(catalog: ContentCatalog, spec: Dictionary) -> Dictionary:
	var combatants: Array[Dictionary] = []
	var player: Array = spec.get("player", [])
	if player.is_empty() or player.size() > 5: return {"ok": false, "message": "Choose 1 to 5 minions for your test team."}
	for index in player.size():
		if not player[index] is Dictionary: return {"ok": false, "message": "Each test team slot must describe a minion."}
		var made := _combatant(catalog, player[index], 0, index, null)
		if not made.ok: return made
		combatants.append(made.combatant)
	var enemy: Array = spec.get("enemy", [])
	var encounter := catalog.get_definition(StringName(String(spec.get("encounter_id", "")))) as EncounterDefinition
	if not String(spec.get("encounter_id", "")).is_empty() and encounter == null: return {"ok": false, "message": "The selected trainer no longer exists. Choose another trainer."}
	if encounter != null:
		enemy = []
		for entry in encounter.team_entries:
			enemy.append({"minion": String(entry.get("definition_id", "")), "level": maxi(1, int(entry.get("level", 1)) + int(entry.get("source_level_offset", encounter.source_level_offset))), "moves": Array(entry.get("move_ids", [])).map(func(value: Variant) -> String: return String(value)), "autobuild": true})
	if enemy.is_empty() or enemy.size() > 5: return {"ok": false, "message": "Choose a trainer, or 1 to 5 opposing minions."}
	var rng := BattleRng.new(hash("workshop/%s" % JSON.stringify(spec)))
	for index in enemy.size():
		if not enemy[index] is Dictionary: return {"ok": false, "message": "Each opposing team slot must describe a minion."}
		var made := _combatant(catalog, enemy[index], 1, index, rng)
		if not made.ok: return made
		combatants.append(made.combatant)
	return {"ok": true, "setup": {"battle_id": "workshop-test", "tie_first_team": 0, "combatants": combatants}}

static func _combatant(catalog: ContentCatalog, member: Dictionary, team: int, slot: int, rng: BattleRng) -> Dictionary:
	var definition := catalog.get_definition(StringName(String(member.get("minion", "")))) as MinionDefinition
	if definition == null: return {"ok": false, "message": "Test team slot %d needs a minion." % (slot + 1)}
	var level := clampi(int(member.get("level", 10)), 1, 99)
	var moves: Array[StringName] = []
	for move_id in member.get("moves", []):
		if not catalog.get_definition(StringName(String(move_id))) is MoveDefinition: return {"ok": false, "message": "Test team slot %d uses a move that no longer exists: %s" % [slot + 1, move_id]}
		moves.append(StringName(String(move_id)))
	if bool(member.get("autobuild", false)) and rng != null:
		moves = AUTOBUILDER.new().build(definition, level, moves, catalog, rng)
	elif moves.is_empty():
		moves.append_array(definition.initial_move_ids)
		moves.append_array(definition.specialization_move_ids)
	var stats := LegacyMinionStats.current_stats(definition, level)
	return {"ok": true, "combatant": {
		"instance_id": "%s-%d" % ["player" if team == 0 else "enemy", slot + 1], "definition_id": definition.id,
		"team": team, "slot_index": slot, "level": level, "type_ids": definition.type_ids.duplicate(), "move_ids": moves,
		"base_max_health": int(stats.health), "max_health": int(stats.health), "health": int(stats.health),
		"base_max_energy": int(stats.energy), "max_energy": int(stats.energy), "energy": int(stats.energy),
		"attack": int(stats.attack), "healing": int(stats.healing), "speed": int(stats.speed),
		"max_attack_stat": LegacyMinionStats.max_attack_stat(definition), "max_healing_stat": LegacyMinionStats.max_healing_stat(definition),
	}}
