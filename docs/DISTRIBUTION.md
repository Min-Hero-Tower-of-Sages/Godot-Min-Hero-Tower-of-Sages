# Repository and Windows release preparation

This is the **original** branch of `Godot-Min-Hero-Tower-of-Sages`, formerly
`main`. The default and active development branch is **extended**, formerly
`multiplayer`; its README and distribution guide cover current Extended releases.
This branch retains its `Windows Desktop` preset and `MinHero.exe` output.
A normal checkout includes all runtime content and
does not require the original developer's extraction tree. No machine-specific
export-template path is stored in the preset.

Keep code, scenes, content, tests, tools, docs, `.uid` and resource `.import`
metadata in Git. Exclude `.godot/`, builds, toolchains, reference extraction
trees, credentials, personal saves and diagnostic captures/logs.

## Export

1. Install standard Godot 4.7.2 and matching export templates.
2. Allow Godot to import the project once.
3. Export the `Windows Desktop` release preset, or run:

   ```powershell
   ./tools/export_windows.ps1 -GodotExecutable 'C:\path\to\Godot.exe'
   ```

4. Launch the exported executable independently of the editor. Check title,
   loading, new-save intro, room entry and a battle before calling it share-ready.
5. Upload `build/windows/MinHero-windows-x86_64.zip` as a GitHub Release asset,
   not a Git commit. Include the SHA-256 file. Do not bundle personal saves.

The preset embeds the PCK and explicitly includes runtime JSON. Unsigned builds
can trigger Windows trust prompts; do not ask recipients to disable security
software. Review `ASSET_NOTICES.md` before public distribution.
The export helper keeps temporary pack serialization inside `build/`, rejects
logged export errors even with a zero exit code, and checks the standalone
player with isolated settings/saves before creating the release ZIP.

## Publish

The repository is already published. Push documentation or baseline maintenance
to `original`:

```powershell
git push -u origin original
```

Current `MinHeroExtended.exe` releases are built and tagged from `extended`.
Keep any Original baseline builds clearly labeled and tied to their own source
commit. Renaming the branches does not move or rewrite earlier release tags.

## Maintainer-only asset repackaging

`tools/package_runtime_assets.ps1` copies media from a local recovery tree,
generates explicit runtime symbol aliases and migrates image/room references.
It refuses to replace differing packaged images and preserves original files.
This tool is not needed to run a normal checkout. Reference-recovery tools may
still need the local materials described in `docs/REFERENCE_RECOVERY.md`.
