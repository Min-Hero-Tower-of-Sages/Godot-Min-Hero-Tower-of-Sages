extends Control

## The end of a multiplayer session, shown over the title screen: the host
## closed their game, or the connection dropped. Styled like the other
## multiplayer panels, with a colored stripe for what happened and a reminder
## that nothing was lost.

signal closed

const PANEL_SIZE := Vector2(430.0, 200.0)
const KINDS := {
	"closed": {"caption": "Game closed", "accent": Color8(255, 214, 110)},
	"lost": {"caption": "Connection lost", "accent": Color8(255, 120, 110)},
}

var _panel: Panel

## `kind`: "closed" or "lost" (NetSession.last_disconnect_kind); `was_guest`
## adds the reminder that the player's own saves were never touched.
func configure(kind: String, message: String, was_guest: bool) -> void:
	var style: Dictionary = KINDS.get(kind, KINDS.lost)
	_panel = MultiplayerUi.modal(self, PANEL_SIZE)
	_panel.name = "NoticePanel"
	var stripe := ColorRect.new()
	stripe.color = style.accent
	stripe.position = Vector2(4.0, 4.0)
	stripe.size = Vector2(6.0, PANEL_SIZE.y - 8.0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(stripe)
	var caption := MultiplayerUi.title(_panel, String(style.caption), Vector2(26.0, 14.0), PANEL_SIZE.x - 46.0, 22)
	caption.add_theme_color_override("font_color", style.accent)
	caption.name = "Caption"
	MultiplayerUi.label(_panel, message, Vector2(26.0, 52.0), Vector2(PANEL_SIZE.x - 46.0, 44.0), 17, MultiplayerUi.INK).name = "Message"
	var hint := "Your own saves were not changed. What you did in their world is kept there for your next visit." if was_guest else "Your campaign is saved."
	MultiplayerUi.label(_panel, hint, Vector2(26.0, 96.0), Vector2(PANEL_SIZE.x - 46.0, 40.0), 13, MultiplayerUi.MUTED).name = "Hint"
	var ok := MultiplayerUi.button(_panel, "OK", Vector2(PANEL_SIZE.x - 146.0, PANEL_SIZE.y - 52.0), Vector2(126.0, 36.0), func() -> void: closed.emit())
	ok.name = "OkButton"
	ok.grab_focus.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
