# Milestone status — 2026-09-24

Current parity implementation and outstanding user observations are tracked in
[PARITY_WORK_TRACKER.md](PARITY_WORK_TRACKER.md) (2026-10-01). Percentages below
are the historical estimates from this report; they have not been re-certified
by a complete campaign/presentation audit. Gem inventory persistence and
hard/expert first-clear gem awarding now exist, superseding the older statements
below that all random-gem rewards lack inventory support. Gem management UI
and complete campaign/release coverage remain open.

## Executive snapshot

The rough effort-weighted completion estimate is **48–53% of the complete port**.
This is not an average of the rows: campaign integration, full reachable-content
migration, complete presentation, and release validation dominate what remains.
Milestones 1 and 2 are complete; milestones 3 and 4 have passed representative
gates, with milestone 4 using a playable five-versus-five battle slice. Milestone
5 now has the complete source-backed standard Floor 1 room graph playable, the
ten-room Floor 2 slice, the nine-runtime-room Floor 3 route, the eleven-room
source index-3 slice, and the one-room Grass Sage gym at source index 4. The
gym is reachable through the source frontier unlock and its first clear
unlocks source index 5. Source index 3 remains an optional registered slice;
one trainer binding is unresolved because its authored room has no button zone.
The expert room remains source-only.
Most of the 31-floor
tower, broader campaign menus and source behaviors, full migration, extension,
and release work remain.

Milestone percentages are rough scope estimates, not percentages of manifest
rows. The earlier 95% estimate for Milestone 1 overstated completion. The
current source pass has reconciled progression and move-to-visual identity; a
structural SWF audit also confirmed that frame-based move animations are not
present in either supplied SWF.

| Milestone | Rough progress | Gate status | Principal remaining scope |
|---|---:|---|---|
| 1. Reference recovery | 100% | Passed | Recovered-source inventories and image provenance dispositions are complete; Godot runtime conversion is later migration work |
| 2. Project foundation | 100% | Passed | Optional clean desktop launch outside the sandboxed user-data environment |
| 3. Headless combat | 94% | Passed for representative mechanics | Broader source-derived golden fixtures |
| 4. Playable battle | ~97% | Representative five-versus-five gate previously passed; source catalog has 160 animation profiles and eight explicit system/alias handlers. Elimination awards reduced experience before defeat recovery; forfeit bypasses that reward and loss screen. First-loss experience tutorial is persisted, campaign-only, and now uses recovered panel/skull/button artwork with source-mapped layout and fades. Impact presentation waits for target-specific VFX contact before HP/status feedback and impact audio. Latest assertions have not yet been rerun. | Rerun the animated/immediate equivalence gate after recent timing/audio changes and visually inspect the first-loss tutorial in the open editor |
| 5. Campaign loop | ~78% | Not passed; Floor 1–3 runtime slices are connected through the Lobby/floor selector; the source-frontier Grass Sage gym at index 4 is registered and gym clears advance progression to index 5. The optional index-3 slice remains registered, with Floor 4 trainer 3 unbound because it has no authored button zone; expert layouts and gem inventory remain unavailable | Remaining 26 floors and their layouts, menus/dialogue/tutorials, broader quest/reward and party flows, authored minimap presentation, and complete campaign coverage |
| 6. Complete migration | ~23% | Not passed | Convert the remaining source rooms/objects, menus, progression, audio, visuals, modes, and executable move behavior |
| 7. Extension verification | ~60% | Extension seams and content/menu/ruleset fixtures are authored; fixtures have not been runtime-verified | Add a room-extension fixture and run the content, menu, ruleset, and room contracts |
| 8. Release verification | 0% | Not passed | Complete campaign and standalone Windows build |

Recent campaign integration: Floor 2 (`Level_1_2`, source floor index 1) has
ten normalized-payload rooms in the standard tower catalog. The source expert
room remains cataloged as hard-only/source-only because its authored layout is
not represented by a normalized room payload. Floor 2's standard path gives
one floor key for each of its three normal trainers; its hard, expert, and boss
trainer resources grant Eggery keys. The boss's first clear unlocks the next
source tower floor without awarding a Sage Seal (the source awards actual seals
only for gym-trainer types). Floor entry resets per-floor keys/doors/map and
Eggery selection count, then heals the party. Both converted floors' Eggery
pools now work through room-scoped, weighted candidate data. The Lobby route
uses the recovered special transition IDs (101 from each converted floor's
start room and 100 from each converted Eggery); unavailable/unported unlocked floors are shown
but disabled. Hard-only interactions are gated in both room presentation and
the campaign session service. Floor 3 (`Level_1_3`, source floor index 2) adds
nine runtime rooms, the normalized embedded Eggery payload, the source Water
Seal/Bird 60/40 pool and level-13 base, trainers 1–3 and boss 6 on the standard
route, and the hard-only trainer 4 resource. Its expert layout remains
script-authored and excluded from runtime. Floor 4 (`Level_1_4`, source index 3)
adds eleven normalized runtime rooms, Eggery candidates Healing Horse/Holy
Mantris/T-Rex at 50/30/20, and the source level-22 base plus 0–2 offset. Trainers
1–2 and boss 6 are bound to authored button zones; hard trainer 4 is mode-gated
in C. Trainer 3 is defined for room index 3 (E), but neither the normalized
payload nor embedded room class has a `buttonZoneObject`, so the graph records
the anomaly without inventing a trigger or location. Expert trainer 5 remains
attached to the script-authored, hard-mode source-only room. The source
`UnlockNextFloor` rule advances from index 2 to index 4, bypassing this index-3
slice; progression is unchanged. Source hard/expert random-gem rewards still
have no campaign inventory representation. The latest additions have not been
runtime-verified in the open editor.

## 1. Reference recovery — complete

Completed: immutable-byte inventory, SHA-256 provenance, Git revision recovery,
class/import index, initial coverage CSV, mod-group extraction, and safe staged
export wrapper. The wrapper isolates JPEXS from an unreadable roaming profile that
otherwise crashes configuration initialization. The complete category export
succeeded: 2,119 scripts, 1,454 images, 78 sounds, one font, 257 binaries, and the
symbol table. All 249 identified room payloads match their timeline-qualified
symbol identity and normalize from compressed XML with zero errors. The specific
room/symbol gate is cleared. The reconciled class/interface coverage has 2,111
rows and zero unresolved imports. That class-level inventory is still separate
from the per-entry reachable-content manifest; gameplay conversion is under way
for battle content but not for the campaign/world families. The generated
reachable-content manifest now contains 61,211 unique rows, including 46,184
normalized room-object instances, 2,566 current-source scripted placements,
398 room behavior families with 48,750 per-instance dispatch links, 28 source
factory-handler records, 36 reachable room-object classes/ancestors, and 192
method-effect summaries carrying 2,475 callsites and 433 mutable writes. The room
source-effect audit is complete; Godot scene/interactable conversion is deferred
to later migration milestones. It also contains 302 active trainer
definitions, 302 floor/room-to-actor bindings, and 1,436 ordered trainer roster
entries. It also indexes 36 menu-tree scripts (35 edited and one original-only),
maps all six root GameState screens, records 17 literal screen transitions,
85 button/listener bindings with 85 handler summaries across 25 classes, 67
typed modal/root route calls, and 228 guarded visibility/input-state assignments.
The menu source-route inventory is complete; Godot menu runtime routing remains
later migration work. The audio source audit now joins all 78 recovered sounds against
edited scripts and original-only classes, with 72 controller API callsites, 15
scheduled callbacks, 295 literal asset resolutions, 161 visual `SetSounds`
bindings, 16 visual sound-field assignments, 17 generic visual sound triggers,
nine music tracks plus the `NONE`/`HALLWAY` policies, and the distance-ambience
rule. The single recovered sound without a static source binding,
`menu_tutorialOpen`, remains explicitly listed rather than discarded. Godot
playback integration is later complete-migration work, not an open M1 source
inventory gap.

The source-level animation join now covers all 168 declared visual IDs: 164
explicit `StaticData.GetVisualMinionMove` cases, the `VISUALS_SameAsClass`
move-class alias, and three IDs recorded as falling through to `TestVisualMove`.
All 918 constructed move Resources link to their source visual ID; 154 bindings
join visual constructor asset keys to qualified `SpriteHandler` symbols, SWF
character IDs, and exported PNGs. The existing audio map contributes 161 visual
`SetSounds` bindings. This is source identity and dispatch coverage, not recovered
Flash frame timing or Godot VFX playback.

The progression source-flow audit is also complete: 22 selected campaign methods
with 270 callsites and 109 state writes, 68 typed `DynamicData` fields, and all
47 literal `SaveValue` keys. It traces battle rewards, trainer completion,
evolution, floors/unlocks, checkpoints/death return, and save/load ordering.
The campaign/save service boundary is now implemented for an initial source-backed
slice; broad gameplay conversion and presentation remain later migration work.
Trainer minion, move, room, actor, and interaction-zone references resolve
against the recovered catalogs/source. Disabled Ice-floor draft code is excluded
from the active trainer count.

The source rule inventory now reconciles all eight displayed groups across the
title Mod Menu and in-save Settings Menu: 27 registered flags (24 grouped plus
three always-on internal BMods), 26 exact key-access locations, 23 single-flag
guards, one compound guard, four configuration/persistence/application policies,
and all three Infinite Tower modes. In-save settings prevent disabling content
groups that have owned minions and prevent disabling Ice Floor while inside it;
the title-screen handler has no such guard. Flags persist individually, while
the source applies them when `LoadData(slot, true)` rebuilds mod-dependent static
content. Maintained Arkvian rule/resource IDs use `holyBird1` and `holyBird2`.
Exact aliases preserve source keys `holyBirb1`, `HolyBirb1`, and `holyBirb2`;
there is no general case-folding, and the reference checkout remains unchanged.

The trainer and roster records are inventory evidence rather than converted
Godot resources. Room objects now link to exact source dispatch conditions,
factory handlers, reachable class/ancestor chains, interaction callbacks,
stateful effects, and visual-only fallbacks. Their Godot components and campaign
service integration are still unconverted. The source-level animation
dispatch/content map and progression/reward flow inventory are complete.

The SWF structural audit is also complete. Both supplied SWFs contain only the
`Preloader` and `Main` root frames, with no nested movie-clip definitions or
display-list placements. Of 17 ActionScript visual classes, 16 use
`TweenLite`/`TimelineLite`; those programmatic sequences, not missing SWF frame
records, are the behavior to port for animated move visuals. This closes the
former timeline-recovery question. Final source-to-asset/provenance coverage
reconciliation is now complete: every image is joined by exact symbol identity,
linked through an exact ActionScript embed, excluded as user-confirmed test
output, or retained with an evidence-backed supplemental disposition. Rule-set/
special-mode runtime conversion is later migration work, not an M1 inventory
gap. The rule, menu route/availability, audio source-event, and room interaction
source-effect inventories are complete; their runtime integrations belong to
later migration work.

The final provenance audit exactly joins 1,452 of 1,454 original image exports
and 1,452 edited source images to their own symbol tables. The remaining two
original and two edited unqualified shared images resolve through six exact
SpriteHandler embed identities per source. The edited source also contains the
user-confirmed Eevee Minion Maker fixture (excluded from reference-game scope)
and an unembedded `mainMenu_modMenuBackground.png` variant, explicitly linked
to the registered character-1682 handler and retained as supplemental source
art. The audit has zero unresolved gaps; see
`development/inventory/asset_provenance_audit.json`.

Progress since recovery: the strict importer now parses 16 types, 923 declared
move identities, all 125 minions with 62 explicit evolution links, and all 167
talent trees as 1,634 nodes containing 3,374 ordered move references. Five source
defects are now handled by exact, audited corrections: two Arkvian-family
`holyLight_t1` typos and three Ice Floor Mud Blast namespace mistakes. The strict
cross-reference stage now passes; see `CONTENT_IMPORT_STATUS.md`.

Value-level move recovery strictly reconstructs all 918 moves instantiated by
the source (including 30 Ice Floor tiers). The five declared-but-unconstructed
`group_reflect` IDs are preserved as unavailable tombstones rather than receiving
invented gameplay values. Compiled-SWF normalized comparison reports zero
differences. The maintained catalog contains 923 move Resources and 1,467
ordered typed effects; constructed effects are implemented, while the five
source tombstones remain explicitly unavailable.

The strict importer also reconstructs the complete classic type chart: 89 source
assignments collapse to 83 unique attacker/defender pairs after six consistent
duplicate Demonic assignments. This includes Ice Floor's five defensive Thaw
pairs and is maintained as a typed Godot Resource. The playable battle now loads
this production catalog rather than leaving it only in staging.

## 2. Project foundation — implemented and export verified

Completed: Godot 4.7.2 pin, Compatibility renderer, 700×525 keep-aspect canvas,
1050×788 default window, input actions, bootable shell, Windows preset, definition
families, pack/catalog validation, deterministic engine boundary, application
controller, event presenter, atomic JSON save repository, Python tests, and
dependency-free Godot tests.

Evidence: Godot MCP reports `4.7.2.stable.official.ed1daf0bf`. The last completed
consolidated Godot suite passed 170 checks, including the Bird-ID cleanup,
five-versus-five battle UI integration, real viewport-mouse target selection,
and the low-energy Desperation fallback. Modifier-panel coverage has since been
extended; its attempted consolidated rerun remained silent past one minute and
was stopped without a pass/fail result. A Godot 4.7.2 parser-only check passes
for the later modifier and selector animation changes; the consolidated suite
has not been rerun. The Godot 4.7.2 Windows x86-64 debug/release
templates were downloaded into the ignored local toolchain directory and
SHA-256-verified. The release preset exported `build/windows/MinHero.exe` at
113,719,016 bytes. The executable launched headlessly for a short smoke run.
Godot emitted environment-level certificate-store and sandboxed `user://logs`
write warnings, but they did not prevent packaging or startup. The export preset
excludes local toolchain, build, test, and development files from the game pack.

## 3. Headless combat — deterministic core expanding

Implemented: isolated combatants, scripted RNG, revisions, command validation,
chosen/all/random target infrastructure, ordered phased effects, damage, healing,
energy, shields, stat stages, stun, freeze, cleanse, cost/cooldown, miss,
defeat/forfeit, events, snapshot/restore, and exactly-once result boundary. The
runtime now uses the recovered level/power/stat formula, the four shared legacy
move rolls in source order, strict comparison boundaries, cost and percentage
energy restoration before accuracy, cooldown only after a hit, one shared base
damage/heal amount across targets, 1.1 STAB, dual-type effectiveness, reversed
healing effectiveness, and per-target critical checks with the source default
6.25% rate. Periodic payloads now refresh by move ID, replace their source,
reroll power on every tick, traverse in reverse attachment order, apply typed
DOT/HOT without STAB or critical, aggregate to one shield/health update, expire
after the configured final tick, and run between completed turns and the next
round. Battle-mod shields prevent applicable payload attachment. The
Armor, reflection, and redirection now derive from active payloads, owned
passives, and deduplicated living-team global passives. Damage preserves the
reference order across normalized redirection, redirected reflection, redirector
armor, remaining-target reflection, and target armor, including the source's
repeated redirection-divisor conversion on subsequent targets. Stat stages use
the recovered lookup table and preserve the source's squared application for
attack, healing, energy, and speed. Passive stat percentages and critical chance,
scaled shield replacement, flat self-damage, and maximum-health percentage
self-damage are also executable. Charge, exhaustion, cooldown elapsed counters,
frozen thaw rolls, and stunned activation rolls now follow the recovered
activation order. Charged moves lock their targets when selected and pay energy,
roll accuracy, establish exhaustion, and start cooldown only when released.

The enemy AI now uses a deterministic port of `AIMoveSystem` threat scoring
rather than a generic damage ranking. It evaluates damage, healing, shields,
periodic payloads, status chances, stat changes, recoil, armor, energy cost,
target threat ratios, redirection, kill timing, random-target expectations, and
the universal Desperation move. Its persistent team-threat memory is included in
battle snapshots. Derived health maximums apply one stage multiplier while
energy maximums preserve the source's squared multiplier; current values are not
percentage-scaled when those maximums change. Equal-speed turn ordering uses the
single strict battle-activation tie roll and the source's actual side/slot
insertion order. The enemy difficulty modifier now follows the source's
per-candidate scoring path and uses the injected seeded battle RNG rather than
adding one bonus after target scores are aggregated. A focused fixture verifies
draw count and target ranking; broader source-derived golden fixtures remain.
Round-start cooldowns now tick only on living, non-defeated combatants, matching
the source `m_currHealth > 0` guard before `OwnedMinion.TickTurn()`; a focused
runtime regression verifies a defeated minion retains its cooldown through a
later round. The last full consolidated run was 170 checks and predates this
batch; the targeted cooldown regression passed independently.
`BattleEngine.get_result()` now returns a typed `BattleResult` with the completed
outcome and ordered per-participant survival/defeat state plus remaining
health/energy deltas. Removed extra-minion predecessors are retained in battle
history and included in the result. `battle_completed` emits that same payload,
and `BattleController.consume_result_once()` records it into the supplied
campaign-state dictionary exactly once. The consolidated Godot suite covers the
headless combat core, recovered content, and UI integration in one 170-check run.

All recovered executable effect families are represented. Trainer battle
modifiers cover source-style shield assignment and last-survivor removal,
resurrection with exponential health reduction and turn-order re-entry, explicit
extra-minion replacement, and interval-based move-timer activations. Turn order
tracks combatants that have actually acted and is rebuilt after each activation,
so speed changes, defeat, replacement, and resurrection take effect without
double turns. The suite also retains source-derived move/stat fixtures and the
real recovered-battle immediate-versus-timed presentation equivalence gate.

This remains architecture and partial fidelity evidence, not a complete-combat
claim. Broader reference-derived golden fixtures remain outstanding.

## 4. Playable battle — source-backed five-versus-five slice

The presentation now constructs ten combatants on the reference 700×525 arena,
using the recovered five-slot formation, original minion art, overlaid HP/shield bars, side/slot
badges, levels, status text, and turn indicator. The enemy party and its ordered
moves come from the recovered Hard Floor 1 Room 1 trainer definition. The player
party is a fixed level-25 test roster (Raptor, Fire Frog, Healing Horse,
Ice Tree, and Griffen), with extra recovered moves assigned for exercising
two-target chosen moves, random multi-target attacks, healing over time, and
three-target ally shields. It is still a showcase setup, not a party loaded
from campaign/save state.

The player chooses an available move and clicks legal minion sprites directly;
viewport-coordinate hit testing now selects only legal living targets. The UI
test sends a real mouse input through the viewport, checks all ten views and
source slot positions, then confirms command submission. Desperation is hidden
while another legal move is available and appears alongside the dimmed learned
moves when none is usable. Cooldown icons carry a white progress overlay like
the source selector. A separate warning distinguishes insufficient energy from
moves that are cooling down despite a nearly full energy bar; the source showed
the same out-of-energy message in both cases.

The recovered move selector module, energy bar, out-of-energy tip, top-right
forfeit button with confirmation box, and back button now appear at their
source coordinates.
Move buttons use the source fan positions and custom source-styled hover
popups; target selection dims non-legal combatants, highlights legal sprites,
and submits chosen targets on sprite clicks. Move order numbers are centered
inside their recovered badges. HP and shield updates now wait for each target's
visual impact time, including end-of-round periodic effects. Battle entry keeps
the selector closed until the recovered teleport-in sequence finishes.
The turn marker now fades over the recovered 0.3 seconds, and event handoff
waits for its exit before indicating the next actor. Target-focus dimming fades
to the source 55% amount over 0.5 seconds and fades back out over the same time.
Source-derived animation profiles now cover 160 visual IDs across nine
families: rotate-into-target, fall-onto-target, fall-from-top,
rise-out-of-target, orbit-into-target, burn-at-target,
fade-through-target, screen-shake, and the no-texture TestVisualMove white flash.
That source fallback restores the full-screen 0.2-second fade-in/fade-out for
Group Reflect, Taunt, and Titan Restore rather than treating them as projectiles.
The fade-through family uses source
stagger, travel speed,
object count, hang time, direction, and per-visual overrides for 29 visual IDs;
its first-contact damage time is distinct from the final sprite fade. The
target-rise and orbit families span 56 used visual IDs and 229 constructed move
tiers. Claw, Spike, Pound, Burn, and the fade-through family no longer use the
generic attacker-to-target flight. Turn indicators now remain hidden during
event presentation and return at the next decision-ready handoff. All 181 distinct move-icon
names used by the maintained move Resources now resolve to packaged PNGs.
The `VISUALS_SameAsClass` alias resolves through each move's class ID, fixing
texture selection for 193 alias-using Resources. Health and shield bars tween
over the source's 0.6 seconds; defeated minions now fade after a 1.2-second
delay. Misses show the recovered rising popup. End-of-round periodic ticks use
the move's separate DOT visual ID, including Burn flames and Poison Tooth's
rising drops on both application and later ticks. Charging, frozen, stunned,
exhausted, and stat-stage changes now show source badge assets with the
recovered fade-and-rise timing. Damage now displays the original source
super-effective, not-effective, critical, and redirection popups using a
consistent centered origin. Reflected damage now uses the source callout sprite,
target-relative placement, 0.2/0.4/0.2-second fade sequence, 0.8-second drift,
and 0.9-second battle handoff. Periodic tick events carry type effectiveness
into the same visual callouts. Positive healing also floats a green recovered-HP
number; Drain's actor-after-targets heal is represented in the event log, and a
zero heal is explained instead of silently looking like a missing effect. Move
selection starts its source-style outro when a move is chosen/submitted,
including automatic/self-target paths. Buttons fan in from their recovered
staging point with staggered movement and delayed name-tag fades; the outro
stagger returns, delays the panel fade using the source move-count rule, and
blocks the next decision until the selector has closed.
Fall-onto-target moves now reproduce the source's 0.3-second up/down bounce,
per-object impact staggering, yellow/orange impact burst, and its per-visual
impact visibility override. HP timing remains pinned to first contact, while
the event presentation waits for the last burst to finish. A focused headless
Godot runtime smoke covers nine animation checks for bounce motion, impact
timing, and visibility overrides. Fall-from-top and rotate-into-target now also
restore the source impact-burst choreography, per-object scale and staggering,
and optional-impact behavior. Their source constructor defaults are materialized
in the animation profile Resource data so the runtime no longer relies on
duplicated fallback values for these families.
The recovered ground-crack overlays are now packaged and restored across the
six source families that use them: fade-through selects crack 1, burn selects
crack 2, fall-onto/fall-from-top select crack 3, and orbit/rotate select crack 4.
They use the source per-family slot offsets, player-side mirroring, 0.15-second
delay, and 0.7-second fade-in, then persist beneath their target minion. A focused
headless smoke covers family selection, both sides' coordinates, overlay depth,
re-use, and fade completion in five checks.
The three source IDs which fall through to `TestVisualMove` now use its full-
screen 0.2-second white fade-in/fade-out rather than the generic projectile,
including the source's hard-coded thump sound; the no-texture `Titan Restore`
route is covered by a separate six-check visual/audio smoke.
Battle entry and resurrection now play all seven recovered teleport pieces,
moving inward from 80-pixel offsets at the source's 51-degree spacing; pieces
fade out with source stagger while the minion fades in after 0.5 seconds and
its health/interface fades in after 0.8 seconds.
Victory now uses the recovered 197×274 card and 57×57 star artwork at its
source position (504, 105). Its star count follows the recovered owned-party
loss thresholds; the background and staggered star reveals, hold/fade, and
0.4-second victory-sound delay follow the source sequence. The practice result
still uses a local restart control rather than the campaign finish flow.
Defeat now plays the source's immediate lose sound, 0.5-second pause, 1-second
blackout/message fade, 1.5-second hold, and 0.5-second fade-out before exposing
the practice restart panel. The campaign return-to-safe-room and party-heal
callbacks are intentionally not invoked without campaign state. A focused
headless Godot runtime smoke passes four checks across both result sequences.
Resurrection countdowns now use the recovered tombstone and Burbin number,
follow engine progress/resurrection events, and fade in/out over the source's
0.5 seconds. The per-minion battle-mod shield uses its recovered sprite and
source placement, reacting to shield assignment/removal events and combatant
state with the source's 0.8-second rise/fade choreography. Configured global
shield and resurrection modifiers now display their recovered stone assets at
the original battle-screen coordinates; shield counters match the configured
player/enemy counts and stones use the source loop timing. The global move-timer
and extra-minion panels now use recovered artwork and placements. Timer count
follows modifier state and the timer icon plays its scale/720-degree spin
sequence; extra-minion counts and configured species icons track spawn events,
and newly spawned combatants use the recovered entry choreography. Campaign
encounters can now pass trainer-authored battle-modifier configurations through
to the rule set and engine; the current standard Floor 1 trainer resources do not
activate any of those optional modes.
Earthquake, Destabilize, and Stonequake now use the source's staged global field
shake instead of the generic projectile fallback; per-visual intensity, shake
count, distance, and source movement-duration formulas are preserved. The hover
content and some label geometry are not yet exact. Campaign battle results now
show source-art XP bars and per-level stat cards in party order, including the
source delays and level-up health increase. Interactive talent/evolution
choices now persist to the campaign save. Elimination defeats now run the
source-reduced 75% experience award before the blackout, then heal/restore the
safe location and return automatically; forfeits award no experience and bypass
the defeat screen after the source 0.5-second music fade. Practice defeats keep
the restart panel. The first-death experience tutorial now appears once on a
campaign loss before XP presentation, persists across saves, and is skipped for
forfeits/practice battles. The shared
event-driven VFX overlay uses 144
packaged SWF effect images across 168 source visual IDs. The 78 recovered
battle sounds and 155 source visual-to-sound mappings are wired into battle,
and source callback timing is now profiled for five tween families (fall from
above, fall onto target, rotate into target, orbit into target, rise out of
target); battle music has the recovered six-second linear-volume fade-in.
Secondary `m_mainSound2` callback patterns are also sequenced. Target-specific
impact deadlines now hold health/status changes and impact audio until VFX
contact; this latest timing adjustment has not yet had its animated/immediate
equivalence rerun.
A source-ID audit accounts for all 168 visual
IDs: 160 profile-backed families and eight explicit system/alias handlers for
charging, reflected damage, exhaustion, frozen, miss, stat change, stun, and
`SameAsClass`. Remaining presentation work is current animated-versus-immediate
gate evidence and visual inspection of the first-loss tip. The
campaign battle route now builds setup
from the saved owned party and the source trainer's level-adjusted roster, then
settles the typed result through the campaign save service; the practice route
retains its curated level-25 party. What remains here is the first-death
tutorial's runtime pacing and final animated-versus-immediate rerun—not basic campaign-party routing, reduced defeat experience, or the
automatic source-timed defeat return.

## 5. Campaign loop — source indices 0–4 content slices, gate not passed

The campaign runtime now serializes owned party/storage records, stable campaign
and room IDs, progression, safe locations, active/pending mods, pending battle
context, and applied result IDs. Save schema 2 has a pure in-memory schema-1
migration plus nested identity/party validation. `CampaignSession` provides
new/load/save, connected-room transitions, interaction dispatch, pre-battle
rest and ID persistence, setup construction from owned minions, and atomic
result-and-save settlement. Result application updates only owned player IDs,
persists health/energy, grants recovered victory/defeat experience (but none on
forfeit), records a
trainer clear once, awards floor-zero money and one normal-trainer key, and
implements the source defeat return-and-heal path.

The standard Floor 1 graph now registers all thirteen source rooms: Entry
Hallway, A–E, H0–H4, Courtyard, and Eggery. The authored transition IDs resolve
to their matching entry markers with the recovered Flash-to-player position
offset. Floor keys from normal trainer clears open the H2 boss route; the boss
reward supplies the separate Eggery key; the Eggery door opens the H4 route to
the nine-choice egg room. Trainer 4 remains a future hard-mode encounter, not a
standard-floor battle. D presents its recovered map-station interaction, H1–H3
heal the party on entry, and the Grand Sage, Eggery, locked-door, map, and party
storage interactions are represented in the playable shell.

Floor 2 adds ten runtime rooms, three standard trainers, the standard boss,
its keyed boss/Eggery routes, map station, two recovery points, and its weighted
Eggery pool. Its hard-mode trainer is bound but mode-gated; the expert layout
remains script-authored. Floor 3 adds nine runtime rooms (including its
normalized embedded Eggery), three standard trainers and the standard boss,
two recovery points, source transition IDs, and a 60/40 Water Seal/Water Bird
Eggery pool with the source level-13 base. Its C-room hard trainer remains
mode-gated, and its expert room is still source-only. The hard/expert random
gem reward does not yet have a campaign inventory implementation.

Floor 4's eleven normalized rooms and six trainer encounter resources are also
registered. Its standard graph binds trainer 1 to A and trainer 2 to B, hard
trainer 4 to C only in hard mode, and boss 6 to D; H2/H3 healing, F's Eggery
door, H4/Eggery access, and all nine weighted Eggery picks are represented.
Trainer 3 is source-authored for room index 3 (E), but E has no source button-zone
object, so it remains an explicit unbound encounter rather than an invented
interaction. Expert trainer 5 is cataloged with the hard-mode source-only expert
room. The source frontier rule jumps from floor index 2 to 4, leaving index 3
outside fresh-run progression; the original unlock rule is preserved. Index 4
is now the source-authored one-room Grass Sage gym, with its trainer battle and
Sage Seal first-clear reward connected. Gym victory advances the frontier to
index 5. Its six trainer encounters are staged, but source index-5 room layouts
are not yet converted. Random-gem rewards still lack a campaign inventory field.

The application shell offers title/slot selection and new-character
name/gender setup; it starts or loads a campaign, renders every Floor 1 room,
moves the player, activates source collision and transition/interaction zones,
enters the attached trainer battles, saves the campaign result, and returns to
the recorded room location. Floor 1 egg picks use the recovered 60/40 Grass
Snake/Grass Gorilla weights and level range; new minions join an open active
party slot or enter storage, where the new party manager can swap them with an
active minion without losing owned state.

Exploration uses the recovered 30 Hz / 11-unit axis-step rule, source 45×25
player collision box at offset (14,70), top-left sprite origins, original male
and female direction/pose offsets, all 60 walking frames, and extracted
height-layer thresholds for source foreground objects. The campaign path uses
the player's saved owned party rather than the fixed practice roster, with
result health/energy, XP, first-clear rewards, and defeat recovery applied by
the existing campaign services. The 9-check progression-presentation smoke
covers the source XP bar, level-card update, earned-point marker, health gain,
and campaign return gate. Five focused room-runtime checks and the 15-check
campaign/save smoke currently pass.

This provides playable standard routes through Floor 3, a source-backed but
frontier-skipped index-3 content slice, and the reachable Grass Sage gym at
source index 4, not full campaign completion. The
remaining standard floors, hard/tower modes, most campaign
menus and dialogue, tutorials, broader quest/reward content, the original
authored minimap presentation, and much of party/storage/progression remain to
be converted. The campaign gate remains open until the intended tower route and
its save/load/reward behavior are complete beyond this Floor 1 slice.

## 6–8 — not complete

Full reachable-content migration, extension fixtures, and release verification
remain open. The source inventory includes 249 recovered room payloads; 44
runtime rooms across source indices 0–4 now have content conversions (32 are
the playable Floors 1–3 routes and one is the Grass Sage gym), with the remaining rooms and
non-room systems still outstanding. Completion still means a full campaign and
standalone Windows release; this repository has not reached that condition.

## Port exceptions and bug backlog

Exact content/reference corrections cover five move-reference defects (two
Holy Light references and three Mud Blast references) plus the Arkvian Bird-ID
migration aliases. Weighted Eggery selection is implemented for converted
floors; source modifier-specific pool variations remain later campaign work.
Other suspected items remain investigation notes only: dynamic numeric mod IDs, the `NUM_OF_MOVES` assignment
around `initMoveID`, strict random boundary comparisons, random tie-side selection,
and unusual initialization values. None has been “fixed” or rebalanced.
