extends RefCounted

## TCButton defaults: OnOver uses menu_tickSound(.5), Clicked uses
## menu_onPress(.65). Keep bindings single-use across menu rebuilds.
static func bind_button(button: BaseButton) -> void:
	# Flash TCButtons never take keyboard focus on click. Space belongs to
	# exploration/dialogue, not the last mouse-operated music/menu button.
	button.focus_mode = Control.FOCUS_NONE
	if button.has_meta("source_menu_audio_bound"):
		return
	button.set_meta("source_menu_audio_bound", true)
	var owner: BattleAudioController = button.get_tree().get_first_node_in_group("source_menu_audio") as BattleAudioController if button.is_inside_tree() else null
	button.mouse_entered.connect(_play.bind(button, owner, "menu_tickSound", 0.5, true))
	button.pressed.connect(_play.bind(button, owner, "menu_onPress", 0.65, false))

static func bind_tree(node: Node) -> void:
	if node is BaseButton:
		bind_button(node as BaseButton)
	if not node.has_meta("source_menu_audio_children_bound"):
		node.set_meta("source_menu_audio_children_bound", true)
		node.child_entered_tree.connect(bind_tree)
	for child in node.get_children():
		bind_tree(child)

static func _play(button: BaseButton, owner: BattleAudioController, sound: String, volume: float, hover: bool) -> void:
	if not is_instance_valid(button) or button.disabled or hover and not button.is_visible_in_tree():
		return
	var audio := owner
	if not is_instance_valid(audio) and button.is_inside_tree():
		audio = button.get_tree().get_first_node_in_group("source_menu_audio") as BattleAudioController
	if is_instance_valid(audio):
		audio.play_sound(sound, volume)
