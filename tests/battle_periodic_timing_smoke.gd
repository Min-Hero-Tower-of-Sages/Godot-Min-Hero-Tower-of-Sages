extends SceneTree

var failures: Array[String] = []
var tick_times: Array[int] = []
var health_times: Array[int] = []
var move_start := 0
var attack_duration := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"move_used":
			move_start = Time.get_ticks_usec()
		elif event.kind == &"damage":
			attack_duration = main._last_move_visual_duration_seconds
		elif event.kind == &"periodic_tick":
			tick_times.append(Time.get_ticks_usec())
		elif event.kind == &"periodic_health_applied":
			health_times.append(Time.get_ticks_usec())
	)
	var first := main.combatant_views["player-1"] as BattleCombatantView
	var second := main.combatant_views["player-2"] as BattleCombatantView
	var first_health := int(first.state_cache.health)
	var second_health := int(second.state_cache.health)
	var events: Array[BattleEvent] = [
		BattleEvent.new(0, &"move_used", &"enemy-1", &"", {"move_id": "base:move/claw/tier1", "target_ids": ["player-1"], "hit": true}),
		BattleEvent.new(1, &"damage", &"enemy-1", &"player-1", {"health": first_health - 1, "amount": 1}),
		BattleEvent.new(2, &"periodic_tick", &"enemy-1", &"player-1", {"move_id": "base:move/poison_tooth/tier1", "kind": EffectDefinition.Kind.PERIODIC_DAMAGE, "amount": 2, "effectiveness": 2.0}),
		BattleEvent.new(3, &"periodic_health_applied", &"", &"player-1", {"health": first_health - 3, "net": -2, "applied": -2}),
		BattleEvent.new(4, &"periodic_tick", &"enemy-1", &"player-2", {"move_id": "base:move/burn/tier1", "kind": EffectDefinition.Kind.PERIODIC_DAMAGE, "amount": 2}),
		BattleEvent.new(5, &"periodic_health_applied", &"", &"player-2", {"health": second_health - 2, "net": -2, "applied": -2}),
		BattleEvent.new(6, &"round_started", &"", &"", {"round": 2}),
	]
	await main._present(events)
	_check(tick_times.size() == 2 and health_times.size() == 2, "Both periodic targets must be presented")
	if tick_times.size() == 2 and health_times.size() == 2:
		_check(abs(tick_times[1] - tick_times[0]) < 50000, "Round-end visuals must start together, not wait for each other's contact")
		_check(health_times[0] - tick_times[0] < 50000 and health_times[1] - tick_times[1] < 50000, "Periodic HP transitions must start with the visuals")
		_check(float(tick_times[0] - move_start) / 1000000.0 >= attack_duration - 0.04, "Periodic phase must not overlap the final attack's tail")
	_check(not main.current_turn_indicator.visible or main.current_turn_indicator.modulate.a < 0.01, "Next actor indicator must stay hidden throughout playback")
	_check(int(first.state_cache.health) == first_health - 3 and int(second.state_cache.health) == second_health - 2, "Presented HP must equal the resolved net changes")
	_check(not first._health_tween.is_running() and not second._health_tween.is_running(), "Playback must wait for HP transition completion")
	first.apply_event_values({"shield": 40, "max_shield": 40})
	await create_timer(0.65).timeout
	var shield_start := first.shield_fill_visual.position.x
	first.apply_event_values({"shield": 20})
	_check(is_equal_approx(first.shield_fill_visual.position.x, shield_start) and first._shield_tween.is_running(), "Shield fill must animate rather than snap")
	await create_timer(0.2).timeout
	_check(first.shield_fill_visual.position.x < shield_start and first.shield_fill_visual.position.x > first._shield_visual_target_x, "Shield fill must visibly occupy an intermediate position")
	await create_timer(0.5).timeout
	_check(is_equal_approx(first.shield_fill_visual.position.x, first._shield_visual_target_x), "Shield fill must finish at its resolved fraction")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: grouped DOT/HOT contact, attack/round boundary, indicator gating and smooth shield fill")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
