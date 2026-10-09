# Mod integration status — 2026-10-09

The new-save character screen restores the original seven-option mod sidebar.
Settings belong to the save, not the process or shared content resources.
Existing saves are not automatically changed or given mods.

| Option | Current implementation |
| --- | --- |
| Zanyu | Dirt Fish acquisition in the source Floor 5-2 hatchery table |
| Stingaray | Water Ray acquisition in source Floors 1-3 and 3-1 |
| Arkvian | Holy Bird / Arkclaw acquisition in source Floors 1-4 and 4-2; legacy Holy Birb spelling translated |
| Ophan | Source hatchery branches in Floors 4-2 and 5-3, with the recovered later branch retained |
| Ice Floor | Twelve recovered forms and thirty move tiers remain registered; toggle exposes data in the Minionpedia and Flash imports retain these minions. No playable Ice Floor route is claimed. |
| Nuzlocke | Fainted active minions are retired after battle, including equipped gems. A non-playable memorial is retained. If the party is wiped, surviving storage minions fill it; an empty total roster ends the run and blocks further battles. |
| No Regen | Pre-battle preparation refills energy but preserves health. Explicit healing, defeat recovery and floor entry still restore health. |

The user confirmed Ice Floor was incomplete in the Flash releases. The
recovered lobby condition is inverted and IceFloorEntry invokes the ordinary
elevator. There is no recovered Ice Floor room/trainer chain. Inventing that
chain is a separate content-design task, not source parity.

The four acquisition mods use content/mods/source_egg_tables.json, generated
from recovered SetupTheEggeryInfo branches. Original integer conversion of
fractional weights and fallback to entry zero when weights total below 100
are retained. The missing DEX_ID_holy_eye_1 reference in an Ophan branch
resolves to Ophan. No room resource is mutated when selecting flags, and
Minionpedia acquisition hints use the same per-save tables as hatching.

Internal BMod trainer placeholders and the user's Eevee fixture are not
collectible mod minions. Infinite Tower is not one of the recovered menu's
seven options and remains unimplemented.

Flash import translates ModName through canonical flag mappings and retains
custom minions, learned moves and equipment. Unknown definitions or moves
reject the whole import instead of dropping data.

Focused validation covers flat AMF0/3 decoding, acquisition variants, No Regen,
Nuzlocke retirement, menu creation and empty-slot import. It is not a complete
campaign playthrough of every custom minion, evolution or move animation.
