class_name CampaignYouMenuView
extends Control

signal closed

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const UPGRADE_IDS: Array[StringName] = [&"health", &"energy", &"attack", &"healing", &"speed", &"movement_speed", &"experience", &"money"]
const UPGRADE_DESCRIPTIONS := ["Increase all your minions health to", "Increase all your minions energy to", "Increase all your minions attack to", "Increase all your minions healing to", "Increase all your minions speed to", "Increase your movement speed to", "Increase your exp to", "Extra money is given out"]
const UPGRADE_PERCENTAGES := [2, 2, 2, 4, 2, 10, 5, 2]
const SOURCE_PANEL_POSITION := Vector2(5, 41)
const UPGRADE_ART := [
	"menus_youMenu_starUpgradeButtonHealth",
	"menus_youMenu_starUpgradeButtonEnergy",
	"menus_youMenu_starUpgradeButtonAttack",
	"menus_youMenu_starUpgradeButtonHealing",
	"menus_youMenu_starUpgradeButtonMinionSpeed",
	"menus_youMenu_starUpgradeButtonWalkSpeed",
	"menus_youMenu_starUpgradeButtonXP",
	"menus_youMenu_starUpgradeButtonExtraMoney",
]
const SEAL_ART := ["menus_plantMedallion", "menus_fireMedallion", "menus_electricMedallion", "menus_undeadMedallion", "menus_plantWizardMedallion", "menus_undeadWizardMedallion"]

var _session: Variant
var _panel: Control
var _source_root: Control
var _tooltip: PanelContainer
var _tooltip_text: Label
var _message := ""

func configure(session) -> void:
	_session = session
	_refresh()

func _refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.65)
	add_child(shade)
	_source_root = Control.new()
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_source_root.position = (viewport_size - Vector2(700, 525) * factor) * 0.5
	_source_root.scale = Vector2.ONE * factor
	_source_root.size = Vector2(700, 525)
	add_child(_source_root)
	_panel = Control.new()
	_panel.position = SOURCE_PANEL_POSITION
	_panel.size = Vector2(650, 430)
	_source_root.add_child(_panel)
	SourceMenuArt.image(_panel, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_panel, "menus_youMenu_yourInformationBackground", Vector2(344, 20))
	SourceMenuArt.image(_panel, "menus_youMenu_yourInformationBackground", Vector2(20, 20))
	SourceMenuArt.image(_panel, "menus_pendant", Vector2(386, 20))
	SourceMenuArt.image(_panel, "menus_youMenu_gemBackground", Vector2(18, 151))
	SourceMenuArt.button(_panel, "menus_exitButton", Vector2(624, -23), func() -> void: closed.emit())
	SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 409), func() -> void: closed.emit())
	var summary: Dictionary = _session.star_summary() if _session != null else {}
	var character: Dictionary = _session.state.character if _session != null else {}
	var progression: Dictionary = _session.state.progression if _session != null else {}
	var name := String(character.get("name", "Hero"))
	var money := int(progression.get("currency", 0))
	var owned_ids: Array = progression.get("owned_minion_ids", [])
	_label("Name", Vector2(115, 38), Vector2(150, 27), 20)
	_label("Money", Vector2(115, 68), Vector2(150, 27), 20)
	_label("Minion-Pedia", Vector2(115, 98), Vector2(150, 27), 20)
	_label(name, Vector2(213, 38), Vector2(150, 27), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_label(preload("res://src/presentation/campaign_currency_text.gd").format_amount(money), Vector2(213, 68), Vector2(150, 27), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(owned_ids.size()), Vector2(213, 98), Vector2(150, 27), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Your Seals", Vector2(328, 22), Vector2(150, 26), 20, HORIZONTAL_ALIGNMENT_CENTER)
	var seals := int(progression.get("sage_seals", 0))
	for index in SEAL_ART.size():
		var badge := SourceMenuArt.image(_panel, SEAL_ART[index], Vector2(396 + 28 * index, 62))
		if badge != null:
			badge.visible = index < seals
	var character_art := "menus_gemCombiner_male_charIcon" if String(character.get("gender", "male")).to_lower() == "male" else "menus_gemCombiner_female_charIcon"
	SourceMenuArt.image(_panel, character_art, Vector2(23, 22))
	SourceMenuArt.image(_panel, "battleScreenVictoryStar", Vector2(546, 223))
	var available_label := _label(str(summary.get("available", 0)), Vector2(395, 226), Vector2(150, 54), 40, HORIZONTAL_ALIGNMENT_RIGHT)
	available_label.name = "AvailableStars"
	for index in UPGRADE_IDS.size():
		var row_y := 182 if index < 4 else 292
		var column := index % 4
		var x := 63 + 90 * column
		var rank := _upgrade_rank(summary, UPGRADE_IDS[index])
		var cost := 10 + rank * 2
		var upgrade := Control.new()
		upgrade.name = "StarUpgradeGroup%d" % index
		upgrade.position = Vector2(x, row_y)
		upgrade.modulate.a = 1.0 if int(summary.get("available", 0)) >= cost else 0.5
		_panel.add_child(upgrade)
		var button := SourceMenuArt.button(upgrade, UPGRADE_ART[index], Vector2.ZERO, _purchase.bind(index))
		if button == null:
			var fallback := Button.new()
			fallback.text = "Buy"
			fallback.position = Vector2.ZERO
			fallback.size = Vector2(74, 74)
			fallback.pressed.connect(_purchase.bind(index))
			upgrade.add_child(fallback)
			button = null
		if button != null:
			button.name = "StarUpgrade%d" % index
			# The source keeps unaffordable buttons hoverable for their explanation.
			button.mouse_entered.connect(_show_upgrade_tooltip.bind(index, rank))
			button.mouse_exited.connect(_hide_upgrade_tooltip)
		_label("%d" % cost, Vector2(-8, 62), Vector2(50, 22), 15, HORIZONTAL_ALIGNMENT_RIGHT, upgrade)
		var cost_star := SourceMenuArt.image(upgrade, "battleScreenVictoryStar", Vector2(41, 65))
		if cost_star != null:
			cost_star.scale = Vector2.ONE * 0.35
		if rank > 0:
			_label("Rank %d" % rank, Vector2(3, -18), Vector2(70, 18), 13, HORIZONTAL_ALIGNMENT_CENTER, upgrade)
	var reset := SourceMenuArt.button(_panel, "menus_youMenu_resetButton", Vector2(493, 287), _reset)
	if reset != null:
		reset.name = "StarReset"
	if reset == null:
		var reset_fallback := Button.new()
		reset_fallback.text = "Reset upgrades"
		reset_fallback.position = Vector2(493, 287)
		reset_fallback.size = Vector2(150, 40)
		reset_fallback.pressed.connect(_reset)
		_panel.add_child(reset_fallback)
	_label(_message, Vector2(205, 408), Vector2(300, 22), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_build_tooltip()

func _purchase(index: int) -> void:
	if _session == null:
		return
	var summary: Dictionary = _session.star_summary()
	if int(summary.get("available", 0)) < 10 + 2 * _upgrade_rank(summary, UPGRADE_IDS[index]):
		return
	var result: Dictionary = _session.purchase_star_upgrade(index)
	_message = "" if result.get("ok", false) else String(result.get("message", "Purchase failed."))
	_refresh()

func _reset() -> void:
	if _session == null:
		return
	var result: Dictionary = _session.reset_star_upgrades()
	_message = "" if result.get("ok", false) else String(result.get("message", "Reset failed."))
	_refresh()

func _upgrade_rank(summary: Dictionary, upgrade_id: StringName) -> int:
	var upgrades: Dictionary = summary.get("upgrades", {})
	return maxi(0, int(upgrades.get(String(upgrade_id), 0)))

func _label(value: String, at: Vector2, dimensions: Vector2, font_size: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, parent: Node = null) -> Label:
	var label := Label.new()
	label.position = at + Vector2(2, 2)
	label.size = dimensions
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.hex(0xf9f9f9ff))
	(parent if parent != null else _panel).add_child(label)
	return label

func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.name = "StarUpgradeTooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 50
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color8(94, 100, 116, 242)
	frame.border_color = Color8(229, 232, 232, 217)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(3)
	frame.content_margin_left = 7
	frame.content_margin_right = 7
	frame.content_margin_top = 7
	frame.content_margin_bottom = 12
	_tooltip.add_theme_stylebox_override("panel", frame)
	_tooltip_text = Label.new()
	_tooltip_text.custom_minimum_size.x = 150
	_tooltip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_text.add_theme_font_override("font", FONT)
	_tooltip_text.add_theme_font_size_override("font_size", 14)
	_tooltip_text.add_theme_color_override("font_color", Color.hex(0xf9f9f9ff))
	_tooltip.add_child(_tooltip_text)
	_source_root.add_child(_tooltip)
	_tooltip.hide()

func _show_upgrade_tooltip(index: int, rank: int) -> void:
	_tooltip_text.text = UPGRADE_DESCRIPTIONS[index]
	if index != 7:
		_tooltip_text.text += " %d%%" % (UPGRADE_PERCENTAGES[index] * (rank + 1))
	_tooltip.size = Vector2.ZERO
	_tooltip.show()

func _hide_upgrade_tooltip() -> void:
	if is_instance_valid(_tooltip):
		_tooltip.hide()

func _process(_delta: float) -> void:
	if is_instance_valid(_tooltip) and _tooltip.visible:
		var mouse := _source_root.get_local_mouse_position()
		_tooltip.position = Vector2(mouse.x - _tooltip.size.x * 0.5 + 5, maxf(10, mouse.y - _tooltip.size.y))
