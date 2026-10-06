# Grand Sage and hard tower implementation — 2026-10-06

## Implemented

- Replacement events contain their spawn-time state, and presentation creates
  the view before later automatic/timer actions in the same response. Grouped
  entries use the source 1s handoff rather than the opening 1.9s delay, preserving
  owned originals for finish/XP. Event-time turn-order badges and immediate
  presented-roster buff icons avoid future-state reads during those chains.
- Hidden move-timer casters now play native target-anchored effects without an
  attacker sprite. Hidden timer DOT/HOT and retired-original periodic effects
  retain their source through ticking and snapshot/restore. Ten authored
  floor-7–10 battles complete via legal native actions/settlement (131 actions,
  21 timer casts); native timer animation samples cover every configuration.
  Full-fight animated presentation and all combinations remain separate work.
- Visual-owned battle sound scheduling follows recovered object-family
  callbacks, including each target/object's impact, primary and secondary cue.
  Falling effects and sounds share one sampled start delay. Damage/reflection/
  redirection no longer add attack sounds; repeated freeze/stun badge playback
  includes its cue. All 160 authored profiles resolve their scheduled sounds;
  native and rendered timeline/Burn checks pass, without certifying every mix.
- Standard Floor 31: source Grand Sage room, five-minion roster, move IDs,
  trainer dialogue, entry and lobby return route. Registered with the existing
  standard campaign and runtime rather than a separate debug scene.
- Grand Sage victory unlocks hard mode. Completing the standard Grand Sage
  immediately meets the Titan reward frontier; both Titans are granted by the
  existing atomic claim, without a sponsor requirement.
- All 31 hard floors and 151 source hard encounters are registered. Source
  base levels and authored offset metadata are retained; ordinary trainer
  offsets are deliberately ignored in hard setup by LoadTrianer's >=31 branch.
  Modifier replacement offsets still apply. Source shield, timer,
  resurrection and extra-minion calls are imported, with repeated setters
  retaining the final source value.
- Trainer interaction, battle preparation, completed-encounter lookup and
  post-win dialogue resolve the actual hard encounter. The original room
  interaction ID is preserved for return-position lookup and room validation.
- Restored source expert rooms and paired hard-only routes on Floors 1–4,
  plus the Floor 1 hard trainer. All 151 hard rosters have live room bindings.
- Standard-mode hard-trainer rooms expose the source Qui-tel map interaction
  instead of becoming uninteractable. All 24 applicable map rooms are bound.
- Currency now uses source integer semantics in load normalization, separate
  first-clear award assignments, chest awards and merchant transactions.
  Old fractional balances truncate on load; no manual save reset is needed.
- Starter Burn inherits its source flamethrower sound at volume 0.4. The same
  fallback covers Intense Flame and Crazed, while explicit sound overrides are
  preserved. This corrects sound, not an alleged missing visual animation.
- Battle entry reuses catalog validation instead of rebuilding every room
  graph three times. Explicit rebuild remains available when content changes.
- Exploration now selects source regional music from ordered payload markers
  and volume overrides. A persistent shared music player spans room, battle
  and title scenes, resumes paused tracks and retains hallway region history.
  Older saves recover missing region history from their floor payloads.
- Source battle-track timing (one-second delay, six-second fade), quiet music
  return during long victories and immediate handoff after a short/skipped
  finish queue are restored. Hard rematch prompts/ratings use hard clear IDs.
- Replacement minions now use the source talent autobuilder rather than being
  granted every preferred high-tier move. Original owned views survive their
  temporary replacement and return before XP/talent/evolution presentation.
  Finish screens apply the source interface/opponent fades and dead-party
  half-opacity presentation. XP uses final opponent species/effective levels,
  excluding retired replacements rather than reading only the authored roster.
- Ordinary source trainers now use the same talent autobuilder with their
  level-based budget. Their constructor's random single-stat bonus and source
  floor/socket stat multipliers also affect current and level-60 power stats.
  Rebuilding a pending battle is deterministic; explicit extension grants stay
  unchanged. No enemy IVs/equipped gems are invented: the loader grants neither.
- Temporary replacements now get their new constructor stat bonus and proper
  side scaling: player stars versus enemy floor/socket coefficients. This source
  context survives engine snapshots. Source XP receives the per-party-member
  -1/0/+1 level comparison adjustment after Floor 1 with retry-stable rolls;
  hard fallback rosters no longer apply standard-only ordinary trainer offsets.
- Owned current stats now incorporate saved IVs, retain fractional base values
  until final rounding and put energy gem bonuses before the 1.5 multiplier.
  1,500 independent formula cases and production setup checks cover the change.
  Broader suite now passes 244 checks after source-backed expert-route/integer
  reward expectation updates; no live routes were reverted for stale tests.
- Native combat stat values now retain source fractions until final passive/stage
  casts, including replacements and snapshots. Explicit extension arithmetic is
  retained. Party/storage and campaign level-up displays include local passives
  and unique global moves from living party providers; setup avoids double buffs.
  Sixty focused source cases and the broader/keyboard/replacement checks pass.
- Permanent-passive persistence is integrated into source-ordered rest, setup
  energy limits, legacy result caps, XP health deltas, campaign evolution and HUD
  card bars. Native result health is transferred without unmodified-base clamps;
  native energy uses its reported maximum. Final health is transferred for all
  owned participants before fallback global energy caps are calculated. Save
  round-trip, duplicate settlement and rejected-save rollback checks pass.
- Finish XP/level cards/evolution now receive native temporary stages and
  trainer aura IDs until sequence exit. Owned originals keep their own retired
  stages after replacement. The source trainer aura persists beyond DeActivate
  until another trainer loads, unlike stat stages: runtime-only state preserves
  it across room/menu transactions but excludes it from disk saves. Cold load
  resets it. Controlled victory/level-card, copy/rejection/reset and cancellation
  checks pass; do not equate those with full win/loss animated playthroughs.

## Focused evidence

Fixtures use in-memory sessions, not player save files.

- Hard tower: all 31 floor selections, 151 native battle setups and starts,
  151 room-bound rosters, hard offset suppression, dialogue and modifier registration.
  A separate synthetic boss-settlement sequence checks the natural hard-floor
  unlock frontier through the hard Grand Sage.
- Standard Grand Sage: source content, synthetic victory settlement, hard-mode
  unlock, rejected-save rollback and atomic/idempotent two-Titan claim.
- Maps/currency: standard map grant and repeat interaction, old fractional
  balance normalization, whole-coin labels and cached catalog validation.
- Burn: inherited sound bindings and preserved explicit overrides; native
  cast/DOT playback retains the visible flames without duplicate cast effects.
- Clean headless startup with the hard-tower pack registered.
- Native music checks cover all 288 room tracks, 31 standard/hard regional
  fallbacks, shared-player resumption and guarded victory music callbacks.
  Rendered entry/victory/forfeit/defeat handoffs cover the source screen fades.
- Replacement batch: 61 source talent builds and a controlled native lethal
  action cover original-view/XP restoration, finish interface/opponent fades,
  dead-party ghosts and final-opponent-roster XP. The 101 later standard battle
  setups and 151 hard setups remain accepted; full animated battles are separate.

## Remaining fidelity work

Content registration and synthetic settlement do not establish full parity.

- Continue listening/playing through the intermittent battle music reports.
  The concrete missing exploration playback and shared handoff gaps are fixed,
  and rendered fades are exercised, but this does not certify every encounter's
  audible mix. Existing sourced intro delays are intentionally retained.
- Play complete later battles with modifier combinations and verify replacement
  presentation, original-party restoration and win/loss cleanup.
- Continue auditing enemy-stat/difficulty formulas and newly encountered move
  sounds/contact timing against the source.
- Defeat healing/checkpoint timing is now separated from settlement: the source
  finish queue/blackout precedes the atomic checkpoint return and slot-order
  rest. Saved unfinished returns recover on load without replaying XP; dead
  global providers stay dead during loss finish presentation. Native lifecycle
  and rendered shared transition checks pass. Continue remaining audiovisual
  parity and complete modifier-fight playthroughs rather than treating this
  lifecycle fix as battle parity certification. Trainer
  aura and temporary-stage finish lifetimes are implemented. Permanent-passive
  rest/result/save and XP health deltas are now
  integrated. Native passive/stage casts and party display aggregation are
  corrected. Owned base/IV/gem/star rounding is corrected. Native replacement
  stat/star scaling and 360 XP formula cases now cover the concrete gaps above.
  Ordinary trainer talent preparation now covers all
  308 registered source encounters / 1,470 opponents; all 62 source floor stat
  coefficient rows are checked independently against StaticData calls.
- Compare later room layering, regional music, maps, dialogue and HUD placement
  through actual play, including the restored early hard expert routes.
- Standalone asset packaging and full-game visual certification remain separate
  work. Some source assets still use the established development fallback.

Importer tools emit apply_patch changes and do not modify saves. The early
expert-route restoration emitter is intentionally a one-time transformation.
