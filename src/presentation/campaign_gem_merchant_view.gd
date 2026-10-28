class_name CampaignGemMerchantView
extends CampaignGemMenuView

## BaseLargeGemMenu / GemCombiner / GemShop authored coordinates.
var _mode: StringName = &"shop"
var _materials: Array[StringName] = []
var _stock_selection := -1
var _audio: BattleAudioController
var _skill_forge := false
var _recipe_open := false

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
	if _mode == &"combine" and CampaignModService.enabled(_session.state, "skill_gems"):
		var inset := NinePatchRect.new()
		inset.texture = SourceMenuArt.texture("menus_gemCombiner_npcsGemsBackground")
		inset.position = Vector2(23, 20)
		inset.size = Vector2(302, 250)
		inset.patch_margin_left = 5
		inset.patch_margin_right = 5
		inset.patch_margin_top = 5
		inset.patch_margin_bottom = 5
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(inset)
	else:
		SourceMenuArt.image(_panel, "menus_sponsorMoreGames_background", Vector2(23, 20))
	SourceMenuArt.image(_panel, "menus_gemCombiner_characterDetailsBackground", Vector2(20, 277))
	SourceMenuArt.image(_panel, "menus_gemCombiner_npcsGemsBackground", Vector2(334, 278))
	var gender := String(_session.state.character.get("gender", "male")).to_lower()
	var bust := SourceMenuArt.image(_panel, "menus_%sBust_icon" % gender, Vector2(27, 302))
	if bust != null:
		bust.scale = Vector2.ONE * 0.7
	var money_text := "Unlimited" if CampaignDebugService.enabled(_session.state, "unlimited_money") else preload("res://src/presentation/campaign_currency_text.gd").format_amount(float(_session.state.progression.get("currency", 0)))
	var balance := "Money: %s" % money_text
	var font_size := 24
	while font_size > 12 and FONT.get_string_size(balance, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 186: font_size -= 1
	var money_label := _label(balance, Vector2(132, 323), Vector2(186, 34), font_size)
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
	if _recipe_open: _build_recipe_reference()

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
		if CampaignSkillGemService.is_skill(gem):
			_message = "Skill gems cannot be combined."
			_refresh()
			return
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
	var preview: Dictionary = CampaignSkillGemService.forge_preview(_session.state, _session.catalog, gems) if _skill_forge else CampaignGemEconomyService.combine_preview(gems)
	if CampaignModService.enabled(_session.state, "skill_gems"):
		_build_forge_information()
	for index in 4:
		var at := Vector2(342 + index * 64 if index < 3 else 584, 302)
		var gem: Dictionary = gems[index] if index < gems.size() else preview.get("gem", {}) if index == 3 else {}
		if not gem.is_empty():
			_portrait(_panel, gem, at, 1.0)
			_hover_gem(gem, at)
		else:
			SourceMenuArt.image(_panel, "menus_emptyGemSocket", at)
	var cost := int(preview.get("cost", 0))
	var affordable := CampaignDebugService.can_afford(_session.state, cost)
	var verb := "Forge" if _skill_forge else "Combine"
	_action("menus_gemCombiner_CombineButton", Vector2(507, 386), "%s($%d)" % [verb, cost] if preview.get("ok", false) else verb, _combine, bool(preview.get("ok", false)) and affordable)
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
	_action("menus_gemCombiner_buySellButton", Vector2(553, 396), "Buy ($%d)" % cost if can_buy else "Buy", _buy, can_buy and CampaignDebugService.can_afford(_session.state, cost))
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
	var result: Dictionary = _session.combine_gems(_materials, _page, _skill_forge)
	if result.get("ok", false):
		_materials.clear()
		_play_sound("menu_buyingItem", 0.6)
	_message = "Forged %s" % CampaignSkillGemService.label(result.gem) if result.get("ok", false) and _skill_forge else "" if result.get("ok", false) else String(result.get("message", "Could not combine gems."))
	_refresh()

func _set_forge(value: bool) -> void:
	if value and not CampaignSkillGemService.forge_unlocked(_session.state): return
	_skill_forge = value
	_message = ""
	_refresh()

func _build_forge_information() -> void:
	var stat_tab := TypeGuideView.tab_button(_panel, "Stat Gems", Vector2(30, 31), Vector2(142, 35), _set_forge.bind(false))
	var skill_tab := TypeGuideView.tab_button(_panel, "Random Forge", Vector2(172, 31), Vector2(145, 35), _set_forge.bind(true))
	stat_tab.name = "StatGemTab"
	skill_tab.name = "SkillGemTab"
	for button in [stat_tab, skill_tab]: button.toggle_mode = true
	stat_tab.set_pressed_no_signal(not _skill_forge)
	skill_tab.set_pressed_no_signal(_skill_forge)
	skill_tab.disabled = not CampaignSkillGemService.forge_unlocked(_session.state)
	skill_tab.tooltip_text = "Defeat the Talo Sage to unlock Random Forge." if skill_tab.disabled else "Forge a random skill from three stat gems."
	_label("Three stat gems · same tier", Vector2(36, 74), Vector2(275, 24), 17)
	_label("Gem color", Vector2(36, 104), Vector2(120, 22), 14)
	_label("Tier → skill level", Vector2(182, 104), Vector2(129, 22), 14)
	var bands := ["1–3 → Lv.1", "4–5 → Lv.2", "6–7 → Lv.3", "8–9 → Lv.4", "10 → Lv.5"]
	for index in 5:
		var color_label := _label(CampaignSkillGemService.COLOR_NAMES[index], Vector2(36, 131 + index * 21), Vector2(57, 21), 14)
		color_label.add_theme_color_override("font_color", Color(STAT_COLORS[index]))
		var badge := SourceMenuArt.image(_panel, "menus_minionType_%s" % CampaignSkillGemService.COLOR_TYPES[index], Vector2(95, 135 + index * 21))
		if badge != null: badge.scale = Vector2.ONE * 0.77
		_label(bands[index], Vector2(185, 131 + index * 21), Vector2(118, 21), 14)
	var info := "Skill hidden until forged" if _skill_forge else "Forge unlocks after Talo" if skill_tab.disabled else "Choose a crafting tab"
	_label(info, Vector2(36, 241), Vector2(185, 24), 13)
	TypeGuideView.text_button(_panel, "Recipes", Vector2(236, 237), Vector2(74, 26), _show_recipes, 13).name = "ForgeRecipes"

func _show_recipes() -> void:
	_recipe_open = true
	_refresh()

func _close_recipes() -> void:
	_recipe_open = false
	_refresh()

func _build_recipe_reference() -> void:
	var shade := ColorRect.new()
	shade.name = "ForgeRecipeModal"
	shade.size = Vector2(700, 525)
	shade.color = Color(0, 0, 0, 0.65)
	shade.z_index = 100
	_source_root.add_child(shade)
	var sheet := Control.new()
	sheet.position = Vector2(5, 40)
	sheet.size = Vector2(690, 468)
	shade.add_child(sheet)
	SourceMenuArt.image(sheet, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(sheet, "minionPedia_background", Vector2(21, 18))
	_label("Random Forge · Recipes", Vector2(30, 27), Vector2(620, 38), 27, sheet).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("Three gems of the same tier. Their colors choose the skill's type.", Vector2(38, 70), Vector2(615, 27), 17, sheet)
	var row := 0
	for recipe in CampaignSkillGemService.RECIPES:
		var at := Vector2(40 + (row % 2) * 315, 113 + (row / 2) * 42)
		var names: Array[String] = []
		for color in recipe.split(","): names.append(CampaignSkillGemService.COLOR_NAMES[int(color)])
		_label("/".join(names) + " →", at, Vector2(208, 28), 16, sheet)
		var badge := SourceMenuArt.image(sheet, "menus_minionType_%s" % CampaignSkillGemService.RECIPES[recipe], at + Vector2(210, 8))
		if badge != null: badge.scale = Vector2.ONE * 0.9
		row += 1
	_label("One color: its own type. Other mixes: a non-elemental stat skill.\nTiers 1–3: Lv.1   4–5: Lv.2   6–7: Lv.3   8–9: Lv.4   10: Lv.5\nSkills cap at their highest rank. Skill gems cannot be combined.", Vector2(40, 337), Vector2(600, 70), 15, sheet)
	SourceMenuArt.button(sheet, "menus_returnButton", Vector2(3, 409), _close_recipes)
	SourceMenuArt.button(sheet, "menus_exitButton", Vector2(624, -22), _close_recipes)

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
