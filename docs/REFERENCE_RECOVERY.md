# Reference recovery

The inventory tool reads and hashes the current reference bytes without changing
the checkout. Generated outputs are in `development/inventory/`:

- `reference_inventory.json`: hashes, counts, revision read directly from Git
  metadata, class index, unresolved imports, and mod groups.
- `coverage_manifest.csv`: edited and exported classes plus unresolved imports.

The initial edited-only run records revision
`96f2e2b07ee647b951c278ecce5087bca2f4583b`, 189 ActionScript classes, 1,455
PNGs, one JPEG, and both SWFs. Its missing non-platform definitions included
GreenSock/analytics libraries plus `DataEvent`, `LevelContainer`, `Random`, and
`RectangleCollisionList`; all are present after original export reconciliation.

`tools/recover_reference.py` stages JPEXS exports under
`development/extracted/` and refuses to overwrite a non-empty staging directory.
On 2026-09-08 the supplied custom JPEXS initially failed before parsing CLI
arguments under both Java 21.0.10 and Java 26.0.1:
`Configuration.getPlayerSwcOld` raised a null pointer because the discovered
roaming profile was unreadable to the sandbox. The recovery wrapper therefore
redirects `APPDATA` and `LOCALAPPDATA` to an isolated profile inside staging.
This workaround does not touch the user's real profile or the reference checkout.

The isolated run completed successfully: 2,119 scripts, 1,454 images, 78 sounds,
one font, 257 binary payloads, and one symbol table were exported. The room
normalizer matched and decompressed 249 room classes with zero mapping/XML errors.
Normalized review data is staged under `development/normalized/rooms-20260908/`.
The reconciled class/interface manifest contains 2,111 rows and zero unresolved
imports (generated asset wrapper files account for the difference from script-file
count).

`tools/build_reachable_content_manifest.py --force` builds the combined,
deterministically sorted `reachable_content_manifest.csv`. It joins the class
coverage and strict staged catalogs with each normalized room payload and placed
object, preserved original-SWF media identity, current edited-source media
hashes, mod groups, and trainer definitions/rosters parsed from the current
edited `TrainerSystem.as` and `MinionDexID.as`. It joins those trainers to
`StaticData.m_normalRooms`, exact normalized room payloads/source-authored room
classes, trainer-character object identities, and trainer interaction zones. It
also scans current-source room-class `AddObject` callsites and maps all object
families through the authoritative `BaseTopDownLevel.AddObject` conditions to
their handler methods/classes, dynamic guards, and explicit visual fallback.
The recorded snapshot contains 61,211 unique entries: 46,184 normalized room
objects, 2,566 source-authored placements, and 398 source-dispatch families
across 249 rooms, with all 48,750 normalized/source room instances linked to a
dispatch record. The room source-effect audit adds 28 factory-handler records,
36 reachable object classes/ancestors, and 192 method-effect summaries with
2,475 callsites and 433 mutable writes. This is source inventory evidence, not
Godot scene conversion. The manifest also has 302 active trainer definitions,
302 floor/room-to-actor
bindings, and 1,436 roster slots; 125 minions,
923 move identities (918 constructed and five unavailable tombstones), 167
talent trees, 16 types, and the other recovered media/class records. Trainer
roster references resolve to the staged minion/move catalogs. The disabled Ice
Floor draft inside a block comment is excluded from active definitions. It also
contains 36 menu-tree scripts (35 current edited paths plus one original-SWF-only
class), six root screen-state mappings, and 17 literal `SetSceneTo(GameState.*)`
transitions. It indexes 85 button/listener bindings and handler summaries across
25 classes, 67 typed modal/root route calls, and 228 visibility/input-state
assignments with their enclosing `if`/`else`, loop, or switch-case guards. The
menu inventory uses current-source precedence on overlapping paths and includes
original-only classes. This closes the M1 source-route/availability audit;
Godot menu implementation remains later migration work.

The source-level animation join contains 168 declared visual IDs: 164 explicit
`GetVisualMinionMove` dispatch cases, `VISUALS_SameAsClass`, and three visual IDs
that fall through to `TestVisualMove`. All 918 constructed moves now have a
visual-ID binding; 154 constructor asset bindings resolve through the qualified
`SpriteHandler` class and symbol character ID to an exported PNG. Those PNGs
are static art symbols rather than animation sequences. A JPEXS structural
export of both supplied
SWFs confirms two root frames (`Preloader`, `Main`) and zero nested movie clips
or display-list placements. The move animations are ActionScript-built: 16 of 17
visual classes use `TweenLite`/`TimelineLite`. Therefore frame-based animation
records are not missing reference data; porting the available programmatic
sequences is runtime work for the battle-presentation milestone. Full details
are recorded in `development/inventory/swf_timeline_audit.json`.

Progression/reward source flows are reconciled in 22 selected methods, with 270
callsites, 109 mutable state writes, 68 `DynamicData` state fields, and all 47
literal `SaveValue` keys. This closes the source-flow inventory gap; campaign,
reward, checkpoint, and save/load behavior still needs Godot integration.

The audio audit joins all 78 recovered sound symbols to edited-source and
original-SWF-only references: 72 controller API callsites, 15 scheduled
callbacks, 295 literal asset resolutions, 161 visual `SetSounds` bindings, 16
visual sound-field assignments, and 17 generic visual sound triggers. It also
maps nine music tracks, the `NONE`/`HALLWAY` policies, SoundController's mute,
lookup, volume and playback contract, and distance-based ambience attenuation.
`menu_tutorialOpen` is the sole recovered sound with no static source binding;
it is retained as explicitly unreferenced, not treated as unused. This closes
the M1 audio source-inventory audit. Godot playback integration remains later
complete-migration work.

The rule extension inventories eight groups with matching memberships in both
menu surfaces, all 27 registered mod flags, exact source accesses and guards,
the in-save ownership/current-floor restrictions, persistence and static-data
rebuild timing, and the Normal/Hard/All-Trainers Infinite Tower modes. The
reference spells the Arkvian identifiers `holyBirb1`/`holyBirb2` and has a
separate capitalization mismatch (`HolyBirb1`). Maintained Godot flags and
resource IDs now use `holyBird1`/`holyBird2`; exact aliases retain both source
spellings for tier 1 and the source spelling for tier 2. Sprite/class names stay
as source provenance, and no generic case-insensitive fallback is used. The
original source tree is not modified.

The former open Flash-timeline question is resolved by the structural audit
above: there are no nested frame timelines to reconstruct. Rule-set/special-mode
source inventory is complete; Godot runtime conversion belongs to later
migration work.
Room interaction source effects are now mapped through factory methods,
reachable classes/ancestors, callback methods, calls, writes, and guards; a
separate deferred-migration record keeps the Godot room component/service work
visible. The audio, menu, progression/reward, and source-level move-visual audits
are complete; their runtime integrations remain later migration work. None of
those runtime conversions is being counted as missing M1 source recovery, and
the source dispatch inventory does not claim those systems have already been
ported.

The image provenance gate is complete. The audit exactly joins 1,452 of 1,454
original exports and 1,452 edited source images to their own symbol tables;
the unqualified 262/490 shared images resolve through six exact SpriteHandler
Embed identities on each side. The Eevee Minion Maker fixture is explicitly
excluded from reference-game scope by user confirmation, while the extra
unembedded `mainMenu_modMenuBackground.png` is retained as supplemental source
art tied to the registered character-1682 handler. There are zero unresolved
image gaps; the full disposition is in
`development/inventory/asset_provenance_audit.json`.

`tools/reconcile_reference.py` compares original and edited material by qualified
identity and records the overlay policy in `development/inventory/reconciliation.json`.
Asset identity includes container, numeric character ID, and qualified class name;
the numeric prefix is never used by itself.
