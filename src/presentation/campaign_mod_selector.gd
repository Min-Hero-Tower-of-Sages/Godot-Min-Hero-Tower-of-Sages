class_name CampaignModSelector
extends Control

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
var flags: Dictionary = {}
var _holder: Control
var _buttons: Array[TextureButton] = []
var _scroll := 0
var _up: TextureButton
var _down: TextureButton
var _scroll_tween: Tween

func _ready() -> void:
	name = "ModSelector"
	size = Vector2(215, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SourceMenuArt.image(self, "mainMenu_modMenuBackground", Vector2.ZERO)
	var clip := Control.new()
	clip.position = Vector2(5, 55)
	clip.size = Vector2(200, 190)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_holder = Control.new()
	_holder.position = Vector2(5, 0)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_holder)
	for index in CampaignModService.OPTIONS.size():
		var option: Dictionary = CampaignModService.OPTIONS[index]
		var caption := Label.new()
		caption.text = option.name
		caption.position = Vector2(5, index * 38)
		caption.size = Vector2(115, 35)
		caption.add_theme_font_override("font", FONT)
		caption.add_theme_font_size_override("font_size", 16)
		caption.add_theme_color_override("font_color", Color8(250, 250, 250))
		caption.tooltip_text = option.description
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		_holder.add_child(caption)
		var toggle := SourceMenuArt.button(_holder, "menus_settings_offButton", Vector2(128, index * 38), _toggle.bind(index))
		if toggle != null:
			toggle.tooltip_text = option.description
			_buttons.append(toggle)
	_up = SourceMenuArt.button(self, "minionPedia_upArrow", Vector2(175, 10), _change_scroll.bind(-1))
	_down = SourceMenuArt.button(self, "minionPedia_upArrow", Vector2(175, 280), _change_scroll.bind(1))
	if _down != null: _down.scale.y = -1
	_refresh()

func _toggle(index: int) -> void:
	var option: Dictionary = CampaignModService.OPTIONS[index]
	var value := not bool(flags.get(option.flags[0], false))
	for flag in option.flags: flags[flag] = value
	_refresh()

func _change_scroll(direction: int) -> void:
	_scroll = clampi(_scroll + direction, 0, CampaignModService.OPTIONS.size() - 5)
	if _scroll_tween != null: _scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_holder, "position:y", -float(_scroll * 38), 0.25)
	_refresh()

func _refresh() -> void:
	for index in _buttons.size():
		var on := bool(flags.get(CampaignModService.OPTIONS[index].flags[0], false))
		var art := SourceMenuArt.texture("menus_settings_onButton" if on else "menus_settings_offButton")
		_buttons[index].texture_normal = art
		_buttons[index].texture_hover = art
		_buttons[index].texture_pressed = art
	if _up != null: _up.visible = _scroll > 0
	if _down != null: _down.visible = _scroll < CampaignModService.OPTIONS.size() - 5
