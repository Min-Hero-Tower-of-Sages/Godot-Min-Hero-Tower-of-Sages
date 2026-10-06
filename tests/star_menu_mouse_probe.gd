extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	print("pointer target: ", root.gui_get_hovered_control())
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.progression["floor_index"] = 0
	session.state.progression["encounter_star_ratings"] = {"fixture1": 3, "fixture2": 3, "fixture3": 3, "fixture4": 3, "fixture5": 3}
	session.state.progression["star_upgrades"] = {"health": 1}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_show_you_menu")
	await create_timer(0.65).timeout
	var menu: CampaignYouMenuView = shell.interaction_dialog
	var reset := menu._panel.get_node("StarReset") as TextureButton
	print("reset bounds: ", reset.get_global_rect(), " summary before: ", session.star_summary())
	_click(reset)
	await process_frame
	print("summary after: ", session.star_summary(), " saves: ", session.saves)
	var passed: bool = session.saves == 1 and session.star_summary().spent == 0 and session.star_summary().available == 15
	var buy := menu._panel.get_node("StarUpgradeGroup0/StarUpgrade0") as TextureButton
	_click(buy)
	await process_frame
	passed = passed and session.saves == 2 and session.star_summary().spent == 10
	reset = menu._panel.get_node("StarReset") as TextureButton
	_click(reset)
	await process_frame
	passed = passed and session.saves == 3 and session.star_summary().spent == 0 and session.star_summary().available == 15
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: real mouse reset refunds stars" if passed else "FAIL: real mouse reset did not refund stars")
	quit(0 if passed else 1)
