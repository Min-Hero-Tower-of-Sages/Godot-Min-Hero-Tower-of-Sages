extends PanelContainer

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const STAT_COLORS := ["#fc7979", "#ca8ada", "#f6834c", "#fff764", "#72ade6"]
var _skill_details: BattleMoveTooltip
var _stat_style: StyleBox

func _init() -> void:
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(94, 100, 116, 242)
	style.border_color = Color8(229, 232, 232, 217)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_stat_style = style
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.x = 200
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color8(242, 242, 242))
	column.add_child(title)
	var description := RichTextLabel.new()
	description.name = "Description"
	description.bbcode_enabled = true
	description.fit_content = true
	description.scroll_active = false
	description.custom_minimum_size.x = 200
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_font_override("normal_font", FONT)
	description.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(description)
	hide()

func show_gem(gem: Dictionary, catalog: ContentCatalog = null) -> void:
	var skill := CampaignSkillGemService.is_skill(gem)
	get_child(0).visible = not skill
	if _skill_details != null: _skill_details.hide()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new() if skill else _stat_style)
	if skill:
		if _skill_details == null:
			_skill_details = BattleMoveTooltip.new()
			add_child(_skill_details)
		var move := catalog.get_definition(StringName(gem.get("move_id", ""))) as MoveDefinition if catalog != null else null
		if move != null:
			_skill_details.show_move(move)
			_skill_details.title.text = CampaignSkillGemService.label(gem)
			_skill_details.details.text += "\n[color=#ffec9a]%s[/color]" % ("Any minion can equip" if CampaignSkillGemService.universal(move) else "Cannot equip if weak to this type")
			if move.is_global_passive: _skill_details.details.text += "\n[color=#c5c9d5]Party bonus while the holder lives[/color]"
			_skill_details.details.text += "\n " # Reserve the source type badge's footer.
		else:
			_skill_details.title.text = "Unknown Skill · Lv.%d" % int(gem.get("skill_level", 1))
			_skill_details.details.text = "[color=#ffec9a]%s[/color]\nRevealed after forging" % CampaignSkillGemService.type_label(StringName(gem.get("type_id", "base:type/none")))
			_skill_details.type_icon.hide()
		_skill_details.show()
		_skill_details.reset_size()
		reset_size()
		show()
		return
	var title := get_child(0).get_node("Title") as Label
	var description := get_child(0).get_node("Description") as RichTextLabel
	title.text = "Gem  (tier %d)" % int(gem.get("tier", 1)) if not gem.is_empty() else "Move Gem"
	title.add_theme_font_size_override("font_size", 21 if not gem.is_empty() else 14)
	var lines: Array[String] = []
	for index in CampaignGemEquipmentService.STAT_IDS.size():
		var value := CampaignGemEquipmentService._extra_stat(gem, index) if not gem.is_empty() else 0
		if value > 0:
			lines.append("[color=%s]+%d %s[/color]" % [STAT_COLORS[index], value, CampaignGemFactory.STAT_LABELS[index]])
	description.text = "\n".join(lines)
	description.visible = not lines.is_empty()
	reset_size()
	show()

func _process(_delta: float) -> void:
	if visible and get_parent() is Control:
		var mouse: Vector2 = get_parent().get_local_mouse_position()
		_place_at_canvas_point(get_parent().get_global_transform_with_canvas() * mouse)

func _place_at_canvas_point(screen_mouse: Vector2) -> void:
	var parent_control := get_parent() as Control
	# Equipped-gem tooltips can live inside a scaled source-art panel.
	# Clamp in screen space, then convert back to the parent's coordinates.
	var transform := parent_control.get_global_transform_with_canvas()
	var screen_size := size * transform.get_scale().abs()
	var viewport_size := get_viewport_rect().size
	var screen_position := Vector2(screen_mouse.x - screen_size.x * 0.5 + 5, screen_mouse.y - screen_size.y)
	screen_position.x = clampf(screen_position.x, 8, maxf(8, viewport_size.x - screen_size.x - 8))
	screen_position.y = clampf(screen_position.y, 8, maxf(8, viewport_size.y - screen_size.y - 8))
	position = transform.affine_inverse() * screen_position
