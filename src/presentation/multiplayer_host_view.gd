extends Control

## "Open to friends" panel, reached from the multiplayer panel beside the
## in-game menu. Opens this campaign on a UDP port; friends join from their
## title screen. Mode and player cap (duo or unlimited) are chosen before
## opening; who may bring a team and duo double battles (shown only for a duo)
## can change at any time. "Saved players"
## lists (and forgets) the teams this world keeps.

signal closed
signal profiles_requested
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

const MODES := ["coop", "follow", "versus"]
const CAP_LABELS := ["Duo", "Unlimited"]
const MODE_HELP := {
	"coop": "Co-op: everyone explores this floor on their own and fights their own battles. Keys, doors, chests and stars are shared. You lead the way to the next floor.",
	"follow": "Follow me: friends stay in your room and watch every battle together. Anyone can start a trainer battle.",
	"versus": "Versus: a race up the tower. Everyone, you included, starts a fresh run at Floor 1 with their own keys, stars and seals. Your campaign is untouched.",
}

var _username: LineEdit
var _port: LineEdit
var _mode_buttons: Array[Button] = []
var _mode_help: Label
var _cap_buttons: Array[Button] = []
var _import_buttons: Array[Button] = []
var _double_buttons: Array[Button] = []
var _double_caption: Label
var _status: Label
var _toggle: Button
var _profiles_button: Button
var _mode := "coop"
var _cap := 0

func configure(prefs: Dictionary, character_name: String) -> void:
	var default_name := String(prefs.get("username", ""))
	if default_name.is_empty():
		default_name = character_name
	_mode = String(prefs.get("host_mode", net.MODE_COOP))
	if _mode not in MODES:
		_mode = net.MODE_COOP
	_cap = int(prefs.get("host_max_players", 0))
	if _cap not in net.PLAYER_CAPS:
		_cap = 0
	var allow_import := bool(prefs.get("host_allow_import", true))
	var double_battles := bool(prefs.get("host_double_battles", true))
	var panel := MultiplayerUi.modal(self, Vector2(480.0, 512.0))
	MultiplayerUi.title(panel, "Play with friends", Vector2(20.0, 12.0), 440.0)
	_username = MultiplayerUi.field(panel, "Your username", default_name, Vector2(20.0, 46.0), 300.0, 16)
	_port = MultiplayerUi.field(panel, "Port (UDP)", str(prefs.get("host_port", net.DEFAULT_PORT)), Vector2(336.0, 46.0), 124.0, 5)
	MultiplayerUi.label(panel, "Mode", Vector2(20.0, 102.0), Vector2(440.0, 20.0), 14, MultiplayerUi.MUTED)
	_mode_buttons = MultiplayerUi.choice_row(panel, PackedStringArray(["Co-op", "Follow me", "Versus"]), Vector2(20.0, 122.0), 440.0, 30.0, MODES.find(_mode), _pick_mode)
	_mode_help = MultiplayerUi.label(panel, "", Vector2(20.0, 155.0), Vector2(440.0, 54.0), 12, MultiplayerUi.MUTED)
	MultiplayerUi.label(panel, "Players", Vector2(20.0, 212.0), Vector2(440.0, 20.0), 14, MultiplayerUi.MUTED)
	_cap_buttons = MultiplayerUi.choice_row(panel, PackedStringArray(CAP_LABELS), Vector2(20.0, 232.0), 440.0, 30.0, net.PLAYER_CAPS.find(_cap), _pick_cap)
	MultiplayerUi.label(panel, "Newcomers may bring the team from their own save", Vector2(20.0, 268.0), Vector2(440.0, 20.0), 14, MultiplayerUi.MUTED)
	_import_buttons = MultiplayerUi.choice_row(panel, PackedStringArray(["Allowed", "Starters only"]), Vector2(20.0, 288.0), 440.0, 30.0, 0 if allow_import else 1, func(index: int) -> void:
		if net.is_host(): net.set_allow_import(index == 0)
	)
	_double_caption = MultiplayerUi.label(panel, "Duo: fight trainers together (double battles)", Vector2(20.0, 324.0), Vector2(440.0, 20.0), 14, MultiplayerUi.MUTED)
	_double_buttons = MultiplayerUi.choice_row(panel, PackedStringArray(["Together", "Separately"]), Vector2(20.0, 344.0), 440.0, 30.0, 0 if double_battles else 1, func(index: int) -> void:
		if net.is_host(): net.set_double_battles(index == 0)
	)
	_status = MultiplayerUi.label(panel, "", Vector2(20.0, 382.0), Vector2(440.0, 72.0), 13, MultiplayerUi.MUTED)
	MultiplayerUi.button(panel, "Back", Vector2(20.0, 462.0), Vector2(100.0, 36.0), func() -> void: closed.emit())
	_profiles_button = MultiplayerUi.button(panel, "Saved players", Vector2(128.0, 462.0), Vector2(150.0, 36.0), func() -> void: profiles_requested.emit(), 15)
	_profiles_button.name = "SavedPlayersButton"
	_toggle = MultiplayerUi.button(panel, "Open game", Vector2(286.0, 462.0), Vector2(174.0, 36.0), _toggle_hosting)
	net.status_changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if net.status_changed.is_connected(_refresh):
		net.status_changed.disconnect(_refresh)

func _pick_mode(index: int) -> void:
	if net.is_active():
		_refresh() # The mode is fixed while the game is open.
		_show_error("Close the game to change mode.")
		return
	_mode = MODES[index]
	_refresh()

func _pick_cap(index: int) -> void:
	if net.is_active():
		_refresh()
		_show_error("Close the game to change the number of players.")
		return
	_cap = net.PLAYER_CAPS[index]
	_refresh()

func _refresh() -> void:
	var hosting: bool = net.is_host()
	var guest: bool = net.is_guest()
	_username.editable = not net.is_active()
	_port.editable = not net.is_active()
	if net.is_active():
		_mode = String(net.settings.get("mode", net.MODE_COOP))
		_cap = net.max_players()
		_select(_import_buttons, 0 if bool(net.settings.get("allow_import", true)) else 1, guest)
		_select(_double_buttons, 0 if bool(net.settings.get("double_battles", true)) else 1, guest)
	_select(_mode_buttons, MODES.find(_mode), guest)
	_select(_cap_buttons, net.PLAYER_CAPS.find(_cap), guest)
	# The double-battle choice only exists in a duo game.
	var duo := _cap == 2
	_double_caption.visible = duo
	for button in _double_buttons:
		button.visible = duo
		button.disabled = guest
	_status.position.y = 382.0 if duo else 326.0
	_mode_help.text = String(MODE_HELP.get(_mode, ""))
	_toggle.disabled = guest
	_toggle.text = "CLOSE GAME" if hosting else "OPEN GAME"
	_profiles_button.disabled = not hosting
	if guest:
		_status.text = "You are a guest in %s's game. Only the host can open or close it." % net.player_name(1)
	elif hosting:
		var addresses: PackedStringArray = net.local_addresses()
		_status.text = "Open on port %s, %d/%s players. On your network, friends join with %s. Over the internet they need your public IP, with port %s (UDP) forwarded on your router." % [_port.text, net.players.size(), "∞" if _cap <= 0 else str(_cap), " or ".join(addresses) if not addresses.is_empty() else "this PC's IP address", _port.text]
	else:
		_status.text = "Friends join from their title screen with your IP address and port. Each username keeps its own team in your world, so friends find their minions again next time."
	_status.add_theme_color_override("font_color", MultiplayerUi.MUTED)

func _select(buttons: Array[Button], index: int, disabled: bool) -> void:
	for other in buttons.size():
		buttons[other].set_pressed_no_signal(other == index)
		buttons[other].disabled = disabled

func _toggle_hosting() -> void:
	if net.is_host():
		net.leave()
		return
	if not _port.text.is_valid_int():
		_show_error("The port must be a number like 7777.")
		return
	var options := {"mode": _mode, "max_players": _cap, "allow_import": _import_buttons[0].button_pressed, "double_battles": _double_buttons[0].button_pressed}
	var result: Dictionary = net.host(int(_port.text), _username.text, options)
	if not result.get("ok", false):
		_show_error(String(result.get("message", "Could not open the game.")))

func _show_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", MultiplayerUi.ERROR)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
