class_name CampaignGemMerchantView
extends CampaignGemMenuView

## BaseLargeGemMenu / GemCombiner / GemShop authored coordinates.
var _mode: StringName = &"shop"
var _materials: Array[StringName] = []
var _stock_selection := -1
var _audio: BattleAudioController

func configure_merchant(session, mode: StringName, audio: BattleAudioController = null) -> void:
	_session = session
	_mode = mode
	_audio = audio
	if mode == &"shop" and session.gem_shop_stock().is_empty():
		var result: Dictionary = session.refresh_gem_shop()
		_message = "" if result.get("ok", false) else String(result.get("message", "Could not load shop."))
	_refresh()

func _refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portraits.clear()
	_source_root = Control.new()
	_source_root.size = Vector2(700, 525)
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_source_root.position = (viewport_size - _source_root.size * factor) * 0.5
	_source_root.scale = Vector2.ONE * factor
	add_child(_source_root)
	_panel = Control.new()
	_panel.position = Vector2.ZERO # BaseLargeGemMenu is added directly to TopdownScreen.
	_panel.size = Vector2(650, 430)
	_source_root.add_child(_panel)
	_create_tooltip()
	SourceMenuArt.image(_panel, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_panel, "menus_sponsorMoreGames_background", Vector2(23, 20))
	SourceMenuArt.image(_panel, "menus_gemCombiner_characterDetailsBackground", Vector2(20, 277))
	SourceMenuArt.image(_panel, "menus_gemCombiner_npcsGemsBackground", Vector2(334, 278))
	var gender := String(_session.state.character.get("gender", "male")).to_lower()
	var bust := SourceMenuArt.image(_panel, "menus_%sBust_icon" % gender, Vector2(27, 302))
	if bust != null:
		bust.scale = Vector2.ONE * 0.7
	_label("Money:", Vector2(109, 323), Vector2(150, 32), 24).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var money_label := _label(preload("res://src/presentation/campaign_currency_text.gd").format_amount(float(_session.state.progression.get("currency", 0))), Vector2(198, 323), Vector2(150, 32), 24)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	money_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	money_label.clip_text = true
	var return_button := SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 409), _return_from_merchant)
	return_button.name = "MerchantReturn"
	_build_inventory()
	_selector.position = Vector2(332, 15)
	if _mode == &"combine":
		_build_combiner()
	else:
		_build_shop()
	if _message != "Gems need to be of the same tier":
		_label(_message, Vector2(335, 265), Vector2(310, 32), 12).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for gem in super._inventory():
		result.append({} if StringName(gem.get("instance_id", "")) in _materials else gem)
	return result

func _select_slot(slot: int) -> void:
	var inventory := _inventory()
	if slot < inventory.size() and not inventory[slot].is_empty():
		_select_gem(StringName(inventory[slot].get("instance_id", "")))

func _select_gem(id: StringName) -> void:
	if _mode == &"shop":
		_selected_gem = &"" if _selected_gem == id else id
	else:
		var gem := _gem_by_id(id)
		if _materials.size() >= 3:
			return
		if not _materials.is_empty() and int(_gem_by_id(_materials[0]).get("tier", 1)) != int(gem.get("tier", 1)):
			_message = "Gems need to be of the same tier"
		else:
			if id in _materials or gem.is_empty():
				return
			_materials.append(id)
			_message = ""
	_refresh()

func _gem_by_id(id: StringName) -> Dictionary:
	for gem in _session.state.owned_gems:
		if StringName(gem.get("instance_id", "")) == id:
			return gem
	return {}

func _build_combiner() -> void:
	var gems: Array[Dictionary] = []
	for id in _materials:
		gems.append(_gem_by_id(id))
	var preview: Dictionary = CampaignGemEconomyService.combine_preview(gems)
	for index in 4:
		var at := Vector2(342 + index * 64 if index < 3 else 584, 302)
		var gem: Dictionary = gems[index] if index < gems.size() else preview.get("gem", {}) if index == 3 else {}
		if not gem.is_empty():
			_portrait(_panel, gem, at, 1.0)
			_hover_gem(gem, at)
		else:
			SourceMenuArt.image(_panel, "menus_emptyGemSocket", at)
	var cost := int(preview.get("cost", 0))
	var affordable := float(_session.state.progression.get("currency", 0)) >= cost
	_action("menus_gemCombiner_CombineButton", Vector2(507, 386), "Combine($%d)" % cost if preview.get("ok", false) else "Combine", _combine, bool(preview.get("ok", false)) and affordable)
	if _message == "Gems need to be of the same tier":
		_warning("SameTierWarning", _message, Vector2(334, 283))
	if preview.get("ok", false) and not affordable:
		_warning("MoneyWarning", "Not enough money", Vector2(485, 369))
	if not _materials.is_empty():
		SourceMenuArt.button(_panel, "menus_gemCombiner_resetButton", Vector2(341, 408), _reset_materials)
	_action("menus_gemCombiner_CombineButton", Vector2(507, 220), "Sort Gems", _sort, true)

func _build_shop() -> void:
	var stock: Array[Dictionary] = _session.gem_shop_stock()
	for index in stock.size():
		var gem: Dictionary = stock[index]
		if gem.is_empty() or gem.get("purchased", false):
			continue
		var at := Vector2(334 + index * 50, 308)
		if index == _stock_selection:
			SourceMenuArt.image(_panel, "menus_gemMenuGemSelected", at - Vector2(10, 11))
		_portrait(_panel, gem, at, 1.0)
		_hover_gem(gem, at, _select_stock.bind(index))
	var selected := _gem_by_id(_selected_gem)
	_action("menus_gemCombiner_buySellButton", Vector2(553, 224), "Sell ($%d)" % CampaignGemEconomyService.sell_price(int(selected.get("tier", 1))) if not selected.is_empty() else "Sell", _sell, not selected.is_empty())
	var can_buy: bool = _stock_selection >= 0 and _stock_selection < stock.size() and not stock[_stock_selection].is_empty() and not stock[_stock_selection].get("purchased", false)
	var cost := CampaignGemEconomyService.buy_price(int(stock[_stock_selection].get("tier", 1))) if can_buy else 0
	_action("menus_gemCombiner_buySellButton", Vector2(553, 396), "Buy ($%d)" % cost if can_buy else "Buy", _buy, can_buy and float(_session.state.progression.get("currency", 0)) >= cost)
	_action("menus_gemCombiner_buySellButton", Vector2(343, 396), "Refresh", _refresh_stock, true)

func _action(symbol: String, at: Vector2, text: String, action: Callable, enabled: bool) -> void:
	var button := SourceMenuArt.button(_panel, symbol, at, action)
	if button != null:
		button.disabled = not enabled
		button.modulate.a = 1.0 if enabled else 0.3
	var offset := Vector2(4, 9) if symbol.ends_with("CombineButton") else Vector2(-19, 6)
	var caption := _label(text, offset, Vector2(150, 28), 18 if symbol.ends_with("CombineButton") else 16, button)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.add_theme_color_override("font_color", Color.hex(0xf0f0f0ff))
	button.name = "MerchantAction_%s" % text.get_slice(" ", 0).get_slice("(", 0)

func _warning(node_name: String, text: String, at: Vector2) -> void:
	var warning := _label(text, at, Vector2(200, 32), 12)
	warning.name = node_name
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	warning.add_theme_color_override("font_color", Color.hex(0xf42b2bff))

func _hover_gem(gem: Dictionary, at: Vector2, action: Callable = Callable()) -> void:
	var button := Button.new()
	button.position = at
	button.size = Vector2(53, 53)
	button.flat = true
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.mouse_entered.connect(_show_tooltip.bind(gem))
	button.mouse_exited.connect(func() -> void: _tooltip.hide())
	if action.is_valid():
		button.pressed.connect(action)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.add_child(button)

func _select_stock(index: int) -> void:
	_stock_selection = index
	_refresh()

func _reset_materials() -> bool:
	if not _materials.is_empty():
		var restored: Dictionary = _session.restore_combiner_materials(_materials)
		if not restored.get("ok", false):
			_message = String(restored.get("message", "Could not return gems."))
			_refresh()
			return false
	_materials.clear()
	_page = 0
	_selected_gem = &""
	_message = ""
	_refresh()
	return true

func _return_from_merchant() -> void:
	if _mode == &"combine" and not _reset_materials():
		return
	closed.emit()

func _combine() -> void:
	var result: Dictionary = _session.combine_gems(_materials, _page)
	if result.get("ok", false):
		_materials.clear()
		_play_sound("menu_buyingItem", 0.6)
	_message = "" if result.get("ok", false) else String(result.get("message", "Could not combine gems."))
	_refresh()

func _sell() -> void:
	var result: Dictionary = _session.sell_gem(_selected_gem)
	if result.get("ok", false):
		_selected_gem = &""
		_page = 0
		_play_sound("tower_moneyPickup")
	_message = "" if result.get("ok", false) else String(result.get("message", "Could not sell gem."))
	_refresh()

func _buy() -> void:
	var result: Dictionary = _session.buy_shop_gem(_stock_selection, _page)
	if result.get("ok", false):
		_stock_selection = -1
		_play_sound("menu_buyingItem", 0.6)
	_message = "" if result.get("ok", false) else String(result.get("message", "Could not buy gem."))
	_refresh()

func _refresh_stock() -> void:
	var result: Dictionary = _session.refresh_gem_shop()
	if result.get("ok", false):
		_play_sound("menu_buyingItem", 0.6)
	_message = "" if result.get("ok", false) else String(result.get("message", "Could not refresh shop."))
	_refresh()

func _play_sound(sound: String, volume: float = 1.0) -> void:
	if _audio != null:
		_audio.play_sound(sound, volume)
