# Current limitations

- The reference SWFs contain no nested battle-move timelines. Their 16
  ActionScript tween implementations are inventoried; nine now have source-
  derived Godot presentation families. Profiles cover 160 visual IDs across
  rotate, falling, rise-out, orbit-in, burn, fade-through-target, and
  source-timed screen-shake plus TestVisualMove white-flash families. The
  no-texture fallback now restores the source 0.2-second fade-in/fade-out for
  Group Reflect, Taunt, and Titan Restore, including its unbound hard-coded
  `battle_hit_thump_splat` sound. Earthquake, Destabilize, and Stonequake
  preserve their source intensity, shake counts, distances, and movement-time
  formula rather than falling through to a missing-texture projectile. Other
  profiles include Claw, Spike, Pound, Burn, Fire Blast, Mud Blast, Spark,
  Slow, Tackle, and Refreshing Wave. The target-rise and orbit families span 56 used
  visual IDs and 229 constructed move tiers. Nine ActionScript presentation
  families are represented; fall-onto-target now reproduces its configured bounce,
  per-object stagger, optional impact burst, and first-contact HP timing;
  fall-from-top and rotate-into-target now restore their source impact cadence,
  scale, and visibility overrides. The four recovered ground-crack overlays now
  appear under hit targets for fade-through, burn, fall-onto/fall-from-top, and
  orbit/rotate animations with their source offsets, side mirroring, and fade-in.
  Other family-specific choreography and the remaining tween implementations
  are still simplified. The
  78 recovered battle sounds are packaged
  and the source visual-sound mapping is wired, but playback timing is still
  approximate.
- Charging, frozen, stunned, exhausted, and stat-stage feedback now use their
  recovered source badges. They replay the 0.2-second fade-in, 0.4-second hold,
  0.2-second fade-out, and 50-pixel rise; frozen/stunned artwork is packaged by
  exact recovered `SpriteHandler` symbol identity.
- Battle entry, extra-minion entry, and resurrection now use the seven recovered
  teleport-piece sprites. Their 51-degree radial scatter, 80-pixel inward move,
  staggered fade, delayed minion fade-in, and delayed health/interface fade-in
  follow the source choreography. Resurrection now has the recovered tombstone
  and countdown text, updated from engine progress events and faded on revive.
  Per-minion battle-mod shields use the recovered sprite, state, and
  assignment/removal events with the source rise/fade timing. Configured global
  shield and resurrection modifiers now use recovered stone assets, source
  placement, and shield-count visibility. The global move-timer and extra-minion
  panels use recovered artwork and source positions; the timer counts down from
  engine state and animates on its trigger, while extra-minion counts/icons update
  from replacement events and replacement minions use the recovered entry effect.
  Campaign-owned modifier configuration and tutorials remain missing or simplified.
- All 181 move-icon names used by maintained move Resources now have packaged
  PNGs, and class-aliased visuals resolve by move class. This does not imply
  every move's full ActionScript animation is ported. End-of-round Burn and
  Poison Tooth DOT visuals, Poison Tooth's on-application poison drops, and the
  source Missed popup now render; periodic tick effectiveness is carried into
  super/not-effective feedback. Other periodic effects with no texture and
  exact choreography remain incomplete.
- The playable battle now draws five combatants per side in the recovered arena
  formation. Its fixed level-25 test roster uses Raptor, Fire Frog, Healing
  Horse, Ice Tree, and Griffen, with extra moves to exercise multi-target,
  healing-over-time, and ally-shield behavior. Party/save-derived setup and the
  trainer's real floor-level adjustment are not connected to the practice path.
- Battle controls work, including direct sprite hit-testing for target choice
  and Desperation as a UI fallback when no ordinary move is currently legal.
  The selector now uses recovered module, energy-bar, out-of-energy, and back
  artwork at the source coordinates relative to the active minion. A separate
  cooldown warning avoids claiming the minion is out of energy when its moves
  are simply cooling down; this wording intentionally differs from the source.
  Learned moves stay visible at 30% opacity when unusable, with a white progress
  overlay for cooldowns, matching the source selector. Target mode dims non-legal combatants and highlights
  legal ones with the source 0.5-second dim/fade timing, and one-target moves
  submit on the sprite click. The turn marker uses the source 0.3-second fade
  and presentation waits for it to clear before the next actor is indicated. The move panel
  now fans in/out with the recovered button stagger and delayed panel fade; the
  shared presenter waits for the outro before exposing the next decision. Battle
  entry holds the selector closed until the recovered teleport-in finishes.
  Move hover uses
  a source-styled custom popup, though its content and layout are not yet exact.
  Forfeit now uses the recovered confirmation-box assets. Some label geometry
  and hover content remain approximate.
- In-battle buff icons now show deduplicated living-team global passives plus
  each living minion's active periodic damage/healing effects. They use the
  recovered half-size side placement and hover text for DOT/HOT, stat, armor,
  critical, reflect, and redirection effects.
- Damage now uses the original super-effective, not-effective, critical, and
  redirection popup artwork with a consistent top-left positioning origin so
  each callout centers above its minion; positive heals show a green recovered-HP number. Drain applies
  its source-ordered actor self-heal after damaging targets. Campaign results
  now show source-art XP bars and level/stat cards in party order, with saved XP
  driving the fill and source health-stat gain applied to persistent HP.
  Interactive talent allocation/evolution choices, campaign-derived
  battle-modifier setup, tutorials, and the full defeat aftermath are still
  missing or simplified. Victory now shows the recovered source card and stars using the
  source party-loss thresholds and popup timing. Defeat now follows the source
  blackout/message cadence. Campaign battles now route victory/defeat through
  result settlement, reward/save, and return/heal behavior; the separate practice
  route still ends at its local restart panel. Interactive talent/evolution
  decisions, campaign-derived modifier configuration, tutorials, and the larger
  death choreography remain incomplete.
- The 61,211-row reference manifest is a provenance/reachability inventory, not
  61,211 items that must be rewritten as gameplay code. It describes broad
  source coverage while substantial Godot migration remains.
- The campaign now has an end-to-end four-room vertical slice: title/slot/new-
  character flow; Entry Hallway, Courtyard, H0 and A room rendering; 30 Hz source
  movement, player collision, source foreground layering, and transition/trainer
  interaction; campaign-owned party and trainer-level battle setup; result save,
  first-clear rewards, and room return. The four scenes use source-backed payloads
  and 81 shared room sprites; male/female player art includes all 60 walking
  frames. This does not convert the remaining 245 of 249 room payloads, most
  interactable behavior, campaign dialogue/tutorial/menu flows, or the full
  progression path; the campaign gate remains open.
- The headless combat core implements recovered representative mechanics and
  trainer-difficulty scoring. Typed battle results expose each participant's
  outcome and remaining health/energy. Campaign battles now build from saved
  owned minions and call result settlement/save/return; the separate practice
  route intentionally keeps its fixed showcase party. XP bars and per-level
  stat cards now play after campaign battles; talent/evolution decisions and
  broader source-derived golden fixtures remain unfinished.
- Menus, room interactables, audio playback, and rule/mode behavior have source
  audits, but those audits do not mean the complete Godot runtime integrations
  exist.
- The Windows preset, templates, and executable have been verified in the
  sandboxed environment. A clean desktop launch outside that environment and
  final release verification remain.
- Extension verification and a complete standalone campaign release are not
  complete.
