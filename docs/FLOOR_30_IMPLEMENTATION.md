# Standard campaign through Floor 30

User-expanded scope, 2026-10-05: correct Floors 7–8 routing, then finish the
standard campaign through Floor 30. Preserve existing saves and early fixes;
do not use agents. This document records that initial expansion. Floor 31 and
hard-mode content have subsequently been integrated; see
[Grand Sage and hard tower implementation](GRAND_SAGE_HARD_TOWER_IMPLEMENTATION.md).

## Implemented in this expansion

1. Source room mapping for Floors 7–8: original Fire expert layouts, Floor 8
   D/C order and source-index trainer bindings, preserved public identities.
2. Source-table importer for Floors 11–30: 195 room payloads, 100 encounters,
   explicit room order, paired numbered/teleport exits, source embedded Eggery
   ownership, base-only hatchery pools, healstones, dialogue and reward bases.
3. Registration in standard_tower and CampaignRuntime, keeping existing
   resources and save IDs. The runtime selects new floors through normal
   progression, not a debug unlock-all path.
4. All authored modifier calls represented: shield, timer, player/enemy extras
   and resurrection. Extra templates derive species/level stats, use the source
   level-budgeted talent autobuild with authored move preferences, inherit timer
   bonuses and refill effective HP/energy. Original owned views are restored
   before result progression; XP uses the final enemy roster after replacements.
5. Source teleport markers, including telport_ aliases, create actual movement
   contacts and play tower_teleport on room changes. Expert portals stay
   hard-mode-only, as in ExpertRoomTransitionObject.OnColl.
6. Sage families 3–6: original fusion medallions, three/four-piece layouts,
   post-win dialogue and names. Fifth Sage grants a one-time tier-10 gem when
   its seal advances the frontier. Existing native thresholds already match:
   combiner after seal 2; second hatchery pick after seal 3; gem chests after
   seal 4; third hatchery pick after seal 6.

## Remaining implementation/parity work

- Inspect actual full battles using the new extra/resurrection/timer/shield
  combinations, including replacement presentation and original-party cleanup
  at win/loss. Setup acceptance is not proof of complete action playback.
- Audit newly used move icons, source VFX/contact times and animation tails;
  fill any presentation gaps without changing source mechanics.
- Audit later-floor enemy-stat/difficulty formulas against source tables.
- Compare rendered room layering, source dialogue/HUD/map placement and regional
  audio during a representative playthrough. Fix concrete discrepancies rather
  than re-opening historical issues based on old screenshots.
- Audit source-only later tutorials/quests and any remaining Sage consequences.
- Keep the floor-30 implementation separate from Floor 31/Grand Sage, hard
  mode, standalone asset packaging and full-game visual certification.

## Evidence and its limits

- Startup/catalog validation passes with all registered floors.
- Native synthetic handoff coverage: 123 standard-mode trainer encounters,
  470 room exits; natural unlock/backfill progression reaches six Sage seals.
- All 100 later encounter battle setups pass; 47 have modifier configurations.
  Source replacements spawn with derived stats and full HP/energy.
- All 48 source doors pass contact, unlock, key consumption, failed-save
  rollback and portal use without reconstructing the room.
- Rendered representative coverage: six later-region rooms, three teleport
  contacts, six fusion families, fifth-Sage gem/idempotence and Sage dialogue.

These checks do not certify every rendered room or full animated battle. No
player saves were edited or deleted. Stop and run the game again to load the
new runtime pack registrations; existing campaign saves can be retained.

## Reusable conversion tools

- tools/standard_tower_source_plan.py reads source orders/methods/levels.
- tools/extend_standard_tower.py emits per-floor apply_patch groups; it never
  writes content or saves directly. --metadata-only excludes payload updates.
- tools/register_extended_tower.py emits one-time campaign/runtime registration
  after all new referenced resources exist; it refuses duplicate registration.
- tools/extend_source_trainer_dialogue.py adds later entries while preserving
  existing early dialogue.
