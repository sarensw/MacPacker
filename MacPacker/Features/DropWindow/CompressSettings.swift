//
//  CompressSettings.swift
//  MacPacker
//
//  Shared by every "drop files to compress" surface — the quick-compress window
//  and the start page's column — so a drop does the same thing wherever it lands.
//  Only what the writer supports: format and level.
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
    /// What a drop should use right now.
    @MainActor static var current: SevenZipCompressionOptions {
        let defaults = UserDefaults.standard
        let format = SevenZipCompressionOptions.Format(
            rawValue: defaults.string(forKey: Keys.dropWindowFormat) ?? Keys.defaultDropWindowFormat) ?? .zip
        let level = defaults.object(forKey: Keys.dropWindowLevel) as? Int ?? Keys.defaultDropWindowLevel
        return SevenZipCompressionOptions(format: format, level: UInt32(level))
    }

    /// The picker and the summary line read this same list.
    static let levels: [Int] = [0, 3, 5, 9]

    static func levelName(_ level: Int) -> String {
        switch level {
        case 0: String(localized: "Store", comment: "Compression level: no compression")
        case 3: String(localized: "Fast", comment: "Compression level: fast")
        case 9: String(localized: "Maximum", comment: "Compression level: maximum")
        default: String(localized: "Normal", comment: "Compression level: normal")
        }
    }
}

/// Borderless: in a small glass panel the button chrome is louder than the choice.
/// The label is only ever "zip" or "7z", never translated, so its width is fixed.
struct CompressFormatMenu: View {
    @AppStorage(Keys.dropWindowFormat) private var formatRaw = Keys.defaultDropWindowFormat

    var body: some View {
        Menu {
            Picker(selection: $formatRaw) {
                Text(verbatim: "zip").tag(SevenZipCompressionOptions.Format.zip.rawValue)
                Text(verbatim: "7z").tag(SevenZipCompressionOptions.Format.sevenZ.rawValue)
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
            Text(verbatim: formatRaw.uppercased())
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
