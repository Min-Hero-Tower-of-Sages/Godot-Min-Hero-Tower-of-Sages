# Mod Workshop and player mods

Open **Play → Mod Workshop** on the title screen, below the save slots.
The Workshop creates player mods inside the game's user-data directory. Enable
one for a new save under **Mod Menu → Player Mods**, or for a loaded save under
**Settings → Mod Menu → Player Mods**. Editing a mod affects its next activation;
it does not rewrite the shipped content files.

For a first example, choose **Install the example mod**, select **Frost Pack**,
then **Edit**. It adds the Frost type, the three-tier Frost Bite move and the
Frostcub/Glaciger evolution line, adds Frostcub to the Floor 1 hatchery, changes
the first trainer and increases Bab-8r's base Attack. The example is installed
only when requested; ordinary saves do not enable it automatically.

## Make a mod

Enter a name beside **Create**. Each mod has a fixed ID, a name, a version,
an author and a description. Its ID is used by saves and by everything it adds;
changing a display name leaves those references intact.

Edits save automatically after a short pause. The top-right status reports
whether saving succeeded. Returning to the list, sharing and starting a test
battle flush pending edits first. A mod can be unfinished while editing: use
**Test → Check this mod for problems** before enabling or sharing it.

The editor groups its tabs into five categories along the top (**Mod**, **Create**,
**Change**, **World**, **Test**); the tabs of the chosen category appear on the
second row, with a count of what the mod holds. The editors are visual where
that helps: portraits, stat bars, a level 1-60 growth chart and the evolution
line for minions, a card with plain-language effect lines and a damage/healing
estimate for moves, a "what this change does" summary for patches, a matchup
overview for types, an odds bar for eggs, a skill grid for trees, a map and
blueprint for rooms, and a side-by-side matchup for test battles.

The Workshop uses the game's own menu look and art. Every reference to a type,
move, minion, skill tree or trainer shows its badge, icon or portrait, both on
the field and in the searchable picker, where minions and moves also show their
type badges (searching a type name such as "fire" filters by type). Hovering any
move shows the in-game move card, as the mod would play it: the mod's own moves
and changed moves are previewed, not just recovered ones. This works on fields,
pickers, the move lists and the skill grid.

| Tab | What it edits |
| --- | --- |
| **Info** | The name, version, author and description, plus tiles that count what the mod contains and jump to it. |
| **Minions** | New minions copied from an existing minion: portrait, types, base stats (live bars and a hoverable level 1-60 chart drawn with the game's stat formula), starting moves, specialization choices, skill trees, experience rate, gem sockets, evolution and art. |
| **Moves** | New move families copied from an existing move, with one to five tiers. A move card summarises cost, targets and what each effect does. Edit costs, timing, targeting and ordered effects for each tier (effects can be reordered). Choose an existing animation and icon through **Looks like**. **Power preview** estimates each damage/heal effect for a chosen user level and base stat, against neutral, strong and resisted types, with over-time totals. |
| **Skill trees** | New talent trees, copied from a recovered tree or started blank, and assigned to minions from the Minions tab. See below. |
| **Types** | New types with a name, color and generated badge, or an imported badge picture (framed and resized to the game's badge size). A "matchups at a glance" summary and one clickable box per pair (x1, x1.5, x0.67) in both directions. **Existing matchups** also edits recovered type pairs. Healing follows the game's reversed matchup rules. |
| **Changes** | Patches to existing minions or individual move tiers. Removing a patch restores the original definition when the mod next activates. Minion patches list every changed field as original → new (with stat deltas) and show a tick on each stat bar where the original value was. |
| **Trainers** | Existing tower trainers' teams (shown as portraits), levels, preferred moves, reward money basis and dialogue. |
| **Hatchery** | Adds weighted minions to a floor's egg pool or replaces the pool. A stacked bar shows the resulting odds. Additions can occupy at most 90%; replacements must total 100%. |
| **Rooms** | A floor map and a to-scale room blueprint. See below. |
| **Test** | Content checks and a sandbox battle using the edited mod. Choose one to five minions per side, or fight an existing trainer. |

## Skill trees

A talent tree is the grid on a minion's level-up screen: three columns by four
rows. Each **skill** is a line of moves, up to five **ranks**; buying rank 1
teaches the first move, rank 2 the second, and so on. Rows open as the minion
spends points in the tree (row 1 at 0, row 2 at 3, row 3 at 6, row 4 at 9). A
skill may require skills from an earlier row, shown as arrows.

In the Skill trees tab, press **New tree from...** to copy a recovered tree
(or one of your own) or **New blank tree**. In the grid, press an empty box to
add a skill (pick any move; its higher tiers become the ranks), press a skill
to edit its ranks and requirements below the grid, and drag a skill to move it
or swap it with another. The tree's name is the tab label on the in-game talent
screen, so it is limited to 14 characters.

A minion has up to three trees, one for each of its three specialization moves
(the same position in both lists). Give a tree to a minion in the Minions tab
(or a minion change in the Changes tab) under **Skill trees**. **Check this mod
for problems** warns about trees no minion uses. Removing a tree also takes it
off the mod's minions.

## Rooms

The Rooms tab opens on a **floor map**: the in-game minimap with the links
between rooms. Ordinary two-way doors are faint lines; one-way and rerouted
doors get arrows, and rerouted ones are gold. Selecting a room brightens its
links and labels every room they lead to. Gold outlines mark rooms the mod edits, red rooms can no longer be
reached from the floor's entrance, and small dots show trainers, eggs, healing
and services. Use the floor buttons to change floor. Press a room to see where
its doors lead; double-click it, or press **Edit this room**, to open it.

A room opens as a **blueprint**: the real room art drawn to scale, with its
walls (red), numbered doors (teal), arrival points (green) and interaction
zones (orange). Hover for details and press a marker to select it in the
inspector. Rooms open in **focus mode**, which gives the room editor the whole
screen (**Exit focus** or Esc brings back the Workshop header). The side panel
slides over the blueprint's right edge; **Panel** or **P** hides it so the room
uses the full width. **Show** hides layers, the grid menu sets snapping, and
**Undo**/**Redo** step through every change made to the room. Mouse wheel zooms around the cursor, right or middle
drag pans and **F** fits the room again.

The blueprint is also an object editor:

- Click art, a wall or an interaction zone to select it; Shift+click selects
  several. Drag to move (snapped to the grid; hold Ctrl to place freely).
  Arrow keys nudge (Shift for 10x), Delete removes, Ctrl+D duplicates and
  Ctrl+Z / Ctrl+Y undo and redo.
- To move a trainer, select both their figure (art) and their interaction zone,
  then drag. The same works for a healing stone and its zone.
- The **Objects** card edits the selection's exact position, scale (negative
  scale mirrors) and rotation, with **Flip**, **Duplicate**, **Remove** and
  **Reset**. **+ Add to room** opens a searchable art palette, with the room's
  own art first and an invisible **Wall** for blocking movement.
- Doors, entry markers and gated walls stay where they are, because exits and
  arrival points are bound to them. Eggs, chests and healing stones can be
  moved or removed but not added, as they carry saved game state.

The inspector also offers:

- **Doors:** where each door leads and which arrival point you appear at, with
  a thumbnail of the destination, a **Reset** button and **Go there**.
- **Arrival points:** where you stand after coming through a door. Drag the
  green circle on the blueprint, or type exact coordinates. Points must stay
  inside the room; the room's walls are not checked.
- **Inside this room:** the trainer who stands there, the hatchery eggs and
  their chances, key requirements for the boss and hatchery doors, and shop,
  combiner and storage text.

Opening a room does not change it; it joins the mod when you first change
something in it. **Reset room** removes the edit.

Starting a minion or move from a copy preserves the existing game's mechanics
and presentation. A copied minion keeps its talent trees but starts with no
evolution unless you choose one. Changing a minion's starting moves does not
replace moves that an already-owned minion has learned. Each minion needs one
or two types, at least one starting move, and either zero or three specialization
choices. Initially open and locked gem sockets must total at most eight.

New moves use the existing battle executors. The effect editor supports damage,
healing, energy, stat stages, shields, reflection, periodic damage/healing,
armor, self damage, percentage-health damage, stun, freeze, buff/debuff removal,
passive stat percentages, damage redirection and critical-chance changes.
Stat-stage and stat-percentage effects require a stat selection. Each tier can
contain one to eight ordered effects. Select appropriate targets and phases for
the intended effect; copying a similar recovered move is a useful starting point.

For minion art, copy an existing sprite and adjust hue, saturation and
brightness, or import a PNG of your own. An imported picture opens in a framing
window first: drag it to move it, scroll or use the slider to zoom in or out,
**Fit** / **Fill** / **Centre** it, and **Mirror** it (battle art faces right).
Zooming out past the picture's edges leaves transparent space. The framed
square keeps the picture's own resolution up to **512 × 512 pixels**, so there
is no need to resize anything beforehand (pictures up to 4096 × 4096 can be
opened). Saved art must be at most **1 MB**, and a shared mod code or ZIP at most **64 MB** in total. Imported art is copied into the
mod and included when sharing it. A mod can contain at most 48 PNG files. Type
badges are framed the same way and saved at the recovered badge size.

## Check and try it

**Check this mod for problems** builds the definitions, validates references,
room links, spawns, egg weights and art, then restores the previous catalog.
It also reports new minions without a hatchery/evolution acquisition route and
new moves not yet assigned to minions.

**Start test battle** saves the edited manifest and activates that mod in a
sandbox. The battle uses the normal battle interface, custom art/types and the
selected trainer's team and battle modifiers. An opposing team chosen directly
uses the normal practice rules. Empty move lists use starting and specialization
moves; trainer opponents also build their talents for their level.

Use **Back to Workshop** to return to the same mod and Test tab. The sandbox
does not award experience, change campaign saves or record battle history.
Editor test-team choices survive this round trip for the current game session.

The room editor changes the existing tower graph, where you arrive and the
objects in a room. It cannot create new rooms, doors or trainers (a trainer
interaction can point at a different encounter). Door references, arrival
points and object edits are checked, but a valid graph can still have an unwinnable
route or inaccessible rewards. The floor map's red marking only follows doors
from the entrance and ignores keys. Try route changes in a separate campaign
save before sharing them.

## Saves and multiplayer

A save records its enabled player mods with IDs, display names, versions and
content fingerprints. Missing or invalid mods stop loading with an explanation.
Reinstall the mod to resume that save. A changed installed mod can still load;
the save refreshes its reference and the game reports the updated mod. If the
author removed content the save still needs, restore a compatible copy first.

Turning a player mod off is refused while party/storage minions, learned moves
or skill gems depend on its added content. Other enabled mods must also retain
valid references. Stat changes recalculate through the normal stat system;
lower maxima clamp current HP/energy without granting free healing.

Multiplayer partners need the same installed player mods, including their art.
During joining, the guest can activate the host's installed mod set automatically.
Missing files or different fingerprints stop the join and name the required
mods; the game does not download them. Send their share codes or ZIPs first.
Versus race states retain the host's mod references. Leave multiplayer before
changing enabled player mods.

Mods apply in save selection order, and later patches override earlier ones.
A manually authored mod that refers to another mod must come after it. The
Workshop edits one mod against the shipped catalog; it does not provide a
dependency manager.

## Share and install

Select **Share** in the mod list or editor:

- **Copy code** produces an `MHMOD1:` share code containing the manifest and
  imported PNGs. A friend uses **Paste a share code → Install**.
- **Save as ZIP** writes a ZIP to the user-data `mod_exports` directory and
  opens that folder. A friend uses **Import a ZIP file**.
- **Open mods folder** opens the installed mod folders for manual editing or
  copying. A ZIP can contain `mod.json` and `sprites/` directly, or one containing
  folder with that structure.

Installing over an existing ID asks for replacement in the Workshop. Installation
stages the complete replacement before swapping folders; manifest saves keep a
backup. Deleting a mod removes its installed folder, so saves using it need a
compatible copy reinstalled before they can load again.

## JSON format

Each installed mod lives at `user://mods/<id>/mod.json`, with optional flat PNG
files under `sprites/`. Mods are JSON data and PNGs. They cannot register scripts
or supply effect executor paths. IDs use 2–32 lowercase letters, digits or
underscores, starting with a letter. The `base`, `extended` and `user` namespaces
are reserved. Added content IDs use `<mod_id>:<kind>/<local_name>`, where a local
name contains lowercase letters, digits or underscores.

This complete small mod changes Bab-8r's base Attack:

```json
{
  "format": 1,
  "id": "bab_balance",
  "name": "Bab Balance",
  "version": "1.0.0",
  "author": "Your name",
  "description": "A small Attack boost for Bab-8r.",
  "minion_patches": [
    {"target": "base:minion/anteater_1", "stats": {"attack": 34}}
  ]
}
```

Optional top-level arrays are `types`, `type_chart`, `moves`, `talent_trees`,
`minions`, `minion_patches`, `move_patches`, `trainers`, `hatchery` and `rooms`.
The bundled [`frost_pack.json`](../content/mods/examples/frost_pack.json) is a
larger working example. Workshop edits write the same format; the generated
JSON is also a reference for the supported fields.

Move family records hold `id`, `name`, `description`, `type`, `looks_like`
(an existing move tier ID) and a `tiers` array. The builder generates
`<family>/tier1` through `/tier5`; minions and trainers reference those tier IDs.
Move patches use `target` to name one existing tier. Minion additions use `id`
and `based_on`; patches use `target`.

Hatchery JSON uses zero-based source floors: `floor: 0` is Floor 1. The UI shows
one-based floor numbers. A hatchery rule has `mode: "add"` or `"replace"` and
`entries: [{"minion": "<id>", "weight": 15}]`.

Talent trees have an `id` (`<mod_id>:talent_tree/<name>`), a `name` of at most
14 characters, and `nodes`: `{"column": 0-2, "row": 0-3, "moves": [1-5 move tier
IDs, one per rank], "requires": ["<column>_<row>", ...]}`. At most one skill sits
in each box, and a skill may only require skills from an earlier row. A minion
uses trees through its `talent_trees` list (up to three), which may mix
recovered trees and the mod's own.

Room edits use the room's `target` ID, `exits` with existing `transition_id`
values and `target_room_id`/`target_spawn_id`, and `interactions` with existing
interaction IDs. Trainer interactions accept `encounter_id`; other supported
interaction fields live inside a `set` object. Arrival points are edited
with `spawns`: `[{"id": "entry-1", "x": 417, "y": 672}]`, using the room's
existing spawn IDs and coordinates inside the room. Room objects are edited
with `objects`, addressed by their index in the room's payload:
`{"index": 12, "x": 400, "y": 310, "x_scale": 1.5, "y_scale": 1.5, "rotation": 90}`
moves or resizes one (any subset of fields), `{"index": 12, "remove": true}`
hides it, and `{"add": "plantRoom_bush", "x": 200, "y": 150}` places new art
(`"collRect"` adds a wall). Removed objects keep their index, so later indices
never shift; added objects follow the room's own in order. The game applies
them to a copy of the room's payload and rebinds healing stones to their zones.
Unknown references,
unsupported interaction fields and malformed field types are rejected before
activation.

## Implementation and checks

`UserModRepository` handles manifests, PNGs, fingerprints, share codes and ZIPs.
`UserModBuilder` builds definitions and records reversible patches.
`UserModService` activates one mod set on the shared catalog and restores it
when saves change. The Workshop controller owns sandbox transitions; its view,
form helpers and searchable pickers live under `src/presentation/mod_workshop/`.

Focused checks:

```powershell
godot --headless --path . --script tests/user_mods_smoke.gd
godot --headless --path . --script tests/mod_workshop_smoke.gd
godot --headless --path . --script tests/multiplayer_network_smoke.gd -- --user-mods
```

The Workshop check can also run with a renderer and
`-- --capture-dir=res://build/workshop` to capture its screens. These fixtures
use scratch mod folders and in-memory campaign repositories.
