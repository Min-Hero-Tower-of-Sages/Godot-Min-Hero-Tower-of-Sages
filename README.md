# Min Hero Extended

An unofficial Godot rebuild of **Min Hero: Tower of Sages**, combining the
recovered Flash campaign and modded content with new gameplay options,
multiplayer, battle replays and interface improvements.

## Branches

| Branch | Purpose |
| --- | --- |
| **[extended](https://github.com/Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages/tree/extended)** | Default and active development branch. Source for Min Hero Extended releases. Formerly `multiplayer`. |
| **[original](https://github.com/Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages/tree/original)** | Earlier Godot port baseline, formerly `main`, with its own README and `MinHero.exe` export preset. |

The feature list below describes **Extended**. The `original` branch preserves
the earlier port separately; its name refers to the Godot branch history.

## Play

Download and run **[MinHeroExtended.exe](https://github.com/Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages/releases/latest/download/MinHeroExtended.exe)**
from the **[latest release](https://github.com/Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages/releases/latest)**.
Release notes describe the changes in each build. If a ZIP is supplied,
extract it before running the executable.
Godot is not required to play. Saves/settings are stored in Godot's per-user
application-data directory, not in this repository.

## Open the source project

1. Install **Godot 4.7.2 stable**, the standard non-.NET editor.
2. Clone/download the **extended** branch and import `project.godot` in Godot.
3. Allow the first asset import to finish, then press **F5** to run the game.

The configured main scene is `scenes/application_shell.tscn`. All runtime
assets and room data are included under `content/`. The original extraction
directories, SWF decompiler and Python are not needed simply to run the game.
`.godot/` is generated locally.

Controls: **WASD / arrow keys** to walk, **Space** to interact/advance dialogue,
and the mouse for battle selections and menus.
Press **T** during battle decisions to open the Type Guide.

## Added in Extended beyond the modded Flash version

These systems were added for this Godot version. The recovered custom minions
and Flash challenge rules are listed separately below.

| Addition | What it provides |
| --- | --- |
| **[Multiplayer](docs/MULTIPLAYER.md)** | Co-op exploration, Follow me mode, a versus tower race, duo double battles, spectating and lobby arena challenges. Host from the in-game Multiplayer panel; join from the title screen. LAN play uses the host's address; internet play needs the host's UDP port reachable. |
| **[Battle replays](docs/BATTLE_REPLAYS.md)** | Automatic battle recording, saved favorites, playback at ×1/×2/×4 and share codes. Open Battle replays from the title screen or in-game menu. |
| **Battle information viewer** | Click one of your minions' health bars during a battle to inspect its current stats, buffs/debuffs, armor, conditions, effects and cooldowns. Enemy stats stay hidden. |
| **[Type Guide and matchup hints](docs/TYPE_GUIDE.md)** | Damage/healing type reference from battle or Minion-pedia, plus compact effectiveness badges on legal targets. Press T during a battle decision; toggle previews in Settings → Type Hints. |
| **[Flash save importing](docs/FLASH_SAVE_IMPORT.md)** | Preview and convert supported `.sol` saves into an empty slot, carrying over minions, learned moves, gems, progression, maps and Minion-pedia history. The Flash files are preserved. |
| **[In-save mod controls](docs/SAVED_MODS.md)** | Categorized Mod Menu at creation and in Settings. Enable options on existing saves; each toggle explains its switching rules. Nuzlocke is one-way, and added Move Trees talents must be reset before disabling that option. |
| **[Skill Gems and Random Forge](docs/SKILL_GEMS.md)** | Optional gems that grant active or passive skills while equipped. Rare field finds, Hard Mode map/extra-sage rewards, and color-based crafting after Talo. Non-elemental recipes include stats, armor, reflection and Taunt/Torment. |
| **[Shinies](docs/SHINY_PALETTES.md)** | Optional 1-in-512 chance for newly obtained minions. Programmatic color palettes are consistent across each evolution line and persist through saving and evolution. Cosmetic only. |
| **[Move Trees](docs/BEHAVIOR_EXCEPTIONS.md)** | Optional talents for recovered unused skills: Martyr for Holymantis/Foramare and Righteous Fate for Arkvian/Arkclaw. They use normal talent points. |
| **Starter Eggs** | Optional Ticub and Zapig acquisition in the Floor 1-1 hatchery, also in Hard Mode, with a 10% chance each. These acquisitions use normal shiny rolls. |
| **[Gated debug tools](docs/DEBUG_MODE.md)** | Enable the Debug Mode mod to expose Settings tools for unlimited money/stars, full keys, level-60 party members and guaranteed new shinies. A separate action makes current party/storage minions shiny. |

Extended also makes deliberate gameplay corrections beyond Flash behavior:
cleansing allies preserves their buffs, dispelling enemies preserves their
debuffs, and Invigorate/Watergize restore the selected ally's energy. See
[behavior exceptions](docs/BEHAVIOR_EXCEPTIONS.md) for the exact scope.
Website-only gem sockets work locally, all four sockets are available at level
60, and more than twelve active moves use additional selector pages.

## Recovered campaign and Flash mods

The standard tower through the Grand Sage, Hard Mode, hatchery, evolutions,
three-branch talents, storage, stars, lobby merchants and original presentation
assets form the campaign foundation.

The modded Flash version already supplied **Zanyu, Stingaray, Arkvian and
Ophan**, plus **Nuzlocke** and **No Regen**. Extended restores their acquisition
tables/rules and groups them in the Mod Menu. These are recovered additions,
rather than new minions invented for this port. See
[mod integration status](docs/MOD_STATUS.md).

**Ice Content remains experimental.** Its recovered minions and moves support
imports and Minion-pedia visibility, but the reference Ice Floor was unfinished
and this port does not add a completed Ice Floor campaign. Infinite Tower is
also unimplemented.

Development is ongoing, with campaign, combat and UI fixes delivered through
the [releases](https://github.com/Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages/releases).
For implementation history, see [the parity tracker](docs/PARITY_WORK_TRACKER.md).
Older milestone percentages and migration notes are historical snapshots;
this README and the feature guides describe the current Extended build.

## Windows export

Install the export templates matching **Godot 4.7.2** via
**Editor → Manage Export Templates**. Then use **Project → Export → Min Hero
Extended → Export Project**, with **Export With Debug** unchecked.
The preset embeds the game data in `build/windows/MinHeroExtended.exe`.

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
