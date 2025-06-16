<p align="center">
  <img alt="MacPacker Logo" src="https://raw.githubusercontent.com/brainchest/MacPacker/main/MacPacker/Assets.xcassets/Logo.imageset/icon_256x256.png"  align="left">
</p>

# MacPacker

MacOS archive previewer and manager

<div>
  <a href="https://github.com/brainchest/MacPacker/releases"><img src="https://img.shields.io/github/downloads/sarensx/macpacker/total?color=%2300834a" /></a>
  <a href="https://github.com/brainchest/MacPacker/releases/latest"><img src="https://img.shields.io/github/downloads/sarensx/macpacker/latest/total?color=%2300834a&label=latest" /></a>
  <a href="https://github.com/brainchest/MacPacker/releases/latest"><img src="https://img.shields.io/github/v/release/sarensx/macpacker?color=%2300834a" /></a>
</div>

<br /><br /><br /><br />

## Why?

- Because essential tools should be free
- Because open source creates a community for long-time maintenance
- Because extracting the full archive to get just one file doesn't make sense

## What is MacPacker?

A free, open-source, tool to work with archives. Currently, it supports navigating and extracting files from an archive only. Creating or editing archives will follow. Inspired by 7-Zip, but without any claim to comparability. See the roadmap for more details.

## Roadmap

### Backlog
- Support decompression of formats: Deflate, LZMA2, LZMA, BZip2
- Support archives: ZLib, GZip, XZ, RAR
- Right click context menu in Finder to immediately extract the archive to a sub folder or without
- Create/edit archive

### v0.5
- feat: multiple windows support
- feat: open info for archive
- feat: breadcrumb view for navigation
- fix: "Open With" in Finder not working
- chore: major code cleanup

### v0.4
- feat: viewer to show preview of files
- feat: 7zip read support
- chore: clean cache when MacPacker terminates

### v0.3
- feat: highlight when dragging file to MacPacker window
- feat: double click any file opens it using the default system app
- feat: breadcrumb showing the current path in the archive
- feat: support for any valid zip-based file
- feat: automatic cache cleaning

### v0.2
- feat: welcome & about dialog
- feat: auto update
- feat: zip support
- feat: "Open With..." context menu support

### v0.1
- feat: Drag & drop an lz4 or tar file to MacPacker
- feat: Manual option to clear the cache
- feat: Traverse through nested archives
