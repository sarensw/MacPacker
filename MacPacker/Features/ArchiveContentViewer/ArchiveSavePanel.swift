//
//  ArchiveSavePanel.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import AppKit
import Core
import Swift7zip
import SwiftUI

/// Options picked in the save panel when creating an archive — the 7-Zip
/// "Add to Archive" essentials (format + compression level) as a native
/// NSSavePanel accessory.
@MainActor
final class ArchiveSavePanelOptions: ObservableObject {
    @Published var format: SevenZipCompressionOptions.Format = .zip
    @Published var level: UInt32 = 5
}

struct ArchiveSavePanelAccessoryView: View {
    @ObservedObject var options: ArchiveSavePanelOptions
    var onFormatChange: (SevenZipCompressionOptions.Format) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 16) {
            Picker(selection: $options.format) {
                Text(verbatim: "zip").tag(SevenZipCompressionOptions.Format.zip)
                Text(verbatim: "7z").tag(SevenZipCompressionOptions.Format.sevenZ)
            } label: {
                Text("Format:", comment: "Label of the archive format picker in the save panel")
            }
            .fixedSize()

            Picker(selection: $options.level) {
                Text("Store", comment: "Compression level: no compression").tag(UInt32(0))
                Text("Fast", comment: "Compression level: fast").tag(UInt32(3))
                Text("Normal", comment: "Compression level: normal").tag(UInt32(5))
                Text("Maximum", comment: "Compression level: maximum").tag(UInt32(9))
            } label: {
                Text("Compression:", comment: "Label of the compression level picker in the save panel")
            }
            .fixedSize()
        }
        .padding(10)
        .onChange(of: options.format) { _, newFormat in
            onFormatChange(newFormat)
        }
    }
}

/// Shows the archive save panel (used when saving a new, not-yet-on-disk
/// archive) and applies the state's pending changes to the picked location.
@MainActor
enum ArchiveSavePanel {
    /// - Parameter onSave: called with the running save `Task` once the user
    ///   confirms the panel, or `nil` if they cancel it. Lets callers (e.g. the
    ///   save-on-close prompt) wait for the write before acting.
    static func runAndSave(
        state: ArchiveState,
        window: NSWindow? = nil,
        onSave: ((Task<Void, Never>?) -> Void)? = nil
    ) {
        let options = ArchiveSavePanelOptions()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = String(localized: "New Archive", comment: "Title of the save panel used to create a new archive")

        let baseName = state.name ?? String(localized: "New Archive", comment: "Default file name of a new archive")
        panel.nameFieldStringValue = (baseName as NSString).deletingPathExtension + ".zip"

        // switching the format keeps the file name but swaps the extension
        let accessory = NSHostingView(rootView: ArchiveSavePanelAccessoryView(options: options) { newFormat in
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + newFormat.rawValue
        })
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                onSave?(nil)
                return
            }
            let task = state.save(
                to: url,
                options: SevenZipCompressionOptions(format: options.format, level: options.level)
            )
            onSave?(task)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}
