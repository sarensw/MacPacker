v0.14
- feat: New menu to open a new empty window
- feat: Extended info on archive in status bar (#61)
- fix: tar.gz and tgz not working (#54)
- fix: Can't close QuickLook with Space (#55)
- fix: MacOS not recognizing MacPacker as a viable VHDX reader (#56)
- fix: Cache cleanup not happening when just closing a window or loading a new archive (#58)
- fix: App crashes when unpacking exe / msi files (#59)
- fix: Extract here and Extract to folder via Finder don't work (#62)

v0.13
- feat: arj, dmg/apfs (Apple File System), chm, fat, ntfs, tar.z/taz, qcow2, squashfs, vdi, vhd, vhdx, vmdk, xar support
- feat: Special handling for Apple Installer Packages (pkg)
- feat: Added settings for easier access to managing the Finder file provider extension
- fix: Extracting folders does not include files
- core: Added attributions for 3rd party libraries/code
- core: Language support for Persian

v0.12
- feat: Added 'File' > 'Open...' menu to open archives when no window is open
- feat: Improved TAR archive handling
- fix: MacPacker not showing up in 'Open With…' menu in Finder (App Store version only)
- fix: Chinese (Unicode) characters in archive contents not displayed correctly 
- core: Separated localization of changelog from app localization
- core: Language support for Ukranian, Russian
- core: Detect archive type based on magic number in addition to file extension

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
