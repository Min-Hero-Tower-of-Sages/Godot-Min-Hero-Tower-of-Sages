# October 26 player-report follow-up

## Floor 1-4: displayed three keys, but door refuses entry

The tester had not received the October 20 room-order fix. That fix also
addresses the apparent three-key failure: D hosted encounter 6 (boss), not
encounter 3 (normal). Completing A/B/D therefore gave two floor keys and one
hatchery key. The source-style HUD sums those counters, displaying x3, while
the regular door correctly requires three floor keys. Full Keys is not
needed to produce this symptom and is not blamed for this report.

Keep the source door rules and combined HUD counter unchanged. The expanded
fixture settles actual wins against A/B/D, checks three floor keys and zero
hatchery keys, opens the regular door, then settles the correctly bound F
boss and opens the hatchery with its earned hatchery key.

## Floors 5-1 and 5-2: missing expert-room slot

Both graphs omitted StaticData's Room1_1_expertRoom at index 5. This shifted
later minimap indices and attached the expert encounter (blank source text,
gem reward, no next-floor unlock) to the visible boss. The real boss was
attached to a decorative room on 5-1 and a hallway without its NPC zone on
5-2. This explains 5-1's apparent completion without unlocking 5-2.

Restore the source expert-room slot, using the existing recovered Grass
Floor1_1 expert layout with floor-specific payload identities. Its source
access is in 5-1 C and 5-2 A, hard-mode-only. Move encounter 6 to the actual
boss room (5-1 F / 5-2 D), retain existing encounter IDs and rewards, and
restore all following minimap indices. Include the new rooms in the campaign
room lists. Save history uses stable room/encounter IDs and is not erased.

Tests verify the visible NPC contacts, nonempty boss dialogue, actual victory
settlement unlocking 5-2/5-3, persistence after loading, and source minimap
lookup/highlight at the boss room.

## Declining a lobby exit

Previously release_transition_lock suppressed an overlapping portal until
the player walked clear, including outward through the open doorway into
empty space. That behavior is necessary for arrival teleports but is wrong
for a declined exit.

Keep the confirmation transition locked while it is displayed. No restores
the last pre-contact position, clears the transition lock, and then closes
the dialogue. Reapproaching the exit asks again. Arrival/teleporter
walk-clear guards remain unchanged. The real shell callback is checked for
both starting-room and hatchery exits on four floors.

## Opposing movement keys

Both opposing pairs still stop translation. They now face the most recently
pressed direction rather than unconditionally choosing left/up. Track
movement action press order without consuming input; ignore echo and presses
while room controls are disabled. All four press orders are exercised.

Fixture: `tests/player_report_20261026_smoke.gd`; in-memory repository only.
The previously published executable/release is not updated by these changes.
