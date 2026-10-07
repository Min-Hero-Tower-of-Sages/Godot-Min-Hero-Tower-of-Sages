extends Control

## Host: the usernames this world (or versus race) keeps a team for. Forgetting
## one deletes that kept team; the next join under that name is a first visit
## again. Players who are connected right now cannot be forgotten.

signal closed
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

const PANEL_SIZE := Vector2(440.0, 420.0)
const ROW_HEIGHT := 40.0
const ROWS_VISIBLE := 7

var _list: VBoxContainer
var _status: Label

func configure() -> void:
	var panel := MultiplayerUi.modal(self, PANEL_SIZE)
	MultiplayerUi.title(panel, "Saved players", Vector2(20.0, 14.0), PANEL_SIZE.x - 40.0)
	var what := "race runs" if net.is_versus() else "teams"
	MultiplayerUi.label(panel, "Your world keeps the %s of everyone who joined. Forget a name to let its next visit start over." % what, Vector2(20.0, 50.0), Vector2(PANEL_SIZE.x - 40.0, 40.0), 13, MultiplayerUi.MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20.0, 96.0)
	scroll.size = Vector2(PANEL_SIZE.x - 40.0, ROW_HEIGHT * ROWS_VISIBLE)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(PANEL_SIZE.x - 52.0, 0.0)
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = MultiplayerUi.label(panel, "", Vector2(20.0, PANEL_SIZE.y - 84.0), Vector2(PANEL_SIZE.x - 40.0, 22.0), 13, MultiplayerUi.ERROR)
	MultiplayerUi.button(panel, "Back", Vector2(20.0, PANEL_SIZE.y - 54.0), Vector2(120.0, 38.0), func() -> void: closed.emit())
	_refresh()

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var entries: Array = net.saved_profiles()
	if entries.is_empty():
		var empty := MultiplayerUi.label(_list, "Nobody has joined this world yet.", Vector2.ZERO, Vector2(PANEL_SIZE.x - 52.0, 30.0), 15)
		empty.custom_minimum_size = Vector2(PANEL_SIZE.x - 52.0, 30.0)
		return
	for entry in entries:
		var row := Control.new()
		row.custom_minimum_size = Vector2(PANEL_SIZE.x - 52.0, ROW_HEIGHT - 6.0)
		_list.add_child(row)
		var caption := String(entry.name)
		if bool(entry.online):
			caption += "  (playing now)"
		elif not bool(entry.has_team):
			caption += "  (no team yet)"
		var name_label := MultiplayerUi.label(row, caption, Vector2(0.0, 6.0), Vector2(250.0, 24.0), 16)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		var forget := MultiplayerUi.button(row, "Forget", Vector2(row.custom_minimum_size.x - 110.0, 0.0), Vector2(110.0, 32.0), _forget.bind(String(entry.name)), 15)
		forget.name = "Forget_%s" % String(entry.key)
		forget.disabled = bool(entry.online)

func _forget(username: String) -> void:
	var result: Dictionary = net.forget_profile(username)
	_status.text = "" if result.get("ok", false) else String(result.get("message", "Could not forget %s." % username))
	if result.get("ok", false):
		_status.add_theme_color_override("font_color", MultiplayerUi.MUTED)
		_status.text = "%s's team is forgotten." % username
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
