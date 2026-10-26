# October 20 player report

## Floor 1-4 trainers

The curated room graph had E/D/F ordered as indices 3/6/7. Both recovered
StaticData versions instead specify D/F/E at indices 3/6/7. As a result, the
third normal encounter was attached to empty E, the boss encounter was on D,
and the visible boss/zone in F had no trainer binding.

Corrected room indices, minimap identities, encounter attachments and trigger
bindings to the recovered order. Existing encounter IDs, trainer rosters,
star history and portal destinations are retained. No new NPC or trigger
geometry is invented. The previous missing-trigger anomaly was a consequence
of the wrong room assignment, not a missing source button zone.

The focused fixture walks the source contact zones for D and F, obtains
dialogue, prepares/cancels both battles and verifies the hatchery key reward.
All four bonus floors have three standard fights plus their hatchery boss.

## Key-reset report

With Full Keys off, fresh entries to source floor indices 3, 8, 13 and 18
already clear both key counters and door flags. Floor 1-4's hatchery door is
locked without its boss key and consumes the earned key normally. These paths
are covered explicitly; no unrelated reset or door-gating rule was changed.

The existing Full Keys debug setting intentionally refills keys after floor
entry/reset and door unlocks. Disabling it stops replenishment, and a fresh
floor entry then clears the counters. The reporter's debug state is unknown,
so that behavior is not asserted to be the cause of their particular bypass.

October 26 follow-up: the tester confirmed Full Keys off for the door refusal.
The wrong D-room encounter gave a hatchery key instead of the third floor
key, and the combined HUD counter displayed x3. The existing room-order fix
corrects the earned key types; see PLAYER_REPORT_20261026.md for the actual
three-trainer/door settlement check and the additional Floor 5-1/5-2 fixes.

## Acquisition and shiny options

- Extra Minions has a default-off Starter Eggs option: Ticub/Zapig each get
  10% of Floor 1-1's hatchery distribution, including Hard Mode. The remaining
  candidates keep their relative proportions over 80%. Other floors, shared
  catalog data, original mod-mask bits and egg allowances are unchanged.
- Debug Mode has a one-time Make Current Minions Shiny button for party and
  storage. It requires the existing debug mod gate, blocks pending battles
  and reveals, and commits only after a successful save. It does not enable
  guaranteed future shinies or alter ordinary odds.

`tests/starter_shiny_floor4_smoke.gd` uses in-memory saves and isolated settings.
