extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const RECOVERED_CATALOG := preload("res://content/imported/recovered-20260911/catalog.tres")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var main := MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	call_deferred("_run_fallback_visual", main)

func _run_fallback_visual(main: Control) -> void:
	await process_frame
	main.catalog = RECOVERED_CATALOG
	var catalog_errors: PackedStringArray = main.catalog.rebuild_index()
	var fallback_profiles_valid := catalog_errors.is_empty()
	for visual_id in [27, 57, 173]:
		var profile: Dictionary = main.vfx_catalog.profile_for(visual_id)
		fallback_profiles_valid = fallback_profiles_valid and String(profile.get("family", "")) == "test_white_flash" and is_equal_approx(float(profile.get("duration", 0.0)), 0.4)
	_check(fallback_profiles_valid, "all three reference IDs falling through to TestVisualMove must receive its recovered 0.4-second flash profile")
	var titan_restore := main.catalog.get_definition(&"base:move/titan_restore/tier2") as MoveDefinition
	var no_texture_fallback := titan_restore != null and main.vfx_catalog.texture_for(173) == null
	main._last_move_visual_duration_seconds = 0.0
	var hit_event := BattleEvent.new(0, &"move_used", &"", &"", {"move_id": String(titan_restore.id) if titan_restore != null else "", "hit": true})
	var hit_delay := float(main.call("_animate_move_visual", hit_event, &""))
	var flash := main.get_node_or_null("SourceTestVisualWhiteFlash") as ColorRect
	_check(no_texture_fallback and flash != null and is_equal_approx(hit_delay, 0.3) and is_equal_approx(main._last_move_visual_duration_seconds, 0.4), "TestVisualMove must play without a texture, queue ApplyEffects at source m_moveTime-.1 (0.3s), and hold presentation for 0.4 seconds")
	_check(flash != null and flash.color == Color.WHITE and flash.mouse_filter == Control.MOUSE_FILTER_IGNORE and flash.z_index == 1500 and flash.get_global_rect().size == main.size, "the source fallback must create a full-screen, non-blocking white overlay above battle presentation")
	var fallback_sound := main.audio_controller.get_node_or_null("battle_hit_thump_splat") as AudioStreamPlayer
	_check(String(main.audio_controller.binding_for_visual(173).get("main", "")).is_empty() and fallback_sound != null and fallback_sound.stream != null and is_zero_approx(fallback_sound.volume_db), "TestVisualMove must play its hard-coded source thump even though the visual ID has no main-sound binding")
	await create_timer(0.15).timeout
	_check(flash != null and is_instance_valid(flash) and flash.modulate.a > 0.0 and flash.modulate.a < 1.0, "the source white flash must fade in over its first 0.2 seconds")
	await create_timer(0.35).timeout
	await process_frame
	_check(flash == null or not is_instance_valid(flash), "the source white flash must fade out and clean itself up after 0.4 seconds")
	main._last_move_visual_duration_seconds = 0.0
	var quake_event := BattleEvent.new(0, &"move_used", &"player-1", &"enemy-1", {"move_id": "base:move/earthquake/tier1", "hit": true})
	var quake_targets: Array[StringName] = [&"enemy-1", &"enemy-2"]
	var original_layer_positions := Vector3(main.arena_floor.position.x, main.combatant_layer.position.x, main.battle_modifier_layer.position.x)
	var quake_delays: Dictionary = main._animate_event(quake_event, quake_targets)
	_check(is_equal_approx(float(quake_delays.get("enemy-1", -1.0)), 0.925) and is_equal_approx(float(quake_delays.get("enemy-2", -1.0)), 0.925) and is_equal_approx(float(quake_delays.get("", -1.0)), 0.925), "one field shake must propagate its source 0.925s ApplyEffects wait to every target and secondary-effect fallback")
	_check(main._earthquake_tween != null and main._earthquake_tween.is_running() and is_equal_approx(main._last_move_visual_duration_seconds, 1.025), "multi-target earthquake must retain its single field visual and source 1.025s presentation lifetime")
	await create_timer(1.8).timeout
	var final_layer_positions := Vector3(main.arena_floor.position.x, main.combatant_layer.position.x, main.battle_modifier_layer.position.x)
	_check(final_layer_positions.is_equal_approx(original_layer_positions), "the field shake must restore all three authored layer positions after its independent motion tail")
	if fallback_sound != null and is_instance_valid(fallback_sound):
		fallback_sound.stop()
	main.free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: source fallback visual and audio (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d source-fallback checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
