# Recovered mod integration status — 2026-10-06

Recovered data is not the same as a playable optional campaign. The current
gameplay scope centers on the standard and hard towers. Do not describe all
mods from the reference game as implemented.

| Reference addition | Packaged/registered data | Campaign integration |
| --- | --- | --- |
| Arkvian | Two Holy Bird minion definitions and presentation resources | No custom acquisition bindings in active campaign room/encounter definitions |
| Ophan | Three Holy Eye minion definitions and presentation resources | No custom acquisition bindings in active campaign room/encounter definitions |
| Stingaray | Two Water Ray minion definitions and presentation resources | No custom acquisition bindings in active campaign room/encounter definitions |
| Zanyu | Dirt Fish minion definition and presentation resource | No custom acquisition bindings in active campaign room/encounter definitions |
| Ice Floor | Twelve minion forms, recovered artwork, 30 constructed Ice move tiers | No registered playable Ice Floor campaign route |
| Mod selection | Pack mod-flag metadata, canonical Holy Bird typo aliases, saved `active_mods` field | No source-parity creation sidebar or active campaign toggle handling |
| Nuzlocke / No Regen / Infinite Tower | Reference source inventory | No corresponding gameplay toggle implementation in `src/` |

The recovered catalog is loaded by `src/application/campaign_runtime.gd`.
Its optional pack definitions remain in
`content/imported/recovered-20260911/catalog.tres`; custom minions have not been
removed by packaging cleanup. `active_mods` currently persists state only.
Reference source audits/imports mentioning Ice moves demonstrate recovery,
not floor routing, trainer integration, acquisition or end-to-end parity.

Future integration needs source-authored routes/rooms/trainers, the original
new-save mod selector, acquisition rules and per-save activation of applicable
rules. The Eevee test addition remains excluded as previously requested.
