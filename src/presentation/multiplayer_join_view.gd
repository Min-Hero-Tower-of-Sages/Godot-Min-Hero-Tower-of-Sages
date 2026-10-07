extends Control

## Title-screen "Join a friend's game" panel: host address, port, username,
## and the team to bring on a first visit (a save's party, gems and money, or
## a fresh start with the starters). A username the host already knows always
## gets back the team it has in that world. The player's saves are only read.

signal join_requested(address: String, port: int, username: String, team: Dictionary)
signal closed
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

const FRESH := 0

var _address: LineEdit
var _port: LineEdit
var _username: LineEdit
var _status: Label
var _connect: Button
var _gender_caption: Label
var _gender_buttons: Array[Button] = []
## Choice index -> save slot (FRESH = 0 means a fresh start).
var _choice_slots: Array[int] = []
var _slot := FRESH
var _gender := "male"
var _busy := false

func configure(prefs: Dictionary, used_slots: Dictionary) -> void:
	var panel := MultiplayerUi.modal(self, Vector2(470.0, 440.0))
	MultiplayerUi.title(panel, "Join a friend's game", Vector2(20.0, 14.0), 430.0)
	_address = MultiplayerUi.field(panel, "Host IP address", String(prefs.get("join_address", "127.0.0.1")), Vector2(20.0, 52.0), 290.0, 64)
	_port = MultiplayerUi.field(panel, "Port", str(prefs.get("join_port", 7777)), Vector2(326.0, 52.0), 124.0, 5)
	_username = MultiplayerUi.field(panel, "Your username (shown above your head)", String(prefs.get("username", "")), Vector2(20.0, 110.0), 430.0, 16)
	MultiplayerUi.label(panel, "First time in this world? Bring a team:", Vector2(20.0, 170.0), Vector2(430.0, 20.0), 14, MultiplayerUi.MUTED)
	var labels := PackedStringArray()
	var slots: Array = used_slots.keys()
	slots.sort()
	for slot in slots:
		labels.append(String(used_slots[slot]))
		_choice_slots.append(int(slot))
	labels.append("Fresh start")
	_choice_slots.append(FRESH)
	var preferred_fresh := not String(prefs.get("join_fresh_gender", "")).is_empty()
	var preferred_slot := FRESH if preferred_fresh else int(prefs.get("join_slot", 1))
	if preferred_slot not in _choice_slots:
		preferred_slot = _choice_slots[0]
	_slot = preferred_slot
	MultiplayerUi.choice_row(panel, labels, Vector2(20.0, 190.0), 430.0, 36.0, _choice_slots.find(preferred_slot), _pick_team, 14)
	_gender_caption = MultiplayerUi.label(panel, "Fresh start as:", Vector2(20.0, 234.0), Vector2(120.0, 30.0), 14, MultiplayerUi.MUTED)
	_gender = "female" if String(prefs.get("join_fresh_gender", "male")) == "female" else "male"
	_gender_buttons = MultiplayerUi.choice_row(panel, PackedStringArray(["Boy", "Girl"]), Vector2(140.0, 232.0), 200.0, 30.0, 1 if _gender == "female" else 0, func(index: int) -> void: _gender = "female" if index == 1 else "male", 14)
	MultiplayerUi.label(panel, "Coming back under the same username? The host kept your team and it comes back on its own. Your own saves are never changed.", Vector2(20.0, 270.0), Vector2(430.0, 54.0), 13, MultiplayerUi.MUTED)
	_status = MultiplayerUi.label(panel, "", Vector2(20.0, 330.0), Vector2(430.0, 44.0), 14, MultiplayerUi.ERROR)
	_connect = MultiplayerUi.button(panel, "Connect", Vector2(262.0, 386.0), Vector2(188.0, 38.0), _submit)
	MultiplayerUi.button(panel, "Back", Vector2(20.0, 386.0), Vector2(120.0, 38.0), _close)
	for edit in [_address, _port, _username]:
		edit.text_submitted.connect(func(_text: String) -> void: _submit())
	_refresh_gender()
	(_username if _username.text.is_empty() else _address).grab_focus.call_deferred()

func set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", MultiplayerUi.ERROR if is_error else MultiplayerUi.MUTED)

func set_busy(value: bool) -> void:
	_busy = value
	_connect.disabled = value
	_connect.text = "CONNECTING…" if value else "CONNECT"

func _pick_team(index: int) -> void:
	_slot = _choice_slots[index]
	_refresh_gender()

func _refresh_gender() -> void:
	var fresh := _slot == FRESH
	_gender_caption.visible = fresh
	for button in _gender_buttons:
		button.visible = fresh

func _submit() -> void:
	if _busy:
		return
	var name_error: String = net.validate_username(_username.text)
	if not name_error.is_empty():
		set_status(name_error, true)
		return
	if not _port.text.is_valid_int() or int(_port.text) < 1 or int(_port.text) > 65535:
		set_status("The port must be a number like 7777.", true)
		return
	var team := {"fresh": true, "gender": _gender} if _slot == FRESH else {"slot": _slot}
	join_requested.emit(_address.text.strip_edges(), int(_port.text), _username.text.strip_edges(), team)

func _close() -> void:
	if not _busy:
		closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
