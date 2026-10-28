# October 28 player-report follow-up

## Hard Mode Floor 1-1: five keys and the map giver

The Floor 1-1 graph supplied both a map-station and a hard-trainer
interaction at source button zone 0. The hard trainer was correctly limited
to Hard Mode, but the older authored map interaction had no mode limit.
Both contacts were active in Hard Mode; the map interaction was first, so
the player could never start the hard trainer's fight and obtain its key.

Mark the authored map interaction as standard-only, matching Floor 1-2. The
catalog's shared hard-trainer binding now also restricts any legacy paired
map interaction that has no explicit mode. It leaves explicit mode choices
on extension content intact. Normal-mode map interactions remain available.

The regression exercises the actual room contact and Space input in both
modes. It settles the three student fights, expert sage and minor sage, saves
and reloads the resulting three floor keys plus two hatchery keys, then fights
the previously hidden hard trainer. It verifies the sixth key, the unlocked
hatchery and 18-star result, plus paired map contacts throughout the tower.

## Next-floor unlock

In the recovered Flash source, defeating a frontier boss sets the new-seal
flag in BattleScreen.OpenVictoryMenus; MainChar.FinishActivate calls
UnlockNextFloor when the player returns to exploration. The hatchery is not
a prerequisite. The port unlocks at battle settlement, so a newly unlocked
Hard 1-2 after defeating the minor sage and returning to the lobby is
consistent with that rule. The regression checks the unlock before hatchery
entry; no floor-unlock rule was changed.

## Stun, freeze, and extra minions

PlayerMoveSystem and AIMoveSystem both allow a stunned minion to act on a
roll below 50, otherwise skip its turn. Stun stays active after a successful
roll until cleared; seeing the move selector while the stun tint is visible
is therefore not sufficient to identify a failed stun. Freeze always skips
its first activation and can thaw on later activations. The engine follows
those rules and deterministic tests cover the 50% boundary and thaw.

Flash's BattleScreen.CheckForWinLose creates a new minion with its own
unmoved state, then recalculates the order. A replacement is eligible to act;
if other remaining minions are faster, they may defeat it before it gets a
turn. The regression covers both a faster replacement acting and a slower
one being defeated first. A screenshot after a replacement appears does not
establish whether a turn was incorrectly skipped.

The focused fixture uses in-memory saves and does not modify player saves.
