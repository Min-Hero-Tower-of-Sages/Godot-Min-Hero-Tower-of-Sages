# Godot-Min-Hero-Tower-of-Sages

A maintainable Godot rebuild of **Min Hero: Tower of Sages**, with recovered
game content and source-derived presentation. This is a work in progress,
not an official release or a claim of complete visual/behavioral parity.

## Play

Download the Windows build from this repository's **Releases** page when a
release is available. Extract the release ZIP and run `MinHero.exe`.
Godot is not required to play. Saves/settings are stored in Godot's per-user
application-data directory, not in this repository.

## Open the source project

1. Install **Godot 4.7.2 stable**, the standard non-.NET editor.
2. Clone/download this repository and import `project.godot` in Godot.
3. Allow the first asset import to finish, then press **F5** to run the game.

The configured main scene is `scenes/application_shell.tscn`. All runtime
assets and room data are included under `content/`. The original extraction
directories, SWF decompiler and Python are not needed simply to run the game.
`.godot/` is generated locally.

Controls: **WASD / arrow keys** to walk, **Space** to interact/advance dialogue,
and the mouse for battle selections and menus.

## Current scope

- Title screen, three save slots, character creation and skippable new-save intro.
- Standard tower content through the Grand Sage, plus the hard tower.
- Campaign movement, trainers, battles, progression, hatchery, party/talents,
  stars, settings and lobby merchants.
- Recovered artwork, font and music/sound bindings.
- Live multiplayer (co-op free roam, follow-the-host, or a versus race; duo
  double battles): open your game from the
  **Multiplayer** panel beside the in-game menu, friends join from the title
  screen. See [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md).
- Battle replays: every battle is recorded. Watch it again or share it as a
  code from **Battle replays** (title screen or in-game menu). See
  [docs/BATTLE_REPLAYS.md](docs/BATTLE_REPLAYS.md).

Content integration does **not** mean every presentation detail or mechanic
has been certified. See [docs/PARITY_WORK_TRACKER.md](docs/PARITY_WORK_TRACKER.md),
[docs/LIMITATIONS.md](docs/LIMITATIONS.md) and
[docs/MILESTONE_STATUS.md](docs/MILESTONE_STATUS.md).
Recovered optional minion/Ice data is packaged, but the Ice Floor and reference
mod-selection/acquisition flows are not playable yet; see
[docs/MOD_STATUS.md](docs/MOD_STATUS.md).

## Windows export

Install the export templates matching **Godot 4.7.2** via
**Editor → Manage Export Templates**. Then use **Project → Export → Windows
Desktop → Export Project**, with **Export With Debug** unchecked.
The preset embeds the game data in `build/windows/MinHero.exe`.

Alternatively:

```powershell
./tools/export_windows.ps1 -GodotExecutable 'C:\path\to\Godot.exe'
```

The script also creates a ZIP for a GitHub Release. Build outputs, export
templates and local diagnostics are ignored by Git. See
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for packaging and publishing.

## Development

`src/` contains domain/application/presentation code, `scenes/` Godot scenes,
`content/` runtime content, and `tests/` focused regression fixtures. Godot
`.uid` and resource `.import` metadata are retained; `.godot/` caches are not.

Run the GDScript suite:

```powershell
godot --headless --path . --scene res://tests/test_runner.tscn
```

The rendered title/intro fixture is
`res://tests/fixtures/title_menu_intro_smoke.tscn`.

Reference-recovery tools and source-audit tests additionally require local
material under `development/`, intentionally excluded from a normal checkout.
The packaged game itself does not require that material. For conversion tools:

```powershell
python -m unittest discover -s tools -p 'test_*.py' -v
```

The content pass logs every approved exact source correction. The move pass
reconstructs constructor/copy/setter behavior and compares normalized values with
the JPEXS-exported compiled SWF. Both refuse to overwrite non-empty staging
directories and reject unsupported expressions.

## Attribution and rights

This is an unofficial rebuild. Original artwork, audio, font and recovered
source-derived content are **not relicensed** by this repository. See
[ASSET_NOTICES.md](ASSET_NOTICES.md). No blanket open-source license is asserted
for the combined project. Confirm permissions before distributing third-party
material or assigning a license to it.
