# Gem Affinity mod

Enable **Gameplay Tweaks → Gem Affinity** at creation or through
**Settings → Mod Menu**. The per-save `gem_affinity` flag defaults to off.
It is independent of Skill Gems and can be switched in either direction.

## Matching the affinity stat

A minion's affinity is its existing randomly assigned **5% stat bonus**:
Health, Energy, Attack, Healing or Speed. While the mod is enabled, equipped
stat gems contribute **20% more to that matching stat**. Mixed gems boost only
the matching component; their other components keep their ordinary value.
Skill gems have no flat stat contribution and receive no extra skill levels,
damage or passive percentages from this option.

The normal 5% affinity bonus, star upgrades and passives still apply through
the usual stat calculation. Fractional contributions survive until the final
stat is rounded. Thus a +10 Attack contribution becomes +12 before the normal
5% affinity/star/passive multipliers. Item tooltips continue to show the gem's
base values; the holder's stat display includes its affinity benefit.

## Energy correction

The Flash formula adds Energy gems before multiplying Energy by 1.5. The mod
moves those gem contributions after that multiplication, preserving the base
and IV Energy calculation and the normal 5% affinity bonus.

With no stars or passives and an Energy-affinity minion whose pre-multiplier
base/IV Energy is 100, a +10 Energy gem produces:

- Mod off: `(100 + 10) × 1.5 × 1.05 = 173.25`, rounded to 173.
- Mod on: `(100 × 1.5 + 10 × 1.2) × 1.05 = 170.1`, rounded to 170.

Energy maxima may therefore decrease when enabling the mod, despite the new
affinity benefit. This is the removal of the previous 50% gem multiplier.
Non-affinity Energy gems also lose that multiplier while the mod is on.
Switching it off restores the legacy calculation exactly.

## Existing saves and battles

Existing party and storage equipment is recalculated immediately. Switching
never changes gem records, socket assignments, IVs, affinities or learned moves.
Current HP and Energy are clamped when a maximum decreases; increasing a maximum
does not provide a free refill. Uninitialized HP/Energy keep their usual sentinel.
Rejected saves preserve the flags and current values. Changes are blocked during
a pending battle, checkpoint return or unfinished egg preview.

Menus, evolution/level stat cards, campaign battle setup and owned-party
multiplayer use the same calculation. Attack/Healing move-power maxima receive
the affinity bonus too. Battles and replays consume their prepared stat snapshot.
Trainer and gemless replacement stats retain the ordinary base formula.

`tests/gem_affinity_smoke.gd` checks every affinity and gem component, fractional
arithmetic, original/off behavior, battle power, passives, real disk save/reload,
rejected toggles and party/storage clamping. It refuses to write outside the
isolated `build/gem-affinity-profile` preferences/save directory.
