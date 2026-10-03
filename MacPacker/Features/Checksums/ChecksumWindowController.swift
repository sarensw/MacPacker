//
//  ChecksumWindowController.swift
//  MacPacker
//

import AppKit
import Core
import SwiftUI

@MainActor
final class ChecksumWindowController: NSWindowController, NSWindowDelegate {
    private static var retained: [ChecksumWindowController] = []

    private let model: ChecksumWindowModel

    private init(files: [URL], verifyFromClipboard: Bool) {
        model = ChecksumWindowModel(
            files: files,
            expectedInput: verifyFromClipboard ? NSPasteboard.general.string(forType: .string) ?? "" : ""
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "File Checksums", comment: "Title of the window that calculates and verifies file checksums")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ChecksumWindowView(model: model))
        window.contentMinSize = NSSize(width: 690, height: 360)
        window.setContentSize(NSSize(width: 780, height: 540))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(files: [URL], verifyFromClipboard: Bool) {
        guard !files.isEmpty else { return }
        let controller = ChecksumWindowController(files: files, verifyFromClipboard: verifyFromClipboard)
        retained.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.model.start()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        Self.retained.removeAll { $0 === self }
    }
}

@MainActor
private final class ChecksumWindowModel: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        let file: URL
        var checksums: FileChecksums?
        var error: String?
    }

    @Published var rows: [Row]
    @Published var expectedInput: String
    private var task: Task<Void, Never>?

    init(files: [URL], expectedInput: String) {
        rows = files.map { Row(file: $0) }
        self.expectedInput = expectedInput
    }

    var expected: ExpectedChecksum? {
        ChecksumVerifier.expected(from: expectedInput)
    }

    func start() {
        let files = rows.map(\.file)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            for (index, file) in files.enumerated() {
                if Task.isCancelled { return }
                do {
                    let checksums = try await FileChecksumCalculator.calculate(file)
                    await self?.finish(index: index, checksums: checksums)
                } catch is CancellationError {
                    return
                } catch {
                    await self?.finish(index: index, error: error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func paste() {
        expectedInput = NSPasteboard.general.string(forType: .string) ?? ""
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func saveSHA256(for row: Row) {
        guard let checksum = row.checksums?.sha256 else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = row.file.lastPathComponent + ".sha256"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try "\(checksum)  \(row.file.lastPathComponent)\n".write(
                    to: destination, atomically: true, encoding: .utf8
                )
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private func finish(index: Int, checksums: FileChecksums) {
        rows[index].checksums = checksums
    }

    private func finish(index: Int, error: String) {
        rows[index].error = error
    }
}

private struct ChecksumWindowView: View {
    @ObservedObject var model: ChecksumWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Checksums", comment: "Heading of the window for file checksums")
                    .font(.title2.bold())
                Spacer()
                Group {
                    if model.rows.count == 1 {
                        Text("1 file", comment: "One file being checked")
                    } else {
                        Text("\(model.rows.count) files", comment: "Number of files being checked")
                    }
                }
                .foregroundStyle(.secondary)
            }

            HStack {
                TextField(
                    "Paste a CRC-32, MD5, SHA-1 or SHA-256 checksum",
                    text: $model.expectedInput
                )
                .textFieldStyle(.roundedBorder)
                Button(action: model.paste) {
                    Text("Paste", comment: "Paste an expected checksum from the clipboard")
                }
            }
            if !model.expectedInput.isEmpty && model.expected == nil {
                Text("Copy one complete checksum to compare it with the selected files.",
                     comment: "Shown when clipboard text is not one recognizable checksum")
                    .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.rows) { row in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(row.file.lastPathComponent)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    if let checksums = row.checksums, let expected = model.expected {
                                        Label(
                                            expected.matches(checksums)
                                                ? String(localized: "Checksum matches", comment: "File matches copied checksum")
                                                : String(localized: "Checksum does not match", comment: "File differs from copied checksum"),
                                            systemImage: expected.matches(checksums) ? "checkmark.circle.fill" : "xmark.circle.fill"
                                        )
                                        .foregroundStyle(expected.matches(checksums) ? .green : .red)
                                    }
                                }
                                if let checksums = row.checksums {
                                    ForEach(ChecksumAlgorithm.allCases, id: \.self) { algorithm in
                                        HStack(spacing: 8) {
                                            Text(algorithm.rawValue)
                                                .frame(width: 62, alignment: .leading)
                                            Text(checksums.value(for: algorithm))
                                                .font(.system(size: 11, design: .monospaced))
                                                .textSelection(.enabled)
                                            Spacer(minLength: 0)
                                            Button {
                                                model.copy(checksums.value(for: algorithm))
                                            } label: {
                                                Text("Copy", comment: "Copy this file checksum to the clipboard")
                                            }
                                            if algorithm == .sha256 {
                                                Button {
                                                    model.saveSHA256(for: row)
                                                } label: {
                                                    Text("Save .sha256…", comment: "Write this file's SHA-256 checksum to a checksum file")
                                                }
                                            }
                                        }
                                    }
                                } else if let error = row.error {
                                    Text(error).foregroundStyle(.red)
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 690, minHeight: 360)
    }
}
