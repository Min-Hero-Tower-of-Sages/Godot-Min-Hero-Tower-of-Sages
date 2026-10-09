# Importing a Flash save

Open **Play**, then the small **Import** button at the top-right of an empty
**New Slot** card. That slot is preselected as the destination. Choose
`TCrpgSaveSlot0.sol`, `TCrpgSaveSlot1.sol`, or `TCrpgSaveSlot2.sol`. Select an
empty Godot destination in the preview and confirm. Load that slot normally
afterward; the Flash slot number does not dictate the destination slot.

Keep `TCrpgInitialData.sol` beside it if available. Flash stored the character
name, gender and sage-seal metadata there. Without it, import uses “Flash
Hero”, male appearance and seals inferred from completed sages.

Do not select the initial metadata file as the campaign save. Flash Player's
Windows saves commonly live inside `%APPDATA%/Macromedia/Flash Player/` under
`#SharedObjects`; the player/site determines the remaining directory. Use the
player's save export feature if saves live in browser storage. The importer
does not scan browser profiles or change Flash files.

## Preserved data

- First five Flash minion slots become the active party; later slots become
  storage. Slot order is retained within those lists.
- Base Dex IDs and custom ModName values translate to stable IDs. Holy Birb
  aliases resolve to Holy Bird.
- Nicknames, XP, levels, stat bonuses and all twenty-five move fields
  are translated. Talent ranks are derived from learned moves, as in native
  saves.
- The active party starts healed at the lobby resume point. Stored minions
  retain their archived HP. Earlier imports receive this repair once on load;
  subsequent loads preserve damage taken in Godot.
- Supported tutorial-seen flags are retained, including the first-gem prompt.
- Equipped gems retain socket positions. Inventory gems retain their grid
  positions, tiers, five raw stats and twelve facets.
- Integer money, star upgrades, best trainer ratings, trainer completion,
  floor unlocks, sage seals and supported mod flags are retained.
- Original flat fields are archived in the Godot save for future migration.
  The archive is data only and is never executed.

## Safe resumption and limitations

Import begins in the lobby, not potentially incompatible world coordinates.
Selecting the saved floor once restores its keys, door flags, map flag and
remaining egg picks along with trainer completion. Selecting another imported
floor clears that floor's old per-visit completion flags so trainers can supply
door keys again; best stars remain historical. Resumption is consumed only
after a successful save of floor entry.

Flash did not save IVs, current energy, per-egg selection identities or chest
history. IVs and energy use port defaults, and original egg identities cannot
be reconstructed. Ice minions and moves can be imported, but the reference
Ice Floor campaign was unfinished and remains unavailable.

Unknown minions/moves reject the entire import with a specific error. No
minion is silently skipped. Malformed or unsupported files change no saves.
Live, backup and temporary save files all prevent overwriting a destination.
Use normal save deletion deliberately if you need to free a slot.

## Implementation and validation

The native reader accepts the flat scalar AMF0/AMF3 SharedObjects written by
DynamicData.SaveAllData. It checks the 8 MiB limit, header and length, field
limits, string references, finite numbers and scalar types. Compound and
externalizable values are rejected; no ActionScript class is instantiated.
See the [Adobe AMF specification](https://rtmp.veriskope.com/pdf/amf3-file-format-spec.pdf).

The fixture is `tests/fixtures/flash_import_mods_smoke.tscn`. Run it only with
isolated application data: it writes/deletes fixture slots. It must not run
against real saves. Synthetic fixtures cover both encodings; a real exported
save is still needed to validate a particular Flash release/player end to end.
