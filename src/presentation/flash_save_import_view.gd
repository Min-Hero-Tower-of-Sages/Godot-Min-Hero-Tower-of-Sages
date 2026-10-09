class_name FlashSaveImportView
extends Control

signal closed
signal imported(slot: int)
const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
var runtime: Node
var destination_slot: int = 0
var _preview: Dictionary = {}
var _text: Label
var _slots: OptionButton
var _confirm: Button
var _file_dialog: FileDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	add_child(shade)
	var panel := Panel.new()
	panel.name = "ImportStonePanel"
	panel.position = Vector2(50, 40)
	panel.size = Vector2(600, 445)
	var background := StyleBoxTexture.new()
	background.texture = SourceMenuArt.texture("menus_backgroundLarge")
	background.set_texture_margin_all(20)
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var title := Label.new()
	title.text = "IMPORT FLASH SAVE"
	title.position = Vector2(25, 18)
	title.size = Vector2(550, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color8(255, 233, 111))
	title.add_theme_color_override("font_shadow_color", Color8(35, 37, 45))
	title.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(title)
	var inset := Panel.new()
	inset.position = Vector2(21, 68)
	inset.size = Vector2(558, 232)
	var inset_skin := StyleBoxFlat.new()
	inset_skin.bg_color = Color8(43, 48, 55)
	inset_skin.border_color = Color8(23, 26, 31)
	inset_skin.set_border_width_all(2)
	inset_skin.set_corner_radius_all(4)
	inset.add_theme_stylebox_override("panel", inset_skin)
	panel.add_child(inset)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(31, 78)
	scroll.size = Vector2(538, 212)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_text = Label.new()
	_text.text = "Choose TCrpgSaveSlot0.sol, 1.sol or 2.sol. If TCrpgInitialData.sol is beside it, your character name and gender are read too.\n\nImport only uses empty Godot slots. The Flash files are never changed."
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("font", FONT)
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color8(244, 244, 239))
	scroll.add_child(_text)
	var choose := _stone_button(panel, "Choose Flash .sol file…", Vector2(25, 314), Vector2(345, 36))
	choose.pressed.connect(_choose_file)
	_slots = OptionButton.new()
	_slots.position = Vector2(385, 314)
	_slots.size = Vector2(190, 36)
	_skin_button(_slots)
	_slots.get_popup().add_theme_font_override("font", FONT)
	_slots.get_popup().add_theme_font_size_override("font_size", 18)
	var first_empty := -1
	for slot in range(1, 4):
		var empty: bool = runtime.session.save_repository.load_slot(slot).get("code", "") == "not_found"
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists("user://save_slot_%d.json%s" % [slot, suffix]): empty = false
		_slots.add_item("Slot %d — %s" % [slot, "empty" if empty else "unavailable"], slot)
		_slots.set_item_disabled(slot - 1, not empty)
		if empty and first_empty < 0: first_empty = slot - 1
	if first_empty >= 0: _slots.select(first_empty)
	if destination_slot >= 1 and destination_slot <= 3 and not _slots.is_item_disabled(destination_slot - 1):
		_slots.select(destination_slot - 1)
	panel.add_child(_slots)
	_confirm = _stone_button(panel, "IMPORT SAVE", Vector2(25, 371), Vector2(345, 42))
	_confirm.disabled = true
	_confirm.pressed.connect(_commit)
	var cancel := _stone_button(panel, "RETURN", Vector2(385, 371), Vector2(190, 42))
	cancel.pressed.connect(func() -> void: closed.emit(); queue_free())

func _stone_button(parent: Control, caption: String, at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = at
	button.size = dimensions
	_skin_button(button)
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	return button

func _skin_button(button: Button) -> void:
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 19)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var skin := StyleBoxTexture.new()
		var art := AtlasTexture.new()
		art.atlas = SourceMenuArt.texture("mainMenu_saveSlotFilled")
		# The save-card PNG includes exterior transparent padding. Crop that
		# before nine-slicing so compact controls keep a full-height stone rim.
		art.region = Rect2(9, 6, 230, 62)
		skin.texture = art
		skin.set_texture_margin_all(8)
		skin.content_margin_top = 2
		skin.content_margin_bottom = 2
		if state_name == "hover": skin.modulate_color = Color(1.08, 1.08, 1.12)
		elif state_name == "pressed": skin.modulate_color = Color(0.85, 0.85, 0.9)
		elif state_name == "disabled": skin.modulate_color = Color(0.7, 0.7, 0.75)
		button.add_theme_stylebox_override(state_name, skin)
	for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state_name, Color8(69, 71, 116))
	button.add_theme_color_override("font_disabled_color", Color8(96, 97, 116))

func _choose_file() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.sol ; Flash SharedObject saves"])
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(_preview_file)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.8)

func _preview_file(path: String) -> void:
	_preview = FlashSaveImportService.new().preview_file(path, runtime.catalog)
	if not _preview.ok:
		_text.text = String(_preview.get("message", "Could not read Flash save."))
		_confirm.disabled = true
		return
	_text.text = String(_preview.summary) + "\n\n" + "\n\n".join(_preview.warnings)
	_confirm.disabled = _slots.is_item_disabled(_slots.selected)

func _commit() -> void:
	if not _preview.get("ok", false): return
	var slot := _slots.get_selected_id()
	var result: Dictionary = runtime.import_flash_candidate(slot, _preview.state)
	if not result.ok:
		_text.text = String(result.get("message", "Import failed."))
		return
	imported.emit(slot)
	queue_free()
