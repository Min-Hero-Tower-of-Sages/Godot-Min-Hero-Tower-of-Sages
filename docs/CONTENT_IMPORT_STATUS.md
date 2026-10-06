# Content import status — 2026-09-11

## Accepted recovery inputs

- 16 logical types: 15 base constants plus Ice Floor's dynamic Thaw type.
- 923 declared move identities: 893 static tier constants and 30 dynamically
  registered Ice Floor tiers. These are identity/reference records only; move
  values and effects are not yet accepted.
- 167 talent trees normalized into 1,634 explicit nodes, 3,374 ordered move
  references, and 598 nodes with previous-row prerequisites.
- 125 parsed minions: 102 base, 20 player-facing mod minions, and three internal
  battle-mod fixtures.
- 62 explicit stage-to-stage evolution links.
- One classic type chart containing 83 unique non-neutral pairs recovered from
  89 assignments, including all five Ice Floor Thaw defenses. The six duplicate
  Demonic assignments are accepted only because their values agree.

Every parsed field retains a source file and line. The parser accepts only
integers, quoted strings, named constants, and the three explicit dynamic lookup
forms. Unknown expressions have no fallback and stop acceptance.

## Staged Godot Resources

The accepted stage was converted successfully into 16 type Resources, one type
chart Resource, 125 minion Resources, 115 deduplicated presentation Resources,
and 918 move Resources under the
excluded `development/staged_import/` area. These are inspection artifacts, not
the maintained release catalog. The current immutable output is
`godot-content-20260911-q`.

## Accepted source corrections

The strict importer applies five exact, audited corrections. Arkvian and Arkclaw
reference the nonexistent constant `MinionMoveID.holyLight_t1`; both now resolve
to the declared `holy_light_t1` move. This is an exact-expression correction, not
a case-insensitive or fuzzy alias.

Ice Floor talent content also accesses base Mud Blast tiers 3–5 through the
dynamic `ModToMoveID` dictionary, although those dynamic keys are never
registered. The `iSloth_Thaw` source comment says these moves temporarily replace
the unimplemented `iSland` family, while many original trees use the same base
Mud Blast constants. Those three lookups therefore resolve to the existing base
tiers at legacy IDs 182–184.

Each occurrence, source line, original expression, corrected stable ID, and
rationale is written to `import_corrections.json`. Unknown expressions outside
this four-entry correction table remain fatal.

## Next action

Implement the remaining battle modifiers and expand reference-derived golden
fixtures across representative multi-effect move families. Derived maximum
health/energy stages, charge, exhaustion, cooldown, frozen and stunned
activation, complete round transitions, equal-speed side selection, and
source-style enemy AI are now executable in the headless engine.

## Move-value recovery

The strict move evaluator recovers all 918 move records that
`AllBaseMovesContainer` actually constructs: 888 base tiers and all 30 dynamic
Ice Floor tiers. It models constructor defaults, legacy helper defaults,
`CreateMove`, `CopyMove`, passive construction, setter-side integer coercion,
per-tier arrays, and the shared buff/debuff vectors produced by
`GetMoveCopy`. Arithmetic uses ActionScript `int` truncation toward zero; it does
not round armor values.

Five additional IDs, `group_reflect_t1–t5` (135–139), are enum declarations
only. Neither edited source nor compiled `default.swf` constructs them, and no
recovered minion or talent references them. They are retained as explicit
unavailable identities in `unconstructed_move_identities.json`; no values were
invented. Any different missing family remains a fatal import error.

The importer can independently parse the JPEXS-exported compiled source and
compare every normalized value while ignoring provenance-only file/line fields.
The current comparison covers all 918 constructed moves and reports zero
differences.

Those moves now normalize into 1,467 typed, ordered effect records and stage as
918 `MoveDefinition` Resources with embedded `EffectDefinition` Resources. Every
constructed move has at least one effect. The effects retain legacy phase,
target scope, scaling source, chance, stat identity, duration, type-effectiveness,
critical eligibility, battle-mod-shield interception, and source order.

All imported effects remain marked `RUNTIME_PENDING` until their whole family is
verified. This is intentional. The runtime now reproduces primary damage/healing
scaling, shared move rolls, stat stages, stun, freeze, cleanse, and periodic
damage/healing lifecycle, armor, reflection/redirection, shield replacement,
flat and health-percentage self-damage, passive stat percentages, and passive
critical aggregation. Pending flags remain until complete battle lifecycle and
reference fixtures permit family-level acceptance; they therefore cannot be
silently promoted into release content.
