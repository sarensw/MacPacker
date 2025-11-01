<h1 align="center">
  <br>
  <a href="http://macpacker.app"><img src="https://raw.githubusercontent.com/sarensw/MacPacker/main/MacPacker/Assets.xcassets/Logo.imageset/icon_256x256.png" alt="MacPacker" width="128"></a>
  <br>
  MacPacker
  <br>
</h1>

<div align="center">
  <a href="https://github.com/sarensw/MacPacker/releases"><img src="https://img.shields.io/github/downloads/sarensw/macpacker/total?color=%2300834a" /></a>
  <a href="https://github.com/sarensw/MacPacker/releases/latest"><img src="https://img.shields.io/github/downloads/sarensw/macpacker/latest/total?color=%2300834a&label=latest" /></a>
  <a href="https://github.com/sarensw/MacPacker/releases/latest"><img src="https://img.shields.io/github/v/release/sarensw/macpacker?color=%2300834a" /></a>
</div>

Say hello to **MacPacker**, the archive manager for macOS. Open source, because essential tools should be free. Preview (nested) archives. Extract selected files. Creating or editing archives will follow. Inspired by 7-Zip, but without any claim to comparability. See the roadmap for more details.

<p align="center">
  <img src="https://raw.githubusercontent.com/sarensw/MacPacker/main/assets/v0.10_main.gif" alt="Demo GIF" />
</p>



## Installation

### System Requirements
- macOS 13.5 or later

### Option 1: Download from GitHub

Download the .zip file from <a href="https://github.com/sarensw/MacPacker/releases">GitHub Releases</a>. Extract and move the app to the Applications folder. The app is sandboxed, signed, and notarized by Apple.

### Option 2: App Store

<a href="https://apps.apple.com/us/app/macpacker/id6473273874"><img src="https://raw.githubusercontent.com/sarensw/MacPacker/main/assets/mas.svg" alt="MacPacker" width="128"></a>

### Option 3: Homebrew

```bash
brew install --cask macpacker
```

## Contribution

### Translation

MacPacker use POEditor for managing translations. If you want to improve an existing translation or want to add a new language, go to the following page, sign up and make the edits.

> https://poeditor.com/join/project/J2Qq2SUzYr

### Pull Requests

Pull requests are welcome. Please note that MacPacker is in early development and there are still a few breaking changes coming up. Pull requests therefore might need some rework or wait time before they can be merged.

More info on how to contribute and on the architecture of MacPacker will be added soon.

## Roadmap

- [x] Navigate through (nested) archives
- [x] Extract selected files via drag & drop to any target
- [x] Breadcrumb for quick navigation
- [x] Support (my) most needed archives .zip, .tar, .lz4
- [x] Extract the full archive at once
- [x] Preview files without extraction
- [x] Finder extensions for quick access to the most important functions
- [x] ~~Fully fledged internal previewer~~ System previewer instead of internal previewer
- [ ] Support all formats that TheUnarchiver & Keka supports
- [ ] Create archives and edit archives (most common ones only)

## Building from Source

### Prerequisites
- macOS 14.5 or later
- XCode 16 or later

### Process

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/sarensw/MacPacker.git
   cd MacPacker
   ```

2. **Open the Project in Xcode**:
   ```bash
   open MacPacker.xcodeproj
   ```

3. **Build and Run**:
    - Click the "Run" button or press `Cmd + R`. Watch the magic unfold!

