v0.11
- feat: Use system preview instead of internal previewer
- feat: Navigate the archive using keys similar to Finder
- fix: Crash when using the open with option
- fix: Quick look extension missing in App Store version
- fix: Empty window opened in addition to file opened with 'Open With' option in Finder
- core: Re-enable macOS 13 as minimum deployment target
- core: Language support for Italian

v0.10
- feat: Quick Look extension
- feat: Added Send-a-smile menu to let users quickly star the repo or add a review in the App Store
- fix: App crashes when all windows are closed and then the app gets terminated
- core: Cleanup logging

v0.9
- feat: Finder integration via context menu
- core: Language support for German, French, Simplified Chinese

v0.8
- feat: gzip, bzip2, xz, cab, iso, sit & sea (StuffIt), Z, cpio support
- feat: show packed size, size, modified date, permissions in columns

v0.7
- feat: lzh, lha, lzx support
- feat: close internal previewer using Space, or Esc
- feat: show archive name in title
- feat: extract selected files via UI
- feat: extract full archive
- fix: app store version shows "MacPacker store" as product name in launchpad
- core: new architecture for archive handlers

v0.6
- feat: hit space to open internal preview
- feat: setting to change the breadcrumb position
- feat: rar read support
- feat: show folder / file icons in table
- chore: add support for macOS 14

v0.5
- feat: multiple windows support
- feat: open info for archive
- feat: breadcrumb view for navigation
- fix: open with in Finder not working
- chore: major code cleanup

v0.4
- feat: viewer to show preview of files
- feat: 7zip read support
- chore: clean cache when MacPacker terminates

v0.3
- feat: highlight when dragging file to MacPacker window
- feat: double click any files extracts it and opens it using the default editor
- feat: breadcrumb showing the current path in the archive (incl. nested support)
- feat: support for any valid zip-based file
- feat: automatic cache cleaning & zip creation support
- chore: prepare the core for creating/editing archives
- chore: unit tests

v0.2
- feat: welcome & about dialog
- feat: auto update
- feat: zip support
- feat: "Open With..." context menu support

v0.1
- Drag & drop an lz4 or tar file to MacPacker
- Manual option to clear the cache
- Traverse through nested archives
