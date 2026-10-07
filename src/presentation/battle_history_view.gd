extends Control

## "Battle replays": the battles this PC recorded (newest first) and any
## pasted from a friend. Each row can be watched, kept for good, copied as a
## share code, or deleted. A pasted code is stored (kept) and played.

signal closed
signal watch_requested(replay: Dictionary)

const PANEL_SIZE := Vector2(580.0, 470.0)
const ROW_HEIGHT := 50.0
const LIST_HEIGHT := 262.0
const OUTCOME_COLORS := {
	"Victory": Color8(150, 226, 120),
	"Defeat": Color8(255, 120, 110),
	"Forfeited": Color8(255, 170, 110),
	"Unfinished": Color8(168, 176, 190),
}
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var history := BattleHistoryRepository.new()
var _list: VBoxContainer
var _code: LineEdit
var _status: Label

func configure(repository: BattleHistoryRepository = null) -> void:
	if repository != null:
		history = repository
	var panel := MultiplayerUi.modal(self, PANEL_SIZE)
	var inner := PANEL_SIZE.x - 40.0
	MultiplayerUi.title(panel, "Battle replays", Vector2(20.0, 14.0), inner)
	MultiplayerUi.label(panel, "Your last %d battles are recorded here. Keep one to save it for good, or copy its code to share it." % BattleHistoryRepository.MAX_RECENT, Vector2(20.0, 48.0), Vector2(inner, 36.0), 13, MultiplayerUi.MUTED)
	var well := Panel.new()
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Color8(34, 37, 43)
	well_style.border_color = MultiplayerUi.PANEL_RIM
	well_style.set_border_width_all(1)
	well_style.set_corner_radius_all(4)
	well.add_theme_stylebox_override("panel", well_style)
	well.position = Vector2(20.0, 90.0)
	well.size = Vector2(inner, LIST_HEIGHT)
	panel.add_child(well)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 6.0)
	scroll.size = Vector2(inner - 12.0, LIST_HEIGHT - 12.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	well.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "ReplayList"
	_list.custom_minimum_size = Vector2(inner - 26.0, 0.0)
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_code = MultiplayerUi.field(panel, "Got a code from a friend? Paste it here:", "", Vector2(20.0, 360.0), inner - 150.0)
	_code.name = "CodeField"
	_code.placeholder_text = BattleReplay.CODE_PREFIX + "…"
	_code.text_submitted.connect(func(_text: String) -> void: _watch_code())
	MultiplayerUi.button(panel, "Watch code", Vector2(PANEL_SIZE.x - 160.0, 380.0), Vector2(140.0, 30.0), _watch_code, 15).name = "WatchCodeButton"
	_status = MultiplayerUi.label(panel, "", Vector2(160.0, PANEL_SIZE.y - 48.0), Vector2(inner - 140.0, 34.0), 13, MultiplayerUi.ERROR)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MultiplayerUi.button(panel, "Back", Vector2(20.0, PANEL_SIZE.y - 50.0), Vector2(120.0, 36.0), func() -> void: closed.emit())
	_refresh()

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var entries := history.list()
	var width := _list.custom_minimum_size.x
	if entries.is_empty():
		var empty := MultiplayerUi.label(_list, "No battles yet. Fight a trainer, a friend in the arena, or watch one, and it shows up here.", Vector2.ZERO, Vector2(width, 60.0), 15, MultiplayerUi.MUTED)
		empty.custom_minimum_size = Vector2(width, 60.0)
		return
	for entry in entries:
		_add_row(entry, width)

func _add_row(entry: Dictionary, width: float) -> void:
	var id := String(entry.id)
	var row := Panel.new()
	row.name = "Replay_%s" % id
	row.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = MultiplayerUi.PANEL_FILL.lightened(0.04)
	style.border_color = MultiplayerUi.GOLD.darkened(0.25) if bool(entry.get("kept", false)) else MultiplayerUi.PANEL_RIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	row.add_theme_stylebox_override("panel", style)
	_list.add_child(row)
	var text_width := width - 240.0
	var heading := MultiplayerUi.label(row, String(entry.get("title", "Battle")), Vector2(10.0, 4.0), Vector2(text_width, 22.0), 16, MultiplayerUi.CREAM)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var outcome := String(entry.get("outcome", ""))
	var outcome_label := MultiplayerUi.label(row, outcome, Vector2(10.0, 26.0), Vector2(84.0, 18.0), 13, OUTCOME_COLORS.get(outcome, MultiplayerUi.GOLD))
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	outcome_label.custom_minimum_size = Vector2.ZERO
	outcome_label.size = Vector2.ZERO
	var detail := "%s · %d turns · %s" % [String(entry.get("kind", "")), int(entry.get("turns", 0)), _date(int(entry.get("recorded_at", 0)))]
	if bool(entry.get("imported", false)):
		detail = "Shared · " + detail
	var detail_label := MultiplayerUi.label(row, "· " + detail, Vector2(10.0 + outcome_label.get_minimum_size().x + 5.0, 26.0), Vector2(text_width, 18.0), 12, MultiplayerUi.MUTED)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail_label.clip_text = true
	detail_label.size.x = text_width - outcome_label.get_minimum_size().x - 5.0
	var x := width - 232.0
	var keep := MultiplayerUi.button(row, "Kept" if bool(entry.get("kept", false)) else "Keep", Vector2(x, 9.0), Vector2(58.0, 32.0), _toggle_keep.bind(id, not bool(entry.get("kept", false))), 13)
	keep.name = "Keep"
	if bool(entry.get("kept", false)):
		keep.add_theme_color_override("font_color", MultiplayerUi.GOLD)
		keep.add_theme_color_override("font_hover_color", MultiplayerUi.GOLD)
	MultiplayerUi.button(row, "Code", Vector2(x + 62.0, 9.0), Vector2(58.0, 32.0), _copy.bind(id), 13).name = "Copy"
	MultiplayerUi.button(row, "Watch", Vector2(x + 124.0, 9.0), Vector2(68.0, 32.0), _watch.bind(id), 13).name = "Watch"
	var remove := MultiplayerUi.button(row, "X", Vector2(x + 196.0, 9.0), Vector2(28.0, 32.0), _remove.bind(id), 13)
	remove.name = "Delete"
	remove.tooltip_text = "Delete this replay"

func _date(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var when := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%d %s, %02d:%02d" % [int(when.day), MONTHS[clampi(int(when.month) - 1, 0, 11)], int(when.hour), int(when.minute)]

func _watch(id: String) -> void:
	var loaded := history.load_replay(id)
	if not loaded.get("ok", false):
		_set_status(String(loaded.get("message", "This replay could not be opened.")), true)
		return
	watch_requested.emit(loaded.replay)

func _copy(id: String) -> void:
	var loaded := history.load_replay(id)
	if not loaded.get("ok", false):
		_set_status(String(loaded.get("message", "This replay could not be opened.")), true)
		return
	DisplayServer.clipboard_set(BattleReplay.encode(loaded.replay))
	_set_status("Code copied! Send it to a friend: they paste it here to watch.", false)

func _toggle_keep(id: String, kept: bool) -> void:
	if not history.set_kept(id, kept):
		_set_status("You already keep %d replays. Delete one first." % BattleHistoryRepository.MAX_KEPT, true)
		return
	_set_status("", false)
	_refresh()

func _remove(id: String) -> void:
	history.remove(id)
	_set_status("Replay deleted.", false)
	_refresh()

func _watch_code() -> void:
	var decoded := BattleReplay.decode(_code.text)
	if not decoded.get("ok", false):
		_set_status(String(decoded.get("message", "That code doesn't work.")), true)
		return
	history.add(decoded.replay, true)
	_code.text = ""
	_refresh()
	watch_requested.emit(decoded.replay)

func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", MultiplayerUi.ERROR if is_error else MultiplayerUi.GOLD)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
