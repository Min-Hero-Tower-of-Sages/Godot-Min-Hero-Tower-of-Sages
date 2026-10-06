# Repository and Windows release preparation

The intended repository name is `Godot-Min-Hero-Tower-of-Sages`, with `main`
as the default branch. A normal checkout includes all runtime content and
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

## Publish

Choose **public or private** before publishing. GitHub Desktop's **Add Local
Repository** and **Publish Repository** can publish the existing local repo.
Alternatively, after creating an empty GitHub repository:

```powershell
git remote add origin https://github.com/YOUR_ACCOUNT/Godot-Min-Hero-Tower-of-Sages.git
git push -u origin main
```

No remote URL, token or account credential is embedded in the project, and
repository preparation does not infer a public/private choice.

## Maintainer-only asset repackaging

`tools/package_runtime_assets.ps1` copies media from a local recovery tree,
generates explicit runtime symbol aliases and migrates image/room references.
It refuses to replace differing packaged images and preserves original files.
This tool is not needed to run a normal checkout. Reference-recovery tools may
still need the local materials described in `docs/REFERENCE_RECOVERY.md`.
