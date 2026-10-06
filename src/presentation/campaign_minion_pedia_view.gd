class_name CampaignMinionPediaView
extends Control

signal closed

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
var _catalog: ContentCatalog
var _state: CampaignState
var _minions: Array[MinionDefinition] = []
var _selected := 0
var _panel: Control
var _description: Control
var _owned: Dictionary = {}
var _seen: Dictionary = {}
var _list_holder: Control
var _selection: TextureRect
var _scroll_position := 0
var _scroll_tween: Tween
var _up_buttons: Array[TextureButton] = []
var _down_buttons: Array[TextureButton] = []
var _found_floors: Dictionary = {}

func configure(catalog: ContentCatalog, state: CampaignState) -> void:
	_catalog = catalog
	_state = state
	_minions.clear()
	_owned.clear()
	_seen.clear()
	_found_floors.clear()
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is MinionDefinition:
				_minions.append(definition)
	_minions.sort_custom(func(a: MinionDefinition, b: MinionDefinition) -> bool:
		return a.legacy_numeric_id < b.legacy_numeric_id if a.legacy_numeric_id != b.legacy_numeric_id else String(a.id) < String(b.id)
	)
	for group in [state.party, state.storage]:
		for member in group:
			_owned[String(member.definition_id)] = true
			_seen[String(member.definition_id)] = true
	for id in state.progression.get("seen_minion_ids", []):
		_seen[String(id)] = true
	for id in state.progression.get("owned_minion_ids", []):
		_owned[String(id)] = true
		_seen[String(id)] = true
	# Like GetFloorsAMinionIsFoundOn, report acquisition tables, not
	# trainer sightings. Read the active campaign's authored hatcheries.
	for pack in catalog.packs:
		for definition in pack.definitions:
			if not definition is CampaignDefinition:
				continue
			for floor_data in definition.floors:
				var floor_index := int(floor_data.get("floor_index", 0))
				for room_id in floor_data.get("room_ids", []):
					var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
					if room == null or not String(room_id).ends_with("_eggery"):
						continue
					for interaction in room.interactions:
						for minion_id in interaction.get("candidates", []):
							var key := String(minion_id)
							var floors: Array = _found_floors.get(key, [])
							if not floor_index + 1 in floors:
								floors.append(floor_index + 1)
							_found_floors[key] = floors
	_build()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.3)
	add_child(shade)
	_panel = Control.new()
	var viewport_size := get_viewport_rect().size
	var source_scale := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_panel.position = (viewport_size - Vector2(700, 525) * source_scale) * 0.5 + Vector2(5, 13) * source_scale
	_panel.size = Vector2(690, 512)
	_panel.scale = Vector2.ONE * source_scale
	add_child(_panel)
	SourceMenuArt.image(_panel, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_panel, "minionPedia_background", Vector2(21, 18))
	SourceMenuArt.image(_panel, "minionPedia_minionBackground", Vector2(56, 56))
	SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 409), func() -> void: closed.emit())
	var clip := Control.new()
	clip.position = Vector2(325, 24)
	clip.size = Vector2(300, 419)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(clip)
	_list_holder = Control.new()
	_list_holder.position = Vector2(32, 19)
	_list_holder.size = Vector2(268, _minions.size() * 52)
	_list_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_list_holder)
	for index in _minions.size():
		var definition := _minions[index]
		var row := Control.new()
		row.position.y = index * 52
		row.size = Vector2(268, 52)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list_holder.add_child(row)
		SourceMenuArt.button(row, "minionPedia_minionSelectBackground", Vector2.ZERO, _select.bind(index))
		_text(row, "%03d   %s" % [definition.legacy_numeric_id + 1, definition.display_name if _seen.has(String(definition.id)) else "????????"], Vector2(7, 3), Vector2(250, 43), 21)
		SourceMenuArt.image(row, "minionPedia_seenIcon", Vector2(200, 10))
		if _owned.has(String(definition.id)):
			SourceMenuArt.image(row, "minionPedia_OwnedIcon", Vector2(200, 2))
	_selection = SourceMenuArt.image(_list_holder, "minionPedia_minionSelectedIcon", Vector2(-26, -2))
	for fast in 2:
		var symbol := "minionPedia_upArrow" if fast == 0 else "minionPedia_doubleUpArrow"
		var up := SourceMenuArt.button(_panel, symbol, Vector2(610 + fast * 32, 30), _scroll_by.bind(-1 if fast == 0 else -3))
		var down := SourceMenuArt.button(_panel, symbol, Vector2(610 + fast * 32, 438 if fast == 0 else 437), _scroll_by.bind(1 if fast == 0 else 3))
		if up != null:
			_up_buttons.append(up)
		if down != null:
			down.scale.y = -1
			_down_buttons.append(down)
	_update_scroll(false)
	_description = Control.new()
	_panel.add_child(_description)
	if not _minions.is_empty():
		_select(0)

func _select(index: int) -> void:
	_selected = index
	if _selection != null:
		_selection.position = Vector2(-26, -2 + index * 52)
	for child in _description.get_children():
		_description.remove_child(child)
		child.queue_free()
	var definition := _minions[index]
	var known := _seen.has(String(definition.id))
	var presentation := _catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition
	var texture: Texture2D = SourceMenuArt.texture("unknownMinion") if not known else null
	if known and presentation != null:
		var path := "res://content/base/art/battle/minions/%s.png" % String(presentation.legacy_sprite_name)
		if not ResourceLoader.exists(path):
			path = "res://content/base/art/battle/%s.png" % String(presentation.legacy_sprite_name)
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	if texture != null:
		var portrait := Sprite2D.new()
		portrait.name = "SourcePediaPortrait"
		portrait.texture = texture
		portrait.centered = false
		portrait.position = Vector2(174 - texture.get_width() * 0.5, 247 - texture.get_height())
		_description.add_child(portrait)
	_text(_description, "Name:  %s" % (definition.display_name if known else "????????"), Vector2(64, 288), Vector2(244, 33), 20)
	_text(_description, "Type: " if known else "Type:    ????????", Vector2(64, 318), Vector2(200, 30), 20)
	if known:
		for type_index in mini(2, definition.type_ids.size()):
			SourceMenuArt.image(_description, "menus_minionType_%s" % String(definition.type_ids[type_index]).get_file(), Vector2(124 + type_index * 82, 324))
	var found := "Found: ????????"
	if known:
		var floors: Array = _found_floors.get(String(definition.id), [])
		var floor_labels: PackedStringArray = []
		for floor_number in floors:
			floor_labels.append("%d-%d" % [int(floor_number) / 5 + 1, int(floor_number) % 5])
		found = "Found: N/A" if floors.is_empty() else "Found: Floor " + ",  ".join(floor_labels)
	_text(_description, found, Vector2(64, 348), Vector2(200, 60), 20)

func _scroll_by(amount: int) -> void:
	_scroll_position = clampi(_scroll_position + amount, 0, 19)
	_update_scroll(true)

func _update_scroll(animated: bool) -> void:
	if is_instance_valid(_scroll_tween):
		_scroll_tween.kill()
	var target_y := 19.0 - _list_holder.size.y / 20.0 * _scroll_position
	if animated:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_list_holder, "position:y", target_y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_list_holder.position.y = target_y
	for button in _up_buttons:
		button.visible = _scroll_position > 0
	for button in _down_buttons:
		button.visible = _scroll_position < 19

func _text(parent: Control, text: String, at: Vector2, label_size: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = label_size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(249, 249, 249))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
