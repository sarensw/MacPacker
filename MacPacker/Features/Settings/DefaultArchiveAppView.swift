import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// Uses Launch Services without launching any of the selected archive types.
@MainActor
struct DefaultArchiveAppView: View {
    let catalog: ArchiveTypeCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var result = ""
    @State private var cancelled = false

    private var formats: [ArchiveTypeDto] {
        // Installer, executable and disk-image associations belong to their
        // normal apps even though an archive engine can inspect their contents.
        catalog.getAllTypes().filter {
            ["archive", "compression"].contains($0.kind)
                && !["ar", "chm", "msapp", "msi", "pkg", "rpm", "sea"].contains($0.id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default archive app", comment: "Settings sheet title for file associations").font(.headline)
            Text("Choose the archive formats MacPacker should open. macOS may confirm each selected format. Numbered archive parts are not included.", comment: "Explanation above file association choices")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Select all", comment: "Select all archive format checkboxes")) { selected = Set(formats.map(\.id)) }
                Button(String(localized: "Clear selection", comment: "Clear archive format checkboxes")) { selected = [] }
            }.disabled(busy)
            List(formats, id: \.id) { format in
                Toggle(isOn: Binding(get: { selected.contains(format.id) }, set: { value in
                    if value { selected.insert(format.id) } else { selected.remove(format.id) }
                })) {
                    Text(verbatim: "\(format.name) (\(DefaultArchiveAssociations.extensions(for: format).joined(separator: ", ")))")
                }.disabled(busy)
            }.frame(height: 260)
            if busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Button(String(localized: "Stop", comment: "Stop requesting further default archive associations")) { cancelled = true }
                        .disabled(cancelled)
                }
            }
            if !result.isEmpty { Text(verbatim: result).font(.footnote).textSelection(.enabled) }
            HStack {
                Spacer()
                Button(String(localized: "Done", comment: "Close file association settings")) { dismiss() }.disabled(busy)
                Button(String(localized: "Make MacPacker default", comment: "Apply selected file associations")) {
                    Task { await apply() }
                }.disabled(busy || selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 510)
    }

    private func apply() async {
        busy = true
        cancelled = false
        result = ""
        defer { busy = false }
        let extensions = Set(formats.filter { selected.contains($0.id) }
            .flatMap { DefaultArchiveAssociations.extensions(for: $0) })
        var visited: Set<String> = []
        for ext in extensions.sorted() {
            guard !cancelled else { break }
            guard let type = UTType(filenameExtension: ext),
                  ![UTType.data, .item, .content].contains(type),
                  visited.insert(type.identifier).inserted else { continue }
            if NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
                continue
            }
            do {
                // Await macOS's consent result before requesting another format.
                // Do not combine the legacy Launch Services API with a fallback:
                // it queues independent prompts before consent has completed.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
                guard NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL else {
                    result = String(localized: "No further default-app changes requested.", comment: "Association batch stopped after macOS did not confirm a change")
                    return
                }
            } catch {
                result = error.localizedDescription
                return
            }
        }
        result = cancelled
            ? String(localized: "No further default-app changes requested.", comment: "Association batch stopped after macOS did not confirm a change")
            : String(localized: "Selected archive associations updated.", comment: "File association success message")
    }
}
