# Skill-gem persistence correction (October 30)

The v1.3.0 skill-gem factory correctly creates `kind: "skill"` records with
an empty `stat_id`, a move ID, a skill rank and a type ID. The save repository
still required every owned gem to have one of the five stat IDs. As a result,
forging or receiving a skill gem failed with "owned gem tier or stat is invalid".
Subsequent writes would also fail if a skill gem was present in an in-memory
multiplayer profile.

Save validation now distinguishes legacy/default stat gems from skill gems.
Stat gems retain their stat-ID checks. Skill gems require valid structural
move/type identifiers and an integer rank from 1 through 5; both kinds retain
their raw-color/facet shape checks. Campaign validation also verifies that a
skill gem's move exists and that its rank/type match that definition.

The former skill-gem fixtures checked campaign logic using replacement save
methods, bypassing the repository validator. They now invoke that validator.
The new `tests/skill_gem_save_regression.gd` uses the actual repository with
isolated disk writes, JSON verification, backup rotation and session reloads.

On the old failed trainer award, the prepared battle had already been saved,
but its result had not. The fatal overlay allowed returning to exploration
with that battle still pending. A failed result commit now retains the result
in the battle scene and offers Retry save. Successful retry follows the normal
victory/defeat flow, and applied battle IDs prevent duplicate rewards.

For a save already affected by v1.3.0, loading it in the corrected build uses
the existing runtime pending-battle recovery. No new save or manual JSON edit
is required. The uncommitted victory must be fought again to receive its award.

The local v1.3.1 Windows export also passes the real-disk fixture. Run the
fixture as an absolute external script with the editor executable's
`--main-pack <MinHeroExtended.exe>` option, the isolated save-profile environment,
and `-- --verify-export --expect-version=1.3.1`. The export flag asserts that
source-only tests are absent from the loaded pack; the version flag checks its
embedded application version. This checks packaged game code and resources
through the real validator/write/reload path rather than a replacement saver.

The existing skill-gem and saved-mod fixtures, the 245-check suite and the
seven battle-result presentation checks also pass. The retry overlay was
verified in a rendered run. All fixture saves remain under ignored `build/`.
