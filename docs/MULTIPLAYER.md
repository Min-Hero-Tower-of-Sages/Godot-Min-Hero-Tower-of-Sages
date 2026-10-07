# Multiplayer

Live multiplayer for the campaign: one player opens their game, friends join,
and everyone plays in the host's world.

## Playing

**Host**: in game, open the menu. A **Multiplayer** panel sits beside it.
Click **Open to friends**, pick a username, a UDP port (default `7777`), the
mode, the number of players (**Duo** or **Unlimited**), whether newcomers
may bring their own team and, in a duo, whether you fight trainers together.
Then click **Open game**.
The panel lists this PC's LAN addresses to give to friends. Over the internet,
friends need your public IP and the port forwarded (UDP) on your router.

**Guest**: on the title screen, after the save slots appear, click **Join a
friend's game**. Enter the host IP, port and a username that nobody in the game
is already using (the check ignores case). On a first visit, choose the team to
bring: one of your saves, or **Fresh start** (the new-campaign starters, as a
boy or girl). You don't need a save of your own to join.

While connected, the menu's **Multiplayer** panel lists the players (★ host,
⚔ in a battle; in versus also their floor and stars). It also opens
**Battle replays** (see [BATTLE_REPLAYS.md](BATTLE_REPLAYS.md)) and the
**Minion Keeper** from anywhere, and lets you leave (or, for the host, change
settings and close the game). The top-left corner shows the same roster while
you explore. Everyone sees everyone else walking live, with a colored name
above their head. Other players also appear as colored dots on the floor map
(when you have it) and as name tags beside their floor in the floor selector.

### Modes

| | **Co-op** (default) | **Follow me** | **Versus** |
| --- | --- | --- | --- |
| World | Shared: keys, doors, chests, stars, seals, storage | Shared | Each player's own run |
| Start | Beside the host | Beside the host | Everyone (host too) at Floor 1's door |
| Rooms | Everyone walks the current floor freely | Guests stand in the host's room | Free |
| Floors | The host leads; everyone is brought along | The host leads | Each player picks their own |
| Trainer battles | Each player fights their own (or together, in a duo) | Anyone starts one; everyone else watches. One at a time | Each player fights their own |
| Arena | The two fighters only | Everyone else watches | The two fighters only |

In co-op and follow mode, guests can't use the floor picker or *Save & return
to lobby*, and can't take the lobby exits (those change the floor).

**Versus** is a race up the tower. Everyone starts a fresh run with their team
(brought from a save, or the starters) and their own keys, stars and seals.
Every racer's chests hand out the same treasure (one chest seed per race). The
host plays a race run too. Their campaign is set aside, never written, and
comes back when they close the game. The host keeps every racer's run, so a
race can be resumed later under the same usernames.

### Duo and double battles

With **Duo** (two players) and **Together**, touching a trainer invites the
other player: *"X is battling Y. Fight together?"* If they accept, it becomes a
**double battle**: both parties fight on the same side against the trainer's
team **duplicated**. Each player picks moves for their own minions only. If
they decline, don't answer within 15 seconds, or are busy, you fight alone as
usual. The player who touched the trainer earns the win for the shared world
(completion, stars, rewards), and both players' minions earn XP. Up to five
minions per side use the normal places. Beyond that, both sides switch to a
denser ten-place layout.

### Arena challenges ask first

An arena challenge now pops up on the other player's screen (*Fight!* / *Not
now*, with a 15-second timer) instead of starting at once. A refusal or no
answer is reported back to the challenger.

**Arena**: in the tower lobby, step into the right-hand side door (the unused
Ice Floor entrance) to pick another player to fight, or *Exit*. The door fires
only once you are in the doorway. Players already in a battle are greyed out.
Both teams start fully healed and energized, and nothing from the fight is
written back to either campaign.

### Your team in someone else's world

The host keeps a **profile** for every username that has joined their world:
party, minion levels and talents, gems, money, tutorials seen. Its file is
`user://multiplayer_profiles/<world id>.json`, next to the host's saves.

- **First visit**: your profile starts from the save you picked (party, gems,
  money; not star upgrades, which belong to the world's stars) or from the
  starters. Tutorials you have seen in any of your saves stay seen.
- **Returning under the same username**: you get your profile back, whatever
  you pick on the join screen. The team doesn't disappear between sessions.
- **Your own saves are never written** while you play in someone else's world.
  Your solo campaign stays exactly as you left it.
- The host can set **Starters only**, so newcomers can't bring a team (for
  example, to keep a fresh run fair). Returning players keep their profile.
  This can be changed while the game is open.
- **Saved players** (in the host panel) lists every username the world keeps
  a team for, and **Forget** deletes one (not while that player is connected).
  Their next join is a first visit again.
- Each host campaign has its own world ID, so a new campaign starts with no
  guest profiles.

### What is shared, what is yours

| Shared (host world) | Personal (your profile) |
| --- | --- |
| Floor, unlocked floors, keys, sage seals, doors, eggs, map, chests | Party, minion levels/XP, talents |
| Completed encounters and **star ratings** (so the earned-star total is shared) | Gems, **money** |
| **Minion Keeper storage** | **Star upgrades** (bought from the shared total) |
| | Tutorials, Minion-pedia, your position and checkpoint |

Minions you deposit into the shared Minion Keeper move into the host's storage.
Minions you withdraw join your party. The host's game autosaves whenever the
shared storage changes, so a minion is never duplicated or lost.

### When a game ends

If the host closes their game, guests land on the title screen with a
**Game closed** card; if the connection drops, the card says **Connection
lost** instead (the host announces a deliberate close just before
disconnecting, so the two can be told apart). Both remind the guest that their
own saves were never changed. When the other side of a shared battle leaves,
the battle shows a **Battle ended** card for a few seconds, then returns to
the game. Every battle, multiplayer ones included, is also kept in
**Battle replays**.

## Architecture

| File | Role |
| --- | --- |
| `src/application/multiplayer_session.gd` | Autoload `NetSession`: ENet connection, modes/settings, roster and activity, presence, world sync, guest profiles, battle/storage arbitration, PvP setup. |
| `src/application/multiplayer_world_sync.gd` | Pure split/merge of a `CampaignState` into shared world vs personal data, and the profile helpers (extract, import from a save, fresh start, guest state). Unit tested. |
| `src/application/multiplayer_guest_profiles.gd` | Host-side profile store, one JSON file per host world (`<id>-versus` for races). |
| `src/application/multiplayer_double_battle.gd` | Duo double battle setup: partner's team, duplicated enemies, slot layout, who controls which minion. Unit tested. |
| `src/application/multiplayer_shell_controller.gd` | Shell glue: HUD, toasts, the menu panel, following the host, spectating, arena, storage lock, join/host panels. |
| `src/presentation/remote_player_avatar.gd` | Another player's sprite and name tag. |
| `src/presentation/multiplayer_{join,host,profiles,prompt,notice}_view.gd`, `multiplayer_arena_picker.gd`, `multiplayer_ui.gd` | Panels and the consent prompt, styled with colors sampled from the source in-game menu. |
| `src/presentation/main.gd` | Battle roles `battler` / `spectator` / `pvp` / `ally` (lockstep), per-minion controllers. |
| `src/presentation/campaign_minimap_view.gd`, `campaign_floor_select_view.gd` | Other players' markers. |

**Topology.** Host-authoritative star: the host validates usernames and
versions, owns the world and the guest profiles, and arbitrates the arena (and,
in follow mode, the single battle slot) and the Minion Keeper. ENet uses three
channels so traffic classes never block each other: world (reliable), presence
(unreliable-ordered), battle (reliable). Range-coder compression is on. Leaving
disconnects *gracefully*: the old connection is polled until its reliable
queue has drained, so a final battle command or profile update is never lost.

**Joining.** The guest's hello carries what the host needs to create a profile
(the chosen save's party, gems and progression, or a character for a fresh
start). The host picks kept profile > import (if allowed) > starters, and
answers with a complete guest state: the host's world around that profile,
standing where the host stands. The guest plays it through
`CampaignRuntime.load_detached_campaign`. Every save it makes goes to
`CampaignSession.save_redirect` instead of a slot. Imported minions get an
`mp<N>-` ID prefix, and new minions/gems are numbered with a per-profile
`save_slot` (`100 + N`), so IDs never collide in shared storage.

**Profiles.** A guest sends its profile (`extract_profile`, or in versus the
whole state) at most once per second when it changed, and once more on
leaving. The host stores it and writes the file every 2 s when dirty, on each
disconnect, and when it closes.

**Status.** Each player reports `{battling, where: {floor, lobby, room},
stars}` to the host when it changes; the host puts it in the roster everyone
receives. It drives the ⚔ marks, versus standings, map dots, floor tags, and
keeps arena challenges and double battle invites away from busy players.

**Questions.** The host asks (`_ask`) and the asked player answers
(`answer_prompt`); accepting sends that player's battle team. A question
expires after 15 s or when the player leaves, and the prompt is withdrawn from
their screen.

**Versus.** No world is synced at all: the host neither broadcasts nor merges.
A racer's profile is a complete state from `race_state_payload` (the campaign's
start room, the race's chest seed, the racer's team). The versus host loads its
own race state detached (`save_redirect`), and `leave()` reloads its real slot.

**Double battles.** The leader asks the host (`request_double`), which locks
the battle slot for both players and asks the partner. On acceptance,
`MultiplayerDoubleBattle.build_setup` adds the partner's team (`ally:` IDs) and
the enemy copies (`#2`) to the leader's prepared trainer battle. The spec
carries `actor_controllers` (which minions the partner controls) and
`double_teams` (the layout). Both machines run the same engine. A turn is local
when its actor belongs to you. At the end, the leader settles normally (the
partner's minions are ignored by instance ID). The partner applies
`apply_ally_battle_result`: final health/energy and XP for its own minions, a
heal on a loss, nothing on the shared world.

**Presence (responsiveness).** Each player sends a tiny sample at 15 Hz:
room, x, y, pose, walking, facing. It sends only on change, plus a 1 s
keepalive. Receivers render 110 ms in the past and interpolate between
samples, so movement looks smooth despite jitter. Jumps over 260 px snap
instead of sliding. The local player is never delayed: it moves immediately
and is never corrected by the network. Avatars are drawn only for players in
the same room.

**World sync.** The host polls its world fingerprint every 100 ms and
broadcasts a snapshot only when it changed. Guests send **deltas**: numbers
as differences, lists as union/remove, maps recursively. Two players spending
keys at once both count, and two completions are both kept. Before applying a
host snapshot, a guest flushes its unsent edits so they merge instead of
being overwritten. In co-op the snapshot never moves a guest's room. The
guest compares the host's floor (`floor_index`, `in_tower_lobby`,
`tower_mode`) with the one it last followed, and fades to the host (adopting
the host's checkpoint) when it changes.

**Battles (lockstep).** `src/domain` is deterministic (no `randf`, no clock,
seeded `BattleRng`). A shared battle is published as `setup + rules + seed`.
Every machine runs its own engine, and only human commands travel, a few bytes
per turn. AI turns are recomputed locally. Each command carries a fingerprint
of the sender's pre-command snapshot. A receiver that disagrees requests that
snapshot and restores it, so drift self-heals. `NetSession` logs the current
battle's commands, so a scene that subscribes late (after its screen fade)
replays the opening turns. In the arena, the fighter controlling team 1 sees
a mirrored view (their minions on the left) while the engine is untouched.
Co-op trainer battles are ordinary local battles. Each player reports
"in battle" to the host, for the roster and so arena challenges skip busy
players.

## Tests

```powershell
godot --headless --path . --script res://tests/multiplayer_sync_smoke.gd       # merge, profiles, import policy, versus, caps, double battles, PvP determinism, arena trigger
godot --headless --path . --script res://tests/multiplayer_spectator_smoke.gd  # battle scene as spectator / mirrored fighter
godot --headless --path . --script res://tests/multiplayer_network_smoke.gd    # two processes over localhost (transport, consent, profile kept across rejoin)
godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd      # two full game shells, co-op
godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=follow
godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=duo
godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=versus
godot --path . --script res://tests/multiplayer_ui_capture.gd -- --out=C:/tmp/mp  # screenshots of the panels (needs a window)
```

The two-process tests launch their own guest process and need nothing else.
When the shell test fails, the host prints the guest's step trace.

## Known limits

- Remote avatars are drawn at the local player's depth. Behind a pillar's
  overlay, a remote player can appear in front of it, because the overlays
  follow the local player only.
- An accepted arena challenge or double battle closes the menu the player had
  open.
- In a double battle, either player's forfeit forfeits for both.
- The partner in a double battle sees a short result card rather than the full
  XP/level-up sequence (the XP is applied).
- Two guests opening the same chest in the same instant may both receive its
  coins. The chest itself is claimed once.
- In co-op, a guest who goes into the eggery waits there for the host: its
  exit leads to the lobby, which only the host can take.
- A gem equipped on a minion deposited into shared storage stays in its
  owner's gem list; another player who withdraws that minion doesn't get it.
- Host and guests must run the same build (checked at join).

## To do (later)

- **Money-bought maluses/bonuses** to send at other players (future idea).
- Watching an arena fight in co-op/versus, and a spectator "skip to result"
  once the battle is decided.
- Versus: a finish line and podium (first to beat a chosen floor wins).
