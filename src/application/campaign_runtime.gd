extends Node

const RECOVERED_CATALOG = preload("res://content/imported/recovered-20260911/catalog.tres")
const CAMPAIGN_PACK = preload("res://content/base/packs/campaign_slice.tres")
const FLOOR_2_PACK = preload("res://content/base/packs/floor_2_slice.tres")
const FLOOR_3_PACK = preload("res://content/base/packs/floor_3_slice.tres")
const FLOOR_3_TRAINER_PACK = preload("res://content/base/packs/floor_3_trainers.tres")
const FLOOR_4_PACK = preload("res://content/base/packs/floor_4_slice.tres")
const FLOOR_4_TRAINER_PACK = preload("res://content/base/packs/floor_4_trainers.tres")
const FLOOR_5_PACK = preload("res://content/base/packs/floor_5_slice.tres")
const FLOOR_5_TRAINER_PACK = preload("res://content/base/packs/floor_5_trainers.tres")
const FLOOR_6_PACK = preload("res://content/base/packs/floor_6_slice.tres")
const FLOOR_6_TRAINER_PACK = preload("res://content/base/packs/floor_6_trainers.tres")
const FLOOR_7_PACK = preload("res://content/base/packs/floor_7_slice.tres")
const FLOOR_7_TRAINER_PACK = preload("res://content/base/packs/floor_7_trainers.tres")
const FLOOR_8_PACK = preload("res://content/base/packs/floor_8_slice.tres")
const FLOOR_8_TRAINER_PACK = preload("res://content/base/packs/floor_8_trainers.tres")
const FLOOR_9_PACK = preload("res://content/base/packs/floor_9_slice.tres")
const FLOOR_9_TRAINER_PACK = preload("res://content/base/packs/floor_9_trainers.tres")
const FLOOR_10_PACK = preload("res://content/base/packs/floor_10_slice.tres")
const FLOOR_10_TRAINER_PACK = preload("res://content/base/packs/floor_10_trainers.tres")
const EXTENDED_TOWER_PACKS = [
	preload("res://content/base/packs/floor_11_slice.tres"),
	preload("res://content/base/packs/floor_11_trainers.tres"),
	preload("res://content/base/packs/floor_12_slice.tres"),
	preload("res://content/base/packs/floor_12_trainers.tres"),
	preload("res://content/base/packs/floor_13_slice.tres"),
	preload("res://content/base/packs/floor_13_trainers.tres"),
	preload("res://content/base/packs/floor_14_slice.tres"),
	preload("res://content/base/packs/floor_14_trainers.tres"),
	preload("res://content/base/packs/floor_15_slice.tres"),
	preload("res://content/base/packs/floor_15_trainers.tres"),
	preload("res://content/base/packs/floor_16_slice.tres"),
	preload("res://content/base/packs/floor_16_trainers.tres"),
	preload("res://content/base/packs/floor_17_slice.tres"),
	preload("res://content/base/packs/floor_17_trainers.tres"),
	preload("res://content/base/packs/floor_18_slice.tres"),
	preload("res://content/base/packs/floor_18_trainers.tres"),
	preload("res://content/base/packs/floor_19_slice.tres"),
	preload("res://content/base/packs/floor_19_trainers.tres"),
	preload("res://content/base/packs/floor_20_slice.tres"),
	preload("res://content/base/packs/floor_20_trainers.tres"),
	preload("res://content/base/packs/floor_21_slice.tres"),
	preload("res://content/base/packs/floor_21_trainers.tres"),
	preload("res://content/base/packs/floor_22_slice.tres"),
	preload("res://content/base/packs/floor_22_trainers.tres"),
	preload("res://content/base/packs/floor_23_slice.tres"),
	preload("res://content/base/packs/floor_23_trainers.tres"),
	preload("res://content/base/packs/floor_24_slice.tres"),
	preload("res://content/base/packs/floor_24_trainers.tres"),
	preload("res://content/base/packs/floor_25_slice.tres"),
	preload("res://content/base/packs/floor_25_trainers.tres"),
	preload("res://content/base/packs/floor_26_slice.tres"),
	preload("res://content/base/packs/floor_26_trainers.tres"),
	preload("res://content/base/packs/floor_27_slice.tres"),
	preload("res://content/base/packs/floor_27_trainers.tres"),
	preload("res://content/base/packs/floor_28_slice.tres"),
	preload("res://content/base/packs/floor_28_trainers.tres"),
	preload("res://content/base/packs/floor_29_slice.tres"),
	preload("res://content/base/packs/floor_29_trainers.tres"),
	preload("res://content/base/packs/floor_30_slice.tres"),
	preload("res://content/base/packs/floor_30_trainers.tres"),
	preload("res://content/base/packs/floor_31_slice.tres"),
	preload("res://content/base/packs/floor_31_trainers.tres"),
]
const BATTLE_DEMO_PACK = preload("res://content/base/packs/battle_demo.tres")
const HARD_TOWER_PACK = preload("res://content/base/packs/hard_tower_trainers.tres")
const SESSION_SCRIPT = preload("res://src/application/campaign_session.gd")

var catalog: ContentCatalog
var session: CampaignSession
var active_campaign_battle := false
var campaign_return_pending := false
var prepared_battle_setup: Dictionary = {}

func _ready() -> void:
	catalog = RECOVERED_CATALOG
	_add_pack_once(CAMPAIGN_PACK)
	_add_pack_once(FLOOR_2_PACK)
	_add_pack_once(FLOOR_3_PACK)
	_add_pack_once(FLOOR_3_TRAINER_PACK)
	_add_pack_once(FLOOR_4_PACK)
	_add_pack_once(FLOOR_4_TRAINER_PACK)
	_add_pack_once(FLOOR_5_PACK)
	_add_pack_once(FLOOR_5_TRAINER_PACK)
	_add_pack_once(FLOOR_6_PACK)
	_add_pack_once(FLOOR_6_TRAINER_PACK)
	_add_pack_once(FLOOR_7_PACK)
	_add_pack_once(FLOOR_7_TRAINER_PACK)
	_add_pack_once(FLOOR_8_PACK)
	_add_pack_once(FLOOR_8_TRAINER_PACK)
	_add_pack_once(FLOOR_9_PACK)
	_add_pack_once(FLOOR_9_TRAINER_PACK)
	_add_pack_once(FLOOR_10_PACK)
	_add_pack_once(FLOOR_10_TRAINER_PACK)
	for pack in EXTENDED_TOWER_PACKS:
		_add_pack_once(pack)
	_add_pack_once(HARD_TOWER_PACK)
	var errors := catalog.rebuild_index()
	if not errors.is_empty():
		push_error("Campaign catalog failed validation: %s" % ", ".join(errors))
	session = SESSION_SCRIPT.new()
	session.catalog = catalog
	var spawn_migration: Dictionary = session.repair_legacy_start_spawns()
	if not spawn_migration.ok:
		push_warning("Some legacy save spawn positions could not be repaired: %s" % "; ".join(spawn_migration.failures))

func start_new_campaign(slot: int, character_name: String, gender: StringName) -> Dictionary:
	if session == null:
		return _error("runtime_not_ready", "campaign runtime has not initialized")
	var party := CampaignProgressionService.starter_party(catalog, "slot-%d-" % slot)
	if party.size() != CampaignProgressionService.STARTERS.size():
		return _error("missing_starter", "a starter minion definition is missing")
	var resolved_name := character_name.strip_edges()
	if resolved_name.is_empty():
		resolved_name = "Vala" if gender == &"female" else "Ryder"
	var result := session.start_new(&"base:campaign/standard_tower", party, {"name": resolved_name, "gender": String(gender)}, slot)
	if result.ok:
		active_campaign_battle = false
		campaign_return_pending = false
		prepared_battle_setup.clear()
	return result

func load_campaign(slot: int) -> Dictionary:
	if session == null:
		return _error("runtime_not_ready", "campaign runtime has not initialized")
	var result := session.load(slot)
	if result.ok:
		# A battle scene cannot survive a process restart. A saved preparation
		# marker must not make its encounter permanently unplayable on reload.
		if not session.state.pending_battle.is_empty():
			var recovered: Dictionary = session.cancel_pending_battle()
			if not recovered.ok:
				return recovered
			result["recovered_pending_battle"] = true
		# Results/XP were already saved, but their UI cannot survive a restart.
		# Complete just the pending checkpoint return, never award results twice.
		if not session.state.pending_defeat_return.is_empty():
			var returned: Dictionary = session.complete_defeat_return()
			if not returned.ok: return returned
			result["recovered_defeat_return"] = true
		active_campaign_battle = false
		campaign_return_pending = false
		prepared_battle_setup.clear()
	return result

## A multiplayer guest's state, built by the host; saves go to `redirect`.
func load_detached_campaign(data: Dictionary, id_slot: int, redirect: Callable) -> Dictionary:
	if session == null:
		return _error("runtime_not_ready", "campaign runtime has not initialized")
	var result: Dictionary = session.load_detached(data, id_slot, redirect)
	if result.ok:
		active_campaign_battle = false
		campaign_return_pending = false
		prepared_battle_setup.clear()
	return result

func has_save(slot: int) -> bool:
	return session != null and session.save_repository.load_slot(slot).ok

func delete_campaign_save(slot: int) -> Dictionary:
	if session == null:
		return _error("runtime_not_ready", "campaign runtime has not initialized")
	var result: Dictionary = session.save_repository.delete_slot(slot)
	if result.ok and session.state != null and session.save_slot == slot:
		session.state = null
		session.campaign = null
		active_campaign_battle = false
		campaign_return_pending = false
		prepared_battle_setup.clear()
	return result

func prepare_trainer_battle(encounter_id: StringName, _player_position: Vector2) -> Dictionary:
	if session == null or session.state == null:
		return _error("no_campaign", "start or load a campaign first")
	var catalog_errors: PackedStringArray = catalog.ensure_index()
	if not catalog_errors.is_empty():
		return _error("invalid_catalog", "campaign content is incomplete: %s" % ", ".join(catalog_errors))
	var battle_result := session.prepare_battle(encounter_id)
	if not battle_result.ok:
		return battle_result
	prepared_battle_setup = battle_result.setup.duplicate(true)
	active_campaign_battle = true
	campaign_return_pending = false
	return battle_result

func cancel_unstarted_battle() -> Dictionary:
	if session == null or session.state == null:
		return _error("no_campaign", "there is no active campaign")
	var result: Dictionary = session.cancel_pending_battle()
	if result.ok:
		active_campaign_battle = false
		campaign_return_pending = false
		prepared_battle_setup.clear()
	return result

func settle_campaign_battle(result: BattleResult) -> Dictionary:
	if not active_campaign_battle:
		return {"ok": true, "already_applied": true}
	var settlement := session.apply_battle_result(result)
	if settlement.ok:
		active_campaign_battle = false
		campaign_return_pending = true
		prepared_battle_setup.clear()
	return settlement

func save_campaign() -> Dictionary:
	return session.save() if session != null else _error("runtime_not_ready", "campaign runtime has not initialized")

func complete_defeat_return() -> Dictionary:
	return session.complete_defeat_return() if session != null else _error("runtime_not_ready", "campaign runtime has not initialized")

func enter_tower_lobby(from_eggery: bool = false) -> Dictionary:
	return session.enter_tower_lobby(from_eggery) if session != null else _error("runtime_not_ready", "campaign runtime has not initialized")

func select_tower_floor(floor_index: int) -> Dictionary:
	return session.select_tower_floor(floor_index) if session != null else _error("runtime_not_ready", "campaign runtime has not initialized")

func _add_pack_once(pack: ContentPackDefinition) -> void:
	for existing in RECOVERED_CATALOG.packs:
		if existing != null and existing.id == pack.id:
			return
	RECOVERED_CATALOG.packs.append(pack)

func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
