//
//  CompressSettings.swift
//  MacPacker
//
//  Shared by every "drop files to compress" surface — the quick-compress window
//  and the start page's column — so a drop does the same thing wherever it lands.
//  The same options the save panel offers, remembered apart from its own.
//

import Core
import Swift7zip
import SwiftUI
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

/// One name so the surfaces that show it cannot drift apart.
enum CompressDropIcon {
    static let name = "archivebox"
}

enum CompressSettings {
    /// One set for every surface that compresses a drop, kept as it changes.
    /// A password lasts only as long as the app runs.
    @MainActor static let shared = ArchiveSaveOptions(storage: .quickCompress)

    /// What a drop should use, taken when it lands: changing the options while
    /// an archive is written does not change that archive.
    @MainActor static var current: (options: SevenZipCompressionOptions, excludeDSStore: Bool) {
        (shared.compressionOptions, shared.excludeDSStore)
    }
}

/// Borderless: in a small glass panel the button chrome is louder than the choice.
/// The label is only ever "zip" or "7z", never translated, so its width is fixed.
struct CompressFormatMenu: View {
    @ObservedObject private var options = CompressSettings.shared

    var body: some View {
        Menu {
            Picker(selection: $options.format) {
                Text(verbatim: "zip").tag(SevenZipCompressionOptions.Format.zip)
                Text(verbatim: "7z").tag(SevenZipCompressionOptions.Format.sevenZ)
            } label: {
                // No label at all. Two entries called "zip" and "7z" need no
                // heading above them, and a string that is never rendered still
                // costs a translation round-trip in every language.
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // a quiet capsule: borderless alone read as a label, not a control
            Text(verbatim: options.format.rawValue.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Hollow off, solid on, in the label colour rather than the accent: it is a
/// state of the window, and an accent control reads as something to press.
struct CompressPinButton: View {
    @AppStorage(Keys.dropWindowFloats) private var floats = true

    /// Applying it needs the window, which the controller owns.
    let apply: (Bool) -> Void

    var body: some View {
        Button {
            floats.toggle()
        } label: {
            Image(systemName: floats ? "pin.fill" : "pin")
                .imageScale(.medium)
                .foregroundStyle(floats ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(Text("Keep on top", comment: "Setting of the Quick Compress window: keeps it visible above other apps, so files can be dragged onto it from Finder."))
        .onChange(of: floats, initial: true) { _, value in apply(value) }
    }
}

/// The urls of one drop, handed over together — one drop is one archive.
///
/// `loadItem` must be *started* inside the drop callback: the providers belong to
/// the drag session and are unreliable once it ends. The answers arrive later, out
/// of order and sometimes empty, so they are slotted by index.
@MainActor
func loadDroppedFileURLs(from providers: [NSItemProvider], then use: @escaping ([URL]) -> Void) {
    let collector = DropURLCollector(expecting: providers.count, complete: use)
    for (index, provider) in providers.enumerated() {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            let url = (data as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            if url == nil { log.error("Drop: could not read a file URL from the dropped item") }
            Task { @MainActor in collector.deliver(url, at: index) }
        }
    }
}

@MainActor
private final class DropURLCollector {
    private var slots: [URL?]
    private var outstanding: Int
    private let complete: ([URL]) -> Void

    init(expecting count: Int, complete: @escaping ([URL]) -> Void) {
        self.slots = Array(repeating: nil, count: count)
        self.outstanding = count
        self.complete = complete
    }

    func deliver(_ url: URL?, at index: Int) {
        guard outstanding > 0 else { return }
        slots[index] = url
        outstanding -= 1
        guard outstanding == 0 else { return }
        let urls = slots.compactMap { $0 }
        if !urls.isEmpty { complete(urls) }
    }
}
