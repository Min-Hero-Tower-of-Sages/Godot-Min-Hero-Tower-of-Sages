class_name ModWorkshopView
extends Control

## The Mod Workshop: make, edit, check, test and share player mods. Every
## edit is written to the mod's JSON (see UserModRepository) after a short
## pause, so there is no separate save step. Changes reach saves the next time
## a save that uses the mod is loaded.

signal closed
signal test_battle_requested(mod_id: String, spec: Dictionary)

const TABS := ["Info", "Minions", "Moves", "Skills", "Types", "Changes", "Trainers", "Hatchery", "Rooms", "Floors", "Test"]
## The tabs grouped for the two navigation rows.
const CATEGORIES := [
	{"name": "Mod", "tabs": ["Info"], "tint": Color8(168, 184, 199)},
	{"name": "Create", "tabs": ["Minions", "Moves", "Skills", "Types"], "tint": Color8(112, 205, 128)},
	{"name": "Change", "tabs": ["Changes", "Trainers"], "tint": Color8(104, 164, 255)},
	{"name": "World", "tabs": ["Hatchery", "Rooms", "Floors"], "tint": Color8(255, 170, 70)},
	{"name": "Test", "tabs": ["Test"], "tint": Color8(236, 150, 204)},
]
const MINION_ART := "res://content/base/art/battle/minions/%s.png"
const MOVE_ICON := "res://content/base/art/battle/%s.png"
const EXAMPLE_PATH := "res://content/mods/examples/frost_pack.json"
const STAT_KEYS := ["health", "energy", "attack", "healing", "speed"]
const EFFECT_STATS := ["", "health", "energy", "attack", "healing", "speed"]
const MATCHUP_VALUES := ["strong", "normal", "weak"]
const MATCHUP_LABELS := ["Strong (x1.5)", "Normal", "Weak (x0.67)"]
const MATCHUP_COLORS := {"strong": Color8(70, 160, 96), "normal": Color8(68, 74, 85), "weak": Color8(184, 80, 76)}
const MATCHUP_SHORT := {"strong": "x1.5", "normal": "x1", "weak": "x0.67"}
## Test teams survive leaving for a test battle and coming back.
static var _test_specs: Dictionary = {}

var catalog: ContentCatalog
var _panel: PanelContainer
var _body: VBoxContainer
var _overlay: Control
var _manifest: Dictionary = {}
var _mod_id := ""
var _tab := "Info"
var _selection: Dictionary = {}
var _status: Label
var _save_timer: Timer
var _dirty := false
var _list_selection := 0
var _confirm := ""
var _entry_cache: Dictionary = {}
var _picker: ModWorkshopPicker
var _filters: Dictionary = {}
var _minion_preview: TextureRect
var _texture_cache: Dictionary = {}
var _preview_guard: Dictionary = {}
var _last_tab: Dictionary = {}
var _skills: ModWorkshopSkills
var _rooms_tab: ModWorkshopRooms
var _floors_tab: ModWorkshopFloors
## The in-game move card, shown while hovering any move in the Workshop.
var _move_tip: BattleMoveTooltip
var _tip_owner: Control
var _move_defs: Dictionary = {}
var _move_defs_key := ""
var _move_defs_frame := -1
## The pointer as the GUI last saw it (from motion events), in view space.
var _pointer := Vector2(-1, -1)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ModWorkshopForm.theme()
	z_index = 20
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.06, 0.08, 0.9)
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.size = Vector2(684, 509)
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_panel.add_child(_body)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)
	_move_tip = BattleMoveTooltip.new()
	_move_tip.z_index = 80
	add_child(_move_tip)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: _pointer = get_global_transform_with_canvas().affine_inverse() * event.position

func _process(_delta: float) -> void:
	if not _move_tip.visible: return
	var owner_rect := _tip_owner.get_global_rect() if is_instance_valid(_tip_owner) else Rect2()
	if not is_instance_valid(_tip_owner) or not _tip_owner.is_visible_in_tree() or not owner_rect.has_point(get_global_transform() * _pointer):
		_move_tip.visible = false
		return
	_place_tip()

## Above the pointer like in battle; below it when there is no room above.
func _place_tip() -> void:
	var mouse := _pointer if _pointer.x >= 0.0 else get_local_mouse_position()
	var at := Vector2(mouse.x - _move_tip.size.x * 0.5, mouse.y - _move_tip.size.y - 8.0)
	if at.y < 4.0: at.y = mouse.y + 22.0
	at.x = clampf(at.x, 4.0, maxf(4.0, size.x - _move_tip.size.x - 4.0))
	at.y = clampf(at.y, 4.0, maxf(4.0, size.y - _move_tip.size.y - 4.0))
	_move_tip.position = at

func open(resume: Dictionary = {}) -> void:
	if not is_inside_tree(): await ready
	if not String(resume.get("mod_id", "")).is_empty() and UserModRepository.exists(String(resume.mod_id)):
		_edit(String(resume.mod_id), String(resume.get("tab", "Info")))
	else:
		_show_list()

func _exit_tree() -> void:
	if _dirty: _save_now()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode != KEY_ESCAPE: return
	get_viewport().set_input_as_handled()
	if is_instance_valid(_picker): _picker.queue_free()
	elif is_instance_valid(_overlay): _close_overlay()
	elif room_focus():
		_selection["room_focus"] = false
		_build_editor()
	elif _tab == "Rooms" and not _mod_id.is_empty() and not String(_selection.get("room", "")).is_empty():
		_selection.erase("room")
		_build_editor()
	elif _tab == "Floors" and _floors_tab != null and _floors_tab.return_to_floor_map():
		return
	elif not _mod_id.is_empty(): _leave_editor()
	else: closed.emit()

func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

func _label(text: String, size: int = 14, color: Color = ModWorkshopForm.INK, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	(parent if parent != null else _body).add_child(label)
	return label

func _button(text: String, callback: Callable, parent: Control) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(callback)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ModWorkshopForm.tint_button(control)
	parent.add_child(control)
	return control

# --- Mod list ----------------------------------------------------------------

func _show_list() -> void:
	_mod_id = ""
	_manifest = {}
	_texture_cache.clear()
	_clear_body()
	var top := HBoxContainer.new()
	_body.add_child(top)
	var title := _label("Mod Workshop", 24, ModWorkshopForm.GOLD, top)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Close", func() -> void: closed.emit(), top)
	var intro := _label("Make your own minions, moves, skill trees, types, trainers and floor changes. Turn a mod on for a save in the save's Mod Menu (new game or Settings).", 12, ModWorkshopForm.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	_body.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 6)
	scroll.add_child(cards)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 236
	side.add_theme_constant_override("separation", 6)
	split.add_child(side)
	var message := Label.new()
	message.add_theme_font_size_override("font_size", 12)
	message.add_theme_color_override("font_color", Color8(240, 200, 120))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 120
	var mods := UserModRepository.list()
	if mods.is_empty():
		var empty := _label("No mods yet. Create one on the right, paste a share code, or install the example mod to see how one is made.", 13, ModWorkshopForm.MUTED, cards)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 120
	for manifest in mods: _mod_card(cards, manifest, message)
	_label("New mod", 16, ModWorkshopForm.GOLD, side)
	var name_entry := LineEdit.new()
	name_entry.placeholder_text = "Mod name, e.g. My Frost Mod"
	name_entry.max_length = 32
	name_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(name_entry)
	var make := func() -> void:
		var result := _create_mod(name_entry.text)
		if result.ok: _edit(result.id, "Info")
		else: message.text = result.message
	name_entry.text_submitted.connect(func(_value: String) -> void: make.call())
	_button("Create", make, side)
	_label("Get mods", 16, ModWorkshopForm.GOLD, side)
	_button("Paste a share code", _show_import_code, side)
	_button("Import a ZIP file", func() -> void: _pick_file("Import a mod ZIP", ["*.zip ; Mod ZIP"], _import_zip), side)
	_button("Install the example mod", _install_example, side)
	_button("Open mods folder", func() -> void:
		DirAccess.make_dir_recursive_absolute(UserModRepository.root)
		OS.shell_open(ProjectSettings.globalize_path(UserModRepository.root)), side)
	side.add_child(message)

func _mod_card(parent: Control, manifest: Dictionary, message: Label) -> void:
	var broken: bool = manifest.get("broken", false)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ModWorkshopForm.card_style())
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(92, 100, 114), 6))
	row.add_child(frame)
	var portrait: Texture2D = null
	if not broken:
		var previous_id := _mod_id
		var previous_manifest := _manifest
		_mod_id = String(manifest.id)
		_manifest = manifest
		var minions: Array = manifest.get("minions", [])
		if not minions.is_empty(): portrait = _minion_texture(String(minions[0].get("id", "")))
		_mod_id = previous_id
		_manifest = previous_manifest
	ModWorkshopForm.picture(portrait, Vector2(60, 60), frame)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	if broken:
		var damaged := _label("%s (damaged)" % manifest.id, 16, Color8(240, 130, 120), text)
		damaged.clip_text = true
		var reason := _label(String(manifest.get("message", "")), 12, ModWorkshopForm.MUTED, text)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.custom_minimum_size.x = 120
	else:
		var heading := _label(String(manifest.get("name", manifest.id)), 17, ModWorkshopForm.GOLD, text)
		heading.clip_text = true
		_label("v%s  ·  by %s" % [manifest.get("version", "1"), String(manifest.get("author", "")) if not String(manifest.get("author", "")).is_empty() else "unknown"], 12, ModWorkshopForm.MUTED, text)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 4)
		chips.add_theme_constant_override("v_separation", 3)
		text.add_child(chips)
		var any := false
		for section in [["minions", "minion", Color8(112, 205, 128)], ["moves", "move", Color8(112, 205, 128)], ["talent_trees", "skill tree", Color8(112, 205, 128)], ["types", "type", Color8(112, 205, 128)], ["minion_patches", "minion change", Color8(104, 164, 255)], ["move_patches", "move change", Color8(104, 164, 255)], ["trainers", "trainer", Color8(104, 164, 255)], ["hatchery", "egg rule", Color8(255, 170, 70)], ["rooms", "room", Color8(255, 170, 70)]]:
			var count: int = manifest.get(section[0], []).size()
			if count > 0:
				any = true
				ModWorkshopForm.chip("%d %s%s" % [count, section[1], "" if count == 1 else "s"], section[2], chips)
		if not any: ModWorkshopForm.chip("Empty so far", Color8(168, 184, 199), chips)
		var description := String(manifest.get("description", "")).strip_edges()
		if not description.is_empty():
			var blurb := _label(description.left(110) + ("..." if description.length() > 110 else ""), 12, ModWorkshopForm.INK, text)
			blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			blurb.custom_minimum_size.x = 120
			blurb.modulate = Color(1, 1, 1, 0.8)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	row.add_child(actions)
	if not broken:
		_button("Edit", func() -> void: _edit(String(manifest.id), "Info"), actions)
		_button("Share", func() -> void: _show_share(String(manifest.id)), actions)
	var delete := Button.new()
	delete.text = "Delete"
	delete.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	actions.add_child(delete)
	delete.pressed.connect(func() -> void:
		if delete.text == "Delete":
			delete.text = "Sure?"
			message.text = "Press again to remove %s from this computer. Saves that use it will not load until it is installed again." % manifest.get("name", manifest.id)
			return
		var deleted := UserModRepository.delete(String(manifest.id))
		if not deleted.ok:
			message.text = deleted.message
			delete.text = "Delete"
			return
		_show_list())

static func slug(text: String) -> String:
	var result := RegEx.create_from_string("[^a-z0-9]+").sub(text.to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	if result.is_empty() or not result[0].is_valid_identifier(): result = "m_" + result
	return result.left(24).trim_suffix("_")

func _create_mod(name: String) -> Dictionary:
	var display := name.strip_edges()
	if display.is_empty(): return {"ok": false, "message": "Give the mod a name first."}
	var id := slug(display)
	if id.length() < 2 or id in ["base", "extended", "user"]: id = "mod_" + id
	var unique := id
	var number := 2
	while UserModRepository.exists(unique):
		unique = "%s_%d" % [id.left(28), number]
		number += 1
	var manifest := {"format": UserModBuilder.FORMAT_VERSION, "id": unique, "name": display, "version": "1.0.0", "author": "", "description": "",
		"types": [], "type_chart": [], "moves": [], "talent_trees": [], "minions": [], "minion_patches": [], "move_patches": [], "trainers": [], "hatchery": [], "rooms": []}
	var written := UserModRepository.write(manifest)
	return {"ok": true, "id": unique} if written.ok else written

func _install_example() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE_PATH))
	if not manifest is Dictionary: return show_message("The example mod is missing from this build.")
	if UserModRepository.exists(String(manifest.id)):
		return show_message("The example (Frost Pack) is already installed. Delete it first to restore the original.")
	var written := UserModRepository.write(manifest)
	if not written.ok: return show_message(written.message)
	_show_list()

# --- Sharing -------------------------------------------------------------------

func _overlay_panel(title: String, height: float = 300.0) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 40
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(90, (525.0 - height) * 0.5)
	panel.size = Vector2(520, height)
	_overlay.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_label(title, 18, ModWorkshopForm.GOLD, rows)
	return rows

func _close_overlay() -> void:
	if is_instance_valid(_overlay): _overlay.queue_free()
	_overlay = null

func show_message(text: String) -> void:
	var rows := _overlay_panel("Mod Workshop", 220)
	var label := _label(text, 13, ModWorkshopForm.INK, rows)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_button("OK", _close_overlay, rows)

func _show_share(mod_id: String) -> void:
	if _dirty and not _save_now(): return
	var code := UserModRepository.export_code(mod_id)
	if not code.ok: return show_message(code.message)
	var rows := _overlay_panel("Share %s" % mod_id, 330)
	_label("Send this code to a friend; they paste it in their Mod Workshop. Players in the same multiplayer game need the same mods.", 12, ModWorkshopForm.MUTED, rows).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var box := TextEdit.new()
	box.text = code.code
	box.editable = false
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(box)
	var status := _label("%d KB code" % maxi(1, ceili(code.code.length() / 1024.0)), 12, ModWorkshopForm.MUTED, rows)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	_button("Copy code", func() -> void:
		DisplayServer.clipboard_set(code.code)
		status.text = "Copied to the clipboard.", buttons)
	_button("Save as ZIP", func() -> void:
		var zip := UserModRepository.export_zip(mod_id)
		status.text = ("Saved %s" % ProjectSettings.globalize_path(zip.path)) if zip.ok else String(zip.message)
		if zip.ok: OS.shell_open(ProjectSettings.globalize_path(zip.path.get_base_dir())), buttons)
	_button("Close", _close_overlay, buttons)

func _show_import_code() -> void:
	var rows := _overlay_panel("Install from a share code", 330)
	var box := TextEdit.new()
	box.placeholder_text = "Paste a code that starts with %s" % UserModRepository.CODE_PREFIX
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(box)
	var status := _label("", 12, ModWorkshopForm.MUTED, rows)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	_button("Paste", func() -> void: box.text = DisplayServer.clipboard_get(), buttons)
	_button("Install", func() -> void:
		var decoded := UserModRepository.decode_code(box.text)
		if not decoded.ok:
			status.text = decoded.message
			return
		_install_bundle(decoded, status), buttons)
	_button("Cancel", _close_overlay, buttons)

func _import_zip(path: String) -> void:
	var decoded := UserModRepository.decode_zip(path)
	if not decoded.ok: return show_message(decoded.message)
	var rows := _overlay_panel("Install %s" % decoded.manifest.get("name", "mod"), 200)
	var status := _label("", 13, ModWorkshopForm.INK, rows)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_install_bundle(decoded, status)
	if UserModRepository.exists(String(decoded.manifest.id)) and _confirm == "replace:%s" % decoded.manifest.id:
		_button("Replace installed copy", func() -> void: _install_bundle(decoded, status), rows)
	_button("Close", _close_overlay, rows)

func _install_bundle(bundle: Dictionary, status: Label) -> void:
	var id := String(bundle.manifest.id)
	var replacing := UserModRepository.exists(id)
	if replacing and _confirm != "replace:%s" % id:
		_confirm = "replace:%s" % id
		status.text = "%s is already installed. Install again to replace your copy (saves using it will load the new version)." % bundle.manifest.get("name", id)
		return
	_confirm = ""
	var installed := UserModRepository.install_bundle(bundle, replacing)
	if not installed.ok:
		status.text = installed.message
		return
	var checked := UserModService.check(catalog, bundle.manifest)
	status.text = "Installed %s.%s" % [bundle.manifest.get("name", id), ("\nIt has problems: %s" % "; ".join(checked.errors).left(300)) if not checked.errors.is_empty() else " Turn it on in a save's Mod Menu."]
	if _mod_id.is_empty():
		var keep := status.text
		_show_list()
		show_message(keep)

## Opens the framing overlay for a picked picture; `on_done(image)` gets the result.
func _crop_picture(path: String, title: String, aspect: float, fixed_size: Vector2i, on_done: Callable) -> void:
	var loaded := ModWorkshopCropper.load_picture(path)
	if not loaded.ok: return show_message(loaded.message)
	var cropper := ModWorkshopCropper.new()
	add_child(cropper)
	cropper.open(title, loaded.image, aspect, fixed_size)
	cropper.cropped.connect(on_done)

func _pick_file(title: String, filters: PackedStringArray, on_file: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		on_file.call(path))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

# --- Editor shell ----------------------------------------------------------------

func _edit(mod_id: String, tab: String) -> void:
	var loaded := UserModRepository.read(mod_id)
	if not loaded.ok: return show_message(loaded.message)
	_mod_id = mod_id
	_manifest = loaded.manifest
	for section in UserModBuilder.SECTIONS:
		if not _manifest.get(section) is Array: _manifest[section] = []
	_tab = tab if tab in TABS else "Info"
	_selection.clear()
	_filters.clear()
	_texture_cache.clear()
	_rooms_tab = null
	_floors_tab = null
	_build_editor()

func _leave_editor() -> void:
	if _dirty and not _save_now():
		show_message("Your changes could not be saved. Check the mod's name and version, and try again.")
		return
	_show_list()

func _changed() -> void:
	_move_defs_frame = -1
	_dirty = true
	if is_instance_valid(_status): _status.text = "Saving..."
	_save_timer.start()

func _save_now() -> bool:
	_save_timer.stop()
	if _mod_id.is_empty() or not _dirty: return true
	var written := UserModRepository.write(_manifest)
	_dirty = not written.ok
	if is_instance_valid(_status): _status.text = "All changes saved" if written.ok else "Not saved: %s" % written.message
	return written.ok

## Room focus mode: the room editor takes the whole screen, without the
## Workshop's header rows (its toolbar then shows the save status).
func room_focus() -> bool:
	return _tab == "Rooms" and bool(_selection.get("room_focus", true)) and not String(_selection.get("room", "")).is_empty()

func _build_editor() -> void:
	_clear_body()
	_entry_cache.erase("own")
	var focus := room_focus()
	_panel.position = Vector2(2, 2) if focus else Vector2(8, 8)
	_panel.size = Vector2(696, 521) if focus else Vector2(684, 509)
	if focus:
		var full := Control.new()
		full.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body.add_child(full)
		_rooms_tab_build(full)
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	_body.add_child(top)
	_button("< Mods", _leave_editor, top)
	var title := _label(String(_manifest.get("name", _mod_id)), 19, ModWorkshopForm.GOLD, top)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.custom_minimum_size.x = 60
	title.tooltip_text = "%s v%s" % [_manifest.get("name", _mod_id), _manifest.get("version", "1")]
	_build_categories(top)
	_button("Share", func() -> void: _show_share(_mod_id), top)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 5)
	_body.add_child(sub)
	_status = _label("Saving..." if _dirty else "All changes saved", 12, Color8(154, 216, 179), sub)
	_build_tabs(sub)
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(content)
	match _tab:
		"Info": _info_tab(_scroll_form(content, false))
		"Minions": _list_tab(content, "minions", "New minion from...", _new_minion, _minion_form)
		"Moves": _list_tab(content, "moves", "New move from...", _new_move, _move_form)
		"Skills": _skills_tab(content)
		"Types": _types_tab(content)
		"Changes": _changes_tab(content)
		"Trainers": _list_tab(content, "trainers", "Edit a trainer...", _new_trainer, _trainer_form)
		"Hatchery": _list_tab(content, "hatchery", "Add a hatchery rule", _new_hatchery_rule, _hatchery_form)
		"Rooms": _rooms_tab_build(content)
		"Floors":
			if _floors_tab == null: _floors_tab = ModWorkshopFloors.new(self)
			_floors_tab.build(content)
		"Test": _test_tab(_scroll_form(content, false))

func _open_tab(tab: String) -> void:
	_tab = tab
	_build_editor()

func _current_category() -> Dictionary:
	for candidate in CATEGORIES:
		if _tab in candidate.tabs: return candidate
	return CATEGORIES[0]

## The category buttons, in the header row.
func _build_categories(parent: Control) -> void:
	var category := _current_category()
	_last_tab[category.name] = _tab
	for candidate in CATEGORIES:
		var total := 0
		for tab in candidate.tabs: total += _tab_count(tab)
		var button := Button.new()
		button.theme_type_variation = "NavPrimary"
		button.toggle_mode = true
		button.button_pressed = candidate == category
		button.text = String(candidate.name) + (" %d" % total if total > 0 and candidate.name not in ["Mod", "Test"] else "")
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var target := String(_last_tab.get(candidate.name, candidate.tabs[0]))
		button.pressed.connect(func() -> void: _open_tab(target if target in candidate.tabs else String(candidate.tabs[0])))
		parent.add_child(button)

## The current category's tabs, in the second row.
func _build_tabs(parent: Control) -> void:
	var category := _current_category()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if category.tabs.size() < 2:
		parent.add_child(spacer)
		parent.move_child(_status, parent.get_child_count() - 1)
		return
	for tab in category.tabs:
		var button := Button.new()
		button.theme_type_variation = "NavSecondary"
		button.toggle_mode = true
		button.button_pressed = tab == _tab
		var count := _tab_count(tab)
		button.text = "%s  %d" % [_tab_title(tab), count] if count > 0 else _tab_title(tab)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func() -> void: _open_tab(tab))
		parent.add_child(button)
	parent.add_child(spacer)
	parent.move_child(_status, parent.get_child_count() - 1)

func _tab_title(tab: String) -> String:
	return "Skill trees" if tab == "Skills" else tab

func _tab_count(tab: String) -> int:
	match tab:
		"Minions": return _manifest.minions.size()
		"Moves": return _manifest.moves.size()
		"Skills": return _manifest.talent_trees.size()
		"Types": return _manifest.types.size()
		"Changes": return _manifest.minion_patches.size() + _manifest.move_patches.size()
		"Trainers": return _manifest.trainers.size()
		"Hatchery": return _manifest.hatchery.size()
		"Rooms": return _manifest.rooms.size()
		"Floors": return _manifest.floors.size()
	return 0

func _make_form() -> ModWorkshopForm:
	var form := ModWorkshopForm.new()
	form.describe = _describe
	form.decorate = decorate_reference
	form.changed.connect(_changed)
	form.pick_requested.connect(_open_picker)
	return form

func _skills_tab(content: Control) -> void:
	if _skills == null: _skills = ModWorkshopSkills.new(self)
	_list_tab(content, "talent_trees", "New tree from...", _skills.new_from_existing, _skills.tree_form, [["New blank tree", _skills.new_blank]], func(index: int) -> void:
		var gone := String(_manifest.talent_trees[index].id)
		for minion in _manifest.minions + _manifest.minion_patches:
			if minion.get("talent_trees") is Array: minion.talent_trees.erase(gone)
		_manifest.talent_trees.remove_at(index))

func _scroll_form(parent: Control, beside_list: bool) -> ModWorkshopForm:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if beside_list:
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(scroll)
	else:
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		parent.add_child(scroll)
	var form := _make_form()
	scroll.add_child(form)
	return form

## A list of the mod's records on the left and the selected record's form.
func _list_tab(content: Control, section: String, new_caption: String, on_new: Callable, build_form: Callable, extra_buttons: Array = [], on_remove: Callable = Callable()) -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 8)
	content.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 178
	split.add_child(left)
	var section_caption := "Changes" if section == "__changes" else "Skill trees" if section == "talent_trees" else section.capitalize()
	_label("%s  ·  %d" % [section_caption, _manifest[section].size()], 14, ModWorkshopForm.GOLD, left)
	var search := LineEdit.new()
	search.name = "ContentSearch"
	search.placeholder_text = "Filter by name…"
	search.text = String(_filters.get(section, ""))
	search.clear_button_enabled = true
	left.add_child(search)
	var list := ItemList.new()
	list.fixed_icon_size = Vector2i(64, 16) if section == "types" else Vector2i(30, 30)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list)
	var records: Array = _manifest[section]
	var filter_records := func() -> void:
		list.clear()
		var query := search.text.strip_edges().to_lower()
		for record_index in records.size():
			var record: Dictionary = records[record_index]
			var caption := _record_label(section, record)
			if not query.is_empty() and not caption.to_lower().contains(query) and not String(record.get("id", record.get("target", ""))).to_lower().contains(query): continue
			var item := list.add_item(caption, _record_icon(section, record))
			list.set_item_metadata(item, record_index)
			list.set_item_tooltip(item, caption)
			if record_index == int(_selection.get(section, 0)): list.select(item)
	filter_records.call()
	if section in ["moves", "__changes"]:
		# Hovering a move in the list shows its in-game card.
		list.gui_input.connect(func(event: InputEvent) -> void:
			if not event is InputEventMouseMotion: return
			var item := list.get_item_at_position(event.position, true)
			var move_id := ""
			if item >= 0:
				var record: Dictionary = records[int(list.get_item_metadata(item))]
				move_id = "%s/tier1" % record.get("id", "") if section == "moves" else String(record.get("target", ""))
			if move_id.contains(":move/"): show_move_tip(list, move_id)
			elif _tip_owner == list: _move_tip.visible = false)
	search.text_changed.connect(func(value: String) -> void:
		_filters[section] = value
		filter_records.call())
	_button(new_caption, on_new, left)
	for extra in extra_buttons: _button(extra[0], extra[1], left)
	var remove := _button("Remove", func() -> void:
		var index := int(_selection.get(section, -1))
		if index < 0 or index >= records.size(): return
		if _confirm != "remove:%s:%d" % [section, index]:
			_confirm = "remove:%s:%d" % [section, index]
			_status.text = "Press Remove again to delete it"
			return
		_confirm = ""
		if on_remove.is_valid(): on_remove.call(index)
		else: records.remove_at(index)
		var remaining := records.size() - (1 if section == "__changes" else 0)
		_selection[section] = mini(index, remaining - 1)
		_changed()
		_build_editor(), left)
	var form := _scroll_form(split, true)
	var index := int(_selection.get(section, 0 if not records.is_empty() else -1))
	remove.disabled = index < 0 or index >= records.size()
	if index >= 0 and index < records.size():
		_selection[section] = index
		build_form.call(form, records[index])
	else:
		form.note(_empty_hint(section))
	list.item_selected.connect(func(picked: int) -> void:
		_selection[section] = int(list.get_item_metadata(picked))
		_confirm = ""
		_build_editor())

func _record_icon(section: String, record: Dictionary) -> Texture2D:
	match section:
		"minions": return _minion_texture(String(record.get("id", "")))
		"moves": return _move_icon("%s/tier1" % record.get("id", ""))
		"types": return _type_badge(String(record.get("id", "")))
		"trainers":
			var team: Array = record.get("team", [])
			return _minion_texture(String(team[0].get("minion", ""))) if not team.is_empty() else null
		"hatchery":
			var entries: Array = record.get("entries", [])
			return _minion_texture(String(entries[0].get("minion", ""))) if not entries.is_empty() else null
		"talent_trees":
			for node in record.get("nodes", []):
				if not node.get("moves", []).is_empty(): return _move_icon(String(node.moves[0]))
		"__changes":
			var target := String(record.get("target", ""))
			return _move_icon(target) if target.contains(":move/") else _minion_texture(target)
	return null

func _editor_pages(parent: ModWorkshopForm, key: String, pages: Array) -> String:
	var tabs := TabBar.new()
	tabs.add_theme_font_size_override("font_size", 12)
	for page in pages: tabs.add_tab(String(page))
	var selected := String(_selection.get(key, pages[0]))
	tabs.current_tab = maxi(0, pages.find(selected))
	parent.add_child(tabs)
	tabs.tab_changed.connect(func(index: int) -> void:
		_selection[key] = pages[index]
		_build_editor())
	return selected

func _record_label(section: String, record: Dictionary) -> String:
	match section:
		"minions", "moves", "types", "talent_trees": return String(record.get("name", record.get("id", "?")))
		"trainers": return _describe("encounter", String(record.get("target", "")))
		"hatchery": return "Floor %d (%s)" % [int(record.get("floor", 0)) + 1, record.get("mode", "add")]
		"rooms": return _describe("room", String(record.get("target", "")))
		"minion_patches": return "Minion: %s" % _describe("minion", String(record.get("target", "")))
		"move_patches": return "Move: %s" % _describe("move", String(record.get("target", "")))
		"__changes": return _record_label("move_patches" if String(record.get("target", "")).contains(":move/") else "minion_patches", record)
	return "?"

func _empty_hint(section: String) -> String:
	match section:
		"talent_trees": return "A skill tree decides which moves a minion can learn as it levels up. Start from a copy of a recovered tree or from a blank grid, then give it to a minion in the Minions tab."
		"minions": return "A new minion starts as a copy of an existing one: its talent trees, art and stats. Then change its name, types, stats, moves and colors."
		"moves": return "A new move starts as a copy of an existing move (all its tiers). It keeps that move's animation and icon; change its type, cost and effects."
		"trainers": return "Pick any tower trainer to change their team, name and what they say."
		"hatchery": return "Add your minions to a floor's hatchery, or replace a floor's eggs entirely."
		"rooms": return "Change a room's doors, door key costs, hatchery eggs and which trainer stands there. Rooms keep their recovered layouts."
	return ""

func _unique_id(category: String, base_name: String) -> String:
	var stem := "%s:%s/%s" % [_mod_id, category, slug(base_name)]
	var candidate := stem
	var number := 2
	while _id_taken(candidate):
		candidate = "%s_%d" % [stem, number]
		number += 1
	return candidate

func _id_taken(id: String) -> bool:
	for section in ["minions", "moves", "types", "talent_trees", "floors"]:
		for record in _manifest[section]:
			if String(record.get("id", "")) == id: return true
	return catalog.has_definition(StringName(id))

# --- Lookups for pickers and labels --------------------------------------------

func _open_picker(kind: String, on_pick: Callable) -> void:
	var picker := ModWorkshopPicker.new()
	_picker = picker
	add_child(picker)
	var titles := {"minion": "Choose a minion", "move": "Choose a move", "type": "Choose a type", "minion_type": "Choose a type", "talent_tree": "Choose a talent tree", "encounter": "Choose a trainer", "room": "Choose a room"}
	picker.icon_for = reference_icon
	picker.badge_for = _type_badge
	picker.hover_for = bind_move_hover
	picker.types_for = func(entry_kind: String, id: String) -> Array:
		match entry_kind:
			"minion": return _minion_types(id)
			"move":
				var move := move_definition(id)
				return [String(move.type_id)] if move != null and move.type_id != &"base:type/none" else []
		return []
	picker.open(titles.get(kind, "Choose"), _entries(kind), kind)
	picker.picked.connect(func(id: String) -> void: on_pick.call(id))

func _entries(kind: String) -> Array:
	var own: Array = []
	match kind:
		"minion":
			for record in _manifest.get("minions", []): own.append({"id": String(record.id), "label": "* %s" % record.get("name", record.id), "detail": "This mod"})
		"move":
			for record in _manifest.get("moves", []):
				for tier in record.get("tiers", []).size():
					own.append({"id": "%s/tier%d" % [record.id, tier + 1], "label": "* %s (tier %d)" % [record.get("name", record.id), tier + 1], "detail": "This mod"})
		"type", "minion_type":
			for record in _manifest.get("types", []): own.append({"id": String(record.id), "label": "* %s" % record.get("name", record.id), "detail": "This mod"})
		"talent_tree":
			for record in _manifest.get("talent_trees", []): own.append({"id": String(record.id), "label": "* %s" % record.get("name", record.id), "detail": "This mod"})
	if not _entry_cache.has(kind):
		var entries: Array = []
		for definition in catalog._by_id.values():
			match kind:
				"minion":
					if definition is MinionDefinition and CampaignModService.minion_is_available(null, definition) or definition is MinionDefinition and definition.source_mod != &"base" and not String(definition.id).contains("bmod"):
						entries.append({"id": String(definition.id), "label": definition.display_name, "detail": ", ".join(Array(definition.type_ids).map(func(value: StringName) -> String: return String(value).get_file().capitalize()))})
				"move":
					if definition is MoveDefinition and definition.available and not definition.effects.is_empty():
						entries.append({"id": String(definition.id), "label": "%s (tier %d)" % [definition.display_name, definition.tier], "detail": String(definition.type_id).get_file().capitalize()})
				"type", "minion_type":
					if definition is TypeDefinition and (kind == "type" or definition.id != &"base:type/none"):
						entries.append({"id": String(definition.id), "label": definition.display_name, "detail": ""})
				"talent_tree":
					if definition is TalentTreeDefinition:
						entries.append({"id": String(definition.id), "label": "%s (%s)" % [definition.display_name, String(definition.id).get_file()], "detail": ""})
				"encounter":
					if definition is EncounterDefinition and not definition.team_entries.is_empty():
						entries.append({"id": String(definition.id), "label": definition.display_name, "detail": "Floor %d" % (definition.source_floor_index + 1)})
				"room":
					if definition is RoomDefinition and String(definition.id).begins_with("base:room/"):
						entries.append({"id": String(definition.id), "label": definition.display_name, "detail": String(definition.id)})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.label).naturalnocasecmp_to(String(b.label)) < 0)
		_entry_cache[kind] = entries
	return own + _entry_cache[kind]

func _describe(kind: String, id: String) -> String:
	if id.is_empty(): return "(none)"
	for section in ["minions", "moves", "types", "talent_trees"]:
		for record in _manifest.get(section, []):
			if String(record.get("id", "")) == id: return "* %s" % record.get("name", id)
			if section == "moves" and id.begins_with(String(record.get("id", "")) + "/tier"):
				return "* %s (tier %s)" % [record.get("name", id), id.get_slice("/tier", 1)]
	var definition := catalog.get_definition(StringName(id))
	if definition == null: return "%s (missing)" % id
	if definition is MoveDefinition: return "%s (tier %d)" % [definition.display_name, definition.tier]
	return definition.display_name

# --- Info ---------------------------------------------------------------------------

func _info_tab(form: ModWorkshopForm) -> void:
	var about := form.card("About this mod")
	about.text("Name", _manifest, "name", 32)
	var id_row := about.row("Mod ID")
	_label("%s  (fixed: saves refer to it)" % _mod_id, 13, ModWorkshopForm.MUTED, id_row)
	about.text("Version", _manifest, "version", 12)
	about.text("Author", _manifest, "author", 32)
	about.text("Description", _manifest, "description", 400, true)
	var inside := form.card("What's inside")
	inside.note("Press a tile to jump to it.")
	var tiles := GridContainer.new()
	tiles.columns = 4
	tiles.add_theme_constant_override("h_separation", 6)
	tiles.add_theme_constant_override("v_separation", 6)
	inside.add_child(tiles)
	for entry in [["Minions", "Minions"], ["Moves", "Moves"], ["Skills", "Skill trees"], ["Types", "Types"], ["Changes", "Changes"], ["Trainers", "Trainers"], ["Hatchery", "Hatchery rules"], ["Rooms", "Rooms changed"]]:
		var count := _tab_count(String(entry[0]))
		var tile := Button.new()
		tile.text = "%d\n%s" % [count, entry[1]]
		tile.custom_minimum_size = Vector2(96, 50)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.6)
		var destination := String(entry[0])
		tile.pressed.connect(func() -> void: _open_tab(destination))
		tiles.add_child(tile)
	if not _manifest.minions.is_empty():
		var strip := HFlowContainer.new()
		strip.add_theme_constant_override("h_separation", 8)
		inside.add_child(strip)
		for record in _manifest.minions.slice(0, 12):
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 0)
			strip.add_child(slot)
			ModWorkshopForm.picture(_minion_texture(String(record.get("id", ""))), Vector2(48, 48), slot)
			var caption := _label(String(record.get("name", "")).left(9), 11, ModWorkshopForm.MUTED, slot)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := form.card("How mods work")
	help.note("- Create: new minions, moves, skill trees and types. New minions copy an existing minion's art (recolored) or use a PNG you import.")
	help.note("- Change: edit existing minions, moves and tower trainers. World: hatchery eggs and the floor map, with doors and arrival points.")
	help.note("- A mod only affects saves that turn it on (Mod Menu at new game, or Settings > Mod Menu). A save cannot turn a mod off while it owns minions, moves or gems from it.")
	help.note("- Use Test to check for problems and fight a test battle. Share gives a code or ZIP for friends; multiplayer partners need the same mods.")

# --- Minions --------------------------------------------------------------------

func _new_minion() -> void:
	_open_picker("minion", func(base_id: String) -> void:
		var base := catalog.get_definition(StringName(base_id)) as MinionDefinition
		var record := UserModBuilder.minion_record(base) if base != null else {}
		for own in _manifest.minions:
			if String(own.id) == base_id: record = own.duplicate(true)
		if record.is_empty(): return
		record["id"] = _unique_id("minion", "new_" + String(record.get("name", "minion")))
		record["name"] = ("New %s" % record.get("name", "Minion")).left(24)
		record["based_on"] = base_id if base != null else String(record.get("based_on", ""))
		record["evolves_into"] = ""
		record["evolution_level"] = 30
		record["sprite"] = {"from": record.based_on, "hue_shift": 0.5, "saturation": 1.0, "value": 1.0}
		_manifest.minions.append(record)
		_selection["minions"] = _manifest.minions.size() - 1
		_changed()
		_build_editor())

func _minion_form(form: ModWorkshopForm, record: Dictionary, is_patch: bool = false) -> void:
	var original: Dictionary = {}
	var defaults: Dictionary = {}
	if is_patch:
		var definition := catalog.get_definition(StringName(String(record.target))) as MinionDefinition
		if definition != null:
			defaults = UserModBuilder.minion_record(definition)
			original = defaults.stats.duplicate()
			var stats: Dictionary = defaults.stats.duplicate()
			stats.merge(record.get("stats", {}), true)
			record.merge(defaults, false)
			record["stats"] = stats
	if not record.get("stats") is Dictionary: record["stats"] = {}
	var identity_id := String(record.target) if is_patch else String(record.get("id", ""))
	# Header: portrait, name and the minion's type badges, kept current as the form changes.
	var head := form.card()
	var head_row := head.row("")
	head_row.add_theme_constant_override("separation", 12)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(92, 100, 114), 6))
	head_row.add_child(frame)
	_minion_preview = ModWorkshopForm.picture(_minion_texture(identity_id) if is_patch else _sprite_preview(record.get("sprite", {"from": record.get("based_on", "")})), Vector2(92, 92), frame)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_text)
	var head_title := _label("", 20, ModWorkshopForm.GOLD, head_text)
	head_title.clip_text = true
	var head_sub := _label("", 12, ModWorkshopForm.MUTED, head_text)
	head_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_sub.custom_minimum_size.x = 120
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	head_text.add_child(badges)
	var refresh_head := func() -> void:
		head_title.text = ("Changing %s" % _describe("minion", identity_id)) if is_patch else String(record.get("name", "Minion"))
		head_sub.text = "Only this mod's saves see these changes. Owned minions use the new stats right away." if is_patch else "ID %s · based on %s" % [record.get("id", ""), _describe("minion", String(record.get("based_on", "")))]
		for child in badges.get_children():
			badges.remove_child(child)
			child.queue_free()
		for type_id in record.get("types", []): ModWorkshopForm.picture(_type_badge(String(type_id)), Vector2(80, 20), badges)
	refresh_head.call()
	form.changed.connect(refresh_head)
	if is_patch and not defaults.is_empty(): _patch_diff_card(form, record, defaults)
	var identity := form.card("Identity")
	identity.text("Name", record, "name", 24)
	identity.text("Pedia text", record, "description", 400, true)
	identity.reference_list("Types (1-2)", record, "types", "minion_type", 2, 1)
	var base_stats := form.card("Base stats")
	base_stats.note("Recovered minions sit between about 20 and 60 per stat at their first stage." + (" The white tick marks the original value." if is_patch else ""))
	var stats_row := base_stats.row("")
	stats_row.add_theme_constant_override("separation", 14)
	var spin_grid := GridContainer.new()
	spin_grid.columns = 1
	spin_grid.add_theme_constant_override("v_separation", 0)
	stats_row.add_child(spin_grid)
	var bars := ModWorkshopStatBars.new()
	bars.stats = record.stats
	bars.original = original
	bars.row_height = 31.0
	stats_row.add_child(bars)
	for stat_index in STAT_KEYS.size():
		var cell := HBoxContainer.new()
		spin_grid.add_child(cell)
		var caption := Label.new()
		caption.text = String(STAT_KEYS[stat_index]).capitalize()
		caption.custom_minimum_size.x = 56
		cell.add_child(caption)
		base_stats.number("", record.stats, STAT_KEYS[stat_index], 1 if stat_index == 0 else 0, 999, 30, 1, cell).value_changed.connect(func(_value: float) -> void: bars.queue_redraw())
	var curve_card := form.card("Level preview")
	curve_card.note("Battle stats from level 1 to 60, using the game's level formula (no gems or stars). Hover the chart for exact values.")
	var curve := ModWorkshopGrowthChart.new()
	curve.stats = record.stats
	curve_card.add_child(curve)
	var refresh_curve := func() -> void:
		curve.evolution_level = int(record.get("evolution_level", 0)) if not String(record.get("evolves_into", "")).is_empty() else 0
		curve.queue_redraw()
	refresh_curve.call()
	form.changed.connect(refresh_curve)
	var growth := form.card("Growth")
	growth.choice("Experience rate", record, "xp_rate", [0, 1, 2, 3, 4], ["Very slow", "Normal", "Fast", "Faster", "Fastest"])
	var gems := growth.row("Gem sockets")
	growth.number("", record, "gem_slots", 0, 8, 1, 1, gems)
	_label("locked", 12, ModWorkshopForm.MUTED, gems)
	growth.number("", record, "locked_gem_slots", 0, 8, 0, 1, gems)
	growth.reference("Evolves into", record, "evolves_into", "minion", true)
	growth.number("At level", record, "evolution_level", 2, 99, 30)
	_evolution_strip(growth, record, identity_id)
	var moves := form.card("Moves and skills")
	moves.reference_list("Starting moves", record, "initial_moves", "move", 8, 1)
	moves.reference_list("Specialization", record, "specialization_moves", "move", 3)
	moves.note("Specialization needs exactly three moves (the level-up choices), or none. Each one opens the skill tree in the same position below.")
	moves.reference_list("Skill trees", record, "talent_trees", "talent_tree", 3)
	moves.button("Open the Skill trees tab to make or edit trees", func() -> void: _open_tab("Skills"))
	if is_patch and not record.has("sprite"):
		form.button("Recolor this minion too", func() -> void:
			record["sprite"] = {"from": String(record.target), "hue_shift": 0.5, "saturation": 1.0, "value": 1.0}
			_changed()
			_build_editor())
		return
	_sprite_section(form.card("Look"), record)

## "What this change does": every field that differs from the recovered minion,
## as old → new with a coloured delta for numbers. Rebuilt live as fields change.
func _patch_diff_card(form: ModWorkshopForm, record: Dictionary, defaults: Dictionary) -> void:
	var card := form.card("What this change does")
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	card.add_child(lines)
	var refresh := func() -> void:
		for child in lines.get_children():
			lines.remove_child(child)
			child.queue_free()
		var rows := _record_diff(record, defaults)
		if rows.is_empty():
			_label("Nothing differs from the original yet. Edit a field below.", 12, ModWorkshopForm.MUTED, lines)
			return
		for entry in rows:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			lines.add_child(line)
			var caption := _label(String(entry.caption), 12, ModWorkshopForm.MUTED, line)
			caption.custom_minimum_size.x = 96
			if entry.has("key") and _diff_kind(String(entry.key)) != "":
				_diff_pictures(String(entry.key), entry.before_value, line).modulate = Color(1, 1, 1, 0.6)
				_label("→", 12, ModWorkshopForm.GOLD, line)
				_diff_pictures(String(entry.key), entry.after_value, line)
				continue
			var before := _label(String(entry.before), 12, Color8(150, 160, 172), line)
			before.clip_text = true
			before.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			before.size_flags_stretch_ratio = 1.0
			_label("→", 12, ModWorkshopForm.GOLD, line)
			var after := _label(String(entry.after), 12, ModWorkshopForm.INK, line)
			after.clip_text = true
			after.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if entry.has("delta"):
				var delta := int(entry.delta)
				_label(("+%d" % delta) if delta > 0 else str(delta), 12, Color8(130, 222, 118) if delta > 0 else Color8(240, 130, 120), line)
	refresh.call()
	form.changed.connect(refresh)

func _record_diff(record: Dictionary, defaults: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key in STAT_KEYS:
		var before := int(defaults.get("stats", {}).get(key, 0))
		var after := int(record.get("stats", {}).get(key, before))
		if before != after: rows.append({"caption": key.capitalize(), "before": str(before), "after": str(after), "delta": after - before})
	var captions := {"name": "Name", "description": "Pedia text", "types": "Types", "xp_rate": "XP rate", "gem_slots": "Gem sockets", "locked_gem_slots": "Locked sockets", "evolves_into": "Evolves into", "evolution_level": "Evolves at", "initial_moves": "Starting moves", "specialization_moves": "Specialization", "talent_trees": "Skill trees"}
	for key in captions:
		if not record.has(key) or record[key] == defaults.get(key): continue
		var before: Variant = defaults.get(key)
		var after: Variant = record[key]
		var row := {"caption": captions[key], "before": _diff_text(key, before), "after": _diff_text(key, after), "key": key, "before_value": before, "after_value": after}
		if (before is int or before is float) and (after is int or after is float): row["delta"] = int(after) - int(before)
		rows.append(row)
	if record.has("sprite"): rows.append({"caption": "Look", "before": "original art", "after": "recoloured" if String(record.sprite.get("file", "")).is_empty() else "own PNG"})
	return rows

func _diff_kind(key: String) -> String:
	return String({"types": "type", "evolves_into": "minion", "initial_moves": "move", "specialization_moves": "move", "talent_trees": "talent_tree"}.get(key, ""))

## Badges, icons or portraits for one side of a reference change.
func _diff_pictures(key: String, value: Variant, parent: Control) -> Control:
	var kind := _diff_kind(key)
	var box := HFlowContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("h_separation", 3)
	box.add_theme_constant_override("v_separation", 2)
	parent.add_child(box)
	var ids: Array = value if value is Array else ([] if String(value if value != null else "").is_empty() else [value])
	if ids.is_empty():
		_label("none", 12, ModWorkshopForm.MUTED, box)
		return box
	for id in ids:
		var picture_size := Vector2(48, 15) if kind == "type" else Vector2(22, 22)
		var picture := ModWorkshopForm.picture(reference_icon(kind, String(id)), picture_size, box)
		picture.tooltip_text = _describe(kind, String(id))
		picture.mouse_filter = Control.MOUSE_FILTER_PASS
		if kind == "move": bind_move_hover(picture, String(id))
	return box

func _diff_text(key: String, value: Variant) -> String:
	var kinds := {"types": "type", "evolves_into": "minion", "initial_moves": "move", "specialization_moves": "move", "talent_trees": "talent_tree"}
	if value is Array:
		if value.is_empty(): return "none"
		return ", ".join(value.map(func(id: Variant) -> String: return _describe(String(kinds.get(key, "")), String(id))))
	if key in kinds: return "nothing" if String(value).is_empty() else _describe(kinds[key], String(value))
	if key == "description": return "\"%s\"" % String(value).left(28) + ("…" if String(value).length() > 28 else "")
	return str(value)

## The evolution line through this minion: portraits joined by "Lv N" arrows.
## Follows this mod's own records first, then the recovered catalog.
func _evolution_strip(form: ModWorkshopForm, record: Dictionary, own_id: String) -> void:
	var holder := form.row("Evolution line")
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	holder.add_child(strip)
	var refresh := func() -> void:
		for child in strip.get_children():
			strip.remove_child(child)
			child.queue_free()
		var chain: Array[Dictionary] = [{"id": own_id, "next": String(record.get("evolves_into", "")), "level": int(record.get("evolution_level", 0))}]
		while chain.size() < 4 and not String(chain[-1].next).is_empty():
			var next_id := String(chain[-1].next)
			if chain.any(func(step: Dictionary) -> bool: return step.id == next_id): break
			chain.append(_evolution_step(next_id))
		for index in chain.size():
			if index > 0:
				_label("Lv %d ›" % int(chain[index - 1].level), 11, ModWorkshopForm.GOLD, strip)
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), ModWorkshopForm.GOLD if index == 0 else Color8(92, 100, 114), 4))
			frame.tooltip_text = _describe("minion", String(chain[index].id)) if index > 0 else String(record.get("name", ""))
			strip.add_child(frame)
			ModWorkshopForm.picture(_minion_preview.texture if index == 0 and is_instance_valid(_minion_preview) else _minion_texture(String(chain[index].id)), Vector2(40, 40), frame)
		if chain.size() == 1: _label("does not evolve", 12, ModWorkshopForm.MUTED, strip)
	refresh.call()
	form.changed.connect(refresh)

func _evolution_step(id: String) -> Dictionary:
	for own in _manifest.get("minions", []):
		if String(own.get("id", "")) == id: return {"id": id, "next": String(own.get("evolves_into", "")), "level": int(own.get("evolution_level", 0))}
	var definition := catalog.get_definition(StringName(id)) as MinionDefinition
	if definition == null: return {"id": id, "next": "", "level": 0}
	return {"id": id, "next": String(definition.evolution_id), "level": definition.evolution_level}

func _sprite_section(form: ModWorkshopForm, record: Dictionary) -> void:
	var sprite: Dictionary = record.sprite
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(120, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var holder := form.row("Preview")
	holder.add_child(preview)
	var refresh := func() -> void:
		preview.texture = _sprite_preview(sprite)
		if is_instance_valid(_minion_preview): _minion_preview.texture = preview.texture
	if String(sprite.get("file", "")).is_empty():
		form.reference("Art copied from", sprite, "from", "minion", false, null, refresh)
	else:
		var file_row := form.row("Own art")
		_label(String(sprite.file), 13, ModWorkshopForm.INK, file_row)
		form.button("Use a copied minion's art instead", func() -> void:
			sprite.erase("file")
			if String(sprite.get("from", "")).is_empty(): sprite["from"] = String(record.get("based_on", record.get("target", "")))
			_changed()
			_build_editor())
	form.button("Import my own PNG...", func() -> void:
		_pick_file("Choose a minion image", ["*.png ; PNG image"], func(path: String) -> void:
			_crop_picture(path, "Frame your minion", 1.0, Vector2i.ZERO, func(image: Image) -> void:
				var imported := UserModRepository.import_image(_mod_id, image, String(record.get("id", record.get("target", "sprite"))).get_file())
				if not imported.ok: return show_message(imported.message)
				sprite["file"] = imported.path
				_texture_cache.clear()
				_changed()
				_build_editor())))
	for setting in [["Hue shift", "hue_shift", 0.0, 1.0, 0.0], ["Saturation", "saturation", 0.0, 2.0, 1.0], ["Brightness", "value", 0.0, 2.0, 1.0]]:
		form.slider(setting[0], sprite, setting[1], setting[2], setting[3], setting[4]).value_changed.connect(func(_value: float) -> void: refresh.call())
	form.note("Minion art faces right, like the recovered battle sprites. Imported art is copied into the mod and travels with its share code.")
	refresh.call()

func _sprite_preview(sprite: Dictionary) -> Texture2D:
	var image: Image
	if not String(sprite.get("file", "")).is_empty():
		var bytes := UserModRepository.read_file(_mod_id, String(sprite.file))
		image = Image.new()
		if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK: return null
	else:
		var from := String(sprite.get("from", ""))
		if _preview_guard.has(from): return null
		_preview_guard[from] = true
		var source := _minion_texture(from)
		_preview_guard.erase(from)
		if source == null or source.get_image() == null: return null
		image = source.get_image().duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	UserModAssets.recolor(image, float(sprite.get("hue_shift", 0.0)), float(sprite.get("saturation", 1.0)), float(sprite.get("value", 1.0)))
	return ImageTexture.create_from_image(image)

# --- Pictures --------------------------------------------------------------------

## A minion's battle art: this mod's own (recoloured or imported) or recovered.
func _minion_texture(id: String) -> Texture2D:
	if id.is_empty(): return null
	for record in _manifest.get("minions", []):
		if String(record.get("id", "")) != id: continue
		var sprite: Dictionary = record.get("sprite", {"from": record.get("based_on", "")})
		var own_key := "minion:%s:%s" % [id, JSON.stringify(sprite)]
		if not _texture_cache.has(own_key): _texture_cache[own_key] = _sprite_preview(sprite)
		return _texture_cache[own_key]
	var key := "minion:" + id
	if not _texture_cache.has(key):
		var definition := catalog.get_definition(StringName(id)) as MinionDefinition
		var presentation := catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition if definition != null else null
		var path := MINION_ART % String(presentation.legacy_sprite_name) if presentation != null else ""
		_texture_cache[key] = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	return _texture_cache[key]

## The small type badge: drawn from the name and colour for this mod's types.
func _type_badge(id: String) -> Texture2D:
	if id.is_empty(): return null
	for record in _manifest.get("types", []):
		if String(record.get("id", "")) != id: continue
		var key := "badge:%s:%s:%s:%s" % [id, record.get("name", ""), record.get("color", ""), record.get("badge", "")]
		if not _texture_cache.has(key):
			var image: Image = null
			if not String(record.get("badge", "")).is_empty():
				var bytes := UserModRepository.read_file(_mod_id, String(record.badge))
				image = Image.new()
				if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK: image = null
			if image == null:
				image = UserModAssets._badge(UserModAssets._size_of("menus_minionType_fire", Vector2i(80, 20)), Color.from_string(String(record.get("color", "#ffffff")), Color.WHITE), String(record.get("name", "")).to_upper(), false)
			_texture_cache[key] = ImageTexture.create_from_image(image)
		return _texture_cache[key]
	var base_key := "badge:" + id
	if not _texture_cache.has(base_key): _texture_cache[base_key] = SourceMenuArt.texture("menus_minionType_%s" % id.get_file())
	return _texture_cache[base_key]

## The icon of a move tier (own tiers borrow the icon of the move they look like).
func _move_icon(id: String, depth: int = 0) -> Texture2D:
	if id.is_empty() or depth > 4: return null
	for record in _manifest.get("moves", []):
		if id.begins_with(String(record.get("id", "")) + "/tier"): return _move_icon(String(record.get("looks_like", "")), depth + 1)
	var key := "move:" + id
	if not _texture_cache.has(key):
		var move := catalog.get_definition(StringName(id)) as MoveDefinition
		var path := MOVE_ICON % String(move.buff_icon_name) if move != null else ""
		_texture_cache[key] = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	return _texture_cache[key]

## The picture for a referenced ID: a type badge, move icon or portrait.
func reference_icon(kind: String, id: String) -> Texture2D:
	if id.is_empty(): return null
	match kind:
		"type", "minion_type": return _type_badge(id)
		"move": return _move_icon(id)
		"minion": return _minion_texture(id)
		"talent_tree": return _tree_icon(id)
		"encounter":
			var team := _encounter_team(id)
			return _minion_texture(String(team[0].get("minion", ""))) if not team.is_empty() else null
	return null

## Gives a reference button its picture, and moves the in-game hover card.
func decorate_reference(control: Control, kind: String, id: String) -> void:
	var button := control as Button
	if button != null:
		# Rows that already show a portrait beside the button don't need a second one.
		var beside := button.get_parent() != null and button.get_parent().get_children().any(func(node: Node) -> bool: return node is TextureRect)
		button.icon = null if beside else reference_icon(kind, id)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 50 if kind in ["type", "minion_type"] else 22)
	if kind == "move": bind_move_hover(control, id)

## Shows the in-game move description card while the pointer is over `control`.
func bind_move_hover(control: Control, move_id: String) -> void:
	control.set_meta(&"workshop_move", move_id)
	control.tooltip_text = ""
	if control.has_meta(&"workshop_move_hover"): return
	control.set_meta(&"workshop_move_hover", true)
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE: control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(func() -> void: show_move_tip(control, String(control.get_meta(&"workshop_move", ""))))
	control.mouse_exited.connect(func() -> void:
		if _tip_owner == control: _move_tip.visible = false)

func show_move_tip(owner: Control, move_id: String) -> void:
	if _move_tip.visible and _tip_owner == owner and _move_tip.get_meta(&"move_id", "") == move_id: return
	_move_tip.set_meta(&"move_id", move_id)
	var move := move_definition(move_id)
	if move == null:
		_move_tip.visible = false
		return
	_tip_owner = owner
	_move_tip.show_move(move)
	# Godot reports mouse_entered before _input sees the motion, so only place
	# the card here; the next frame checks the pointer is still over `owner`.
	_pointer = get_global_transform().affine_inverse() * owner.get_global_mouse_position() if _pointer.x < 0.0 else _pointer
	_place_tip()

## A move tier as this mod plays it: own moves and changed moves come from a
## preview build of the mod, everything else from the catalog.
func move_definition(id: String) -> MoveDefinition:
	if id.is_empty(): return null
	# Edits can only land between frames, so one check per frame is enough
	# (the picker asks for hundreds of moves at once).
	if _move_defs_frame != Engine.get_process_frames():
		_move_defs_frame = Engine.get_process_frames()
		var key := JSON.stringify([_mod_id, _manifest.get("types", []), _manifest.get("moves", []), _manifest.get("move_patches", [])]).sha256_text()
		if key != _move_defs_key:
			_move_defs_key = key
			_move_defs = UserModBuilder.preview_moves(_manifest, catalog) if not _mod_id.is_empty() else {}
	if _move_defs.has(id): return _move_defs[id]
	return catalog.get_definition(StringName(id)) as MoveDefinition

func _tree_icon(id: String) -> Texture2D:
	for record in _manifest.get("talent_trees", []):
		if String(record.get("id", "")) == id: return _record_icon("talent_trees", record)
	var tree := catalog.get_definition(StringName(id)) as TalentTreeDefinition
	if tree == null: return null
	for node in tree.nodes:
		var moves: Array = node.get("move_ids", [])
		if not moves.is_empty(): return _move_icon(String(moves[0]))
	return null

# --- Moves ------------------------------------------------------------------------

func _new_move() -> void:
	_open_picker("move", func(base_id: String) -> void:
		var record := _family_record(base_id)
		if record.is_empty(): return
		record["id"] = _unique_id("move", "new_" + String(record.get("name", "move")))
		record["name"] = ("New %s" % record.get("name", "Move")).left(32)
		_manifest.moves.append(record)
		_selection["moves"] = _manifest.moves.size() - 1
		_changed()
		_build_editor())

## A full, editable copy of a move family, from any of its tiers.
func _family_record(tier_id: String) -> Dictionary:
	for own in _manifest.moves:
		if tier_id.begins_with(String(own.id) + "/tier"):
			return own.duplicate(true)
	var picked := catalog.get_definition(StringName(tier_id)) as MoveDefinition
	if picked == null: return {}
	var tiers: Array[MoveDefinition] = []
	for definition in catalog._by_id.values():
		if definition is MoveDefinition and definition.family_id == picked.family_id and definition.available and not definition.effects.is_empty():
			tiers.append(definition)
	tiers.sort_custom(func(a: MoveDefinition, b: MoveDefinition) -> bool: return a.tier < b.tier)
	var tier_records: Array = []
	for tier in tiers.slice(0, 5):
		var tier_record := UserModBuilder.move_record(tier)
		for key in ["name", "description", "type"]: tier_record.erase(key)
		tier_records.append(tier_record)
	return {"name": picked.display_name, "description": picked.description, "type": String(picked.type_id), "looks_like": tier_id, "tiers": tier_records}

func _move_form(form: ModWorkshopForm, record: Dictionary) -> void:
	var tier_index := clampi(int(_selection.get("tier", 0)), 0, record.tiers.size() - 1)
	_move_card(form, record, record.tiers[tier_index], "ID %s · %d tier%s" % [record.id, record.tiers.size(), "" if record.tiers.size() == 1 else "s"], String(record.id) + "/tier%d" % (tier_index + 1))
	var identity := form.card("Identity")
	identity.text("Name", record, "name", 32)
	identity.text("Description", record, "description", 400, true)
	identity.reference("Type", record, "type", "type")
	identity.reference("Looks like", record, "looks_like", "move")
	identity.note("The move plays this move's animation and uses its icon.")
	var tiers := form.card("Tiers")
	var tier_row := tiers.row("Tier")
	for index in record.tiers.size():
		var tier_button := Button.new()
		tier_button.text = str(index + 1)
		tier_button.toggle_mode = true
		tier_button.button_pressed = index == tier_index
		tier_button.pressed.connect(func() -> void:
			_selection["tier"] = index
			_build_editor())
		tier_row.add_child(tier_button)
	if record.tiers.size() < 5:
		_button("+ Tier", func() -> void:
			record.tiers.append(record.tiers[-1].duplicate(true))
			_selection["tier"] = record.tiers.size() - 1
			_changed()
			_build_editor(), tier_row)
	if record.tiers.size() > 1:
		_button("Remove tier", func() -> void:
			record.tiers.remove_at(tier_index)
			_selection["tier"] = maxi(0, tier_index - 1)
			_changed()
			_build_editor(), tier_row)
	tiers.note("Talents and level-ups unlock tiers in order; trainers and skill gems use the highest tier allowed. Editing tier %d below." % (tier_index + 1))
	_power_preview(form, record, record.tiers[tier_index])
	_tier_form(form, record.tiers[tier_index])

## The move as a player will see it: icon, name, type, cost chips and what each effect does.
func _move_card(form: ModWorkshopForm, record: Dictionary, tier: Dictionary, subtitle: String, icon_id: String) -> void:
	var head := form.card()
	var head_row := head.row("")
	head_row.add_theme_constant_override("separation", 12)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(92, 100, 114), 6))
	head_row.add_child(frame)
	var icon := ModWorkshopForm.picture(null, Vector2(56, 56), frame)
	bind_move_hover(frame, icon_id)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	head_row.add_child(body)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	body.add_child(title_row)
	var title := _label("", 20, ModWorkshopForm.GOLD, title_row)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var badge := ModWorkshopForm.picture(null, Vector2(80, 20), title_row)
	var sub := _label(subtitle, 12, ModWorkshopForm.MUTED, body)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 120
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 3)
	body.add_child(chips)
	var effect_lines := VBoxContainer.new()
	effect_lines.add_theme_constant_override("separation", 1)
	head.add_child(effect_lines)
	var refresh := func() -> void:
		title.text = String(record.get("name", "Move"))
		icon.texture = _move_icon(icon_id)
		badge.texture = _type_badge(String(record.get("type", "")))
		for container in [chips, effect_lines]:
			for child in container.get_children():
				container.remove_child(child)
				child.queue_free()
		ModWorkshopForm.chip("Energy %d" % int(tier.get("energy_cost", 0)), Color8(104, 164, 255), chips)
		ModWorkshopForm.chip("%d%% accurate" % int(tier.get("accuracy", 100)), Color8(168, 184, 199), chips)
		if int(tier.get("cooldown", 0)) > 0: ModWorkshopForm.chip("Cooldown %d" % int(tier.cooldown), Color8(255, 170, 70), chips)
		if int(tier.get("charge", 0)) > 0: ModWorkshopForm.chip("Charge %d" % int(tier.charge), Color8(255, 170, 70), chips)
		if int(tier.get("exhaust", 0)) > 0: ModWorkshopForm.chip("Exhaust %d" % int(tier.exhaust), Color8(236, 96, 88), chips)
		if bool(tier.get("passive", false)): ModWorkshopForm.chip("Passive", Color8(200, 140, 255), chips)
		ModWorkshopForm.chip(_target_text(tier), Color8(112, 205, 128), chips)
		var effects: Array = tier.get("effects", [])
		for index in effects.size():
			var line := _label("%d. %s" % [index + 1, _effect_text(effects[index])], 12, ModWorkshopForm.INK, effect_lines)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = 120
		if effects.is_empty(): _label("This tier does nothing yet. Add an effect below.", 12, Color8(240, 130, 120), effect_lines)
	refresh.call()
	form.changed.connect(refresh)

## Rough numbers for this tier: what each damage/heal effect does for a user
## of the chosen level and base stat, against neutral, weak and resistant types.
## Uses the battle formula (LegacyCombatMath); the settings are not saved.
func _power_preview(form: ModWorkshopForm, record: Dictionary, tier: Dictionary) -> void:
	var card := form.card("Power preview")
	var settings: Dictionary = _selection.get_or_add("power_preview", {"level": 30, "base": 40})
	var controls := card.row("User level / base")
	# Plain spin boxes: these preview settings must not mark the mod as changed.
	var level_box := _preview_spin(settings, "level", 1, 60, controls)
	_label("base Attack/Healing", 12, ModWorkshopForm.MUTED, controls)
	var base_box := _preview_spin(settings, "base", 1, 120, controls)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 3)
	card.add_child(table)
	var refresh := func() -> void:
		for child in table.get_children():
			table.remove_child(child)
			child.queue_free()
		var chart := catalog.get_type_chart()
		var strong := chart.super_effective_multiplier if chart != null else 1.5
		var weak := chart.not_effective_multiplier if chart != null else 0.67
		var level := int(settings.level)
		var stat := float(settings.base) * 60.0 / LegacyMinionStats.STAT_DIVISOR + LegacyMinionStats.BASE_OTHER_STAT
		var effects: Array = tier.get("effects", [])
		var shown := 0
		for index in effects.size():
			var effect: Dictionary = effects[index]
			var kind := String(effect.get("kind", ""))
			if kind not in ["damage", "heal", "periodic_damage", "periodic_heal"] or String(effect.get("scaling", "")) not in ["attack", "healing"]: continue
			shown += 1
			var healing := kind in ["heal", "periodic_heal"]
			var low := LegacyCombatMath.calculate_scaled_amount(float(effect.get("amount", 0)), float(effect.get("random_bonus", 0)), stat, level, 0.0)
			var high := LegacyCombatMath.calculate_scaled_amount(float(effect.get("amount", 0)), float(effect.get("random_bonus", 0)), stat, level, 1.0)
			var line := HFlowContainer.new()
			line.add_theme_constant_override("h_separation", 5)
			line.add_theme_constant_override("v_separation", 3)
			table.add_child(line)
			var turns := int(effect.get("duration", 0))
			var periodic := kind.begins_with("periodic")
			var caption := "%d. %s%s" % [index + 1, "Heal" if healing else "Damage", " / turn" if periodic else ""]
			_label(caption, 12, ModWorkshopForm.INK, line).custom_minimum_size.x = 104
			ModWorkshopForm.chip(_range_text(low, high, 1.0), Color8(168, 184, 199), line)
			if bool(effect.get("type_effectiveness", false)):
				# Healing swaps the chart: a type the move is strong against heals less.
				ModWorkshopForm.chip("%s %s" % ["boosted" if healing else "strong", _range_text(low, high, strong)], Color8(112, 205, 128), line)
				ModWorkshopForm.chip("%s %s" % ["reduced" if healing else "resisted", _range_text(low, high, weak)], Color8(238, 108, 98), line)
			if periodic and turns > 1: ModWorkshopForm.chip("%s over %d turns" % [_range_text(low * turns, high * turns, 1.0), turns], Color8(246, 214, 104), line)
		if shown == 0:
			_label("This tier has no damage or healing that scales with Attack/Healing.", 12, ModWorkshopForm.MUTED, table)
		else:
			var hint := _label("+10%% when the user shares the move's type. Critical hits double direct damage.%s" % (" Over-time ticks ignore types with the Piercing Over-Time save mod." if effects.any(func(effect: Dictionary) -> bool: return String(effect.get("kind", "")).begins_with("periodic")) else ""), 11, ModWorkshopForm.MUTED, table)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = 120
	refresh.call()
	form.changed.connect(refresh)
	level_box.value_changed.connect(func(_value: float) -> void: refresh.call())
	base_box.value_changed.connect(func(_value: float) -> void: refresh.call())

func _preview_spin(settings: Dictionary, key: String, minimum: int, maximum: int, parent: Control) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = int(settings[key])
	spin.custom_minimum_size.x = 72
	spin.value_changed.connect(func(value: float) -> void: settings[key] = int(value))
	parent.add_child(spin)
	return spin

func _range_text(low: float, high: float, multiplier: float) -> String:
	var a := int(roundf(low * multiplier))
	var b := int(roundf(high * multiplier))
	return str(a) if a == b else "%d-%d" % [a, b]

func _target_text(tier: Dictionary) -> String:
	var side := String(tier.get("target_side", "enemy"))
	var mode := String(tier.get("target_mode", "chosen"))
	if bool(tier.get("only_self", false)) or side == "self": return "Self"
	var count := int(tier.get("enemy_target_count", 1)) if side == "enemy" else int(tier.get("ally_target_count", 1))
	return "%s %s%s" % [{"enemy": "Enemies", "ally": "Allies"}.get(side, side.capitalize()), {"chosen": "chosen", "all": "all", "random": "random"}.get(mode, mode), " x%d" % count if mode != "all" and count > 1 else ""]

## One effect in plain words, e.g. "Deals 18 + Attack damage to the enemy".
func _effect_text(effect: Dictionary) -> String:
	var kind := String(effect.get("kind", "damage"))
	var amount := int(effect.get("amount", 0))
	var bonus := int(effect.get("random_bonus", 0))
	var power := str(amount) if bonus <= 0 else "%d-%d" % [amount, amount + bonus]
	var scale_text: String = {"attack": " + Attack", "healing": " + Healing", "energy_stat_percent": " (% of Energy)", "health_stat_percent": " (% of Health)"}.get(String(effect.get("scaling", "none")), "")
	var who: String = {"actor": "itself", "enemy_targets": "the enemy", "ally_targets": "an ally", "both_target_groups": "everyone targeted", "allied_team": "the whole team"}.get(String(effect.get("target", "")), "the target")
	var turns := int(effect.get("duration", 0))
	var for_turns := " for %d turn%s" % [turns, "" if turns == 1 else "s"] if turns > 0 else ""
	var stat := String(effect.get("stat", "")).replace("base:stat/", "")
	var text := ""
	match kind:
		"damage": text = "Deals %s%s damage to %s" % [power, scale_text, who]
		"heal": text = "Heals %s for %s%s" % [who, power, scale_text]
		"energy": text = ("Gives %s %s energy" % [who, power]) if amount >= 0 else "Drains %d energy from %s" % [-amount, who]
		"stat_stage": text = "%s %s's %s by %d%s" % ["Raises" if amount >= 0 else "Lowers", who, stat if not stat.is_empty() else "stat", absi(amount), for_turns]
		"shield": text = "Shields %s with %s%s%s" % [who, power, scale_text, for_turns]
		"reflect": text = "%s reflects damage%s" % [who.capitalize(), for_turns]
		"periodic_damage": text = "Deals %s%s damage to %s every turn%s" % [power, scale_text, who, for_turns]
		"periodic_heal": text = "Heals %s for %s%s every turn%s" % [who, power, scale_text, for_turns]
		"armor": text = "Gives %s armor %s%s" % [who, power, for_turns]
		"self_damage": text = "Hurts itself for %s%s" % [power, scale_text]
		"health_percent_damage": text = "Removes %s%% of %s's health" % [power, who]
		"stun": text = "Stuns %s%s" % [who, for_turns]
		"freeze": text = "Freezes %s%s" % [who, for_turns]
		"clear_buffs_debuffs": text = "Clears %s's %s" % [who, {"buffs_only": "buffs", "debuffs_only": "debuffs"}.get(String(effect.get("removal", "both")), "buffs and debuffs")]
		"stat_percent": text = "%s %s by %d%%" % ["Boosts" if amount >= 0 else "Cuts", stat if not stat.is_empty() else "a stat", absi(amount)]
		"redirect_damage": text = "Redirects damage aimed at %s%s" % [who, for_turns]
		"critical_chance": text = "Critical chance %s%d%%%s" % ["+" if amount >= 0 else "-", absi(amount), for_turns]
		_: text = kind.capitalize()
	var chance := int(effect.get("chance", 100))
	if chance < 100: text += " (%d%% chance)" % chance
	return text

func _tier_form(form: ModWorkshopForm, tier: Dictionary) -> void:
	var costs_card := form.card("Cost and timing")
	var costs := costs_card.row("Energy / accuracy")
	costs_card.number("", tier, "energy_cost", 0, 99, 5, 1, costs)
	costs_card.number("", tier, "accuracy", 0, 100, 100, 1, costs)
	var timing := costs_card.row("Cooldown / charge")
	costs_card.number("", tier, "cooldown", 0, 99, 0, 1, timing)
	costs_card.number("", tier, "charge", 0, 99, 0, 1, timing)
	costs_card.number("Exhaust turns", tier, "exhaust", 0, 99, 0)
	var flags := costs_card.row("")
	costs_card.toggle("Passive", tier, "passive", flags)
	costs_card.toggle("Team-wide passive", tier, "global_passive", flags)
	var targets := form.card("Targets")
	var side := targets.row("Side / choice")
	targets.choice("", tier, "target_side", ["enemy", "ally", "self"], ["Enemies", "Allies", "Self"], side)
	targets.choice("", tier, "target_mode", ["chosen", "all", "random"], ["Chosen", "All", "Random"], side)
	var counts := targets.row("Enemies / allies hit")
	targets.number("", tier, "enemy_target_count", 0, 5, 1, 1, counts)
	targets.number("", tier, "ally_target_count", 0, 5, 0, 1, counts)
	targets.number("Selected target count", tier, "target_count", 1, 5, 1)
	var target_flags := targets.row("")
	targets.toggle("Hit each target", tier, "hit_each_target", target_flags)
	targets.toggle("Random targets", tier, "random_targets", target_flags)
	targets.toggle("Only self", tier, "only_self", target_flags)
	var effects_card := form.card("Effects, in order")
	effects_card.note("Amount is the move's power (scaled by Attack or Healing when chosen). Periodic effects repeat each turn for Duration turns.")
	if not tier.get("effects") is Array: tier["effects"] = []
	var effects: Array = tier.effects
	for index in effects.size():
		_effect_form(effects_card, effects, index)
	if effects.size() < 8:
		effects_card.button("+ Add effect", func() -> void:
			effects.append(effects[-1].duplicate(true) if not effects.is_empty() else {"kind": "damage", "target": "enemy_targets", "phase": "enemy_target", "scaling": "attack", "roll": "shared_move", "amount": 10, "type_effectiveness": true, "can_critical": true})
			_changed()
			_build_editor())

func _effect_form(form: ModWorkshopForm, effects: Array, index: int) -> void:
	var effect: Dictionary = effects[index]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(64, 69, 79), 5))
	form.add_child(box)
	var inner := ModWorkshopForm.new()
	inner.describe = _describe
	inner.changed.connect(_changed)
	box.add_child(inner)
	var summary := _label(_effect_text(effect), 13, ModWorkshopForm.GOLD, inner)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.x = 120
	inner.changed.connect(func() -> void: summary.text = _effect_text(effect))
	var header := inner.row("Effect %d" % (index + 1))
	var kinds := Array(UserModBuilder.effect_kind_names())
	inner.choice("", effect, "kind", kinds, kinds.map(func(value: String) -> String: return value.capitalize()), header)
	if index > 0:
		_button("Up", func() -> void:
			effects.insert(index - 1, effects.pop_at(index))
			_changed()
			_build_editor(), header)
	if index < effects.size() - 1:
		_button("Down", func() -> void:
			effects.insert(index + 1, effects.pop_at(index))
			_changed()
			_build_editor(), header)
	if effects.size() > 1:
		_button("Remove", func() -> void:
			effects.remove_at(index)
			_changed()
			_build_editor(), header)
	var who := inner.row("Applies to / when")
	var scopes := Array(UserModBuilder.enum_names(EffectDefinition.TargetScope))
	var phases := Array(UserModBuilder.enum_names(EffectDefinition.Phase))
	inner.choice("", effect, "target", scopes, scopes.map(func(value: String) -> String: return value.capitalize()), who)
	inner.choice("", effect, "phase", phases, phases.map(func(value: String) -> String: return value.capitalize()), who)
	var power := inner.row("Amount / random +")
	inner.number("", effect, "amount", -9999, 9999, 0, 1, power)
	inner.number("", effect, "random_bonus", 0, 9999, 0, 1, power)
	var chance := inner.row("Chance % / turns")
	inner.number("", effect, "chance", 0, 100, 100, 1, chance)
	inner.number("", effect, "duration", 0, 99, 0, 1, chance)
	var scale := inner.row("Scales with / roll")
	var scalings := Array(UserModBuilder.enum_names(EffectDefinition.Scaling))
	var rolls := Array(UserModBuilder.enum_names(EffectDefinition.RollScope))
	inner.choice("", effect, "scaling", scalings, scalings.map(func(value: String) -> String: return value.capitalize()), scale)
	inner.choice("", effect, "roll", rolls, rolls.map(func(value: String) -> String: return value.capitalize()), scale)
	var stat := inner.row("Stat / removes")
	inner.choice("", effect, "stat", EFFECT_STATS, EFFECT_STATS.map(func(value: String) -> String: return "(no stat)" if value.is_empty() else value.capitalize()), stat)
	var removals := Array(UserModBuilder.enum_names(EffectDefinition.RemovalPolicy))
	inner.choice("", effect, "removal", removals, removals.map(func(value: String) -> String: return value.capitalize()), stat)
	var flags := inner.row("")
	inner.toggle("Type matchups", effect, "type_effectiveness", flags)
	inner.toggle("Can crit", effect, "can_critical", flags)
	inner.toggle("Shield blocks", effect, "blocked_by_shield", flags)
	if String(effect.get("stat", "")).is_empty(): effect.erase("stat")

# --- Types ----------------------------------------------------------------------

func _types_tab(content: Control) -> void:
	_list_tab(content, "types", "New type", func() -> void:
		var record := {"id": _unique_id("type", "new_type"), "name": "New Type", "color": "#88aacc", "description": ""}
		_manifest.types.append(record)
		_selection["types"] = _manifest.types.size() - 1
		_changed()
		_build_editor(), _type_form, [["Existing matchups", func() -> void:
			_selection["types"] = -1
			_selection["matchups"] = true
			_build_editor()]])
	if bool(_selection.get("matchups", false)) and int(_selection.get("types", -1)) < 0:
		var form := content.get_child(0).get_child(1).get_child(0) as ModWorkshopForm
		form.clear()
		_existing_matchups_form(form)

func _type_form(form: ModWorkshopForm, record: Dictionary) -> void:
	_selection.erase("matchups")
	var head := form.card()
	var head_row := head.row("")
	head_row.add_theme_constant_override("separation", 12)
	var big_badge := ModWorkshopForm.picture(null, Vector2(160, 40), head_row)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_text)
	var head_title := _label("", 20, ModWorkshopForm.GOLD, head_text)
	var head_note := _label("ID %s. The ID is fixed once saves use it." % record.id, 12, ModWorkshopForm.MUTED, head_text)
	head_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_note.custom_minimum_size.x = 120
	var refresh_head := func() -> void:
		head_title.text = String(record.get("name", "Type"))
		big_badge.texture = _type_badge(String(record.id))
	refresh_head.call()
	form.changed.connect(refresh_head)
	var identity := form.card("Identity")
	identity.text("Name", record, "name", 16)
	identity.color("Color", record, "color")
	identity.text("Description", record, "description", 300, true)
	identity.note("Badges are drawn from the name and color. To use your own art, import any PNG and frame it; it is resized to the game's badge size.")
	var art := identity.row("")
	_button("Import badge PNG...", func() -> void:
		_pick_file("Choose a type badge picture", ["*.png ; PNG image"], func(path: String) -> void:
			var badge_size := UserModAssets._size_of("menus_minionType_fire", Vector2i(80, 20))
			_crop_picture(path, "Frame your badge", float(badge_size.x) / badge_size.y, badge_size, func(image: Image) -> void:
				var imported := UserModRepository.import_image(_mod_id, image, "badge_" + String(record.id).get_file())
				if not imported.ok: return show_message(imported.message)
				record["badge"] = imported.path
				_texture_cache.clear()
				_changed()
				_build_editor())), art)
	if not String(record.get("badge", "")).is_empty():
		_button("Use drawn badge", func() -> void:
			record.erase("badge")
			_changed()
			_build_editor(), art)
	var types: Array = []
	for entry in _entries("minion_type"):
		if String(entry.id) != String(record.id): types.append(entry)
	var glance := form.card("Matchups at a glance")
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 4)
	glance.add_child(summary)
	var refresh_summary := func() -> void:
		for child in summary.get_children():
			summary.remove_child(child)
			child.queue_free()
		for line in [["Hits hard (x1.5) against", "strong", true], ["Hits weakly (x0.67) against", "weak", true], ["Takes extra damage from", "strong", false], ["Resists damage from", "weak", false]]:
			var holder := HBoxContainer.new()
			holder.add_theme_constant_override("separation", 4)
			summary.add_child(holder)
			var caption := _label(String(line[0]), 12, ModWorkshopForm.MUTED, holder)
			caption.custom_minimum_size.x = 150
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.add_theme_constant_override("h_separation", 3)
			flow.add_theme_constant_override("v_separation", 2)
			holder.add_child(flow)
			var count := 0
			for entry in types:
				var result := _matchup(String(record.id), String(entry.id)) if line[2] else _matchup(String(entry.id), String(record.id))
				if result != line[1]: continue
				count += 1
				var badge := ModWorkshopForm.picture(_type_badge(String(entry.id)), Vector2(56, 14), flow)
				badge.tooltip_text = String(entry.label).trim_prefix("* ")
				badge.mouse_filter = Control.MOUSE_FILTER_PASS
			if count == 0: _label("none", 12, ModWorkshopForm.MUTED, flow)
	refresh_summary.call()
	var matchups := form.card("Matchups")
	matchups.note("Click a box to change it: x1 (normal), x1.5 (strong) or x0.67 (weak). Healing works the other way round, as in the original game.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	matchups.add_child(grid)
	_label("", 12, ModWorkshopForm.GOLD, grid)
	_label("Other type", 12, ModWorkshopForm.GOLD, grid)
	_label("%s hits it" % String(record.get("name", "This")).left(10), 12, ModWorkshopForm.GOLD, grid)
	_label("It hits %s" % String(record.get("name", "this")).left(10), 12, ModWorkshopForm.GOLD, grid)
	for entry in types:
		ModWorkshopForm.picture(_type_badge(String(entry.id)), Vector2(56, 14), grid)
		_label(String(entry.label).trim_prefix("* "), 13, ModWorkshopForm.INK, grid)
		_matchup_choice(grid, String(record.id), String(entry.id), refresh_summary)
		_matchup_choice(grid, String(entry.id), String(record.id), refresh_summary)

## A box showing one matchup's multiplier; pressing it cycles x1 -> x1.5 -> x0.67.
func _matchup_choice(parent: Control, attacker: String, defender: String, on_change: Callable = Callable()) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(66, 22)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var paint := func() -> void:
		var result := _matchup(attacker, defender)
		button.text = String(MATCHUP_SHORT[result])
		var color: Color = MATCHUP_COLORS[result]
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, ModWorkshopForm.flat(color.lightened(0.12) if state == "hover" else color, Color(1, 1, 1, 0.3), 4))
		button.add_theme_color_override("font_color", Color.WHITE)
	paint.call()
	button.pressed.connect(func() -> void:
		var order := ["normal", "strong", "weak"]
		_set_matchup(attacker, defender, order[(order.find(_matchup(attacker, defender)) + 1) % order.size()])
		_changed()
		paint.call()
		if on_change.is_valid(): on_change.call())
	parent.add_child(button)
	return button

func _matchup(attacker: String, defender: String) -> String:
	for entry in _manifest.type_chart:
		if String(entry.get("attacker", "")) == attacker and String(entry.get("defender", "")) == defender: return String(entry.get("result", "normal"))
	var chart := catalog.get_type_chart()
	var value := chart.multiplier(StringName(attacker), StringName(defender)) if chart != null else 1.0
	return "strong" if value > 1.01 else "weak" if value < 0.99 else "normal"

func _set_matchup(attacker: String, defender: String, result: String) -> void:
	for index in range(_manifest.type_chart.size() - 1, -1, -1):
		var entry: Dictionary = _manifest.type_chart[index]
		if String(entry.get("attacker", "")) == attacker and String(entry.get("defender", "")) == defender: _manifest.type_chart.remove_at(index)
	var chart := catalog.get_type_chart()
	var base := "normal"
	if chart != null and catalog.has_definition(StringName(attacker)) and catalog.has_definition(StringName(defender)):
		var value := chart.multiplier(StringName(attacker), StringName(defender))
		base = "strong" if value > 1.01 else "weak" if value < 0.99 else "normal"
	if result != base: _manifest.type_chart.append({"attacker": attacker, "defender": defender, "result": result})

func _existing_matchups_form(form: ModWorkshopForm) -> void:
	form.heading("Change existing matchups")
	form.note("Pick any two types, including recovered ones, and set how the first fares attacking the second.")
	var proxy := {"attacker": "base:type/fire", "defender": "base:type/plant", "result": "normal"}
	var line := form.row("Attacker / defender")
	form.reference("", proxy, "attacker", "minion_type", false, line)
	form.reference("", proxy, "defender", "minion_type", false, line)
	form.choice("Result", proxy, "result", MATCHUP_VALUES, MATCHUP_LABELS)
	form.button("Set this matchup", func() -> void:
		_set_matchup(String(proxy.attacker), String(proxy.defender), String(proxy.result))
		_changed()
		_build_editor())
	form.separator()
	for entry in _manifest.type_chart:
		var row := form.row("")
		for side in [String(entry.attacker), "vs", String(entry.defender)]:
			if side == "vs":
				_label("hits", 12, ModWorkshopForm.MUTED, row)
				continue
			var badge := ModWorkshopForm.picture(_type_badge(side), Vector2(64, 20), row)
			badge.tooltip_text = _describe("type", side)
			badge.mouse_filter = Control.MOUSE_FILTER_PASS
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		_matchup_choice(row, String(entry.attacker), String(entry.defender))

# --- Changes to existing content -------------------------------------------------

func _changes_tab(content: Control) -> void:
	var minion_count: int = _manifest.minion_patches.size()
	var combined: Array = []
	for record in _manifest.minion_patches: combined.append(record)
	for record in _manifest.move_patches: combined.append(record)
	_manifest["__changes"] = combined
	_list_tab(content, "__changes", "Change a minion...", func() -> void:
		_open_picker("minion", func(id: String) -> void:
			var definition := catalog.get_definition(StringName(id)) as MinionDefinition
			if definition == null: return show_message("Change your own minions in the Minions tab.")
			var record := UserModBuilder.minion_record(definition)
			record["target"] = id
			_manifest.minion_patches.append(record)
			_selection["__changes"] = _manifest.minion_patches.size() - 1
			_changed()
			_build_editor()), func(form: ModWorkshopForm, record: Dictionary) -> void:
			if String(record.get("target", "")).contains(":move/"): _move_patch_form(form, record)
			else: _minion_form(form, record, true), [["Change a move...", func() -> void:
			_open_picker("move", func(id: String) -> void:
				var definition := catalog.get_definition(StringName(id)) as MoveDefinition
				if definition == null: return show_message("Change your own moves in the Moves tab.")
				var record := UserModBuilder.move_record(definition)
				record["target"] = id
				_manifest.move_patches.append(record)
				_selection["__changes"] = minion_count + _manifest.move_patches.size() - 1
				_changed()
				_build_editor())]], _patch_list_remove)
	_manifest.erase("__changes")

func _move_patch_form(form: ModWorkshopForm, record: Dictionary) -> void:
	var definition := catalog.get_definition(StringName(String(record.target))) as MoveDefinition
	if definition != null: record.merge(UserModBuilder.move_record(definition), false)
	_move_card(form, record, record, "Changing %s. Each tier of a move is changed separately; owned minions and trainers use the new version." % _describe("move", String(record.target)), String(record.target))
	var identity := form.card("Identity")
	identity.text("Name", record, "name", 32)
	identity.text("Description", record, "description", 400, true)
	identity.reference("Type", record, "type", "type")
	_tier_form(form, record)

## The combined Changes list removes from the right source list.
func _patch_list_remove(index: int) -> void:
	if index < _manifest.minion_patches.size(): _manifest.minion_patches.remove_at(index)
	else: _manifest.move_patches.remove_at(index - _manifest.minion_patches.size())

# --- Trainers ----------------------------------------------------------------------

func _new_trainer() -> void:
	_open_picker("encounter", func(id: String) -> void:
		var encounter := catalog.get_definition(StringName(id)) as EncounterDefinition
		if encounter == null: return
		for existing in _manifest.trainers:
			if String(existing.target) == id: return show_message("This mod already edits that trainer.")
		var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
		var team: Array = []
		for entry in encounter.team_entries:
			team.append({"minion": String(entry.get("definition_id", "")), "level": maxi(1, int(entry.get("level", 1)) + int(entry.get("source_level_offset", encounter.source_level_offset))), "moves": Array(entry.get("move_ids", [])).map(func(value: Variant) -> String: return String(value))})
		var record := {"target": id, "trainer_name": String(dialogue.get("trainer_name", "")), "first_visit_text": String(dialogue.get("first_visit_text", "")), "after_win_text": String(dialogue.get("after_win_text", "")), "repeat_text": String(dialogue.get("repeat_text", "")), "money": int(encounter.rewards.get("first_clear", {}).get("floor_money_basis", 0)), "team": team}
		_manifest.trainers.append(record)
		_selection["trainers"] = _manifest.trainers.size() - 1
		_changed()
		_build_editor())

func _trainer_form(form: ModWorkshopForm, record: Dictionary) -> void:
	if not record.get("team") is Array: record["team"] = []
	var team: Array = record.team
	var encounter := catalog.get_definition(StringName(String(record.target))) as EncounterDefinition
	var head := form.card()
	var head_title := _label(_describe("encounter", String(record.target)), 20, ModWorkshopForm.GOLD, head)
	head_title.clip_text = true
	if encounter != null: _label("Tower floor %d trainer" % (encounter.source_floor_index + 1), 12, ModWorkshopForm.MUTED, head)
	var lineup := HBoxContainer.new()
	lineup.add_theme_constant_override("separation", 10)
	head.add_child(lineup)
	var refresh_lineup := func() -> void:
		for child in lineup.get_children():
			lineup.remove_child(child)
			child.queue_free()
		for member in team:
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 0)
			lineup.add_child(slot)
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(92, 100, 114), 6))
			slot.add_child(frame)
			ModWorkshopForm.picture(_minion_texture(String(member.get("minion", ""))), Vector2(60, 60), frame)
			var level := _label("Lv %d" % int(member.get("level", 1)), 12, ModWorkshopForm.GOLD, slot)
			level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refresh_lineup.call()
	form.changed.connect(refresh_lineup)
	var dialogue := form.card("What they say")
	dialogue.text("Trainer name", record, "trainer_name", 24)
	dialogue.text("Challenge line", record, "first_visit_text", 400, true)
	dialogue.text("After you win", record, "after_win_text", 400, true)
	dialogue.text("Rematch line", record, "repeat_text", 400, true)
	dialogue.number("Money basis", record, "money", 0, 9999, 0)
	var team_card := form.card("Team")
	team_card.note("Tower trainers fill out their moves from each minion's talents for its level; listed moves are their favorites.")
	for index in team.size():
		var member: Dictionary = team[index]
		var line := team_card.row("Slot %d" % (index + 1))
		var portrait := ModWorkshopForm.picture(_minion_texture(String(member.get("minion", ""))), Vector2(30, 30), line)
		team_card.reference("", member, "minion", "minion", false, line, func() -> void: portrait.texture = _minion_texture(String(member.get("minion", ""))))
		_label("Lv", 12, ModWorkshopForm.MUTED, line)
		team_card.number("", member, "level", 1, 99, 5, 1, line)
		if team.size() > 1:
			_button("x", func() -> void:
				team.remove_at(index)
				_changed()
				_build_editor(), line)
		team_card.reference_list("  Favorite moves", member, "moves", "move", 8)
	if team.size() < 5:
		team_card.button("+ Add a minion", func() -> void:
			team.append({"minion": String(team[-1].minion) if not team.is_empty() else "base:minion/tiger_1", "level": int(team[-1].level) if not team.is_empty() else 5, "moves": []})
			_changed()
			_build_editor())

# --- Hatchery ----------------------------------------------------------------------

func _new_hatchery_rule() -> void:
	var used: Dictionary = {}
	for rule in _manifest.hatchery: used[int(rule.get("floor", 0))] = true
	var floor_index := 0
	while used.has(floor_index) and floor_index < 30: floor_index += 1
	var first: String = String(_manifest.minions[0].id) if not _manifest.minions.is_empty() else "base:minion/tiger_1"
	_manifest.hatchery.append({"floor": floor_index, "mode": "add", "entries": [{"minion": first, "weight": 15}]})
	_selection["hatchery"] = _manifest.hatchery.size() - 1
	_changed()
	_build_editor()

func _hatchery_form(form: ModWorkshopForm, record: Dictionary) -> void:
	if not record.get("entries") is Array: record["entries"] = []
	var entries: Array = record.entries
	var settings := form.card("Floor %d hatchery" % (int(record.get("floor", 0)) + 1))
	var proxy := {"floor": int(record.get("floor", 0)) + 1}
	var floor_row := settings.row("Floor")
	settings.number("", proxy, "floor", 1, 31, 1, 1, floor_row).value_changed.connect(func(value: float) -> void:
		record["floor"] = int(value) - 1)
	_button("Show", _build_editor, floor_row)
	settings.choice("Rule", record, "mode", ["add", "replace"], ["Add to the floor's eggs", "Replace the floor's eggs"], null, _build_editor)
	var odds := form.card("Chances for each egg")
	var bar := ModWorkshopWeightBar.new()
	odds.add_child(bar)
	var legend := _label("", 12, ModWorkshopForm.MUTED, odds)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size.x = 120
	var note_label := odds.note("")
	var base_table := _floor_egg_table(int(record.get("floor", 0)))
	var refresh_bar := func() -> void:
		var total := 0
		for entry in entries: total += int(entry.get("weight", 0))
		var segments: Array = []
		var adding: bool = record.get("mode", "add") == "add"
		if adding:
			for index in base_table.size():
				var scaled: float = float(base_table[index].weight) * maxf(0.0, 100.0 - total) / 100.0
				segments.append({"label": _describe("minion", String(base_table[index].id)), "weight": scaled, "color": Color.from_hsv(0.58, 0.28 - 0.04 * (index % 3), 0.78 - 0.07 * (index % 4)), "texture": _minion_texture(String(base_table[index].id))})
		for index in entries.size():
			segments.append({"label": _describe("minion", String(entries[index].get("minion", ""))), "weight": float(entries[index].get("weight", 0)), "color": Color.from_hsv(0.11 + 0.025 * (index % 4), 0.5, 0.97 - 0.06 * (index % 3)), "texture": _minion_texture(String(entries[index].get("minion", "")))})
		bar.segments = segments
		bar.queue_redraw()
		var recovered := ", ".join(PackedStringArray(base_table.map(func(entry: Dictionary) -> String: return "%s %d%%" % [_describe("minion", String(entry.id)), int(entry.weight)])))
		legend.text = ("Gold: your eggs. Blue: the floor's own eggs (%s)." % (recovered if not recovered.is_empty() else "none found")) if adding else "Gold: your eggs replace the floor's own eggs completely."
		var rule := "Your eggs take %d%%; the floor's own eggs share the rest (at most 90%%)." % total if adding else "Chances must add up to 100%% (now %d%%)." % total
		note_label.text = rule
		note_label.add_theme_color_override("font_color", ModWorkshopForm.MUTED if (adding and total <= 90) or total == 100 else Color8(240, 130, 120))
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var line := odds.row("Egg %d" % (index + 1))
		var portrait := ModWorkshopForm.picture(_minion_texture(String(entry.get("minion", ""))), Vector2(30, 30), line)
		odds.reference("", entry, "minion", "minion", false, line, func() -> void:
			portrait.texture = _minion_texture(String(entry.get("minion", "")))
			refresh_bar.call())
		_label("%", 12, ModWorkshopForm.MUTED, line)
		odds.number("", entry, "weight", 1, 100, 10, 1, line).value_changed.connect(func(_value: float) -> void: refresh_bar.call())
		if entries.size() > 1:
			_button("x", func() -> void:
				entries.remove_at(index)
				_changed()
				_build_editor(), line)
	if entries.size() < 9:
		odds.button("+ Add an egg", func() -> void:
			entries.append({"minion": String(entries[-1].minion) if not entries.is_empty() else "base:minion/tiger_1", "weight": 10})
			_changed()
			_build_editor())
	refresh_bar.call()

## The floor's recovered egg odds: [{"id": minion id, "weight": percent}].
func _floor_egg_table(floor_index: int) -> Array:
	var table: Array = []
	for definition in catalog._by_id.values():
		if not definition is RoomDefinition or not String(definition.id).ends_with("_eggery"): continue
		if int(definition.minimap_metadata.get("floor_index", -1)) != floor_index: continue
		for interaction in definition.interactions:
			if String(interaction.get("kind", "")) != "egg_pick": continue
			var candidates: Array = interaction.get("candidates", [])
			var weights: Array = interaction.get("weights", [])
			for index in candidates.size(): table.append({"id": String(candidates[index]), "weight": float(weights[index]) if index < weights.size() else 0.0})
			return table
	return table

# --- Rooms ---------------------------------------------------------------------------

## A room edit that still matches the recovered room: its doors and the
## fields of its editable interactions, ready to be changed.
func _room_draft(room: RoomDefinition) -> Dictionary:
	var record := {"target": String(room.id), "exits": [], "interactions": [], "spawns": []}
	for exit_data in room.exits:
		record.exits.append({"transition_id": int(exit_data.get("transition_id", -1)), "target_room_id": String(exit_data.get("target_room_id", "")), "target_spawn_id": String(exit_data.get("target_spawn_id", ""))})
	for interaction in room.interactions:
		var kind := String(interaction.get("kind", ""))
		if kind == "trainer":
			record.interactions.append({"id": String(interaction.id), "encounter_id": String(interaction.get("encounter_id", ""))})
		elif UserModBuilder.ROOM_INTERACTION_FIELDS.has(kind):
			var values: Dictionary = {}
			for key in UserModBuilder.ROOM_INTERACTION_FIELDS[kind]:
				if interaction.has(key): values[key] = interaction[key].duplicate(true) if interaction[key] is Array else interaction[key]
			record.interactions.append({"id": String(interaction.id), "set": values})
	return record

## Picks a room and adds an edit for it (the Rooms tab does the same from its map).
func _new_room_edit() -> void:
	_open_picker("room", func(id: String) -> void:
		var room := catalog.get_definition(StringName(id)) as RoomDefinition
		if room == null: return
		for existing in _manifest.rooms:
			if String(existing.target) == id: return show_message("This mod already edits that room.")
		_manifest.rooms.append(_room_draft(room))
		_selection["rooms"] = _manifest.rooms.size() - 1
		_changed()
		_build_editor())

func _rooms_tab_build(content: Control) -> void:
	if _rooms_tab == null: _rooms_tab = ModWorkshopRooms.new(self)
	_rooms_tab.build(content)

# --- Check and test --------------------------------------------------------------------

func _test_tab(page: ModWorkshopForm) -> void:
	var form := page.card("Check")
	var results := VBoxContainer.new()
	form.button("Check this mod for problems", func() -> void:
		if _dirty and not _save_now(): return
		for child in results.get_children(): child.queue_free()
		var checked := UserModService.check(catalog, _manifest)
		if checked.errors.is_empty() and checked.warnings.is_empty():
			_label("No problems found.", 13, Color8(140, 220, 140), results)
		for error in checked.errors: _wrapped("Problem: %s" % error, Color8(240, 130, 120), results)
		for warning in checked.warnings: _wrapped("Note: %s" % warning, Color8(240, 200, 120), results))
	form.add_child(results)
	page.card("Test battle").note("Fight with this mod on. Nothing is saved; your saves are untouched.")
	var spec: Dictionary = _test_specs.get(_mod_id, {})
	if spec.is_empty():
		var first: String = String(_manifest.minions[0].id) if not _manifest.minions.is_empty() else "base:minion/tiger_1"
		spec = {"player": [{"minion": first, "level": 10, "moves": []}], "encounter_id": String(_manifest.trainers[0].target) if not _manifest.trainers.is_empty() else "base:encounter/grass_floor1_room1_normal", "opponent": "trainer", "enemy": [{"minion": "base:minion/grasssnake_1", "level": 10, "moves": []}]}
		_test_specs[_mod_id] = spec
	_versus_card(page, spec)
	_test_team(page, "Your team", spec.player)
	var opponent := page.card("Opponent")
	opponent.choice("Opponent", spec, "opponent", ["trainer", "custom"], ["A tower trainer", "A team you choose"], null, _build_editor)
	if spec.opponent == "trainer": opponent.reference("Trainer", spec, "encounter_id", "encounter")
	else: _test_team(page, "Their team", spec.enemy)
	var go := page.card()
	go.note("Moves left empty use the minion's starting and specialization moves.")
	go.button("Start test battle", func() -> void:
		if _dirty and not _save_now(): return
		var request := {"player": spec.player.duplicate(true)}
		if spec.opponent == "trainer": request["encounter_id"] = spec.encounter_id
		else: request["enemy"] = spec.enemy.duplicate(true)
		test_battle_requested.emit(_mod_id, request))

## Both sides at a glance: portraits, levels and types, kept current as the
## team, trainer or opponent choice changes below.
func _versus_card(page: ModWorkshopForm, spec: Dictionary) -> void:
	var card := page.card("Matchup")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var refresh := func() -> void:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		var enemy: Array = spec.enemy if spec.opponent != "trainer" else _encounter_team(String(spec.get("encounter_id", "")))
		_versus_side(row, spec.player, "You")
		var vs := _label("VS", 22, ModWorkshopForm.GOLD, row)
		vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_versus_side(row, enemy, _describe("encounter", String(spec.get("encounter_id", ""))) if spec.opponent == "trainer" else "Them")
	refresh.call()
	page.changed.connect(refresh)

func _versus_side(parent: Control, team: Array, caption: String) -> void:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(side)
	var title := _label(caption, 12, ModWorkshopForm.MUTED, side)
	title.clip_text = true
	var faces := HFlowContainer.new()
	faces.add_theme_constant_override("h_separation", 4)
	side.add_child(faces)
	for member in team:
		var id := String(member.get("minion", ""))
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.tooltip_text = _describe("minion", id)
		faces.add_child(cell)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(19, 21, 23), Color8(92, 100, 114), 4))
		cell.add_child(frame)
		ModWorkshopForm.picture(_minion_texture(id), Vector2(40, 40), frame)
		var level := _label("Lv %d" % int(member.get("level", 1)), 11, ModWorkshopForm.INK, cell)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for type_id in _minion_types(id).slice(0, 1): ModWorkshopForm.picture(_type_badge(type_id), Vector2(44, 11), cell)
	if team.is_empty(): _label("nobody", 12, ModWorkshopForm.MUTED, side)

## A trainer's team as this mod plays it: the mod's own team override first.
func _encounter_team(encounter_id: String) -> Array:
	for trainer in _manifest.get("trainers", []):
		if String(trainer.get("target", "")) == encounter_id and trainer.get("team") is Array: return trainer.team
	var encounter := catalog.get_definition(StringName(encounter_id)) as EncounterDefinition
	if encounter == null: return []
	return encounter.team_entries.map(func(entry: Dictionary) -> Dictionary: return {"minion": String(entry.get("definition_id", "")), "level": int(entry.get("level", 1))})

func _minion_types(id: String) -> Array:
	for own in _manifest.get("minions", []):
		if String(own.get("id", "")) == id: return own.get("types", [])
	var definition := catalog.get_definition(StringName(id)) as MinionDefinition
	return [] if definition == null else Array(definition.type_ids).map(func(value: StringName) -> String: return String(value))

func _test_team(page: ModWorkshopForm, caption: String, team: Array) -> void:
	var form := page.card(caption)
	for index in team.size():
		var member: Dictionary = team[index]
		var line := form.row("Slot %d" % (index + 1))
		var portrait := ModWorkshopForm.picture(_minion_texture(String(member.get("minion", ""))), Vector2(30, 30), line)
		form.reference("", member, "minion", "minion", false, line, func() -> void: portrait.texture = _minion_texture(String(member.get("minion", ""))))
		_label("Lv", 12, ModWorkshopForm.MUTED, line)
		form.number("", member, "level", 1, 99, 10, 1, line)
		if team.size() > 1:
			_button("x", func() -> void:
				team.remove_at(index)
				_build_editor(), line)
		form.reference_list("  Moves", member, "moves", "move", 8)
	if team.size() < 5:
		form.button("+ Add a minion", func() -> void:
			team.append(team[-1].duplicate(true))
			_build_editor())

func _wrapped(text: String, color: Color, parent: Control) -> void:
	var label := _label(text, 12, color, parent)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 600
