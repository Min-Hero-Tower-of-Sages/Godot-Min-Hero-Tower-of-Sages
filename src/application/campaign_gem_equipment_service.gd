class_name CampaignGemEquipmentService
extends RefCounted

const SLOT_COUNT := 4
const INVENTORY_CAPACITY := 99 * 15
const STAT_IDS: Array[StringName] = [&"health", &"energy", &"attack", &"healing", &"speed"]

## Website-only sockets are available locally. Evolution-locked sockets keep
## their authored restriction until the minion reaches the maximum level.
static func slot_is_available(owned: OwnedMinionState, definition: MinionDefinition, slot: int) -> bool:
	return definition != null and slot >= 0 and slot < SLOT_COUNT and (slot < definition.gem_slots or slot >= definition.gem_slots + definition.locked_gem_slots or owned.level >= 60)

static func equip_gem(state, catalog: ContentCatalog, gem_instance_id: StringName, minion_instance_id: StringName, slot: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("invalid_context", "campaign state and content catalog are required")
	var gem := _find_gem(state, gem_instance_id)
	if gem.is_empty():
		return _error("missing_gem", "gem %s is not in the owned gem registry" % String(gem_instance_id))
	var owned := _find_owned_minion(state, minion_instance_id)
	if owned == null:
		return _error("missing_minion", "minion %s is not in the party or storage" % String(minion_instance_id))
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	if definition == null:
		return _error("missing_minion_definition", "minion %s references missing content" % String(minion_instance_id))
	if not slot_is_available(owned, definition, slot):
		return _error("gem_slot_locked", "minion %s has no unlocked gem socket at slot %d" % [String(minion_instance_id), slot])
	var equipped_by := _equipped_minion_for(state, gem_instance_id)
	if not equipped_by.is_empty():
		return _error("gem_already_equipped", "gem %s is already equipped by %s" % [String(gem_instance_id), equipped_by])
	var equipment := _normalized_equipment(owned.equipment_ids)
	var previous_id := equipment[slot]
	if previous_id == gem_instance_id:
		return _error("gem_already_equipped", "gem %s is already in that socket" % String(gem_instance_id))
	var inventory := inventory_slots(state)
	var inventory_index := inventory.find(String(gem_instance_id))
	equipment[slot] = gem_instance_id
	owned.equipment_ids.assign(equipment)
	if inventory_index >= 0:
		inventory[inventory_index] = String(previous_id)
	state.progression["gem_inventory_slots"] = inventory
	return {"ok": true, "kind": &"gem_equipped", "gem": gem.duplicate(true), "replaced_gem_id": String(previous_id), "minion_instance_id": String(minion_instance_id), "slot": slot}

static func unequip_gem(state, catalog: ContentCatalog, minion_instance_id: StringName, slot: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("invalid_context", "campaign state and content catalog are required")
	var owned := _find_owned_minion(state, minion_instance_id)
	if owned == null:
		return _error("missing_minion", "minion %s is not in the party or storage" % String(minion_instance_id))
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	if definition == null:
		return _error("missing_minion_definition", "minion %s references missing content" % String(minion_instance_id))
	# Never trap an imported equipped gem behind an evolution/website lock.
	if slot < 0 or slot >= SLOT_COUNT:
		return _error("gem_slot_locked", "minion %s has no unlocked gem socket at slot %d" % [String(minion_instance_id), slot])
	var equipment := _normalized_equipment(owned.equipment_ids)
	var gem_id := StringName(equipment[slot])
	if gem_id.is_empty():
		return _error("empty_gem_slot", "gem socket %d is already empty" % slot)
	var gem := _find_gem(state, gem_id)
	if gem.is_empty():
		return _error("missing_equipped_gem", "socket %d references missing gem %s" % [slot, String(gem_id)])
	equipment[slot] = &""
	owned.equipment_ids.assign(equipment)
	state.progression["gem_inventory_slots"] = inventory_slots(state)
	return {"ok": true, "kind": &"gem_unequipped", "gem": gem.duplicate(true), "minion_instance_id": String(minion_instance_id), "slot": slot}

static func swap_gems(state, first_id: StringName, second_id: StringName) -> Dictionary:
	if state == null:
		return _error("invalid_context", "campaign state is required")
	if first_id == second_id:
		return {"ok": true, "kind": &"gems_swapped", "first_id": String(first_id), "second_id": String(second_id)}
	if _find_gem_index(state, first_id) < 0 or _find_gem_index(state, second_id) < 0:
		return _error("missing_gem", "both gems must belong to the owned gem registry")
	if not _equipped_minion_for(state, first_id).is_empty() or not _equipped_minion_for(state, second_id).is_empty():
		return _error("gem_equipped", "equipped gems cannot be reordered in the inventory")
	var inventory := inventory_slots(state)
	var first_slot := inventory.find(String(first_id))
	var second_slot := inventory.find(String(second_id))
	inventory[first_slot] = String(second_id)
	inventory[second_slot] = String(first_id)
	state.progression["gem_inventory_slots"] = inventory
	var first_index := _find_gem_index(state, first_id)
	var second_index := _find_gem_index(state, second_id)
	var first_gem: Dictionary = state.owned_gems[first_index]
	state.owned_gems[first_index] = state.owned_gems[second_index]
	state.owned_gems[second_index] = first_gem
	return {"ok": true, "kind": &"gems_swapped", "first_id": String(first_id), "second_id": String(second_id)}

static func sort_gems(state) -> Dictionary:
	if state == null:
		return _error("invalid_context", "campaign state is required")
	state.owned_gems.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_main := _main_stat_index(left)
		var right_main := _main_stat_index(right)
		if left_main != right_main:
			return left_main > right_main
		if int(left.get("tier", 0)) != int(right.get("tier", 0)):
			return int(left.get("tier", 0)) > int(right.get("tier", 0))
		return _max_raw_stat(left) > _max_raw_stat(right)
	)
	state.progression.erase("gem_inventory_slots")
	state.progression["gem_inventory_slots"] = inventory_slots(state)
	return {"ok": true, "kind": &"gems_sorted"}

static func inventory_slots(state) -> Array[String]:
	# Keep the gem registry dense and separate from its source inventory grid.
	# Empty positions are real slots; new rewards fill the first available one.
	var available: Dictionary = {}
	var equipped := equipped_gem_ids(state)
	for gem in state.owned_gems:
		var id := String(gem.get("instance_id", ""))
		if not id.is_empty() and not equipped.has(id):
			available[id] = true
	var inventory: Array[String] = []
	var assigned: Dictionary = {}
	for value in state.progression.get("gem_inventory_slots", []):
		if inventory.size() >= INVENTORY_CAPACITY:
			break
		var id := String(value) if value is String or value is StringName else ""
		if available.has(id) and not assigned.has(id):
			inventory.append(id)
			assigned[id] = true
		else:
			inventory.append("")
	for id in available:
		if assigned.has(id):
			continue
		var empty := inventory.find("")
		if empty >= 0:
			inventory[empty] = id
		else:
			inventory.append(id)
	return inventory

static func move_gem_to_slot(state, gem_id: StringName, target_slot: int) -> Dictionary:
	if state == null or target_slot < 0 or target_slot >= INVENTORY_CAPACITY:
		return _error("invalid_gem_slot", "gem inventory slot is outside the source 99-page grid")
	var inventory := inventory_slots(state)
	var origin := inventory.find(String(gem_id))
	if origin < 0:
		return _error("gem_unavailable", "only unequipped owned gems can move in the inventory")
	if target_slot >= inventory.size():
		inventory.resize(target_slot + 1)
	var displaced := inventory[target_slot]
	inventory[target_slot] = String(gem_id)
	inventory[origin] = displaced
	state.progression["gem_inventory_slots"] = inventory
	return {"ok": true, "kind": &"gem_moved", "origin_slot": origin, "target_slot": target_slot, "displaced_gem_id": displaced}

static func place_gem_from_page(state, gem_id: StringName, page: int = 0) -> Dictionary:
	if page < 0 or page >= 99:
		return _error("invalid_gem_page", "gem inventory page is outside the source grid")
	var inventory := inventory_slots(state)
	var origin := inventory.find(String(gem_id))
	if origin < 0:
		return _error("gem_unavailable", "only unequipped owned gems can enter the inventory")
	inventory[origin] = ""
	var target := page * 15
	while target < INVENTORY_CAPACITY and target < inventory.size() and not inventory[target].is_empty():
		target += 1
	if target >= INVENTORY_CAPACITY:
		return _error("gem_inventory_full", "no free gem slot remains on or after this page")
	if target >= inventory.size():
		inventory.resize(target + 1)
	inventory[target] = String(gem_id)
	state.progression["gem_inventory_slots"] = inventory
	return {"ok": true, "slot": target}

static func equipped_gem_ids(state) -> Dictionary:
	var equipped: Dictionary = {}
	if state == null:
		return equipped
	for owned in state.party + state.storage:
		for gem_id in owned.equipment_ids:
			if not StringName(gem_id).is_empty():
				equipped[String(gem_id)] = String(owned.instance_id)
	return equipped

static func gem_stat_bonus(owned: OwnedMinionState, stat_id: StringName, owned_gems: Array[Dictionary]) -> int:
	if owned == null:
		return 0
	var stat_index := STAT_IDS.find(stat_id)
	if stat_index < 0:
		return 0
	var gem_by_id: Dictionary = {}
	for gem in owned_gems:
		gem_by_id[String(gem.get("instance_id", ""))] = gem
	var total := 0
	for gem_id in owned.equipment_ids:
		var gem: Dictionary = gem_by_id.get(String(gem_id), {})
		if not gem.is_empty():
			total += _extra_stat(gem, stat_index)
	return total

static func _extra_stat(gem: Dictionary, stat_index: int) -> int:
	var tier := maxi(1, int(gem.get("tier", 1)))
	var raw_stats: Array = gem.get("raw_stats", [])
	if raw_stats.size() == STAT_IDS.size():
		var power := float(raw_stats[stat_index])
		if power > 0.0:
			var tier_base := 3.0
			for tier_value in range(2, tier + 1):
				tier_base += float(tier_value)
			return ceili(tier_base * power / pow(3.0, tier))
	var main_stat := StringName(gem.get("stat_id", ""))
	if main_stat == STAT_IDS[stat_index]:
		return maxi(0, int(gem.get("stat_value", 0)))
	return 0

static func _find_owned_minion(state, instance_id: StringName) -> OwnedMinionState:
	for owned in state.party + state.storage:
		if owned.instance_id == instance_id:
			return owned
	return null

static func _find_gem(state, instance_id: StringName) -> Dictionary:
	var index := _find_gem_index(state, instance_id)
	return (state.owned_gems[index] as Dictionary).duplicate(true) if index >= 0 else {}

static func _find_gem_index(state, instance_id: StringName) -> int:
	for index in state.owned_gems.size():
		if StringName(state.owned_gems[index].get("instance_id", "")) == instance_id:
			return index
	return -1

static func _equipped_minion_for(state, gem_instance_id: StringName) -> String:
	for owned in state.party + state.storage:
		if gem_instance_id in owned.equipment_ids:
			return String(owned.instance_id)
	return ""

static func _normalized_equipment(equipment_ids: Array[StringName]) -> Array[StringName]:
	var equipment := equipment_ids.duplicate()
	while equipment.size() < SLOT_COUNT:
		equipment.append(&"")
	if equipment.size() > SLOT_COUNT:
		equipment.resize(SLOT_COUNT)
	return equipment

static func _main_stat_index(gem: Dictionary) -> int:
	var raw_stats: Array = gem.get("raw_stats", [])
	if raw_stats.size() == STAT_IDS.size():
		var main_index := 0
		var max_value := 0.0
		for index in raw_stats.size():
			if float(raw_stats[index]) > max_value:
				max_value = float(raw_stats[index])
				main_index = index
		return main_index
	return maxi(0, STAT_IDS.find(StringName(gem.get("stat_id", ""))))

static func _max_raw_stat(gem: Dictionary) -> float:
	var raw_stats: Array = gem.get("raw_stats", [])
	var max_value := 0.0
	for value in raw_stats:
		max_value = maxf(max_value, float(value))
	return max_value

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
