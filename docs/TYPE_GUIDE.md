# Type Guide and battle matchup hints

The Type Guide is an Extended UI addition, not recovered Flash artwork or a
change to the battle rules. It reuses the original stone frame, dark menu inset,
font, type badges and menu sounds.

## Using it

- In battle, click **Type Guide** next to the audio buttons, or press **T** while
  choosing a move or its targets. Close with Return, X, Escape or T. A pending
  target selection is preserved. Opening the guide does not pause the engine,
  multiplayer peers; if battle playback begins, it closes. The replay transport
  controls are left unchanged rather than placing a guide button over them.
- Outside battle, open **Menu → Minion-pedia → Type Guide**. Returning preserves
  the Pedia selection and scroll position. The entry sits above the portrait;
  the Pedia frame is hidden while the nested guide owns the screen.
- Select the **move's type**, then Damage or Healing. The guide lists the
  stronger and weaker matchups; unlisted types are neutral. It reads the live
  catalog's type chart, including registered mod types such as Thaw.
- **Settings → Type Hints** enables/disables the battle previews. It defaults
  on and is stored with the other application settings, not per save.

## Battle previews

Hovering a usable move shows a compact chip pinned to each legal target's health
bar: **↑ ×1.5** for a bonus, **↓ ×0.67** for resistance, and **?** for an unknown
matchup. Neutral matchups add no badge. Typed healing includes a **♥** marker.
Chips remain while manually choosing targets and disappear when the move
begins, is cancelled, or no longer has a valid local decision. They cannot
intercept target clicks. Arrows and numeric multipliers distinguish matchups
without depending on green/amber colors alone. A chip never relocates across
the battlefield to avoid a tooltip: it belongs to its target's health bar.

An unfamiliar enemy shows **?** rather than leaking its types.
This follows the battle inspector's existing previously-seen rule, including
not revealing an enemy first added to the Pedia by the current encounter.
Friendly target previews do not need discovery. Only actual typed damage,
healing and periodic payloads receive hints: shields, stat changes, energy
restoration and other untyped utility are not labelled as attacks.

These labels show the **type multiplier**, not predicted damage/healing or a
guarantee of an effect landing. They do not include same-type bonuses,
statistics, buffs, armor, shields, accuracy, critical hits or random rolls.

## Calculation and implementation

`TypeChartDefinition.combined_multiplier()` is shared with battle execution.
Its classic strong/resisted factors are 1.5 and 2/3. Defender types multiply,
so two weaknesses yield 2.25, two resistances approximately 0.44, and one of
each cancels to 1. Healing reverses each individual matchup before multiplying.
Display rounding is two decimal places, never used to calculate the result.
Same-type matchups are included: a Fire move against a Fire-type enemy is
resisted. That does not mean the move targets its own caster.

- `src/presentation/type_effectiveness_preview.gd`: side-effect-free effect
  filtering, matchup calculation and captions.
- `src/presentation/type_guide_view.gd`: reusable catalog-driven modal.
- `src/presentation/main.gd`: move-hover/target lifecycle, display-team mapping
  for mirrored multiplayer, discovery gate and non-intercepting label layout.
- `src/application/campaign_settings_service.gd`: persisted hint preference.

The focused `tests/type_guide_smoke.gd` fixture covers single/dual types,
healing, DOT and untyped effects, discovery, hover/target cleanup, mirrored
team data, opening/closing both entry points, frame bounds and settings
persistence. Rendered runs write previews under ignored `build/` output.

```powershell
godot --headless --path . --script res://tests/type_guide_smoke.gd
```
