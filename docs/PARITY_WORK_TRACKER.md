# Parity work tracker — 2026-10-06

The earlier milestone percentages in MILESTONE_STATUS.md are historical scope
estimates, not proof of visual parity. The full game port remains active.
Runtime startup checks establish script loading; user playthroughs establish
the presentation and interaction details listed below.

## Current implementation batch

- Repository/runtime packaging (2026-10-06): initialized local `main` for
  `Godot-Min-Hero-Tower-of-Sages`. Required extracted images now live under
  `content/base/art/source_symbols/`, with explicit aliases in `symbols.json`;
  the runtime helper no longer scans PNG export directories or parses recovered
  ActionScript. Six remaining development-room JSON dependencies are copied
  into packaged content. Runtime scripts/scenes/content no longer reference
  `res://development/`. Recovery files remain intact and ignored. Portable
  export preset includes JSON and uses normally installed matching templates;
  README, distribution guidance, asset provenance and honest mod-integration
  status added. Intro word rendering now uses a one-shot 2x transparent atlas
  and continuously tweened Sprite2D quads: font hinting/rasterization is fixed
  before playback, not recalculated during small scale/upward movements.
  Shared UI font and original story timings are unchanged. Focused rendered
  title/intro/Skip/room fixture passes; user visual confirmation remains open.
- Title/new-save presentation (2026-10-06): restored source title-track fade,
  upward stone/door scroll, timed black reveal, logo/button entrances, Play-to-
  save-card movement, three staggered source save cards, credit-panel entry/
  return, source button sounds and persisted music/sound toggles. Save cards
  show name, party/storage count, seals, stars and existing delete confirmation.
  Character creation fades over the live title instead of replacing it with
  a static background; Cancel restores cards and toggle input. Name input uses
  the recovered font size, colors, character restriction and default names.
  New saves now run the recovered 41.2-second doorway/story cinematic: bitmap
  glow masks plus source filled rectangles, shakes, sliding door leaves, zoom,
  black fade, individual-word text entrances/exits, hum/rumble/whoosh cues and
  title music envelope. A click reveals Skip Intro; playback completion and
  Skip share a one-shot fade-to-room handoff and never grant starters twice.
  All delayed intro callbacks are owned/cancelled by the intro, not the room.
  Focused rendered fixture covers menu entrance, cards, character Cancel,
  full playback, Skip callback cancellation and in-memory room handoff;
  captured doorway/story frames inspected. No player saves modified.
  This is not global parity certification: embedded Flash social widgets and
  the source mod-selection sidebar are not reconstructed by this batch.
- Global condition tint/feedback fidelity: BaseMoveSystem's one-second 50%
  additive blue (#3399ff) freeze / yellow (#ffff66) stun ColorTransform is
  restored on the native minion sprite using per-minion shader materials.
  Thaw, cleanse and resurrection ease back to neutral over one second; a
  later condition interrupts the previous tint tween. Thaw removes the tint
  without incorrectly clearing a still-active stun rule, as in Player/AI
  MoveSystem. Shader tint leaves transparent bitmap edges and parent opacity
  intact. Effectiveness feedback uses the original >1.4 / <0.7 thresholds.
  Removed the added generic red/gold hit flashes and floating heal numbers,
  which are absent from BattleScreenMinionVisual / BaseMoveSystem; authored
  attack VFX, HP easing and effectiveness/critical popups remain. Zero-
  calculated healing suppresses effectiveness/critical feedback, independently
  of full-health clipping of a positive calculated heal. This changes feedback
  metadata only, not healing calculations or critical RNG draws.
  Focused rendered checks pass source RGB pixels/transparent edges, one-second
  tint progression, per-minion isolation, thaw/cleanse, interruption and exact
  thresholds. The broad fixture's earlier heal-number expectation was corrected
  to assert the recovered source's absence rather than preserve the addition.
  The expanded headless fixture passes zero-calculated vs full-health-clipped
  healing feedback; broad 245-check and buffered/unbuffered stun/freeze/reflect
  queue regressions pass. Player saves remain untouched; sandbox user-log and
  shader-cache warnings are environmental.
- Global ApplyEffects resource/redirection presentation: cost and actor energy
  restoration remain in the engine's immutable resolved chronology, but the
  presentation queue now displays their grouped facts after move visuals at
  the same effects barrier as HP/status application. This also holds on a
  miss; spending/restoration do not introduce per-event .1s playback pauses.
  Matching is actor/move-specific, with original-order fallback for incomplete
  streams. Automatic next casts still wait for the prior unconditional finish.
  BaseMoveSystem's redirection feedback now snapshots living unshielded opposing
  redirectors once in native slot order for successful damage moves. All those
  popups start at ApplyEffects before per-target damage; repeated redirected-
  damage events no longer duplicate their artwork. Zero rounded damage retains
  the source feedback, while non-damage moves omit it. Standalone diagnostic
  redirected-damage playback retains its original fallback popup.
  Focused in-memory headless checks pass resource timing on hit/miss, immutable
  event order, no resource pauses, decision isolation, redirection slot order,
  shield/death exclusions and once-per-move feedback. RNG, damage calculations,
  result contracts and player saves are unchanged.
  Both focused fixtures pass rendered; the automatic cost/cast finish fixture
  and broad 245-check battle/campaign runner pass headless. Environment-owned
  user-log/shader-cache warnings remain unrelated to script execution.
- Shared minion gem-detail parity: party and storage now use one renderer for
  MinionDetailsMinionGemsObject's authored socket grid. Empty socket bitmaps
  keep native dimensions and hide behind occupied gems; storage no longer
  stretches them to 48x48 or displays all unavailable slots as locked.
  Unavailable locked/premium artwork is distinguished without introducing
  sponsor/purchase flows. Available socket artwork itself routes selection
  to the same member/socket as Change. Equipped sockets show the recovered
  gem tier and colored Health/Energy/Attack/Healing/Speed stat tooltip;
  tooltip construction is shared with inventory and inherited merchants.
  Storage text fields now include Flash's 2px content inset and do not
  intercept mouse input. A focused in-memory headless fixture passes both
  details views, occupied/empty native artwork, unavailable controls, exact
  socket routing, multi-stat colors/amounts and inventory tooltip reuse.
  The focused fixture also passes rendered. Existing gem/settings flow
  (atomic moves/equipment replacement, socket backdrop/details return and
  merchant tooltips) and campaign-menu integration pass headless. Sandbox
  user-log/shader-cache warnings are unrelated to script execution.
  Presentation does not mutate equipment, currency or player saves.
- Global storage-menu fidelity: MinionStorageMenu's source-stage origin is
  retained under the shared 700x525 letterbox transform; its 667x480 artwork
  no longer independently fits/centers itself and enlarges the grid/details.
  Ordinary selection survives box navigation, and toggling swap mode transfers
  that same selection rather than discarding it. Details hide while swapping
  and return for the retained selection when leaving swap mode, including
  an off-page selection. Source-hidden box tab hit buttons remain hidden.
  Move-list names use the source 250px single-line field; single-page lists
  hide their paging controls, and multi-page boundaries use the source down-
  state artwork instead of disabled up-state buttons. The selected detail
  tab is inactive. Escape/mode changes cannot retire live .5s swap targets.
  Source references: TopDownScreen, MinionStorageMenu/Selector and
  MinionDetailsMinionMovesObject. Focused in-memory headless checks pass for
  stage geometry, portrait baselines, selection continuity, guarded persisted
  party swaps and first/middle-page arrow states. The same focused fixture
  passes rendered; popup crossfade/input/keyboard handoff regression passes
  headless. Sandbox user-log/shader-cache warnings remain environmental.
  Player saves are untouched.
- Global menu-button audio integration: native artwork buttons now retain
  TCButton's menu_tickSound(.5) hover and menu_onPress(.65) click cues. Shared
  construction binds sounds before actions; adopted menu trees bind custom
  controls and newly rebuilt descendants once. Disabled/hidden hover and
  retired disabled controls cannot sound. Cues use the existing campaign audio
  controller/SFX bus, respecting Sound mute without new persistence paths.
  Custom Settings toggles/quality arrows use the same bindings. Dedicated
  merchant purchase/combine and other gameplay sounds remain separate.
  Focused checks pass for original stream IDs/volumes, one binding per control,
  rebuilt descendants, disabled/hidden hover, SFX mute and custom Settings
  controls. Popup crossfade/retired-input regression also passes. Fixtures
  do not write settings or player saves; audible user confirmation remains open.
- Global action-finish queue correction: BaseMoveSystem always queues .2s
  ApplyEffects plus .4s finishing time. Native presentation now retains that
  .6s deadline independently of whether HP/shield changes; full-health healing,
  zero/blocked damage and no-resource-change casts cannot hand off early.
  Multiple automatic charged casts in one response wait for the preceding
  visual/effect/modifier deadline before the next cost/cast is presented.
  Decision prompts, charge/status-skip feedback, round starts and completed-
  battle events use the same handoff gate instead of announcing future state
  over the current animation/finishing pause.
  This overlaps existing HP/cleanup waits rather than stacking a second pause.
  Rendered no-op healing and automatic action-isolation checks pass, as do
  grouped periodic boundaries and the broad 245-check runner. Shared behavior
  applies to the full tower and hard mode; full visual parity remains open.
  The follow-up decision-prompt assertion passes headless. Its initial rendered
  rerun exceeded a 20s process limit without a script error; the earlier
  rendered no-op/automatic-cast check passed before adding that assertion.
- Scope clarification (user, 2026-10-06): current work targets global original-
  game parity across the full standard tower, Grand Sage and hard mode. Floor
  7–10 modifier fixtures are regression samples, not implementation boundaries.
  The older persisted Floor-10 goal text is superseded by this expanded scope;
  no completion claim is made for the full game or its narrower earlier slice.
- Stat-callout queue integration: cast-time shared buff rolls produce ordered
  self buffs/debuffs then target buffs/debuffs, with allied recipients before
  enemies and original per-callout .1s leads where authored. Presentation waits
  for the attack/status queue, plays each stat callout with its .3s queue step,
  then applies gameplay effects. The final .8s artwork lifetime independently
  gates actor handoff. Gameplay stat events no longer repeat the artwork/audio.
  Shared mechanics apply across all floors/modes; complete parity remains open.
  Rendered stat-queue ordering, lead/step delays, grouped HP/stat application,
  duplicate suppression and final artwork cleanup pass. Broad runner passes
  245 checks. Global integration sweeps pass 101 later-floor battle setups
  (47 modifier encounters), 31 hard floor selections/151 bound battle rosters,
  and Grand Sage settlement/hard unlock/both atomic Titan rewards. These are
  content/setup/settlement checks, not complete battle or visual playthroughs.
- Cast-time stun/freeze/reflection queue integration: move_used snapshots the
  already-drawn shared condition rolls and each enemy recipient's pre-effect
  reflect state into visual_callouts. No additional RNG draws or reads of later
  engine state are needed. Buffered casts wait for attack m_moveTime-.1 before
  queuing stun, freeze then reflection, each with its source .8s wait. Unbuffered
  casts insert callouts directly after the attack visual and retain the final
  wait based on the last queued visual, as in BaseMoveSystem. Gameplay HP/status
  effects apply only after this sequence. Later condition/reflected-damage
  events retain state updates but no longer duplicate callouts/audio or add
  spurious post-effect callout waits. Reflection artwork now belongs above the
  reflecting target; reflected HP still applies to the attacker. Native rendered
  checks cover cast metadata, both buffer modes, ordering/waits, correct callout
  owner, grouped HP, no duplicates and cleanup. Broad 245-check runner passes.
  The 160-profile audio timeline and miss playback regressions also pass.
  Ten native floor-7–10 modifier fights pass with 131 legal actions and 21
  timer casts, including hidden-caster target VFX and presenter lead-in. The
  first combined replay exceeded a 40s runner limit; the bounded 100s rerun
  completed without changing gameplay durations or touching player saves.
  Stat-change callout placement is addressed by the later stat-queue entry
  above; full battle certification remains open.
- Miss queue/recipient restoration: BattleEngine resolves recipients before
  the source accuracy-roll bundle, including random-target misses. move_used
  and missed retain the same recipient IDs even though no target effects apply.
  Presentation queues native .8s miss artwork with the move's buffered or
  simultaneous behavior and one-visual-per-team rule; each source callout plays
  its whoosh once. Allied recipients retain their ordinary visual on failed
  accuracy, matching BaseMoveSystem's separate ally loop. The later missed event
  reports the outcome without duplicating the callout/audio, and retains the
  source .4s finishing queue. Rendered checks cover random miss recipients,
  both multi-target modes, single-per-team mode, no hit VFX/damage and cleanup.
  Selector fade completion now clears its own stale handoff deadline instead
  of leaving it set until the attack completes. Stun/freeze/reflection artwork
  and .8s fades match their recovered classes; insertion into the move queue is
  addressed by the later cast-time status entry above. Full parity remains open.
  After the selector correction, the broad 245-check runner and all-918-flags
  buffered queue regression pass; fixtures do not write player saves.
- Buffered multi-target queue restoration: the strict import already recovered
  visuals_have_buffer, but the Godot importer discarded it. MoveDefinition and
  the importer now retain the flag; all 155 simultaneous entries are explicitly
  migrated, while 763 buffered entries use the recovered true default. Native
  presentation runs buffered targets sequentially with each .1s lead and visual
  m_moveTime-.1 wait; simultaneous targets share one effects barrier. Source
  hit_each_target=false uses one visual per affected team while every target
  still receives its effects. ApplyEffects follows the complete sequence, so
  HP is not incorrectly staggered per cast. Visual cleanup/audio retain their
  instance lifetimes and the final cleanup tail still gates actor handoff.
  Rendered checks verify all 918 imported flags, buffered/simultaneous/single-
  per-team playback, grouped HP, seven-family cleanup and periodic round gates.
  Actor lunge now moves the whole minion view 20px toward the opposing team
  over .1s and returns over .1s, at each source MoveCurrentMinion queue step;
  timer stones without ordinary views do not lunge. Miss sequencing is handled
  by the later entry above; additional status queue steps remain open;
  this is not full battle certification.
- Source ApplyEffects queue boundary: ordinary casts now apply damage, healing
  and status feedback at recovered BaseMoveSystem's m_moveTime-.1 wait rather
  than the first object's physical impact callback. Sound callbacks retain their
  separate recovered cues. White-flash (0.3s) and earthquake (0.925s) casts also
  use this boundary; field shaking plays once and propagates its wait to every
  target and secondary-effect fallback. Seven native cleanup-family rendered
  checks pass with smooth HP application while the visual remains present;
  all 25 periodic profiles, grouped DOT/HOT playback and 160 audio profiles pass.
  The broad runner passes 245 checks with source-derived queue assertions.
  Buffered multi-target sequencing is addressed by the later entry above;
  additional status queues still require reconciliation. Full battle parity
  is not certified.
- Native visual cleanup-deadline batch: seven object families now use the
  recovered m_moveTime setters for instance cleanup and presentation duration,
  rather than preserving every sprite's longest tween. Source classes remove
  their visual/impact arrays at that deadline even when a tween callback would
  otherwise finish later. The shared dispatcher captures only that instance's
  created VFX nodes and removes any survivors at its absolute deadline; ground
  damage, health transitions and independently scheduled source audio remain
  separate. Simultaneous/staggered orbit, sampled falling delay, repeated
  pre-impact bounces and count-based .15s tails follow their source formulas.
  Native golden-profile checks cover all seven families' physical deadlines
  and concurrent-instance isolation. This is not a replacement for complete
  battle/HP-contact playthrough certification.
- Periodic visual-family dispatch batch: DOT/HOT application and ticks now use
  the same CreateMove/PlayMove-equivalent visual-instance dispatcher as direct
  attacks. Previously tick playback supported only burn/rise; application also
  supported orbit, but remaining families were replaced with generic fades.
  All 25 authored periodic visual IDs now retain their six native families:
  13 rise, 2 fall-onto, 3 burn, 2 fall-from-top, 4 orbit and 1 rotate. Target
  anchors work for hidden/retired casters, and falling visual/audio instances
  share the sampled profile instead of discarding the audio sample. Textureless
  screen/white-flash families use the common dispatch too. Simultaneous orbit
  entry no longer adds fictitious object-stagger time to the presentation gate.
  Native checks cover both application/tick paths for all authored IDs, family
  object counts, orbit contacts/lifetimes, hidden caster anchoring and cleanup.
  Rendered all-ID playback, grouped periodic timing/HP/indicator, 160-profile
  audio timeline and textureless fallback fixtures pass without touching saves.
  This covers the periodic dispatch gap, not full audiovisual certification of
  every complete battle.
- Panel-center/socket-overlay source correction: party and gem scale wrappers
  use source background-bound centers converted through the viewport scale,
  rather than the viewport midpoint. Their initial bitmap origins now match
  the authored pre-expansion positions while existing settled placement is
  retained. Settings, You, Pedia and storage correctly remain fade-only.
  GemMenu.BringIn explicitly adds a separate .3 black overlay when selecting
  a member socket; the earlier shared-shade suppression incorrectly removed
  this genuine source layer. It is now exempt from global-shade suppression,
  fades in/out over .5s, preserves its alpha/deadline across inventory rebuilds,
  and cancels its entrance before exit. Global .65 world dimming remains one
  shared layer; retained detail screens do not add duplicate global shades.
  Focused native checks cover source centers, authored starting positions,
  overlay intermediate/final alpha, rebuild continuity and exit. Rendered
  center/overlay, crossfade, gem/settings and room/menu presentation checks
  pass without touching saves; complete menu pixel parity remains open.
- Popup crossfade-handoff batch: switching shared exploration-menu pages keeps
  the outgoing canvas for its .5s exit/.1s cleanup while the next popup enters.
  Return signals now overlap those timelines instead of waiting for the old
  popup to disappear before constructing the new one. Outgoing buttons,
  focus, mouse and keyboard processing are disabled immediately; hover
  tooltips hide. Rapid navigation releases all retired canvases, and game-screen
  cleanup removes them immediately. Socket selection's explicitly retained
  details backdrop is not faded; progression presenter lifecycles remain
  separate. Native checks cover intermediate alpha for both popups, steady
  world opacity, Return, rapid changes, old-Settings Escape isolation, Resume
  recovery and screen cleanup. Rendered crossfade, Save, shared backdrop and
  gem/settings fixtures pass without touching player saves. The source Save
  lobby timing difference and complete rendered menu certification remain
  separate requirements.
- Shared exploration-menu backdrop batch: root, Save, Settings, You, Pedia,
  party, storage, gem selection and campaign talents use one source world shade
  below the dialog canvas. It fades to .65 over 1s, persists across pages and
  keeps its original opening deadline even when navigating mid-fade. Local
  input-blocking rectangles remain but no longer multiply opacity; rebuilt
  pages and retained socket-selection details are covered too. The genuine
  .3 socket-selection overlay is restored by the later correction above.
  Closing back
  to exploration starts the source 1s fade-out independently of the .6s popup
  cleanup; the tail ignores mouse input. Screen changes reset it. Root Resume
  now uses the shared source exit instead of disappearing immediately, and
  the root popup scales around its actual bitmap bounds. Focused native checks
  cover six-page continuity, early navigation, rebuilds, socket stacking,
  fade intervals, Resume/input recovery and cleanup without touching saves.
  Rendered backdrop, Save, gem/settings and lobby/HUD checks pass. Individual
  popup crossfades and complete visual certification remain open.
- Source Save-menu integration: the root menu's Save action now opens the
  recovered selection popup at (245,156), using original Save, Save/Return to
  Lobby, Cancel and saving-popup art. Lobby return has source GetHighestFloor
  >1 availability and .3 unavailable alpha. The saving cue fades in for .5s,
  waits .1s before persistence and closes after the source .1/.2s tail. Successful
  Save returns to exploration rather than reopening the root menu; Cancel
  returns to the root without writing. Popup scale transitions use its own
  center, not the fullscreen wrapper's center. Duplicate clicks and Escape/M
  cannot dismiss an in-flight save. Lobby entry/persistence remains atomic:
  rejected writes retain the old room and popup with an explicit retry message.
  The lobby room is presented after the successful closing transition rather
  than source's pre-save room switch, avoiding a premature visual/state change
  on rejected persistence. Focused native and rendered source-flow checks pass,
  along with campaign menu and lobby/HUD integration, without writes to player
  saves. Shared transitions stop an unfinished entrance before exiting, so
  immediate Cancel cannot fight the fade-out. Complete menu crossfades remain
  separate parity work.
- Minimap room-handoff batch: the shell retains its embedded map across HUD
  refreshes and same-floor room changes. The map follows MiniMap.EnteredNewRoom:
  group visibility, tint removal and authored scale update after .5s over .05s;
  the blue current-room tint follows at .55s over .05s. Floor changes rebuild
  the authored layout; lobby/map-lock transitions still remove the map.
  Repeated refreshes do not restart an unfinished room handoff. Embedded map
  pieces and their scaler ignore mouse input so the clickable background owns
  its open action instead of children blocking propagation. A ten-floor check
  covers 18 room entries, retained nodes, delayed highlights, group alpha,
  scale overrides and real viewport mouse input without touching player saves.
  Rendered ten-floor handoffs, actual shell HUD/map grant/lobby/merchant clicks,
  and campaign menu integration pass. This establishes the handoff lifecycle,
  not pixel certification of every map layout or complete floor playthroughs.
- Shared move/talent tooltip batch: descriptions follow recovered
  BaseMinionMove field order rather than imported combat-effect execution order.
  Paired self/target stat debuffs display one source `target/your` line, with
  orange debuff chances and green buff chances. Redirection replaces the normal
  description as in source. The type badge overlays the footer instead of
  adding a full extra layout row. Gameplay effect definitions are not reordered.
  Native party-card offsets/masks already match the source and were retained.
  Focused description/footer checks and rendered storage/Pedia, talent flow
  (75 passive stat descriptions), party/detail and Stars/HUD fixtures pass.
  These checks do not certify every menu or species portrait.
- Replacement event-handoff batch: native spawn events carry a copied
  spawn-time combatant record. Presentation retires the previous view and
  creates its replacement at that event, after the attack/death boundary,
  rather than waiting until the entire response has played. Subsequent timer/
  charged actions in that response can now find the replacement's target view.
  Spawn HP is not read from the engine's later damaged state. Original owned
  views remain retained for finish/XP restoration; duplicate entry is avoided.
- Sibling replacements enter together. CheckForWinLose's replacement handoff
  is 1s, distinct from the 1.9s opening entry: the minion fade finishes at 1s
  while teleport tails may continue. Native and legacy-event fallback paths
  use that source delay. A timer then retains its separate .7s cast lead-in.
- Timer/decision handoff events carry their historical turn order. Badge
  updates use that event's order rather than later engine state, including
  replacements inside an automatic event chain. Buff icons refresh from the
  presented roster immediately when a replacement appears. Projection consumes
  the spawn snapshot without mutating authoritative engine state.
- Evidence: native one-response lethal attack/replacement/timer playback covers
  old-view retention until the death tail, spawn-time HP, target VFX/DOT, source
  entry and timer gates, source order badges, no second entry, owned finish
  restoration and unchanged engine snapshots. Sibling native spawn events are
  grouped. Rendered handoff including the final source 1s timing passes, along
  with 245 checks, periodic source checks and ten native modifier fights.
  Complete animated fights and wider visual parity remain open.
- Hidden/retired modifier-caster batch: native target-anchored visual families
  no longer require a visible attacking minion. The timer BMod remains hidden,
  but its real selected targets receive the original animation and scheduled
  audio; only the non-native projectile fallback requires an attacker origin.
- Periodic effects resolve active, hidden timer and retired-original casters.
  Previously timer DOT/HOT and effects applied before replacement were silently
  removed at the tick boundary because the caster was not in the active roster.
  Recovered OwnedMinion arrays retain that caster reference. Archived original
  state and hidden timer state already survive engine snapshots; ticking now
  uses them rather than attributing the effect to a replacement or discarding it.
- Evidence: native_modifier_fights_smoke completes ten authored floor-7–10
  fights through AI/legal actions and real settlement (131 actions, 21 timer
  casts), exercising wins and losses without decision stalls or generic skips.
  It separately plays actual native timer target animations for all ten
  configurations and a complete timer event sequence with the .7s lead-in.
  Short fights ending before the first timer use a separately labelled fresh
  native cast probe, not a fabricated full-fight cast count. Dedicated periodic
  source checks cover hidden DOT/HOT, retired-original DOT, retained identity,
  snapshot/RNG reproduction and invalid-source handling. The rendered native
  fight/timer-sample run, 245 broader checks, original replacement finish/XP
  restoration and resurrection presentation regressions also pass.
  This is not an animated
  end-to-end playthrough of every full fight or all modifier combinations.
- Follow-up: replacement-spawn ordering inside automatic/timer event batches is
  corrected in the event-handoff batch above. Continue complete modifier
  combinations and campaign audiovisual/room/menu parity; do not reopen it from
  this older entry without a new discrepancy.
- Visual-owned battle audio batch: attack/DOT application and tick visuals now
  schedule their own main/secondary/impact cues. Damage/heal/shield/reflection
  and redirection events no longer manufacture impact sounds. Each target has
  its own source PlayMove instance and repeated objects retain their callbacks.
- Compared all five object-family callbacks against recovered visual classes:
  falling-from-top main/impact times share the exact sampled visual delay;
  rotate main sounds are simultaneous, not object-staggered; fade-down bounce
  sounds do not inherit descent spacing; rise shake sound timelines do not
  inherit sprite spacing; orbit hit sounds follow each object's movement.
  Hidden impact sprites still have source hit callbacks. Burn/fade-through/
  earthquake retain a single main cue per instance and no invented hit cue.
  TestVisualMove keeps its hard-coded thump with the flash, not a damage event.
- Freeze/stun repeated-turn badge playback now includes its recovered cue.
  Delayed sounds use absolute deadlines, guarding against early timer expiry
  on a slow import/shader frame. Inherited Burn cues/explicit overrides remain.
- Evidence: visual_audio_timeline_smoke covers literal source callback times,
  object/target counts, physical scheduling, no reflection/redirection repeats,
  shared audio/visual random sample, repeated freeze/stun cues, and available
  streams for all 160 authored profiles. Rendered timeline and starter Burn
  checks pass; source fallback, grouped periodic timing, and broader 245 checks
  pass. This is not certification of every complete battle's audible mix.
- Defeat-return lifecycle: loss settlement commits final owned resources and XP
  without moving to the checkpoint or resting the party before finish UI.
  LoseScreen.GotoTopDownScreen_part2 performs return/healing only after XP and
  the blackout; the shell now commits that separate transaction before fading
  back to exploration. Dead global providers therefore remain dead during loss
  stat/level presentation unless source XP health deltas revive them.
- Pending defeat return is saved with its battle ID and captured checkpoint.
  Runtime cold load completes only recovery, without re-awarding XP/results.
  Another battle cannot bypass that unfinished return. Recovery is idempotent,
  preserves the pending state on a rejected save, and uses source party-slot
  refill order. ReFillHealthAndEnergy clears stages before recalculation;
  world/trainer aura lifecycle remains distinct. Forfeit retains the source's
  immediate return/healing and does not grant XP.
- Evidence: native defeat/dead-provider finish stats, transaction rejection,
  saved interruption/runtime reload, duplicate delivery/return and immediate
  forfeit pass in defeat_return_lifecycle_smoke.gd. Broader 245 checks,
  finish-stat context and passive-persistence checks pass. Rendered shared
  entry/victory/forfeit/loss transitions also pass; these checks do not certify
  every battle's audiovisual parity or touch user saves.
- Finish-stat lifecycle batch: native result records carry stage values and
  trainer global bonus IDs. Settlement returns transient finish context so XP
  health deltas, level cards and campaign evolution use the stats still active
  before BattleScreen.DeActivate. Restored owned originals read their own retired
  stages, not temporary replacement stages. Sequence cancellation clears context.
- Source lifecycle distinction: DeActivate clears temporary stages, but
  DynamicData.GetGlobalPassiveMovesForPlayer still appends the current trainer's
  timer aura; TrainerSystem.LoadTrianer replaces that current trainer. Runtime
  trainer bonus IDs therefore survive room/menu transactions until the next
  trainer is prepared. CampaignState serialization excludes them from disk saves
  by default; its explicit runtime-copy mode preserves them across the session's
  39 transactional clones. Cold load resets the aura, matching unsaved source
  m_currTrainerData. Do not describe trainer auras as cleared with stat stages.
- Evidence: native timer-bonus/stage result, level-up HP delta and level-card
  content; original/replacement isolation; aura-versus-stage exploration stats;
  room transaction success/rejection, next plain trainer reset, cold-load reset,
  and cancelled-sequence cleanup pass. Broader 244 checks and passive persistence
  checks pass. This controlled victory fixture is not a complete animated fight.
- Follow-up: defeat/checkpoint timing and dead-provider finish ordering are
  corrected in the 2026-10-06 batch above. Continue audiovisual battle parity
  and complete modifier-fight playthroughs; do not reopen the settled lifecycle
  issue merely from this older finish-stat entry.

- Passive persistence batch: battle preparation preserves current health
  rather than clamping it to the unmodified base, and bounds initial energy
  using passive-aware maxima. Settlement first transfers all owned final
  health, then uses recorded native energy maxima (or passive-aware fallback
  for old/synthetic results). This keeps source health getter semantics and
  prevents fallback global providers depending on participant iteration order.
- Rest uses source slot-order passive-aware refill; a provider revived in an
  earlier slot contributes to later slots. XP health deltas now compare passive
  maxima at old/new levels. Campaign evolution receives party context, and HUD
  minion-card bars use the same passive-aware stats as their detailed pages.
- Evidence: passive persistence fixture covers rest/preparation, native transfer,
  final/dead-provider legacy caps, save round-trip/idempotence, ordered revival,
  XP health delta and rejected-save rollback. Broader 244 and passive/stat-stage
  checks pass; no disk saves are used by these fixtures.
- The later finish lifecycle batch above handles stage/timer aura distinction.
  Full animated finish presentation and defeat-rest timing remain separate.

- Passive/stat-stage batch: native campaign combatants carry fractional source
  stat values through setup, temporary construction and snapshots. Health casts
  after one stage multiplier; energy/speed/level-60 attack/healing cast after
  their squared stage and passive rates. Explicit extension setups without raw
  source values preserve their existing arithmetic.
- Party/storage stats and campaign level-up cards now include local learned
  passives and unique global move IDs from living party members. Highest learned
  family tiers are resolved before local/global aggregation; dead global
  providers stop contributing. Setup does not bake these rates in a second time.
  Standalone level cards created before sequence/catalog context retain their
  supported base/IV/gem display path.
- Evidence: 60 independent passive/stage cases check party display/battle
  agreement, duplicate living providers, defeated providers, final integer
  rounding, snapshot raw values and extension float preservation. Broader 244
  checks, 308 trainer setups, replacement/360 XP cases, gem/settings flow and
  rendered-node progression/finish fixtures pass without script errors.
- The previously pending permanent-passive rest/result/save and XP health-delta
  audit is implemented and covered by the later persistence batch above.

- Owned-stat arithmetic batch: party current stats now include saved IVs and
  preserve fractional base arithmetic until the final constructor/star cast.
  Energy gem bonuses are added inside the final 1.5 multiplier, as in source
  CalculateEnergyStat, rather than added to an already-rounded energy stat.
  Menu/stat consumers and campaign setup share the corrected owned_stats path.
  Evidence: 1,500 independent Calculate* comparisons across levels 1–60 and all
  five constructor bonuses, gem/star/IV combinations, plus production setup;
  gem/settings flow, replacement/360 XP cases and 244-check suite pass.
- Resolved the three broader-suite campaign assertions against source data:
  restored expert rooms make early room counts 14/11/10/12; Floor 1 room B has
  two numbered exits plus the source hard-only expert portal (99); source int
  money assigns 2, not 7/3. Updated checks retain the portal mode/destination
  and both door gates. No runtime routes were reverted to satisfy old counts.
  Native door checks pass 48 doors / 239 door-free rooms through Floor 30;
  ten-floor handoffs pass 33 standard trainers and 144 available room exits.

- Replacement stats/XP batch: source temporary minions now receive their
  constructor's fresh single-stat 5% bonus. Player replacements use saved star
  upgrades (4%/rank healing, 2%/rank other stats); enemy replacements use source
  floor/socket coefficients. Neither inherits the retired minion's IVs/gems.
  Current and level-60 power stats include these rates before integer casting.
  Source stat context travels with campaign setup and engine snapshots; passive
  maxima/refill still run after replacement construction. Explicit extension
  stat templates are unchanged.
- Source XP now rolls the Utility -1/0/+1 level-comparison adjustment once per
  party member on floors after the first, before halving/under-level bonuses.
  Pending battle identity seeds the roll so settlement retries stay identical.
  Hard authored-roster fallback now ignores ordinary trainer offsets, matching
  battle setup. Synthetic extension encounters retain non-jitter XP behavior.
- Evidence: native player/enemy replacement injection checks constructor bonus,
  star/floor scaling, power stats, passive refill and snapshot context; 360 XP
  awards cover first/later/hard floors, win/loss, every jitter and retry equality.
  Existing replacement/finish and all source trainer preparation checks pass.
- Historical broader run had three obsolete campaign assertions (241/244);
  source-backed rebaseline and the later 244/244 run are recorded above.

- Ordinary trainer preparation now uses the source level-budget talent builder
  rather than directly granting preferred move tiers. Each constructor receives
  its single random 5% stat bonus; source floor stat coefficients multiply usable
  species sockets (not locked sockets or invented equipment). Current stats and
  level-60 attack/healing power bases include those bonuses. Pending battle IDs
  seed construction so rebuilding/retrying the same encounter cannot reroll it.
  Explicit extension encounters retain their authored moves/stat preparation.
- Corrected the earlier hard-level assumption: TrainerSystem.LoadTrianer applies
  extraMinionLevels only below global floor 31. Hard resource metadata is retained,
  but resolved copies and direct hard setup ignore that ordinary trainer offset.
  Extra-minion modifier offsets remain separate and are not removed.
- Focused source-preparation evidence covers 308 encounters / 1,470 opponents,
  repeatable setup, talent budgets, hard effective levels and all 62 source floor
  coefficient rows parsed independently from StaticData assignment calls. This
  does not certify full animated fights or exact passive/stage rounding.

- Replacement-minion mechanics/finish batch: source extra-minion move arrays
  are preferences for Utility.AutoBuildMovesForMinion, not free grants. Native
  source replacements now retain initial moves, spend their level-based talent
  budget, select specialization/branches and follow the source preferred versus
  fallback/random dependency rules. Explicit extension stat/move templates are
  unchanged. Highest learned family tiers are used for battle actions/passives.
- Player replacement views now retain the defeated original while combat uses
  the temporary minion, then restore that original before XP/talents/evolution.
  Win/loss finish presentation fades combat interfaces/opponents over .3s and
  brings defeated owned minions back at half opacity after .4s. Delayed spawn
  tweens are cancelled so they cannot resurrect combat HUD over the XP screen.
- Native results identify retired participants and effective levels. XP now
  uses the actual final opponent roster after replacements, not the original
  encounter roster or the sum of originals plus retired replacements. Old or
  synthetic results without these fields retain the authored-roster fallback.
- Evidence: all 61 authored source replacement templates pass level-budget,
  starting-move and highest-family-tier checks. A controlled lethal native
  command exercises replacement, retained original view, finish fades/ghosts,
  XP presentation and final-roster experience. Combat snapshots stay unchanged
  by view restoration. All 101 later standard setups/47 modifier encounters,
  151 hard setups and the Grand Sage settlement checks pass. These checks do
  not establish complete animated modifier battles.
- Restored early hard/expert routes exposed five stale first-clear resources:
  normalized their rounded integer money bases, missing gem declarations and
  three expert AI profile references. The reward sweep now passes all 50
  room-bound Floor 1–10 records at money ranks 0/2, including rejected-save
  retry, duplicate settlement and rematches; 16 records grant gems.
- Remaining mechanic audit: defeat rest/checkpoint timing and full lifecycle,
  complete modifier battles and audible/visual contact timing. Replacement
  construction and XP formula checks are not complete battle certification.

- User playthrough on 2026-10-05 reached and defeated the Grass Sage; no
  additional issues were reported along that route beyond those below.
- Fixed missing standard map-giver interactions: BaseTopDownLevel makes
  HARD_TRAINER a Qui-tel map giver in standard mode throughout the tower.
  Catalog normalization now preserves the hard battle route and supplies the
  standard map route across all 24 applicable rooms, without duplicating the
  existing first-two-floor map interactions.
- Corrected integer currency semantics: source DynamicData.m_currMoney is int.
  Upgrade and normal first-clear awards truncate separately; chests and merchant
  transactions retain integer balances. Older fractional balances normalize on
  load, without rounding upward. Whole-coin labels no longer wrap float tails.
- Removed three repeated full room-graph/catalog rebuilds from battle startup.
  ensure_index reuses validation while pack/definition identities and graph
  paths stay unchanged; explicit rebuild_index remains available for edits.
- Restored inherited BaseBurnMove flamethrower audio (volume 0.4) for Burn,
  Intense Flame and Crazed, absent from the explicit SetSounds manifest. Explicit
  Flare Up/Wildfire/Hurricane cues retain their source overrides.
- Floor 31/Grand Sage now has its source room, roster and dialogue registered.
  Victory unlocks hard mode and immediately permits the atomic grant of both
  Titans, without a sponsor gate or an extra hard-mode victory requirement.
- Hard mode now registers all 31 floors and 151 source encounters, retaining
  authored offset metadata, modifier calls and hard-specific trainer dialogue.
  Ordinary trainer offsets are ignored at runtime in hard mode, as in source.
  Restored the first four source expert routes and the Floor 1 hard trainer;
  all 151 rosters are room-bound. Native interaction/preparation and synthetic
  sequential boss settlement pass; these are not full animated playthroughs.
- Source regional music was imported but never played by exploration. Room
  tile assignments and authored music/volume overrides now select the track;
  hallways retain the previous region, including older-save fallback. A shared
  persistent player handles exploration/battle/title music, retaining paused
  track positions and eliminating competing scene-owned background players.
- Battle music now starts after the source one-second spawn delay and fades
  up over six seconds. Long victory sequences restore it quietly after 6.4s;
  cancelled/finishing sequences cannot revive outgoing music. Short/skipped
  victory queues no longer wait additionally for the popup's close animation.
- Rendered entry/victory/forfeit/defeat handoff checks confirm the existing
  0.5s fade-out, 0.2s opaque hold and 0.5s reveal with input gating. Native
  music checks cover all 288 rooms and both modes' 31 regional fallbacks.
  This does not certify every battle's audible mix or every move sound.
- Hard trainer prompts and rematch ratings now look up the resolved hard
  encounter, not the already-cleared standard interaction's encounter ID.
  See GRAND_SAGE_HARD_TOWER_IMPLEMENTATION.md for the expanded handoff.

- Earlier scope expansion on 2026-10-05: fix Floors 7–8 routing, then
  finish the standard campaign through Floor 30. Floor 31/Grand Sage and
  hard-mode encounter conversion were separate from that initial expansion;
  their subsequent implementation is recorded above.
- Floors 7–8 routing: both expert layouts now match source ExpertRoom_fire;
  Floor 8 orders D before C and its trainer bindings move with source indices.
  Saved room/encounter identities were retained. Missing H4 hallways restored
  previously are retained. Source expert portals/interactions are hard-only,
  rather than enabling them accidentally in standard mode.
- Floors 11–30: 195 source room payloads/rows and 100 encounters now have
  live campaign/runtime registration, exact source room order, numbered and
  teleport exits (including the source telport typo), healstones, native egg
  pools, trainer dialogue and all parsed shield/timer/extra/resurrection calls.
  Importers emit apply_patch changes without editing saves or early content.
  Later-floor room bitmaps use the existing original-image fallback; the lack
  of a copied bitmap in art/rooms is not itself a missing rendered asset.
- Native replacement minions now derive stats/types/max attack/healing from
  their source species/level, select highest move tiers, inherit timer bonuses
  and refill final HP/energy. Explicit extension templates are unchanged.
- Sage families 3–6 now fuse before post-win dialogue, with four pieces for
  families 5/6, original medallions and source timing. All 100 later dialogue
  records are normalized, including Sage names. Fifth Sage raises the seal
  frontier and grants its one-time source tier-10 gem. Ordinary Floor 26–30
  gem declarations remain tier 5, matching StaticData (tier 6 begins Floor 31).
- Evidence: clean startup/catalog validation; 30-floor synthetic handoffs
  pass for 123 standard-mode trainer encounters and 470 exits, plus natural
  boss unlock/backfill progression through six seals. All 100 authored later
  battle setups pass, including 47 modifier encounters and replacement stats.
  These are not complete animated player playthroughs or pixel-parity proof.
  The expanded door check passes all 48 doors/234 door-free rooms, including
  Space contacts, key consumption, failed-save rollback and live portal use.
  A rendered representative check passes six later-region rooms, three
  teleport contacts, all six seal-fusion families, fifth-Sage tier-10 gem
  idempotence and later Sage dialogue. Test fixtures use in-memory states.
  Remaining work includes rendered later-floor feedback, complete battles with
  the new modifier combinations, new move presentation coverage, and any
  source mechanic/integration gaps exposed by those checks or user testing.

- First-clear reward correction (2026-10-05): COMPLETE for the current
  floor-1–10 room-bound records. Normal trainers grant one floor key; hard,
  expert and boss trainers grant one Eggery key. Generated Floor 7–9 normals
  previously omitted their floor keys, while generated hard trials granted
  the wrong key type and expert trials omitted Eggery keys. Source money is
  Math.round(7 * 1.25^floor), capped at 2000, before the normal one-third and
  money-star rank-squared one-sixth formulas; early fractional records and
  missing optional-trial money bases now agree with that rounded source.
  Hard/expert gem declarations specify one gem of source floor tier, matching
  actual settlement rather than the stale two-gem declaration on Floor 6.
  Generator reward emission was corrected, and a read-only patch emitter
  updates room-referenced resources without changing identities or saves.
  In-memory native settlement checks pass for all 45 room-bound records at
  money rank 0 and 2, one-time keys/gems/money, rejected-save retry, duplicate
  result and rematches. Four authored records are tower-mode gated: the
  fixture exercises their settlement contract through low-level preparation
  without changing their availability; it does not prove standard-mode entry
  to those trials. The broader battle fixture passes 244 checks. Door contact,
  rendered reward feedback and complete playthrough remain separate evidence.

- Trainer-family/level correction (2026-10-05): COMPLETE for the live Floor
  6 mapping. Its six encounters now use CreateFloor5/index 5, with the original
  30 minions, exact numeric move sequences, offsets and live room dialogue;
  source bindings cite index 5. Existing encounter IDs, interaction IDs and
  completion keys were retained. Incorrect Floor 6 timers were removed; the
  actual source timers remain on Floor 7. The boss is the first Passion Seal
  piece trial, not the second. No player saves were changed.
  Floors 7/8 generator bases were 19/22 instead of source 21/24, and team
  entries already included offsets before runtime applied them again. Content
  now stores base levels 21/24/33 for Floors 7/8/9 with separate offsets, and
  generator emission does the same. Extension/custom setup semantics are
  unchanged. Read-only patch emitter reuses the existing AS importer while
  applying edits through apply_patch, without regenerating unrelated rooms.
  A direct comparison against TrainerSystem/MinionDexID passes for all 25
  live Floor 6–10 encounters, 125 minions/raw move sequences, native runtime
  levels and Floor 6 room dialogues. It intentionally excludes unused legacy
  catalog encounters not referenced by standard_tower's current rooms.
  The ten real source-mapped timer fixture and 41-encounter/144-exit synthetic
  campaign handoff fixture pass. Rendered playthrough certification stays open.
- Historical reward finding, resolved by the first-clear batch above:
  later-floor generated NORMAL_TRAINER rewards omitted floor_keys, while hard
  trials granted the wrong key. Synthetic handoff traversal alone did not
  prove this economy; native settlement now has a dedicated coverage fixture.

- Timer-stone content coverage (2026-10-05): nine authored configurations had
  been omitted from the floor-7–9 conversion (two on Floor 7, four on Floor 8,
  three on Floor 9). Restored original timed moves, intervals, source power,
  native hidden casters and player bonus tiers: Sear/Inner Force, Ice Shield/
  Meteor Strike/Reflect Damage/Wildfire, Rainfall/Roar/Inner Force respectively.
  The generator now parses AddMod_MoveTimer for regular trainers as well as
  the Gym and emits native BMod definitions rather than a visible team minion
  as caster. It was patched without regenerating unrelated room content.
  At this point the fixture passed twelve registered timer encounters,
  including energy and reflection bonuses, snapshot persistence and .7s cast
  lead-in. This does not certify their trainer-to-floor source mapping.
- Historical finding, resolved by the trainer-family batch above:
  floor_6_room_graph.json and its six
  encounters cite/use CreateFloor6 (trainer table index 6), while source floor
  index 5 selects CreateFloor5. Floor 7 already uses CreateFloor6/index 6.
  Floor 6 then duplicated the next floor's trainer family. Corrected
  teams/dialogues/modifiers and their room bindings together while preserving
  public encounter IDs and saved completion keys. Do not regard the earlier
  timer checks or synthetic progression pass as proof this mapping is correct.
  Extra-minion and resurrection encounters occur beyond standard floor index
  9; do not expand those encounter conversions inside the floor-10 goal.

- Shield/resurrection stone batch (2026-10-05): initial shields are deferred
  until the source first-round boundary rather than appearing during entry.
  Team assignments now remove previously selected shields as well as adding
  new ones; .8s QuadOut movement/fades and the source 1s decision handoff apply
  to assignments and last-survivor removal. Absolute deadline waits recheck
  after slow frames instead of releasing the actor early. The authored shield
  rendered fixture passes. The old broad fixture omitted the team field on
  its synthetic shield event; it now supplies the engine's actual contract.
- Resurrection now clears periodic effects in the engine and clears both
  periodic effects and stat stages in the event-driven presentation, matching
  OwnedMinion.ClearBuffsAndDebuffs. Tombstones start transparent, use source
  .5s QuadOut fades, and countdown updates do not restart their entrance.
  Resurrection events are grouped after attack/death playback rather than
  showing tombstones at damage contact or staggering them per minion. New
  tombstone/revival transitions hold the source 1s decision boundary. The
  combined battle fixture passes 244 checks; the focused rendered playback
  fixture passes death separation, countdown, fades, effect clearing and
  revival handoff. These are focused checks, not full floor-1–10 certification.
  Fixtures do not modify player saves.

- Extra-move stone mechanics batch (2026-10-05): the three authored timer
  encounters (Floor 6 trainer, Floor 6 boss, Floor 10 Fire Sage) previously
  displayed their player passive bonuses without applying them, and created
  statless hidden casters using unrelated visible minion definitions. They now
  use the source BMod 2/3 definitions, first enemy's effective level including
  offsets, native type and current/level-60 combat stat bases. Explicit stats
  supplied by extension/test actors remain respected. Stone bonuses are stored
  separately from learned moves, apply once team-wide, persist independently
  of teammate deaths, stack with an identical learned global passive as in
  DynamicData, survive snapshots, and transfer to extra-minion replacements.
- Campaign activation refills HP/energy after final passive maxima are computed;
  increased HP no longer starts partly empty because pre-aura setup was healed.
  Ordinary engine setups retain their explicit current-health semantics.
  Timer visuals wait for the preceding move's tail, then observe the source
  .7s growing/spinning lead-in before the timer move, with the existing 3.3s
  icon animation still gating the next actor. Existing countdown pre-increment
  compensation was already correct and was retained. Focused authored checks
  cover health +15%, attack +15%, speed +20%, caster basis, stacking, death
  independence, snapshot preservation and cast lead-in. The broader 240-check
  fixture passed after correcting its contradictory intro-finished assertion:
  busy must stay TRUE until the final intro frame, while the selector is closed.
  No user saves are modified; full encounter visual certification remains open.

- Campaign/battle scene-transition batch (2026-10-05): trainer entry, victory,
  forfeit and the final defeat return now use ScreenController's original
  .5s fade to black, .2s opaque hold and .5s reveal. Entry initializes the
  hidden battle before fading exploration, so its spawn playback continues
  behind the curtain. The old scene stays until the opaque switch; movement,
  menu reopening and duplicate activations are blocked during handoff. Closing
  a dialogue cannot re-enable movement mid-transition. The loss message stays
  until its old scene is removed rather than disappearing .5s early. Existing
  loss blackout and Sage seal choreography are retained. Delayed third-key
  guidance and seal-completion dialogue also check room ID, not only the
  reusable room node. Actual scene checks pass for entry/forfeit/defeat in
  headless and rendered runs (entry and defeat reveal captures inspected),
  victory/rematch fade phases and stale callbacks, both seal returns, and
  result presentation. The ten-floor synthetic-result fixture still passes
  for 41 trainer encounters and 144 exits; it does not prove rendered combat
  parity for those encounters. Fixtures do not modify player saves.
  These changes close concrete transition gaps, not the
  broader rendered floor-1–10 or battle/menu parity certification.

- Exploration resume/context-guidance batch (2026-10-03): room restoration
  previously read death checkpoint coordinates without checking its room ID.
  Current exploration position/facing now lives separately in room_state's
  current_location, updated in memory while exploring and persisted by normal
  campaign saves. New game, authored room entry, floor selection and Lobby entry
  initialize it; defeat explicitly replaces it with the checkpoint. Reload only
  uses a location belonging to the current room, otherwise an authored spawn.
  JSON numeric coordinate pairs are supported by the shell. Room arrival spawn
  metadata is exposed on the room, and trainer victory returns retain facing.
- Native choose-a-move guidance now appears at source (306,33) after its .5s
  delay/.5s fade, exits with the selector and persists acknowledgement on the
  first move selection. Save rejection leaves the move unsubmitted and retryable.
  Added source key-keeper guidance at Floor 1 room index 11, late-floor tank tip
  after a loss above source floor index 7, and repeated-defeat talent-reset tips
  at two/five losses with original priority. Genuine losses increment the counter,
  victory resets it, and the first talent-reset acknowledgement clears it.
  Forfeits do not increment the loss counter. Contextual guidance is tied to
  its source room, waits for existing dialogues and restores movement on close.
  Original backgrounds/wording/art and moving tank illustration are reused.
  The healer trigger is beyond Floor 10 and is not claimed implemented here.
- In-memory actual-scene checks pass for cross-room checkpoint exclusion,
  JSON live-position/facing resume, unchanged checkpoint while moving, defeat
  return/counter, key-keeper presentation/input restoration, tank/reset priority,
  and move-guidance placement/acknowledgement/selector exit. These fixtures do
  not change player saves. Rendered comparisons and broader gameplay remain open.
- Battle-tip integration batch (2026-10-03): Energy now uses the original
  one-floor-key player-selector trigger; type effectiveness uses two keys and
  the acting Zapig definition, not arbitrary battle count/floor guesses. Both
  appear after the source .8s selector delay while move/target/forfeit actions
  are guarded, and restore the same decision after acknowledgement. The shared
  presenter uses the recovered large background, authored text/art/positions,
  Energy's mirrored moving arrow and fire-vs-plant example. The original hidden
  bigEnergyBar sprite stays hidden rather than adding an invented visible bar.
- Entry tips now follow the source one-tip priority: Battle Basics, the exact
  Floor 2 focus-target trigger, shield, extra moves, extra minions, resurrection.
  Modifier tips use their original stone/headstone assets and descriptions;
  extra-minion art keeps .8 scale. All six added tips persist acknowledgements
  and do not repeat. Campaign entry without a tip observes the source 3.2s
  start boundary; entry-tip dismissal includes the remaining .4s after its .5s
  exit, matching IntroTutFinished's .9s from OK. The focused in-memory fixture
  covers six actual tip constructions, modifier priority, large backgrounds,
  persistence, key/Zapig conditions and decision/forfeit guards/restoration.
  Existing early-tutorial, menu and timing regression checks remain separate;
  rendered parity remains open. Move guidance and in-scope loss tips are added
  in the follow-up above; other contextual source flows remain to audit.
- Early source tutorial batch (2026-10-03): first campaign battle now holds its
  initial decision behind the original Battle Basics / Turn order / Health Bar
  pages, using the source 3.5s intro boundary after spawn playback, native
  tutorial art, text/layout, animated arrows, Next/OK controls, .4s entrance,
  .5s page transitions/exit and whoosh. Floor 2 trainer-room 1 also triggers the
  source focus-target tip once. Space/Escape do not dismiss these tutorials or
  leak into target selection. Completion is persisted before battle resumes;
  rejected saves leave OK retryable and live campaign state unchanged.
- After the three-key reward dialogue, the source Minor Sage/boss-door guidance
  is scheduled at 2.8s. It waits for an existing room dialogue to close, cancels
  if the room changes or the keys have been consumed, blocks movement while
  shown and restores controls on dismissal. Native small background, bossDoor
  art and source wording are used. A focused actual-scene in-memory check
  covers first-battle decision gating, all three pages, double-Next prevention,
  save retry, the authored focus-target trigger, boss guidance and restored
  input. Campaign/save and battle-periodic regression checks are separate;
  rendered tutorial certification remains open. Energy/type/modifier follow-up
  is implemented above. Player saves were not altered by these fixtures.
- Optional-floor reveal batch (2026-10-03): new bonus-floor unlocks now persist
  a pending reveal marker. Floor selection opens on the source bonus reveal page
  with pre-insertion compressed geometry, shakes all tower tiles/mountains after
  1s, moves affected rows after 1.2s over 1.8s, reveals bonus information at
  3.2s, and presents the first bonus tutorial at 4.7s. Source earthquake/whoosh
  sounds are connected through the campaign audio controller. Original small
  tutorial background, bonusRooms bitmap, wording, OK button and .4s entrance/
  .5s exit are used, accounting for its visible-bounds center expansion.
  Floor selection, paging, mode changes and Return/Escape are guarded during
  reveal/tutorial. Acknowledgement is save-before-commit; failed saves leave
  the marker/tutorial intact and OK retries. Successful acknowledgement prevents
  replay; interruption before completion preserves the pending reveal.
  New zero-star standard floors also restore their delayed lock fade, cover
  collapse, unlock sound and number fade. The in-memory frontier fixture now
  exercises real reveal timing, intermediate insertion positions, input guards,
  original tutorial construction, rejected-save retry and reopening. Full
  rendered comparison and the broader source tutorial set remain open.
- Natural frontier/floor-selector batch (2026-10-03): selector activation now
  opens at the source unlocked-count page instead of page zero. Locked optional
  floors 4/9/14/19 are omitted and subsequent tower rows close their gaps.
  Information cards exist only for unlocked converted floors; unavailable later
  floors no longer add invented explanation text to the tower. Paging retains
  the existing screen/clouds and tweens rows, mountains and sky/stars for one
  second instead of rebuilding/snapping. Floor-number bitmap text retains .9
  source scale. Information text uses Flash insets without added shadow; full
  star counts color only the text, not the original star bitmap. Zero-star
  information cards use the source delayed horizontal reveal and moving New
  badge, including the currently selected floor.
- Frontier boss/Sage settlement now refreshes the six shop gems as source
  Utility.UnlockNextFloor does, before changing unlocks. Manual refresh and
  frontier refresh both use the source one-based highest-floor tier lookup.
  The extended in-memory handoff fixture follows natural floor selection,
  synthetic boss results and Lobby returns through 1/2/3/5/6/7/8/10, checks
  Floor 4's delayed backfill, Floor 9 remaining locked, both Sage seals, shop
  refreshes, revisiting Floor 1 and intermediate selector-scroll positions.
  Optional-floor insertion/shake/tutorial choreography is implemented in the
  follow-up above; rendered comparison remains open. Synthetic wins are not
  playthroughs.
- Ten-floor battle handoff follow-up (2026-10-03): CampaignSession now checks
  committed battle IDs before reading the pending encounter. Duplicate results
  after settlement, including delayed callbacks during a replay, return
  already_applied without touching rewards or the newer pending battle.
  Preparation and settlement share the validated save-before-commit path used
  by other campaign operations. The production-catalog in-memory fixture covers
  41 standard-mode trainer interactions and 144 authored room exits across all
  ten converted floors, including gate rejection/activation, preparation,
  settlement, replay cancellation, save rejection and duplicate/delayed results.
  Results are synthetic: this is handoff/content evidence, not battle-animation
  parity or a continuous floor-10 playthrough. Optional floors are explicitly
  unlocked for coverage; the separate frontier fixture above checks unlocks.
- Gems/Settings source-flow batch (2026-10-03): removed the invented minion
  dropdown, socket picker and stat summary from gem inventory. Main-menu Gems
  is inventory-only; a minion's socket opens its own equip overlay. The details
  screen remains visible underneath and cannot receive input. Equip/unequip
  close the overlay and restore the same party minion/Gems tab or storage box.
  Main-inventory Return returns to the menu; its close tab closes menus.
  No external sponsor links are activated; the recovered background is retained.
- GemSelector now supports the original 99 pages with wraparound, empty-slot
  moves, selection clearing after a move and 0.5-second same-page swap motion.
  Inventory positions are a separate sparse ID list, preserving the existing
  dense owned-gem registry. JSON reload retains holes. New gems fill available
  holes; equip replacement returns the old gem to the selected inventory slot.
  Slot moves and equipment updates remain save-before-commit; rejected saves
  leave the live state unchanged. Sort compacts the free inventory as source.
  Recovered source gem tooltip title, colored stat lines and above-pointer
  positioning now apply to inventory, equipped preview and merchants.
- Settings uses the source (148,56) origin on a source-scaled coordinate root,
  source white text/insets, no added text shadows or duplicate quality caption.
  Mirrored Previous keeps source x=207. Quality is bounded Low/Mid/High, with
  unavailable endpoint arrows hidden instead of cycling around.
- Shared merchant integration was updated for the source selector and tooltip:
  shop selection remains sale selection, combiner materials leave their grid
  positions empty, and selector origin remains (332,15), not socket-menu y=18.
  Removed the invented merchant close tab and matched BaseLargeGemMenu's direct
  screen origin; buy/sell/refresh labels use source 16px text.
- Merchant follow-up (2026-10-05): removed the added world shade; action captions
  now belong to their native buttons and inherit disabled alpha, with Flash
  insets/source white text. Combiner warnings use source positions (334,283)
  and (485,369), red 12px text and the original Combine($cost) caption. Occupied
  material/result sockets hide empty-socket art. Successful buy/combine/refresh
  and sell operations play source audio; failures are silent. Buying/combining
  inserts at the first free slot on or after the currently displayed page;
  full page tails reject atomically. Reset/Return restore held gems into earliest
  free slots, Reset returns to page one, selling resets its page, and stock
  refresh retains its selection. Preview materials remain owned until commit;
  duplicate material selections are rejected. Focused merchant fixture passes
  headless/GPU, including rejected-save preservation and Return with materials;
  existing gem/settings and menu integration checks pass. No player saves were
  touched. Rendered capture: development/merchant_combiner_current.png.
- Focused gem/settings flow and menu integration checks pass, covering sparse
  inventory persistence, save rejection, animated/cross-page moves, equip
  replacement, page wrapping, details backdrop and return tab, merchant dispatch
  and hover, Settings positions and endpoint bounds. No player saves/settings
  were modified by these fixtures. Rendered comparison remains open.
- Campaign/save fixture follow-up: its catalog assembled only Floors 1–5 while
  the current campaign definition references Floors 1–10. Added the same later
  floor room/trainer packs loaded by CampaignRuntime, retaining the complete
  reference-validation gate and adding an explicit ten-floor coverage check.
  This corrects the fixture's content scope; it does not certify playthroughs.
- Live exploration updates (2026-10-03): map-station rewards now use the source
  NPC dialogue and refresh the embedded map when it closes, with the original
  map sound; the room is not reloaded. Authored gated transition areas are now
  constructed even while their doors are locked. Both area-entry signals and
  per-tick contacts evaluate current progression, so opening a boss or Eggery
  door activates its portal in the same room instead of only removing a wall.
- Minion overview corrections: portrait frames now retain their native 66×66
  size (previously squeezed to 58×58); gem sockets retain native bitmap sizes
  and empty equipment IDs no longer display as filled sockets. Name/level text
  uses top alignment with the Flash text inset instead of vertical centering.
  Added the source pulsing unspent-talent reminder on each eligible row, and
  gem-selection guidance stops after the first successful gem equip.
  Follow-up screenshot exposed a missing nested center-expansion translation:
  nominal source panel (168,77) and row (39,45) coordinates are pre-animation,
  not their settled origins. Adjusted the panel origin and roster inset to
  (18,21) so cards retain 18px left/right padding and all five fit vertically.
  The details overview and rename/done controls share this corrected inset;
  the card no longer covers the XP strip. A GPU-rendered party fixture captured
  on October 3 confirms the current cards fit within the panel with balanced
  side margins; the user's earlier screenshot still shows the old (39,45)
  inset. Capture: development/party_menu_current_layout.png, reproducible via
  room_menu_presentation_parity_smoke.gd -- --capture-party. This confirms this
  overflow correction, not complete party/details presentation parity.
- Party details flow: selected roster card now slides upward over 0.5s while
  other cards fade over 0.3s; non-first details content enters after the source
  0.4s delay plus 0.1s fade lead-in. Return fades details before moving a
  non-first card back, with other rows reappearing after 0.3s. Input is blocked
  during these transitions. Tabs and move-page changes replace only the page,
  preserving the overview, rename controls and XP strip. Restored pulsing
  first-gem prompts, hid roster talent prompts during selection/details,
  applied Flash text insets and non-wrapping move names, and matched endpoint
  move-page arrow layers. GPU-rendered second-card flow and intermediate
  position checks pass; gem-overlay return regression passes. Details capture:
  development/party_menu_current_details.png. Full menu parity remains open.
- Talent-tree follow-up: exploration talent panels now share the party panel's
  settled origin and viewport scaling, source black 0.65 shade and close button.
  Restored 20px branch/specialization headings, top-aligned Flash text insets,
  and the source red warning's spent-points threshold (10, while node access
  still requires 11). Node desaturation now represents unmet tree-depth,
  prerequisite or specialization access independently of available points and
  maximum rank. Purchases remain gated. Refreshed modals release their old
  node name before rebuilding. Move tooltips use recovered moveDescription
  type artwork and auto-sized non-wrapping descriptions rather than the party
  type badges. New talent_tree_source_flow_smoke passes in headless and GPU
  runs, exercises specialization/branch/purchase/reset/close, and verifies all
  75 imported passive stat descriptions. Rendered captures:
  development/talent_specialization_current.png and talent_advanced_current.png.
- Evolution follow-up: replaced the generic centered modal/resized overlapped
  sprites with EvolvingPopup's recovered top-left art (9,5), native sprites
  foot-anchored at (96,169), new-form cover and old-form alpha mask (13,7),
  source close/message positions and base-species wording. One animation
  timeline delays motion/whoosh to 2s, plays level-up at 3.7s, translates both
  sprites by 173px over 2.5s, then holds completion for 1.5s and fades for 0.5s.
  Close cancels before evolution. Failed saves roll back species/name/HP/EP
  without updating the combatant; successful saves record Pedia seen/owned
  history while preserving live owned-minion references. Default names advance
  with the species, custom names remain; XP anchors refresh for evolved sprite
  height. Removed the unused generic evolution-frame helpers. Headless and GPU
  evolution_source_flow_smoke pass geometry, intermediate motion, sound timing,
  completion, cancel and rejected-save rollback; campaign keyboard and ten-floor
  handoff regressions pass. Rendered start/reveal/completion captures are under
  development/evolution_source_*.png. The rejection log is intentional fixture
  evidence, not a failure of the passing test. Full result-sequence parity and
  rendered floor-1–10 playthrough remain open.
- Stars/You menu: source panel origin (5,41), source-sized scaling root, 0.65
  menu shade, 20px information text, white source colors, centered information,
  40px available-stars text, native cost/rank positions and sizes. Upgrade groups
  occupy the authored rows y=182/292; all group elements dim together at 0.5
  when unaffordable. Those buttons remain hoverable for the source next-rank
  percentage explanation, while purchase remains gated. Removed invented
  upgrade-name captions, refund caption and successful-purchase/reset messages.
  Reset follow-up: real pointer clicks clear a purchased rank and refund stars,
  including after purchase rebuilds the screen. User confirmed their observed
  no-op was on a different save with no purchased upgrades, not a reset failure.
- Exploration HUD: recovered seal-piece drawer and family artwork, source
  piece counts and slide choreography; star counter now displays current-floor
  stars rather than globally spendable stars. Recovered pulsing tutorial art
  follows source talent > first gem > affordable star upgrade priority and
  hides while movement is blocked. First gem equip persists tutorial completion.
- Focused checks passed: room_contact_parity_smoke (locked and live-unlocked
  portals), lobby_hud_dialogue_parity_smoke (real map grant/dialogue completion
  without reload), room_menu_presentation_parity_smoke (native roster geometry,
  Stars layout/hover/color and HUD drawer/reminder states), and menu integration
  smoke. These are interaction/geometry checks, not a claim of complete visual
  parity; user playthrough remains the visual acceptance check.
- Battle: source health/shield easing and left-to-right experience fill were
  implemented in the previous batch. Health now animates the visible clipped
  fill directly; hidden progress-bar updates no longer reset its tween, and
  zero HP hides only after draining. Feedback starts at target contact while
  the remaining VFX lifetime continues to gate the next actor.
- Battle forfeits: separate from defeat; use the source 0.5-second music fade.
  Campaign returns directly; practice battles expose their restart controls.
- Talents: recovered tab strips, source node grid, dependency markers, point
  bubbles, and legal-choice gating. Canonical move icons and custom hover
  tooltips replace name guessing/native tooltips. Purchases refresh the tree
  while points remain; closing preserves unspent points.
  Corrected advanced unlocks to use row depth and points within that tree,
  not column number: all three starting branches can now receive the point.
  Added source reset control, locked-specialization explanation, browsing at
  zero points, remembered tabs, and battle entrance choreography. Save failures
  restore the pre-purchase moves and node ownership.
- Hatchery: rebuilt reveal/details and party replacement layouts from
  EggeryMinionDetailsObject and EggeryPartySwapMenu. Egg sink uses the source
  5.5-second motion. Full-party choices preserve owned minion state in storage.
  The details card uses the 171×169 recovered background, and the replacement
  screen uses the medium panel and five 323×76 overview rows.
  Direct source review found and corrected the egg-prefix collision: nest
  front/back pieces retain their own art, only numbered eggs resolve to the
  shared recovered egg bitmap. All nine eggs and eighteen nest pieces now
  construct. Reveal now shows player-positioned Inner Monologue and details
  together, with source wording, original Yes/No art and keep-before-party flow.
  The last pick waits for dialogue input. Replacement accepts the pending preview
  atomically, including Pedia; it no longer searches storage for an unowned egg.
  Movement is restored during sinking and late refreshes are guarded by room identity.
- Portraits: shared party overview rows now render the original-size minion
  at its authored icon offset behind the recovered alpha mask, replacing
  aspect-fitted thumbnails with incorrectly added offsets. Storage/Pedia
  portrait presentation still needs its own source comparison.
- Text: corrected dialogue, Eggery level and overview/move-list colors to
  source constants. Stat talent tooltips now name the stat and percent; stat
  stages show their actual percentage change and periodic values show totals.
  Remaining tooltip fields, type-icon placement and other screen colors remain open.
- Chests: immediate used/claimed state with a 0.3-second fade. Room remains
  alive and movement continues while the pickup effect plays. Source contact
  checks retry overlaps made while dialogue had controls disabled.
- Doors: transition contacts are retried while moving, so an entry signal
  ignored during a dialogue or room fade does not require leaving the trigger.
  Hidden source regularDoor markers no longer draw yellow rectangles; door
  collisions remain active. Hard-mode Eggery uses recovered six-lock artwork.
  HUD key count includes Eggery keys, matching source movement HUD logic.
- Gems: chest generation and saves exist; hard/expert first clears now award
  the source single gem using the shared random generator and floor tier table.
- Menus/HUD: recovered gameplay dropdown, embedded authored minimap, keys/stars,
  audio toggles, party overview and stats/moves/gems tabs, MinionPedia, Settings,
  and You/star upgrades now replace the empty/generic entry points. M/Escape
  opens the campaign menu; gameplay tab opens it by mouse.
- Gems: equipment/unequipment, inventory paging, sorting and swapping now exist.
  Owned gem bonuses are included in campaign/battle stats and progression cards.
- Stars: best encounter ratings, increasing purchase costs, resetting/refunding,
  stat/XP/money upgrades and movement-speed effects are implemented and saved.
- Settings: persistent independent sound/music, tips and quality controls; battle
  audio uses separate buses. New screens use recovered art/source geometry.
- Integration: six menu constructors and all three party detail tabs pass a
  focused in-memory smoke with no script errors. Source menu entrance/exit
  timing is wired for the campaign screens, including the Gem inventory zoom.
  User visual certification remains open.
- HUD regression: moved gameplay HUD into its own CanvasLayer so exploration
  cameras cannot move it with room art. Room-based menu integration is checked.
  Minions menu now uses the source medium 359×415 panel at (168,77), roster
  rows at panel-local (39,45+75*i), and an aspect-fit 700×525 coordinate root.
- Floor 6: ten payload-backed runtime rooms including Eggery and the scripted
  expert room, source trainer encounters and nine 40/40/20 egg slots added.
- Storage: source box strip, 20-slot grid, details tabs, swap/add-to-party flows
  and confirmation-gated release implemented; at least one party member remains.
- Gem economy: source tier/stat merging, buy/sell prices, persistent six-gem stock
  and free refresh implemented with save-before-commit session operations.
- Lobby: original standard-branch 439-object walking layout and service NPC contacts replace the
  temporary floor list. Crafter requires two seals; keeper requires extra minions.
  Source elevator opens the authored floor selector. Both Titans are granted
  directly without sponsor gating; tower-mode switching is implemented.
  Later floor content remains unconverted and mode parity remains open.
- Dialogue: replaced cumulative pixel-offset stops with whole wrapped-line
  windows; settled text shows two complete lines. User visual check remains open.
- Minimap: runtime now reads all 31 authored layouts (289 pieces) from an
  Inspector-editable resource, including groups, Eggery flags and scale overrides.
  This does not imply that all of those floors have playable content yet.
- Floors 7–9: trainer method/index mapping corrected from SetupLevels and literal
  AddTrainerToFloor arguments. Expert return destinations are derived from the
  actual unique teleporter host, not an assumed B room. This repairs the catalog
  error that prevented otherwise unrelated battles from starting.
- Results: victory background fade/child hierarchy corrected, XP direction fixed,
  and source world-space pickup feedback wired after campaign battle return.

## User-reported parity checks still open

Trainer/door/hatchery return follow-up (2026-10-03): normalized original
TrainerSystem dialogue for all 50 source trainer definitions at indices 0–9.
First-time victory restores the trainer's own source-positioned post-win
dialogue before world reward pickups. Rematches now offer the original Yes/No
choice, Retry-for-three-stars vs Replay-for-exp wording and Stars: n/3 label.
Source first-victory dialogue, optional rematch and both rating cases pass a
focused in-memory integration check; rendered visual certification remains open.

Door unlocks now disable the live wall, consume the source floor key ring,
fade actual locked art for one second and play the unlock sound without a room
reload. Already-open door and exhausted egg interactions no longer offer an
action. The original animated Space bitmap replaces generic interaction text.

User-reported hatchery-to-lobby trap: wallRect_eggeryExit had incorrectly been
treated as permanently solid. It now disappears when loading a completed
hatchery and disables in place when an egg choice completes. Before choosing,
contact shows the original "You still need to choose an egg!" dialogue. The
focused hatchery check covers live unlock, normal lobby routing and its
lobby_from_eggery destination, plus completed-room reloads across all eight
hatcheries in the floor-10 slice. No player saves are modified by these checks.
Post-battle queue follow-up (2026-10-03): restored source Space/Enter
advancement and Escape return. An XP skip completes the fill at its target;
a level-card skip still applies the next-level stat display and advances the
whole card rather than only its entrance. Talent, evolution and first-defeat
tutorial screens keep control of their own input and cannot be bypassed by
queue shortcuts. Skipping changes presentation only, not already-settled XP
or owned levels. Restored the source .5s XP-bar closing and 1.5s final music
fade during the one-second return wait. Normal progression presentation
(11 checks) and focused keyboard behavior both pass. Full rendered battle
results certification remains open.

Sage assembly follow-up (2026-10-03): original three-piece plant/fire families,
authored positions, white flash, convergence, medallion float/fade, .25-volume
level-up sound and 4.95s completion are now connected before the Sage's post-win
dialogue. Movement/Menu stay locked until that sequence reaches dialogue;
rematches do not replay it. Cancelled room changes cannot invoke stale dialogue.
Regular bosses now expose separate sage_seal_pieces feedback followed by their
key at 1.9s; completed Gym seals do not also float as individual pieces. Gym
rewards advance the total to their source family number rather than adding a
duplicate or assuming prior Gyms were cleared in order. Focused choreography
and actual shell-return integration checks cover both Floor 5 and Floor 10.

User-reported lobby/HUD/save follow-up (2026-10-03): embedded minimap root was
full-screen and intercepted Menu clicks. It now ignores mouse/focus outside
its actual clickable map area and does not handle Escape as a modal map.
Lobby entry removes the previous floor's map regardless of map_unlocked.
Actual injected mouse-click checks pass with the map present and after closing
both gem-shop and gem-combiner screens. Dialogue's clip origin moved up 2px;
the settled two-line window is measured from font height/leading/shadow so
second-line descenders fit at source dialogue scales. Pixel appearance still
requires user retest.

Confirmed saved-floor lock cause: JSON decodes indices to floats and Godot
Array membership is type-sensitive (0 not in [0.0], although 0 == 0.0).
CampaignState load now normalizes unlocked floor indices and both global and
per-room taken-egg slots to integer lists, preserving unlocked floors and
always retaining Standard Floor 1. The combined in-memory regression checks
JSON roundtrip, integer egg-slot membership, Floor 1/2 availability, Floor 3
remaining locked, and actual lobby-to-floor entry operations. No existing
player saves were edited or deleted.

Direct menus/exploration batch (2026-10-02): portrait import audit found 125
source icon-offset entries with no resource mismatches; Zapig's runtime bitmap
also matches the extracted original. Portraits retain native scale and source
offsets behind the original (8,8) alpha mask rather than generic centering.
Roster health/energy, party detail XP/stats and storage detail bars now share
the actual InterfaceBar alpha-mask/sliding-fill implementation, including cap
travel width. Fixed the rotated lower comparison arrow's width compensation,
rename input's current displayed name/source colors/size and hidden old label/
rename control, and clickable unlocked gem sockets. Removed added storage
text shadows. Talent icons, point bubbles and counts now share the original
.8s saturation/brightness transition; recovered ColorMatrixFilterPlugin uses
additive brightness (100*value-100), not intensity multiplication.

Healstone integration now restores the source stone glow, player-relative
rising crosses and healed bitmap with original lifetimes/positions and .2
sound volume. Movement stays enabled. A stone is consumed once per room load
only after healing/checkpoint persistence succeeds. All heal interactions use
automatic contact, including any graph missing that flag. Menu integration
and focused room/menu presentation checks pass using in-memory saves; the
focused check covers source icon offset, mask/fill geometry, compare arrow,
rename state, disabled talent uniforms, successful healing/save, animation
movement and consumed interaction. Headless checks do not certify GPU output
or all screens' rendered visual parity. The overall floor-10 goal stays open.

Direct hatchery investigation (2026-10-02): the live shell routes egg picks
through CampaignRoomView and CampaignEggeryPresenter. The focused check now
compares every egg/nest position against the actual authored room payload,
not just node counts: nine eggs and eighteen front/back nest pieces are present.
Original nest artwork hashes match the runtime copies. Remaining concrete
differences fixed in this follow-up: seven-frame fireplace and room-torch loops
at 15 fps; details card kept at source player-relative (87,-184) without extra
clamping; vertical layer-space egg sinking, source easing and single-use
animation guard; .25s full-party question delay; source selector text/button
placement, palette and .1s/.5s entrance/.5s exit; original sent-to-storage
confirmation. Egg completion no longer reconstructs the room, which could
interrupt a newer egg dialogue or restart another sinking egg. Talent title/
point colors now use source #ffea00, locked text #ed5e5e and node counts
#e5e5e5 at .95 scale; the non-source brown/gold tooltip override was removed.
No agents were used for this investigation. Rendered visual certification,
portrait alignment across all minions and remaining menu details stay open.

Room-contact follow-up (2026-10-02): chest rendering and claiming share one
seal/spawn policy (gold one seal/50%, gem four seals/30%), with a persistent
new-game seed. Contacts use actual chest bitmap transforms and source 100x300
door geometry. Space and portal contact refresh use current player geometry;
automatic claims retry after leaving/re-entering rather than every held tick.
The focused room-contact check passes without writes to player saves.

Battle timing follow-up (2026-10-02): RunTickMoves source comparison showed
DOT/HOT visuals are launched together and health begins at phase start. Runtime
now finishes the final attack before this phase, removes per-target contact
waits inside it, and gates the next round/automatic charged action on the full
effect lifetime plus source 0.5s buffer. Status-application VFX tails now also
gate actor handoff instead of using contact time alone. Net-zero HP events no
longer add a spurious bar-animation delay. Shield fills now use the same masked
sliding bitmap/0.6s tween as source health fills; buff hover frame/colors were
matched to BuffIcon.as. Focused playback check covers grouped starts, immediate
periodic HP transition, attack separation, hidden turn marker and intermediate
shield positions. Full battle visual parity is still not certified.

Direct follow-up batch (2026-10-02): storage portraits now use source 0.4
bitmap scale and foot-anchored grid positions, without added level labels.
Same-page swaps animate for 0.5 seconds, party-to-party swaps persist atomically,
and cross-box swap selection survives paging. Pedia uses the authored (5,13)
origin, 419px mask, original arrow controls/selection marker, native-sized
portraits and unknownMinion art, plus Found labels from campaign egg tables.
Shared move tooltips now include zero-amount chance effects, charge/exhaustion,
target counts, type art and passive armor/reflect/crit descriptions. Focused
runtime checks cover these properties; rendered visual certification remains
open. Source acquisition tables for unconverted later floors remain outside
the current floor-10 playable slice.

- Dialogue: verify Space advances exactly one rendered line and no partial
  lines are clipped at the bubble edges across source bubble scales.
- Battle: smooth damage/healing during their appropriate animation contact,
  move animation speed/duration, and no selector/turn indicator appearing early.
- Battle results: experience alignment, level-up presentation, defeat return,
  forfeit return, and all source first-clear reward feedback.
- Hatchery: details card placement, accepting/declining eggs, full-party swap,
  last-pick behavior, and unused eggs sinking out of view.
- Rooms: podium foreground layering, opening doors at close range, and eligible
  chest claiming without incorrect gem chest availability on early floors.
- Talents: specialization and advanced pages, hover appearance, disabled nodes,
  earned points, and correct move icons.

## Larger remaining port scope

All 31 standard floors and all 31 hard floors now have live registered content,
including the Grand Sage and all 151 room-bound hard rosters. Full rendered
battle/room fidelity, remaining menu parity, quests/tutorials, minimap visual
certification, complete storage/gem/shop parity, extension verification and
standalone release remain required. Content integration and synthetic checks
do not establish full parity or mark the overall goal complete.
