extends Control

## Lobby arena door: choose another player to battle, or leave.

signal opponent_chosen(peer_id: int)
signal closed
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

var _status: Label
var _choices: Array[Button] = []

func configure(opponents: Array[int]) -> void:
	var height := 170.0 + 46.0 * maxf(1.0, float(opponents.size()))
	var panel := MultiplayerUi.modal(self, Vector2(360.0, height))
	MultiplayerUi.title(panel, "Arena", Vector2(20.0, 12.0), 320.0)
	MultiplayerUi.label(panel, "Who do you want to battle? Both teams start fully healed, and nothing you win or lose here affects your campaign.", Vector2(20.0, 44.0), Vector2(320.0, 54.0), 13, MultiplayerUi.MUTED)
	var y := 102.0
	if opponents.is_empty():
		MultiplayerUi.label(panel, "Nobody else is here yet.", Vector2(20.0, y + 8.0), Vector2(320.0, 26.0), 16)
		y += 46.0
	for peer_id in opponents:
		var busy: bool = net.player_battling(peer_id)
		var choice := MultiplayerUi.button(panel, net.player_name(peer_id) + ("  ⚔ in battle" if busy else ""), Vector2(20.0, y), Vector2(320.0, 38.0), _choose.bind(peer_id))
		choice.add_theme_color_override("font_color", net.player_color(peer_id))
		choice.add_theme_color_override("font_hover_color", net.player_color(peer_id))
		choice.disabled = busy
		choice.set_meta("busy", busy)
		_choices.append(choice)
		y += 46.0
	_status = MultiplayerUi.label(panel, "", Vector2(20.0, y), Vector2(320.0, 22.0), 14, MultiplayerUi.ERROR)
	MultiplayerUi.button(panel, "Exit", Vector2(20.0, height - 52.0), Vector2(320.0, 38.0), func() -> void: closed.emit())
	for choice in _choices:
		if not choice.disabled:
			choice.grab_focus.call_deferred()
			break

func set_waiting(peer_id: int) -> void:
	for choice in _choices:
		choice.disabled = true
	_status.add_theme_color_override("font_color", MultiplayerUi.MUTED)
	_status.text = "Calling %s to the arena…" % net.player_name(peer_id)

func set_error(text: String) -> void:
	for choice in _choices:
		choice.disabled = bool(choice.get_meta("busy", false))
	_status.add_theme_color_override("font_color", MultiplayerUi.ERROR)
	_status.text = text

func _choose(peer_id: int) -> void:
	opponent_chosen.emit(peer_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
