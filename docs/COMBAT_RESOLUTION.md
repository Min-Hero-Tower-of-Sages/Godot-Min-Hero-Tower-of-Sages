# Combat resolution order

## Implemented headless order

1. Validate phase, expected revision, actor, move, cost, cooldown, and targets.
2. Pay energy and draw the shared buff/debuff, miss, stun, and freeze percentages
   in the recovered source order.
3. Apply before-accuracy effects, including percentage energy restoration.
4. Apply the strict accuracy gate (`accuracy < roll` misses; equality hits).
5. On a hit, resolve targets (chosen, all, or sampled without replacement) and
   execute enemy, ally, then actor phases in authored order.
6. Reuse shared move rolls where required; retain per-target rolls for critical
   and cleanse behavior.
7. Apply shields before health damage; emit defeat immediately at zero health.
8. Start cooldown only after a hit, then check team defeat and emit completion or
   advance through automatic activation states to the next decision.
9. At round wrap, tick periodic payloads, check defeat, decrement cooldowns,
   rebuild turn order, and enter the next activation.
10. Increment revision once for the accepted command.

The presenter consumes these facts and never rerolls them. Cost payment before a
miss follows the observed source organization but still requires fixture-level
validation across move families.

## Legacy facts already recorded

- Reference stage: 700×525 at 30 FPS.
- `StaticData`: party limit 5, STAB 1.1, super-effective 1.5, resisted
  0.66666666667.
- `BattleScreen` chooses its tie side randomly at battle activation. The flag's
  source name is misleading: a strict roll above 50% inserts the opponent first
  at each slot; equality and lower insert the player first. The stable numeric
  speed sort retains that insertion order for equal speeds.
- Random-target selection in `PlayerMoveSystem` samples occupied living slots and
  excludes the opponent battle-mod shield.
- `BaseMoveSystem` uses strict `chance > random * 100` comparisons in observed
  branches.

## Recovered active-move effect sequence

`BaseMoveSystem.ApplyEffectsOfCurrentMove` establishes this coarse authoritative
order. The generated move Resources store the same phase and sequence metadata:

| Order | Phase | Operation | Miss behavior |
|---:|---|---|---|
| 1 | Before accuracy | Subtract the move's energy cost | Always occurs |
| 2 | Before accuracy | Restore a percentage of the actor's current energy stat | Occurs even on a miss |
| 3 | Accuracy gate | Return when `accuracy < pre-rolled miss chance` | Stops all following operations |
| 4 | Action | Assign exhaustion | Hit only |
| 5 | Enemy target, in target order | Damage, including type/STAB, critical, redirection, reflection, and armor | Hit only |
| 6 | Enemy target | Attach periodic damage/armor/reflection payload unless battle-mod shielded | Hit only |
| 7 | Enemy target | Cleanse, freeze, then stun | Hit only |
| 8 | Ally target, in target order | Healing, then shield | Hit only |
| 9 | Ally target | Cleanse, then periodic healing/armor/reflection payload | Hit only |
| 10 | Actor | Flat self-damage, max-stat percentage self-damage, then self-healing | Hit only |
| 11 | Actor | Add move cooldown | Hit only |
| 12 | Actor | Self buffs, then self debuffs, in stored stat-vector order | Hit only |
| 13 | Selected target groups | Target buffs, then target debuffs; allies precede enemies | Hit only |

The runtime now represents the recovered shared move, per-target,
per-effect-target, and periodic-tick roll scopes explicitly. Primary damage and
healing calculate one base amount per move, apply STAB once, multiply both target
types in order, and then roll critical separately for each target. Healing swaps
the chart's resistant and super-effective multipliers exactly as the source does.

## Recovered periodic lifecycle

- A periodic payload is keyed by move ID on its target. Reapplication resets its
  turn counter to zero and replaces the source combatant; different moves stack.
- Payloads traverse from newest to oldest after every living combatant has acted
  and before the next round starts. Within each slot, the opponent ticks before
  the player, matching `BattleScreen.RunTickMoves`.
- DOT and HOT each call the legacy scaling formula again on every tick using the
  retained source's current maximum attack/healing stat and current level.
- Target type effectiveness applies on every tick. Periodic effects receive no
  STAB and cannot critical.
- Every component is accumulated into one net health delta. That integer delta
  is passed once through battle-mod-shield and ordinary shield handling, matching
  `OwnedMinion.TickDotsAndHots` calling `AddToHealth` once.
- The counter increments after the tick, and the payload is removed immediately
  when it reaches `overTimeTurnsActive`.

## Recovered defensive damage pipeline

- Active move-keyed payloads, owned passive moves, and unique global passives
  contribute armor and reflection. Only living allies contribute global moves.
- Armor subtracts every percentage from a starting multiplier of 1.0, then
  clamps the result to `0.05…2.0`. Reflection adds percentages and caps at 1.0.
- A battle-mod shield contributes no redirection and blocks negative health
  updates, but does not retroactively suppress reflection already calculated by
  the attacking move.
- Redirectors are collected once in slot order. If their combined percentage is
  over 100%, shares are normalized by the combined fraction. The source divides
  that stored accumulator by 100 again for every subsequent target; the runtime
  preserves this multi-target quirk in shared move-resolution state.
- Each redirected portion reflects from the originally selected target onto the
  attacker, then passes through the redirector's armor and shield. Remaining
  damage reflects from the selected target before passing through that target's
  armor and shield.

## Recovered passive, recoil, and shield facts

- Positive and negative stat-stage lookup tables clamp at ten stages. Attack,
  healing, energy, and speed apply the stage multiplier twice in the source;
  health applies it once. Derived maxima are recalculated after move/mod
  processing; current values are not percentage-scaled upward with them, and
  energy clamps down to a reduced maximum on access.
- A personal passive contributes only its first stat-percentage entry when that
  entry matches the requested stat. Living-team global passives are deduplicated
  by move ID before contributing the same way.
- Critical chance starts at 6.25% and adds personal and unique global passive
  critical effects.
- Flat self-damage uses the legacy attack formula but receives no STAB, type,
  critical, reflection, redirection, or armor. Maximum-health recoil truncates
  the percentage to an integer. Both still pass through battle-mod and ordinary
  shields because the source calls `AddToHealth`.
- Shields use the legacy healing formula and only replace the existing shield
  when the newly calculated amount is larger; that amount also becomes the new
  maximum shield.

## Recovered activation lifecycle and AI

- Activation checks run in this order: frozen, stunned, charged move, exhaustion,
  then normal decision. A successful thaw or stun-resist enters a normal decision
  immediately and does not also progress a stored charge or exhaustion counter.
- Frozen increments its counter and thaws only when `turnsFrozen > 1 + random*3`.
  The first frozen activation therefore always skips; the fourth always thaws.
- Stun permits an action only when `50 > random*100` and is not cleared merely
  because that activation succeeds.
- Selecting a charged move stores the move and concrete target instances without
  paying energy. Charge advances on later activations. Cost, the four shared
  rolls, effects, exhaustion, and cooldown occur only on release.
- Cooldown stores the source-equivalent elapsed lifecycle: a duration-one move is
  blocked for the entire following round and available in the round after that.
- `LegacyAiPlanner` ports `AIMoveSystem`'s threat model, including its periodic
  raw-power arithmetic and duplicated exhaustion adjustment quirks. Planning
  state participates in snapshot/restore; presentation code receives the chosen
  command and never recalculates targets.

## Required capture before fidelity claim

The complete lifecycle table still needs additional exact source/SWF fixtures
for shared-vs-per-target roll ownership, periodic ticking, passive
recalculation, shield-mod interception, resurrection, Nuzlocke, and encounter
modifiers. Trainer-difficulty scoring now has source-derived per-candidate RNG
coverage; it is no longer an open capture item.
Unverified ordering must remain explicit rather than be inferred from the sample.
