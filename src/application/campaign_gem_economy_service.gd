class_name CampaignGemEconomyService
extends RefCounted

const BUY_PRICES := [6, 14, 31, 67, 142, 296, 610, 1247, 2535, 5132]
const COMBINE_COSTS := [2, 3, 5, 8, 12, 18, 27, 41, 62, 93]
const STAT_IDS := CampaignGemFactory.STAT_IDS
const STAT_LABELS := CampaignGemFactory.STAT_LABELS

static func buy_price(tier: int) -> int:
	return int(BUY_PRICES[tier - 1]) if tier >= 1 and tier <= BUY_PRICES.size() else -1

static func sell_price(tier: int) -> int:
	var price := buy_price(tier)
	return int(price * 0.25) if price >= 0 else -1

static func combine_preview(gems: Array[Dictionary]) -> Dictionary:
	if gems.size() != 3:
		return _error("combine_needs_three_gems", "select exactly three gems to combine")
	var tier := int(gems[0].get("tier", 0))
	if tier < 1 or tier >= COMBINE_COSTS.size():
		return _error("invalid_combine_tier", "these gems cannot be combined into a supported tier")
	var unique_ids: Dictionary = {}
	var combined_raw: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for gem in gems:
		if int(gem.get("tier", 0)) != tier:
			return _error("gem_tier_mismatch", "all three gems must have the same tier")
		var instance_id := String(gem.get("instance_id", ""))
		if instance_id.is_empty() or unique_ids.has(instance_id):
			return _error("duplicate_gem", "combine materials must be three distinct owned gems")
		unique_ids[instance_id] = true
		var raw_stats: Array = gem.get("raw_stats", [])
		if raw_stats.size() != STAT_IDS.size():
			return _error("invalid_gem_stats", "each gem must have five raw stat values")
		for stat_index in STAT_IDS.size():
			combined_raw[stat_index] += float(raw_stats[stat_index])
	return {"ok": true, "gem": _make_gem(tier + 1, combined_raw), "cost": int(COMBINE_COSTS[tier])}

static func combine_gems(state, ids: Array[StringName]) -> Dictionary:
	if state == null or ids.size() != 3:
		return _error("combine_needs_three_gems", "select exactly three gems to combine")
	var input: Array[Dictionary] = []
	for id in ids:
		var index := _gem_index(state, id)
		if index < 0:
			return _error("missing_gem", "gem %s is not owned" % String(id))
		if _is_equipped(state, id):
			return _error("gem_equipped", "equipped gems cannot be used as combine materials")
		input.append(state.owned_gems[index])
	var preview := combine_preview(input)
	if not preview.ok:
		return preview
	var cost := int(preview.cost)
	var currency := int(state.progression.get("currency", 0))
	if currency < cost:
		return _error("insufficient_currency", "combining costs %d coins; only %d are available" % [cost, int(currency)])
	var consumed: Dictionary = {}
	var insertion_index: int = state.owned_gems.size()
	for id in ids:
		consumed[String(id)] = true
		insertion_index = mini(insertion_index, _gem_index(state, id))
	var remaining: Array[Dictionary] = []
	var result_gem: Dictionary = preview.gem.duplicate(true)
	result_gem["instance_id"] = _new_gem_id(state, "combined")
	for index in state.owned_gems.size():
		if index == insertion_index:
			remaining.append(result_gem)
		elif not consumed.has(String(state.owned_gems[index].get("instance_id", ""))):
			remaining.append(state.owned_gems[index])
	state.owned_gems.assign(remaining)
	state.progression["currency"] = currency - cost
	return {"ok": true, "kind": &"gems_combined", "gem": result_gem.duplicate(true), "consumed_ids": ids.map(func(id: StringName) -> String: return String(id)), "cost": cost, "currency": int(currency - cost)}

static func sell_gem(state, gem_instance_id: StringName) -> Dictionary:
	if state == null:
		return _error("invalid_context", "campaign state is required")
	if _is_equipped(state, gem_instance_id):
		return _error("gem_equipped", "unequip a gem before selling it")
	var index := _gem_index(state, gem_instance_id)
	if index < 0:
		return _error("missing_gem", "gem %s is not owned" % String(gem_instance_id))
	var gem: Dictionary = state.owned_gems[index]
	var value := sell_price(int(gem.get("tier", 0)))
	if value < 0:
		return _error("invalid_gem_tier", "this gem has an unsupported tier")
	state.owned_gems.remove_at(index)
	state.progression["currency"] = int(state.progression.get("currency", 0)) + value
	return {"ok": true, "kind": &"gem_sold", "gem": gem.duplicate(true), "value": value, "currency": int(state.progression["currency"])}

static func refresh_shop(state, floor_index: int) -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	if state == null:
		return stock
	var offsets := [0, 0, 1, 1, 2, 3]
	var base_tier := CampaignGemFactory.tier_for_floor(floor_index)
	var refresh_number := int(state.progression.get("gem_shop_refresh_count", 0)) + 1
	state.progression["gem_shop_refresh_count"] = refresh_number
	for index in offsets.size():
		var tier := clampi(base_tier + offsets[index], 1, BUY_PRICES.size())
		var gem := CampaignGemFactory.create_random(tier)
		gem["shop_id"] = "shop-%d-%d-%d" % [floor_index, refresh_number, index]
		stock.append(gem)
	state.progression["gem_shop_stock"] = stock.duplicate(true)
	return stock

static func current_shop_stock(state) -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	if state == null:
		return stock
	for raw_gem in state.progression.get("gem_shop_stock", []):
		if raw_gem is Dictionary:
			stock.append(raw_gem.duplicate(true))
	return stock

static func buy_shop_gem(state, index: int) -> Dictionary:
	if state == null:
		return _error("invalid_context", "campaign state is required")
	var stock := current_shop_stock(state)
	if index < 0 or index >= stock.size() or stock[index].is_empty():
		return _error("shop_slot_empty", "there is no gem for sale in this slot")
	var gem: Dictionary = stock[index]
	var price := buy_price(int(gem.get("tier", 0)))
	var currency := int(state.progression.get("currency", 0))
	if price < 0:
		return _error("invalid_gem_tier", "this shop gem has an unsupported tier")
	if currency < price:
		return _error("insufficient_currency", "this gem costs %d coins; only %d are available" % [price, int(currency)])
	var bought := gem.duplicate(true)
	bought.erase("shop_id")
	bought["instance_id"] = _new_gem_id(state, "shop")
	state.owned_gems.append(bought)
	stock[index] = {}
	state.progression["gem_shop_stock"] = stock
	state.progression["currency"] = currency - price
	return {"ok": true, "kind": &"shop_gem_bought", "gem": bought.duplicate(true), "price": price, "currency": int(currency - price), "slot": index}

static func _make_gem(tier: int, raw_stats: Array[float]) -> Dictionary:
	var gem := CampaignGemFactory.create_random(tier)
	var main_index := 0
	var max_value := -1.0
	for index in STAT_IDS.size():
		if raw_stats[index] > max_value:
			max_value = raw_stats[index]
			main_index = index
	var tier_base := 3.0
	for value in range(2, tier + 1):
		tier_base += float(value)
	gem["tier"] = tier
	gem["raw_stats"] = raw_stats.duplicate()
	gem["stat_id"] = String(STAT_IDS[main_index])
	gem["stat_label"] = STAT_LABELS[main_index]
	gem["stat_value"] = ceili(tier_base * raw_stats[main_index] / pow(3.0, tier))
	return gem

static func _new_gem_id(state, source: String) -> String:
	var sequence := int(state.progression.get("gem_instance_sequence", 0))
	while true:
		sequence += 1
		var candidate := "slot-gem-%s-%d" % [source, sequence]
		var found := false
		for gem in state.owned_gems:
			if String(gem.get("instance_id", "")) == candidate:
				found = true
				break
		if not found:
			state.progression["gem_instance_sequence"] = sequence
			return candidate
	return ""

static func _is_equipped(state, id: StringName) -> bool:
	for owned in state.party + state.storage:
		if id in owned.equipment_ids:
			return true
	return false

static func _gem_index(state, id: StringName) -> int:
	for index in state.owned_gems.size():
		if StringName(state.owned_gems[index].get("instance_id", "")) == id:
			return index
	return -1

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
