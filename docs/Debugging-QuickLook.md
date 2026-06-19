# Debugging the QuickLook preview extension

The QuickLook preview (`QuickLookExtension`, a `com.apple.quicklook.preview`
app extension) is awkward to debug the "normal" way: the `.appex` is loaded by
a **separate, system-spawned host process**, so you can't just hit ⌘R on the app
and step into it, and breakpoints in the appex often don't bind.

To make this painless, the entire preview UI and archive-loading logic live in a
shared Swift package, **`ArchivePreviewUI`** (`Modules/Sources/ArchivePreviewUI/`),
which is used by *both* the appex and an in-app debug harness. The appex's
`PreviewViewController` is just a thin `QLPreviewingController` shell over
`ArchivePreviewViewController`.

## Option A — In-app harness (recommended for development)

Runs the **exact same** preview code in the main app's process, so the debugger
and breakpoints Just Work.

1. Select the **MacPacker** scheme and run it (⌘R) — a Debug build.
2. Open **Settings** (⌘,) → **Debug** tab.
3. Click **“Open Quick Look Harness…”** and pick an archive (a file picker opens
   automatically the first time).
4. Set breakpoints anywhere in `ArchivePreviewUI` or `Core` — e.g.
   `ArchiveViewController.resolvedChildren(of:)`,
   `ArchivePreviewViewController.loadPreview(of:)`,
   `ArchivePreviewLoader.makeState()` — and step through normally.

The harness button only exists in **DEBUG** builds
(`MacPacker/Features/Debug/QuickLookHarnessWindowController.swift`).

## Option B — End-to-end in the real QuickLook host

Use this to verify the extension works *as an extension* (sandbox, packaging,
registration), which the harness does not exercise.

- **One click:** select the **QuickLookExtension** scheme and Run. It builds the
  appex + host app and launches `qlmanage -p <sample archive>` (the sample is
  `Modules/Tests/CoreTests/TestArchives/zip/nestedFolders.zip`; edit the scheme's
  run arguments to point at any archive).
- **From Finder:** select an archive and press **Space**.
- **From Terminal:** `qlmanage -p /path/to/some.zip`

### Make macOS use *your* freshly-built appex

`qlmanage` / Finder use the appex registered with LaunchServices. After building,
register the dev build (point it at the built `.app`):

```sh
APP=~/Library/Developer/Xcode/DerivedData/MacPacker-*/Build/Products/Debug/MacPacker.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
```

If a preview looks stale, reset QuickLook:

```sh
qlmanage -r          # reload generators
qlmanage -r cache    # clear the thumbnail/preview cache
```

### Breakpoints inside the real appex (advanced, finicky)

`qlmanage`/Finder render the preview in a separate extension host, so a debugger
attached to `qlmanage` won't hit appex breakpoints. To break in the appex itself:
trigger a preview, then in Xcode use **Debug ▸ Attach to Process** and pick the
`QuickLookExtension` / preview-extension process. This is fiddly — prefer the
in-app harness (Option A) for day-to-day work.

## Logs

Everything logs via `tb` to the `app.MacPacker` subsystem (categories
`quicklook`, `quicklook.drag`, plus `archive` / `engine` from Core), so it shows
up in Console.app and the TailBeat viewer:

```sh
log stream --level debug --predicate 'subsystem == "app.MacPacker"'
```

## Supported formats in the preview

The extension can't spawn subprocesses, so `ArchivePreviewLoader.makeState()`
pins every format to a library-backed engine (`xad`, plus `swc` for lz4). That
single place is shared by the appex and the harness — change an engine pin there
and both pick it up. (7-Zip now runs in-process too, so the preview could move to
the native `.7zip` engine — tracked separately.)
