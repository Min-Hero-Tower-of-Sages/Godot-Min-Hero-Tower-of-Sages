# Skill Gems mod

Enable **Settings → Mod Menu → Gameplay Tweaks → Skill Gems** in an existing
save, or use the Mod Menu when creating one. Changes save immediately.
It defaults to off and is stored per campaign as `active_mods.skill_gems`.
This is an Extended feature, not original-game parity.

## Acquisition

- On an existing field gem-chest find, one in eight rolls produces a skill
  gem instead of a stat gem. Skill ranks are capped at two. Existing chest
  locations, spawn chances and seal requirements still apply. The skill roll
  is stable for a chest/campaign, including after reload.
- The Hard Mode map trainer (Hard Sage) and extra trainer (Expert Sage)
  replace their first-clear stat-gem rewards with a random rank-three skill
  roll. Replays do not grant additional gems.
- Gem shops continue to sell stat gems. Skill gems can be sold there.
- Defeating the Talo Sage unlocks Random Forge instead of awarding the normal
  tier-ten stat gem. Saves that already have five seals qualify immediately.

## Equipment and battle

A skill gem occupies an ordinary gem socket and grants its referenced catalog
move while equipped. This includes active moves, local passives and party
passives. Party effects use the existing battle rules and stop when the holder
is defeated. Gems never add permanent learned moves, spend talent points, or
provide raw stat bonuses from their cosmetic colors. Party and storage move
pages, campaign battles, owned-party multiplayer setup and level-up stat
presentation use the effective move list.

Support-only skills that increase stats, armor, shielding, reflection,
redirection or critical chance can be equipped by any minion. Imported unused
enemy-effect entries on ally-only skills are ignored when deciding this.
Other skill gems are rejected when their move type is strong against the
minion's combined types, using the game's damage matchup table. This applies
to healing and energy skills too. For example, Falcona cannot equip Cern
Reaction. A resistance that cancels a weakness on a dual-type minion makes
that matchup neutral and permits equipping.

The highest rank of a move family is used if both learned moves and multiple
equipped gems supply it; copies do not add duplicate move-wheel entries.
Unequipping a gem restores the remaining learned/equipped rank. Evolution
rechecks compatibility. Disabling the mod preserves the gems and sockets but
suspends their skills; gems can still be removed and sold.

## Random Forge

The combiner has separate **Stat Gems** and **Random Forge** tabs and a
**Recipes** reference using the source menu artwork. Forge requires three
distinct unequipped stat gems of the same tier. Already-combined stat gems
are accepted; all nonzero colors in them contribute to the recipe.

| Input tiers | Requested skill rank |
| --- | --- |
| 1–3 | 1 |
| 4–5 | 2 |
| 6–7 | 3 |
| 8–9 | 4 |
| 10 | 5 |

One color maps to its original type: Red → Fire, Purple → Undead,
Orange → Dino, Yellow → Electric, Blue → Water. Electric's internal catalog
ID is `base:type/energy`.

| Color combination (any order) | Type |
| --- | --- |
| Red / Yellow / Blue | Plant |
| Red / Purple / Orange | Demonic |
| Red / Purple / Yellow | Earth |
| Red / Purple / Blue | Robot |
| Red / Orange / Blue | Normal |
| Purple / Orange / Yellow | Holy |
| Purple / Orange / Blue | Flying |
| Purple / Yellow / Blue | Titan |
| Orange / Yellow / Blue | Ice |

Other mixes produce a non-elemental stat-boosting skill. The recipe uses the
set of colors: mixed duplicates do not count as a single-color recipe. Four
or five colors also fall back to non-elemental stat skills.

The pool contains one candidate per available implemented move family of the
chosen type, using its highest existing rank at or below the requested rank.
Rank-limited skills such as Purge and Stun cap at their maximum supported rank.
The unconstructed/unavailable moves and Desperation are excluded. No new move
ranks are synthesized. All eligible families have the same selection weight.

Preview reveals the type and requested rank with a question-mark gem. The
actual skill is rolled on crafting and appears in the inventory and tooltip.
Skill gems display their move icon and actual rank. They cannot be used in
either crafting tab, including with other skill gems.

Forge uses the normal combination cost for the input tier (tier ten uses the
last supported cost). The operation uses the session's candidate-save
transaction, so save rejection, insufficient money, invalid material selection
or an unavailable inventory-page tail preserves materials and money.

## Validation

`tests/skill_gems_smoke.gd` covers the refined tier table, all color recipes,
combined-color inputs, rank-limited skills, deterministic field finds, both
Hard Mode reward types, Talo's vanilla/modded rewards, compatibility,
active battle use, aura lifetime, talent isolation, serialization, toggling,
unequipping/selling and transaction rejection/page placement. Rendered runs
write forge-preview, recipe-reference and result captures under ignored
`build/`. Fixtures use in-memory saves.

`tests/skill_gem_save_regression.gd` additionally exercises the production
`SaveRepository` against isolated files: forging across input tiers/colors,
ordinary combining/shop transactions with existing skill gems, equipment,
mod switches, JSON reload, both Hard Mode trainer rewards and exactly-once
battle settlement. Its failed-write case keeps the battle result on screen
with a Retry save action, then resumes only after the disk commit succeeds.
It also verifies recovery of the pending marker left by a v1.3.0 failed award.

This fixture requires `APPDATA` (Windows) or `XDG_DATA_HOME` (Linux) beneath
the project's `build/skill-gem-save-profile`. It refuses a player-save directory.
The in-memory skill-gem/mod fixtures also run the real save-shape validator.
