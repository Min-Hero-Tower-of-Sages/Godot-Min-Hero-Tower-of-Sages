# Gated campaign debug options

Enable **Gameplay Tweaks → Debug Mode** when creating a save. Only campaigns
with the `debug_mode` mod flag expose **Settings → Debug Mode**. The debug
effects are also checked against this gate, not merely hidden in the UI.
All five settings begin off and are saved per campaign in `debug_options`.

- **Unlimited Money**: gem purchases and combining are free; the actual balance
  is preserved and normal charging resumes when disabled. Money displays read
  Unlimited while active. It does not bypass inventory capacity or gem rules.
- **Max Party Levels**: raises active party minions to level 60, supplies their
  normal experience/talent-point entitlement and refills health/energy. While
  enabled, newly added party members are also raised when saved. It does not
  increase party size, auto-evolve or choose talents. Granted levels remain
  after disabling; stored minions are untouched until added to the party.
- **100% Shiny**: guarantees shiny identity for newly acquired minions, even
  with the regular Shinies mod disabled. Existing minions are not recolored.
  This debug override can supersede a previously cached non-shiny egg roll.
- **Unlimited Stars**: upgrades are free without changing earned trainer stars.
  Free purchases are tracked so disabling the option does not retroactively
  debit your earned stars. Upgrades remain until Reset; Reset clears the free
  purchase accounting too. Normal star prices resume when disabled.
- **Full Keys**: tops up floor keys to at least three and hatchery keys to at
  least one in Standard Mode, or three in Hard Mode. Saving floor entry or a
  door unlock replenishes supplies while enabled. It does not grant sage seals
  or complete trainers. Disabling stops replenishment but does not remove keys
  already granted.

Option changes use the normal candidate/save/commit transaction. Rejected saves
leave live flags, levels and resources unchanged. Options cannot be changed
during a pending battle. Disabling the Debug Mode gate makes saved debug option
flags inactive. Old saves/imports without this mod do not expose the menu.

`tests/campaign_debug_smoke.gd` checks gating, save rejection, persistent flags,
level changes, money charging, forced acquisitions and the rendered UI using an
in-memory save repository and isolated application settings.
