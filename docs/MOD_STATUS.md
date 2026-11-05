# Mod integration status — 2026-11-01

The new-save character screen and Settings → Mod Menu group recovered and Extended mod options
into Extra Minions, Challenge Rules, Experimental Content and Gameplay Tweaks.
Settings belong to the save, not the process or shared content resources.
Existing saves can opt in through Settings; loading alone does not enable mods.
See [SAVED_MODS.md](SAVED_MODS.md) for switching restrictions.

| Option | Current implementation |
| --- | --- |
| Zanyu | Dirt Fish acquisition in the source Floor 5-2 hatchery table |
| Stingaray | Water Ray acquisition in source Floors 1-3 and 3-1 |
| Arkvian | Holy Bird / Arkclaw acquisition in source Floors 1-4 and 4-2; legacy Holy Birb spelling translated |
| Ophan | Source hatchery branches in Floors 4-2 and 5-3, with the recovered later branch retained |
| Starter Eggs | Extended opt-in: Ticub and Zapig each have a 10% hatchery chance in Floor 1-1, including Hard Mode; ordinary candidates share the remaining 80%. Uses normal shiny rolls and Pedia acquisition hints. |
| Ice Floor | Twelve recovered forms and thirty move tiers. Ice Content opens Extended’s playable Ice Floor through the Side Hall, using recovered scenery with a new puzzle, Ice Sage battle and hatchery. Flash imports retain the Ice minions. |
| Nuzlocke | Fainted active minions are retired after battle, including equipped gems. A non-playable memorial is retained. If the party is wiped, surviving storage minions fill it; an empty total roster ends the run and blocks further battles. |
| No Regen | Pre-battle preparation refills energy but preserves health. Explicit healing, defeat recovery and floor entry still restore health. |
| Move Trees | Optional Martyr talents for Holymantis/Foramare and Righteous Fate for Arkvian/Arkclaw; see BEHAVIOR_EXCEPTIONS.md. |
| Skill Gems | Extended opt-in: equipped active/passive skills, rare field finds, Hard Sage/Expert Sage rewards and Random Forge after Talo. Non-elemental recipes include defensive support skills. See SKILL_GEMS.md. |
| Gem Affinity | Extended opt-in: matching-affinity gem stats gain 20%; Energy gems are added after base Energy scaling. Existing gear is recalculated and toggles do not refill HP/energy. See GEM_AFFINITY.md. |
| Shinies | 1-in-512 new-acquisition chance; saved, programmatic evolution-line palettes. See SHINY_PALETTES.md. |
| Debug Mode | Unlocks gated per-save settings and the explicit current-roster shiny action. See DEBUG_MODE.md. |

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
