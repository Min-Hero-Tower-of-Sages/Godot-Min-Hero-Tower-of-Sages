# Battle replays

Every battle is recorded and can be watched again, or shared with a code
(like Pokémon Showdown's replays).

## Playing

Open **Battle replays** from the title screen (beside *Join a friend's game*)
or from the in-game menu's side panel. The list shows the last 30 battles,
newest first: who fought, the outcome, the floor (or *Arena* / *Double*), the
number of turns and when.

- **Watch** plays the battle. The bar at the top pauses (or press **Space**),
  switches between **x1 / x2 / x4**, and exits (**Esc**). At the end, a card
  offers *Watch again*, *Copy code* and *Back*.
- **Keep** saves a battle for good. Kept battles are never pushed out by newer
  ones (up to 100).
- **Code** copies the battle's share code (it starts with `MHR1-`). A friend
  pastes it under *Got a code from a friend?* and clicks **Watch code**. A
  pasted battle is stored and kept automatically. Pasting the same code twice
  doesn't list it twice.
- **X** deletes a battle.

What is recorded: campaign trainer battles (solo or as a double battle in
multiplayer), arena fights, and battles you watched as a spectator. Watching
a replay does not record it again. The history lives in
`user://battle_history/`, next to the saves, never inside a save file.

## How it works

`src/domain` is deterministic: the engine uses a seeded `BattleRng` and no
clock, which is also what multiplayer lockstep relies on. A replay is
`setup + rules + seed` plus the human commands in order. AI turns are not
stored: playback calls `submit_ai_turn()` and the engine makes the same
choices again.

| File | Role |
| --- | --- |
| `src/application/battle_replay.gd` | `BattleReplay`: the replay format, recording helpers, share codes (`MHR1-` + base64 of deflated `var_to_bytes`), validation, headless `simulate()`, display labels. |
| `src/infrastructure/battle_history_repository.gd` | `BattleHistoryRepository`: `index.json` summaries plus one compressed `.mhr` file per battle; pruning, keeping, de-duplication by fingerprint. |
| `src/application/battle_history_controller.gd` | Shell glue: opens the list, plays a replay full screen, returns to the title screen or the room. |
| `src/presentation/battle_history_view.gd` | The *Battle replays* list. |
| `src/presentation/battle_replay_hud.gd` | The replay bar and end card. |
| `src/presentation/main.gd` | Records every battle; the `replay` role feeds recorded commands back to the engine. |

**Recording.** The battle scene creates the replay right after the engine
accepts the setup, from the same wire form (`var_to_bytes` round trip) the
engine starts from, so Variant types match on playback. Each accepted human
command (local or received over the network) is appended with a 16-bit check
of the engine state it was chosen in. The replay is saved when the result is
shown, or, unfinished, when the battle scene closes early (disconnect, quit).

**Playback.** `begin_replay()` starts the engine like a spectator from a
published spec. Before each recorded turn the scene waits a short beat, checks
the revision and the state check, and submits the command. The recorder's
side stands on the left (arena fights recorded from team 1 are mirrored, as
they were live).

**Speed.** Presentation waits on absolute deadlines. Those now read a battle
clock (`_now_usec()`), which is the system clock unless a replay changes speed.
`set_playback_speed()` rebases that clock and sets `Engine.time_scale` so
timers, tweens and deadlines scale together; speed 0 pauses. Multiplayer
session timers measure real time, so watching a replay never slows presence,
world sync or saving.

**Versions.** A replay stores the content version. A replay from another
version shows a warning, and playback stops with *This replay no longer
matches the game* if a recorded command is refused. Share codes are trusted
as data only: decoding never creates objects, the shape is checked, the size
is capped, and the engine validates every command.

## Tests

```powershell
godot --headless --path . --script res://tests/battle_replay_smoke.gd       # record ~26 campaign fights, share-code round trip, re-simulate without drift, history rules, playback in the battle scene
godot --path . --script res://tests/battle_replay_ui_capture.gd -- --out=C:/tmp/replays  # screenshots (needs a window)
```

Tests launched from `res://tests/` record into `user://battle_history_tests/`,
never into the player's history.

## Known limits

- A share code holds both teams in full (stats, moves, battle modifiers), so
  it is about 2 000–3 000 characters. Discord turns a message that long into a
  `message.txt` attachment; the code still works when copied from it.
- No scrubbing or turn-by-turn stepping yet; only pause and x1/x2/x4.
- The replay of a double battle or arena fight shows the moves and results,
  not the live tutorials, XP sequence or reward screens.
- If a spectator's game had to resync from the battler mid-fight
  (multiplayer drift), its recording may not replay exactly.
