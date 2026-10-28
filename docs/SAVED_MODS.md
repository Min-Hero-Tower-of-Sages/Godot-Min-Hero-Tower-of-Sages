# In-save mod switching

Open **Settings → Mod Menu** from a loaded campaign, including an imported
Flash save. It uses the same categories and grouped flags as new-save creation.
Edits save immediately. Debug Mode is not required to open the mod menu;
its separate debug-tools button still requires the Debug Mode mod.

| Mod | Can enable in a save? | Can disable? | Effect on existing content |
| --- | --- | --- | --- |
| Skill Gems | Yes | Yes | Gems/socket assignments remain; equipped skill grants are suspended while off. Re-enabling does not heal the party. |
| Shinies | Yes | Yes | Future rolls change; existing palettes and cached egg appearances remain. |
| No Regen | Yes | Yes | Future natural healing changes; toggling does not immediately restore HP. |
| Debug Mode | Yes | Yes | Debug toggles clear when switched. Granted levels, keys, upgrades and shiny appearances remain. |
| Zanyu, Stingaray, Arkvian, Ophan, Starter Eggs | Yes | Yes | Future hatchery choices change; existing minions, evolutions and recorded discoveries remain available. |
| Ice Content | Yes | Yes | Imported minions/moves remain usable. This still does not add a playable Ice Floor. |
| Move Trees | Yes | After resetting added talents | Reset purchased Martyr/Righteous Fate talents in party/storage first, so the tree does not hide spent points. Skill-gem grants are separate and do not lock this toggle. |
| Nuzlocke | Yes | No | One-way policy preserves the challenge once enabled. It applies from that point onward; it does not revise previous battles or restore lost minions. |

The Nuzlocke restriction is a deliberate challenge rule. Ordinary content mods
do not need permanent locking: the catalog keeps their definitions registered
when their acquisition flags are off. Move Trees has a conditional restriction
because its added nodes consume normal talent points.

The menu displays each rule and disables toggles that are currently unavailable.
It returns to Settings through Return, the close button, or Escape. Leaving the
mod menu rebuilds Settings, so enabling/disabling Debug Mode immediately changes
whether the debug-tools button appears.

## Save behavior

`CampaignSession.set_mod_option` edits a cloned candidate and commits it only
after saving succeeds. Save rejection leaves live flags, roster, inventory and
progress untouched. It refuses changes during a pending battle, checkpoint
return or unfinished egg preview. Imported saves with just a legacy child flag
enabled count as enabled groups, and a toggle updates every flag in that group.

Removing Skill Gems can reduce aura-based HP/energy maxima. Current values are
clamped to those maxima; enabling the mod later never fills the resulting gap.
Debug Mode switches clear its stored cheat toggles so enabling it cannot silently
reactivate a previous level/key cheat. Existing granted results are retained.

Minion-pedia continues to include registered mod minions in owned/seen history
after their acquisition mod is disabled. Internal trainer-only definitions remain
excluded from this history-based visibility rule.

## Validation

`tests/saved_mods_smoke.gd` exercises the actual candidate-save path with an
in-memory repository: enable/disable rules, grouped imported flags, rejected
saves, session reload, retained content/history, talent resets, debug toggle
clearing, skill-gem aura clamping, pending-action guards, menu navigation and
description bounds. Rendered runs capture Settings and the mod categories under
ignored `build/`; player saves are untouched.
