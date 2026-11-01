# Repository and Windows release preparation

The repository is `Min-Hero-Tower-of-Sages/Godot-Min-Hero-Tower-of-Sages`.
**extended** is the default and active development branch (formerly
`multiplayer`). **original** preserves the earlier Godot port (formerly `main`).
Extended releases use `MinHeroExtended.exe`; Original's own export preset uses
`MinHero.exe`. A normal checkout includes all runtime content and
does not require the original developer's extraction tree. No machine-specific
export-template path is stored in the preset.

Keep code, scenes, content, tests, tools, docs, `.uid` and resource `.import`
metadata in Git. Exclude `.godot/`, builds, toolchains, reference extraction
trees, credentials, personal saves and diagnostic captures/logs.

## Export

1. Install standard Godot 4.7.2 and matching export templates.
2. Allow Godot to import the project once.
3. Export the `Min Hero Extended` release preset, or run:

   ```powershell
   ./tools/export_windows.ps1 -GodotExecutable 'C:\path\to\Godot.exe'
   ```

4. Launch the exported executable independently of the editor. Check title,
   loading, new-save intro, room entry and a battle before calling it share-ready.
5. Upload `build/windows/MinHeroExtended.exe` as a GitHub Release asset, matching
   the current release format. The helper also creates
   `MinHeroExtended-windows-x86_64.zip` (with asset notices) and its SHA-256 file
   if a ZIP is wanted. Build assets do not belong in source commits.

The preset embeds the PCK and explicitly includes runtime JSON. Unsigned builds
can trigger Windows trust prompts; do not ask recipients to disable security
software. Review `ASSET_NOTICES.md` before public distribution.
The export helper keeps temporary pack serialization inside `build/`, rejects
logged export errors even with a zero exit code, and checks the standalone
player with isolated settings/saves before creating the release ZIP.
When a feature adds persistent data, exercise a write and reload through
`SaveRepository` as well. An in-memory replacement that bypasses its validator
does not cover the shipping save path. The Skill Gems disk fixture uses an
isolated `build/skill-gem-save-profile` and tests forge and battle rewards.
Use `-OutputDirectory 'build/releases/extended-v1.3.2'` for an isolated release
build. Commit the game changes and matching application/Windows versions before
exporting, then tag that exact commit. The release tag must resolve to the
exported source, regardless of the repository's default branch.

## Publish

The repository is already published. The current release format is
`Min Hero Extended v<version>`, tag `extended-v<version>`, with a standalone
`MinHeroExtended.exe` asset and concise change paragraphs. Preserve older
release tags and assets.

1. Push the `extended` commit and its release tag.
2. Create a draft using the existing tag (`gh release create --verify-tag`)
   and a release-notes file (`--notes-file`). Upload the verified executable.
3. Compare the uploaded asset's size and SHA-256 digest with the local build,
   and check that the tag resolves to the intended commit.
4. Publish the draft as the latest release. Confirm the latest-release endpoint
   and download URL resolve to the new version.

## Updating older clones

GitHub branch renames preserve branch history and redirect old web links.
Local branch names and upstreams still need updating. For clones that still
have both old local branch names:

```powershell
git fetch origin --prune
git branch -m multiplayer extended
git branch -m main original
git branch --set-upstream-to=origin/extended extended
git branch --set-upstream-to=origin/original original
git remote set-head origin -a
git switch extended
```

Use only the rename command for branches that still have their old names.
Runtime multiplayer classes and `user://multiplayer_profiles` keep their names;
the repository rename does not change the network protocol or save locations.

## Maintainer-only asset repackaging

`tools/package_runtime_assets.ps1` copies media from a local recovery tree,
generates explicit runtime symbol aliases and migrates image/room references.
It refuses to replace differing packaged images and preserves original files.
This tool is not needed to run a normal checkout. Reference-recovery tools may
still need the local materials described in `docs/REFERENCE_RECOVERY.md`.
