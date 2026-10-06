class_name CampaignGemMenuView
extends Control

signal closed
signal exit_requested

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const GEM_TOOLTIP := preload("res://src/presentation/source_gem_tooltip.gd")
const PAGE_SIZE := 15
const PAGE_COUNT := 99
const SOURCE_POSITION := Vector2(44, 102)
const STAT_COLORS := ["#fc7979", "#ca8ada", "#f6834c", "#fff764", "#72ade6"]
var _session: Variant
var _member_id: StringName = &""
var _socket := 0
var _page := 0
var _selected_gem: StringName = &""
var _selected_page := 0
var _panel: Control
var _source_root: Control
var _selector: Control
var _message := ""
var _tooltip: GEM_TOOLTIP
var _portraits: Dictionary = {}
var _swapping := false
var _backdrop: Control
var _socket_shade: ColorRect
var _socket_shade_fade: Tween

func set_backdrop(view: Control) -> void:
	_backdrop = view
	_backdrop.set_meta("source_transition_background", true)
	_backdrop.process_mode = Node.PROCESS_MODE_DISABLED
	_backdrop.reparent(self, false)

func configure(session, member_id: StringName = &"", socket: int = 0) -> void:
	_session = session
	_member_id = member_id
	_socket = socket
	_refresh()

func _refresh() -> void:
	var overlay_alpha := _socket_shade.color.a if is_instance_valid(_socket_shade) else 0.0
	if is_instance_valid(_socket_shade_fade):
		_socket_shade_fade.kill()
	for child in get_children():
		if child == _backdrop:
			continue
		remove_child(child)
		child.queue_free()
	_portraits.clear()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, overlay_alpha if not _member_id.is_empty() else 0.65)
	if not _member_id.is_empty():
		shade.set_meta("source_local_menu_overlay", true)
		_socket_shade = shade
	add_child(shade)
	if not _member_id.is_empty() and overlay_alpha < 0.3:
		_socket_shade_fade = create_tween()
		shade.set_meta("source_local_menu_overlay_tween", _socket_shade_fade)
		_socket_shade_fade.tween_property(shade, "color:a", 0.3, 0.5 * (1.0 - overlay_alpha / 0.3))
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_source_root = Control.new()
	_source_root.size = Vector2(700, 525)
	_source_root.position = (viewport_size - _source_root.size * factor) * 0.5
	_source_root.scale = Vector2.ONE * factor
	add_child(_source_root)
	_panel = Control.new()
	_source_root.add_child(_panel)
	var background := SourceMenuArt.image(_panel, "menus_gemMenuBackground", Vector2.ZERO)
	_panel.size = background.size if background != null else Vector2(676, 340)
	# The source background expands from .9 around its own bounds center,
	# including the close tab above y=0, rather than the whole viewport.
	_panel.position = SOURCE_POSITION - Vector2(_panel.size.x * 0.5, (_panel.size.y - 22) * 0.5) * 0.1
	set_meta("source_transition_center", _source_root.position + (_panel.position + Vector2(_panel.size.x * 0.5, (_panel.size.y - 22) * 0.5)) * factor)
	SourceMenuArt.image(_panel, "menus_sponsorMoreGames_background", Vector2(23, 23))
	if _member_id.is_empty():
		var close := SourceMenuArt.button(_panel, "menus_exitButton", Vector2(624, -22), func() -> void: exit_requested.emit())
		if close != null:
			close.name = "GemClose"
	SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 291), func() -> void: closed.emit())
	var member := _member()
	if member != null:
		var equipped := _equipped_gem(member, _socket)
		if not equipped.is_empty():
			_portrait(_panel, equipped, Vector2(280, 284), 0.7)
			var current_hit := _hit(_panel, Vector2(280, 284), Vector2(53, 53) * 0.7, Callable())
			current_hit.mouse_entered.connect(_show_tooltip.bind(equipped))
			current_hit.mouse_exited.connect(_hide_tooltip)
			SourceMenuArt.button(_panel, "menus_gemMenu_unEquipButton", Vector2(325, 287), _unequip)
		var equip := SourceMenuArt.button(_panel, "menus_gemMenu_equipButton", Vector2(555, 284), _equip)
		if equip != null:
			equip.name = "GemEquip"
			equip.disabled = _selected_gem.is_empty()
			equip.modulate.a = 0.3 if equip.disabled else 1.0
	_build_inventory()
	_label(_message, Vector2(20, 244), Vector2(300, 43), 14)
	SourceMenuArt.button(_panel, "menus_gemCombiner_CombineButton", Vector2(507, 220), _sort)
	var title := _label("Sort Gems", Vector2(511, 229), Vector2(150, 25), 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_create_tooltip()

func _build_inventory() -> void:
	_selector = Control.new()
	_selector.name = "GemSelector"
	_selector.position = Vector2(332, 18)
	_panel.add_child(_selector)
	SourceMenuArt.image(_selector, "menus_gemSelectBackground", Vector2.ZERO)
	var gems := _inventory()
	for index in PAGE_SIZE:
		var at := Vector2(8 + (index % 5) * 64, 10 + floori(float(index) / 5) * 62)
		var slot := _page * PAGE_SIZE + index
		var gem: Dictionary = gems[slot] if slot < gems.size() else {}
		var id := StringName(gem.get("instance_id", ""))
		if gem.is_empty():
			SourceMenuArt.image(_selector, "menus_emptyGemSocket", at)
		else:
			if id == _selected_gem:
				var marker := SourceMenuArt.image(_selector, "menus_gemMenuGemSelected", at - Vector2(11, 13))
				if marker != null:
					marker.name = "GemSelection"
			_portraits[slot] = _portrait(_selector, gem, at, 1.0)
		var hit := _hit(_selector, at, Vector2(53, 53), _select_slot.bind(slot))
		hit.name = "GemSlot%d" % slot
		hit.disabled = gem.is_empty() and _selected_gem.is_empty()
		hit.mouse_entered.connect(_show_tooltip.bind(gem))
		hit.mouse_exited.connect(_hide_tooltip)
	var page_label := _label(str(_page + 1), Vector2(41, 213), Vector2(50, 30), 23, _selector)
	page_label.name = "GemPage"
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SourceMenuArt.button(_selector, "menus_scrollButton_up", Vector2(16, 212), _change_page.bind(-1))
	var next := SourceMenuArt.button(_selector, "menus_scrollButton_up", Vector2(113, 213), _change_page.bind(1))
	if next != null:
		next.scale.x = -1

func _hit(parent: Control, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var hit := Button.new()
	hit.position = at
	hit.size = dimensions
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if action.is_valid():
		hit.pressed.connect(action)
	parent.add_child(hit)
	return hit

func _inventory() -> Array[Dictionary]:
	var gems: Dictionary = {}
	for gem in _session.state.owned_gems:
		gems[String(gem.get("instance_id", ""))] = gem
	var result: Array[Dictionary] = []
	for id in CampaignGemEquipmentService.inventory_slots(_session.state):
		result.append(gems.get(id, {}))
	return result

func _member() -> OwnedMinionState:
	for owned in _session.state.party + _session.state.storage:
		if owned.instance_id == _member_id:
			return owned
	return null

func _equipped_gem(owned: OwnedMinionState, index: int) -> Dictionary:
	if index < 0 or index >= owned.equipment_ids.size():
		return {}
	for gem in _session.state.owned_gems:
		if String(gem.get("instance_id", "")) == String(owned.equipment_ids[index]):
			return gem
	return {}

func _portrait(parent: Control, gem: Dictionary, at: Vector2, factor: float) -> CampaignGemPortrait:
	var portrait := CampaignGemPortrait.new()
	portrait.position = at
	portrait.scale = Vector2.ONE * factor
	parent.add_child(portrait)
	portrait.configure(gem)
	return portrait

func _label(text: String, at: Vector2, label_size: Vector2, font_size: int, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(2, 2)
	label.size = label_size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(240, 240, 240))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _panel).add_child(label)
	return label

func _select_gem(id: StringName) -> void:
	var slots := CampaignGemEquipmentService.inventory_slots(_session.state)
	var slot := slots.find(String(id))
	if slot >= 0:
		_select_slot(slot)

func _select_slot(slot: int) -> void:
	if _swapping:
		return
	var slots := CampaignGemEquipmentService.inventory_slots(_session.state)
	var id := StringName(slots[slot]) if slot < slots.size() else &""
	if _selected_gem.is_empty():
		if not id.is_empty():
			_selected_gem = id
			_selected_page = _page
		_refresh()
		return
	if id == _selected_gem:
		_selected_gem = &""
		_refresh()
		return
	var moved: Dictionary = _session.move_gem_to_slot(_selected_gem, slot)
	if not moved.get("ok", false):
		_message = String(moved.get("message", "Could not move gem."))
		_refresh()
		return
	if _selected_page != _page:
		_finish_swap()
		return
	_swapping = true
	var origin := int(moved.origin_slot)
	var first := _portraits.get(origin) as Control
	var second := _portraits.get(slot) as Control
	var destination := Vector2(8 + (slot % 5) * 64, 10 + floori(float(slot % PAGE_SIZE) / 5) * 62)
	if first != null:
		if second != null:
			create_tween().tween_property(second, "position", first.position, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var swap := create_tween()
		swap.tween_property(first, "position", destination, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swap.tween_callback(_finish_swap)
	else:
		_finish_swap()
	var marker := _selector.get_node_or_null("GemSelection") as CanvasItem
	if marker != null:
		marker.hide()

func _finish_swap() -> void:
	_swapping = false
	_selected_gem = &""
	_refresh()

func _create_tooltip() -> void:
	_tooltip = GEM_TOOLTIP.new()
	_source_root.add_child(_tooltip)

func _show_tooltip(gem: Dictionary) -> void:
	_tooltip.show_gem(gem)

func _hide_tooltip() -> void:
	_tooltip.hide()

func _change_page(direction: int) -> void:
	if _swapping:
		return
	_page = posmod(_page + direction, PAGE_COUNT)
	_refresh()

func _equip() -> void:
	if _selected_gem.is_empty() or _member_id.is_empty() or _swapping:
		return
	var result: Dictionary = _session.equip_gem(_selected_gem, _member_id, _socket)
	if result.get("ok", false):
		closed.emit()
	else:
		_message = String(result.get("message", "Could not equip gem."))
		_refresh()

func _unequip() -> void:
	if _member_id.is_empty() or _swapping:
		return
	var result: Dictionary = _session.unequip_gem(_member_id, _socket)
	if result.get("ok", false):
		closed.emit()
	else:
		_message = String(result.get("message", "Could not remove gem."))
		_refresh()

func _sort() -> void:
	if _swapping:
		return
	var result: Dictionary = _session.sort_gems()
	_message = "" if result.get("ok", false) else String(result.get("message", "Could not sort gems."))
	_refresh()
