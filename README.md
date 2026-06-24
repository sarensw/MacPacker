<h1 align="center">
  <br>
  <a href="https://macpacker.app"><img src="https://raw.githubusercontent.com/sarensw/MacPacker/main/assets/AppIcon-iOS-Default-1024x1024@1x.png" alt="MacPacker" width="128"></a>
  <br>
  MacPacker
  <br>
</h1>

<p align="center">
  <b>The archive manager for macOS that should have existed all along.</b><br>
  Browse archives like folders, preview files without extracting, and drag out only the ones you need.
</p>

<p align="center">
  <a href="https://github.com/sarensw/MacPacker/releases"><img alt="Total downloads" src="https://img.shields.io/github/downloads/sarensw/MacPacker/total?style=flat-square&color=00834a&label=downloads"></a>
  <a href="https://github.com/sarensw/MacPacker/releases/latest"><img alt="Latest release downloads" src="https://img.shields.io/github/downloads/sarensw/MacPacker/latest/total?style=flat-square&color=00834a&label=latest%20downloads"></a>
  <a href="https://github.com/sarensw/MacPacker/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/sarensw/MacPacker?style=flat-square&color=00834a&label=release"></a>
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-00834a?style=flat-square"></a>
  <img alt="Platform: macOS 14.6+" src="https://img.shields.io/badge/macOS-14.6%2B-00834a?style=flat-square">
</p>

<p align="center">
  <a href="https://macpacker.app">Website</a> ·
  <a href="#installation">Install</a> ·
  <a href="#supported-formats">Formats</a> ·
  <a href="https://macpacker.app/en/docs">Docs</a> ·
  <a href="#support-the-project">Support</a> ·
  <a href="#contributing">Contribute</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/sarensw/MacPacker/main/assets/v0.15.4_main.gif" alt="MacPacker demo" />
</p>

MacPacker is a free and open source archive manager for macOS. It opens 40+ archive, disk image, and compression formats, lets you peek inside without extracting, drills into nested archives, and hands you exactly the files you want via drag & drop. Open source, because essential tools should be free. Inspired by 7-Zip, but built natively for the Mac.

## Features

- **Peek inside** — Browse the full contents of any archive without extracting a single byte.
- **Nested archives** — Archives inside archives? Drill in seamlessly, with no intermediate extractions.
- **Selective extraction** — Drag out exactly the files you need. No more 2 GB extractions for one config file.
- **Edit & save** — Modify and re-save ZIP archives in place. Editing for more formats is on the way.
- **Quick Look** — Preview archive contents straight from Finder with the spacebar.
- **Finder integration** — Right-click any archive to extract here or to a folder, without opening the app.
- **Encrypted archives** — Open password-protected and encrypted archives.
- **Built for the keyboard** — Navigate archives with the same keys you use in Finder, with breadcrumbs and sortable columns.
- **Smart detection** — Recognizes formats by their magic number, not just the file extension.
- **Speaks your language** — Available in 13 languages.

## Supported Formats

MacPacker reads and extracts 40+ formats across archives, disk images, and compression containers. ZIP archives can also be edited and re-saved.

| Category | Formats |
| --- | --- |
| **Archives** | 7z · ar · arj · cab · chm · cpio · deb · exe · lha · lzh · lzx · msi · pkg · rar · rpm · sea · sit · sitx · tar · xar · zip · zipx |
| **Disk images** | dmg · fat · iso · ntfs · qcow2 · squashfs · vdi · vhd · vhdx · vmdk · wim |
| **Compression** | bz2 · gz · lz4 · xz · z |
| **Tarballs** | tar.gz (tgz) · tar.bz2 (tbz2) · tar.xz (txz) · tar.lz4 · tar.z (taz) |

See the [full format reference and per-format guides](https://macpacker.app/en/docs) on the website.

## Installation

**Requirements:** macOS 14.6 or later. (macOS 13 was supported through v0.14.1.)

Pick whichever you prefer — all builds are sandboxed, signed, and notarized by Apple.

| Method | How |
| --- | --- |
| **Homebrew** | `brew install --cask macpacker` |
| **Direct download** | Grab the `.dmg` or `.zip` from [macpacker.app](https://macpacker.app) or [GitHub Releases](https://github.com/sarensw/MacPacker/releases), then move the app to Applications. |
| **Mac App Store** | [Download on the App Store](https://apps.apple.com/us/app/macpacker/id6473273874) |

> [!NOTE]
> App Store releases land a few days after the GitHub and direct downloads, because every build goes through Apple's App Store review. For the newest version, use Homebrew or the direct download.

## Support the Project

MacPacker is free and built in the open. If it saves you time, here are a few ways to give back:

**Sponsor the work**

- [GitHub Sponsors](https://github.com/sponsors/sarensw)
- [Buy Me a Coffee](https://www.buymeacoffee.com/sarensw)

**Free ways to help**

- ⭐ Star this repository.
- ✍️ Leave a review on the [Mac App Store](https://apps.apple.com/us/app/macpacker/id6473273874).
- 🌍 [Help translate MacPacker](#translation) into your language.
- 🐞 [Report a bug](https://github.com/sarensw/MacPacker/issues) or suggest a feature.

**More apps by the maker**

MacPacker is built by [Stephan Arenswald](https://x.com/sarensw). If you like it, take a look at the other apps:

- **[TailBeat](https://tailbeat.app)** — A companion for macOS developers that improves logging and app release workflows.
- **[FileFillet](https://www.filefillet.com)** — Organize files quickly on macOS.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

> [!IMPORTANT]
> Using AI to write code? Pull requests where AI is the primary author must follow the [AI Contribution Guidelines](AI_CONTRIBUTING.md): disclose AI involvement, open the PR from a human account, and include verification evidence (before/after screenshots for UI changes, terminal or test output otherwise). Minor AI-assisted edits where you're clearly the author don't need anything special.

### Translation

Translations are managed on POEditor. To improve an existing language or add a new one, sign up and start editing:

> https://poeditor.com/join/project/J2Qq2SUzYr

### Pull Requests

MacPacker is still in early development and a few breaking changes are ahead, so pull requests may need rework or some wait time before they can be merged. Opening an issue first to discuss larger changes is appreciated.

## Building from Source

**Prerequisites**

- macOS 14.6 or later
- Xcode 16 or later

**Steps**

1. **Clone the repository** (it uses submodules for vendored dependencies and test archives):
   ```bash
   git clone --recurse-submodules https://github.com/sarensw/MacPacker.git
   cd MacPacker
   ```
   Already cloned without submodules? Run `git submodule update --init --recursive`.

2. **Open the project in Xcode:**
   ```bash
   open MacPacker.xcodeproj
   ```

3. **Build and run** — click Run or press `Cmd + R`.

4. **Use your own signing team** (optional). If you have a different Apple Developer account, create a local override:
   ```bash
   cp Config/SigningOverride.xcconfig.template Config/SigningOverride.xcconfig
   ```
   Then edit `Config/SigningOverride.xcconfig` and set your Team ID (find it in Xcode under Settings → Accounts). This file is gitignored and never committed.

## Roadmap

- [x] Browse and navigate nested archives
- [x] Breadcrumb and Finder-style keyboard navigation
- [x] Extract selected files via drag & drop to any target
- [x] Extract the full archive at once
- [x] Preview files without extraction (via the system previewer)
- [x] Quick Look and Finder extensions for quick access
- [x] Open password-protected and encrypted archives
- [x] Wide format coverage (40+ formats)
- [x] Edit and re-save ZIP archives
- [ ] Delete files and folders inside archives (coming next)
- [ ] Create archives and edit more formats

## License

MacPacker is licensed under the [GNU General Public License v3.0](LICENSE).
