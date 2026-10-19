# Programmatic shiny palette assignments

The appearance system covers all 122 playable recovered minion forms,
grouped into 62 evolution lines, including modded/Ice minions and both Titans.
Internal battle stones and the excluded Eevee fixture are not assigned.

`content/base/palettes/shiny_palettes.json` stores one named palette and shader
settings per line, plus the member-to-line lookup. Three Luna design passes
proposed the palettes from original contact sheets; the main pass rendered and
corrected weak colors, misleading names and frozen/thawed-stage inconsistencies.
The approved Ticub blue, fire-pig violet and Arkvian teal remain unchanged.

No replacement artwork is generated. `minion_palette.gdshader` recolors the
existing texture/frame, with hue rotation or fixed target hue, optional
saturation/brightness adjustment, and opt-in tinting of neutral midtones.
Bright whites, dark outlines and alpha are protected. Battle status transforms
are applied after the palette transform. Palettes cannot distinguish different
body parts that share the same source colors.

`MinionPaletteService` resolves known line settings and supplies a deterministic
hue-rotation fallback for future models. Evolution links determine a new line's
root. Generic fallback colors are automatic, not artist-reviewed; purely neutral
art may need an authored midtone tint. Materials are separate per instance so
status changes cannot affect another minion. Gameplay wiring covers battle
sprites/condition tints, party/detail portraits, storage grid portraits,
hatchery reveals and evolution portraits. Battle appearance fields persist in
combatant snapshots, replay restoration and multiplayer combatant dictionaries.
The species encyclopedia intentionally shows the ordinary species artwork.

Run Godot rendered with `--script res://tools/preview_shiny_roster.gd` for
original contact sheets, or add `-- --selected` for the six assignment sheets.
Outputs go to the ignored `build/shiny-palettes/` directory. The sheets are
preview artifacts only; games reuse the original sprite assets and JSON data.

## Gameplay Tweaks option

The new-save mod menu has a Gameplay Tweaks category with three toggles:
Move Trees enables both restored skill additions; Shinies enables a 1-in-512
chance on new starters, hatchery minions and Titan rewards. Debug Mode unlocks
the gated debug menu in Settings (see DEBUG_MODE.md). All are default-off.
Owned minions save `is_shiny` and `shiny_line_id`; old saves and Flash imports
default to ordinary appearances. Loading, rendering and evolution never roll.
Shiny identity survives the ordinary talent reset and evolution paths.

Hatchery shiny chances are cached per egg slot for the current floor visit,
persisted alongside preview reservation. Interrupted reveals restore the egg
allowance but retain its shiny result. Starting a fresh floor visit clears the
slot cache. Existing minions are never retroactively randomized. Authored enemy
teams remain normal unless their setup explicitly supplies a shiny identity.

Cerberus uses Ashen Crimson: cool ash-gray midtones and crimson warm accents,
with separate neutral hue/saturation/value controls to keep its body visibly
different. No new artwork is required.
