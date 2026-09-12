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
import UniformTypeIdentifiers

/// The save panel's accessory: format and compression, the two choices made on
/// almost every save, with everything else behind "Options…" — 7-Zip's "Add to
/// Archive" dialog, split the way macOS splits a panel from its options sheet.
struct ArchiveSavePanelAccessoryView: View {
    @ObservedObject var options: ArchiveSaveOptions
    var onFormatChange: (ArchiveSaveOptions.Format) -> Void = { _ in }
    var onOptions: () -> Void = {}

    var body: some View {
        HStack(spacing: 16) {
            FormatPicker(options: options) {
                Text("Format:", comment: "Label of the archive format picker in the save panel")
            }
            .fixedSize()
            .accessibilityIdentifier("saveFormatPicker")

            LevelPicker(options: options) {
                Text("Compression:", comment: "Label of the compression level picker in the save panel")
            }
            .fixedSize()
            .accessibilityIdentifier("saveLevelPicker")

            Button(action: onOptions) {
                Text("Options…", comment: "Button in the save panel that opens the advanced archive options")
            }
            .accessibilityIdentifier("saveOptionsButton")
        }
        .padding(10)
        .onChange(of: options.format) { _, newFormat in
            onFormatChange(newFormat)
        }
    }
}

/// The save panel's options, as a sheet: the same rows the Quick Compress
/// window shows, with a Done button under them.
struct ArchiveSaveOptionsView: View {
    @ObservedObject var options: ArchiveSaveOptions
    var onDone: () -> Void

    /// As wide as the Quick Compress window's options. The height follows the
    /// rows, which come and go with the format.
    static let width: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            SaveOptionsRows(options: options)
                .padding(16)
            Divider()
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Done", comment: "Button that closes the archive options sheet")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!options.canSave)
                .accessibilityIdentifier("saveOptionsDoneButton")
            }
            .padding(12)
        }
        .frame(width: Self.width)
    }
}

/// Every save option, as label-and-control rows. Rows rather than a grouped
/// form: the values line up in one column, a password field looks like a field,
/// and the whole set fits without scrolling. Only what works on macOS is here —
/// no self-extracting archives, update modes, thread counts or raw 7-Zip
/// parameters.
struct SaveOptionsRows: View {
    @ObservedObject var options: ArchiveSaveOptions
    /// Quick Compress keeps its format menu in the titlebar, so it hides the row.
    var showsFormat = true

    private let fieldWidth: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsFormat {
                row(Text("Format", comment: "Label of the archive format picker in the archive options")) {
                    FormatPicker(options: options) { EmptyView() }
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("saveOptions.format")
                }
            }
            row(Text("Compression", comment: "Label of the compression level picker in the archive options")) {
                LevelPicker(options: options) { EmptyView() }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("saveOptions.level")
            }
            row(Text("Split into volumes", comment: "Label of the picker that writes the archive as several files of a given size")) {
                VolumeControl(options: options)
                    .fixedSize()
                    .accessibilityIdentifier("saveOptions.volume")
            }

            Divider()

            row(Text("Password", comment: "Label of the password field in the archive options")) {
                SecureField(text: $options.password) { EmptyView() }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier("saveOptions.password")
            }
            row(Text("Verify", comment: "Label of the field that repeats the archive password")) {
                SecureField(text: $options.passwordConfirmation) { EmptyView() }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier("saveOptions.passwordVerify")
            }
            // zip can still use ZipCrypto for old tools; 7z is AES-256 only
            if options.encryptions.count > 1 {
                row(Text("Encryption method", comment: "Label of the picker between AES-256 and ZipCrypto")) {
                    EncryptionControl(options: options)
                        .fixedSize()
                        .accessibilityIdentifier("saveOptions.encryptionMethod")
                }
            }
            // a zip always lists its file names in the clear
            if options.canEncryptFileNames {
                row(Text("Encrypt file names", comment: "Toggle that hides a 7z archive's file list behind the password")) {
                    Toggle(isOn: $options.encryptFileNames) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("saveOptions.encryptNames")
                }
            }
            encryptionNote

            Divider()

            Group {
                row(Text("Method", comment: "Label of the compression method picker in the archive options")) {
                    MethodControl(options: options)
                        .fixedSize()
                        .accessibilityIdentifier("saveOptions.method")
                }
                if !options.dictionarySizes.isEmpty {
                    row(Text("Dictionary size", comment: "Label of the compression dictionary size picker in the archive options")) {
                        DictionaryControl(options: options)
                            .fixedSize()
                            .accessibilityIdentifier("saveOptions.dictionary")
                    }
                }
                if !options.wordSizes.isEmpty {
                    row(Text("Word size", comment: "Label of the compression word size picker in the archive options (7-Zip's term)")) {
                        WordSizeControl(options: options)
                            .fixedSize()
                            .accessibilityIdentifier("saveOptions.wordSize")
                    }
                }
                if options.hasSolidBlocks {
                    row(Text("Solid block size", comment: "Label of the 7z solid block size picker in the archive options")) {
                        SolidControl(options: options)
                            .fixedSize()
                            .accessibilityIdentifier("saveOptions.solid")
                    }
                }
            }
            // at Store nothing is compressed, so these do nothing
            .disabled(!options.compresses)

            row(Text("Exclude .DS_Store files", comment: "Toggle that leaves Finder's hidden .DS_Store files out of the archive")) {
                Toggle(isOn: $options.excludeDSStore) { EmptyView() }
                    .labelsHidden()
                    .accessibilityIdentifier("saveOptions.excludeDSStore")
            }
        }
    }

    /// Label left, control right, so every value sits in the same column.
    @ViewBuilder
    private func row<Control: View>(_ label: Text, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 8)
            control()
        }
    }

    @ViewBuilder private var encryptionNote: some View {
        if let problem = options.passwordProblem {
            note(Text(verbatim: problem.message), red: true)
                .accessibilityIdentifier("saveOptions.problem")
        } else if !options.password.isEmpty && options.format == .zip {
            if options.encryption == .zipCrypto {
                note(Text("ZipCrypto is easily broken. Pick it only for tools that cannot open AES-256.", comment: "Footer under the archive password when the weak ZipCrypto is picked"))
            } else {
                note(Text("File names stay readable in a zip archive. 7z can encrypt them too.", comment: "Footer under the archive password for zip archives"))
            }
        }
    }

    private func note(_ text: Text, red: Bool = false) -> some View {
        text
            .font(.caption)
            .foregroundStyle(red ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The option controls themselves, without labels. The save panel's sheet and
/// the Quick Compress window lay them out differently, but the choices in each
/// menu are written once.
struct VolumeControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.volumeSize) {
            Text("Don't split", comment: "Split choice: write the archive as a single file")
                .tag(UInt64?.none)
            ForEach(options.volumeSizes, id: \.self) { size in
                Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

struct EncryptionControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.encryption) {
            ForEach(options.encryptions, id: \.self) { encryption in
                Text(verbatim: encryption.displayName).tag(encryption)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

struct MethodControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.method) {
            automaticEntry().tag(SevenZipCompressionOptions.Method?.none)
            ForEach(options.methods, id: \.self) { method in
                Text(verbatim: method.displayName).tag(SevenZipCompressionOptions.Method?.some(method))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

struct DictionaryControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.dictionarySize) {
            automaticEntry().tag(UInt64?.none)
            ForEach(options.dictionarySizes, id: \.self) { size in
                Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

struct WordSizeControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.wordSize) {
            automaticEntry().tag(UInt32?.none)
            ForEach(options.wordSizes, id: \.self) { size in
                Text(verbatim: "\(size)").tag(UInt32?.some(size))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

struct SolidControl: View {
    @ObservedObject var options: ArchiveSaveOptions

    var body: some View {
        Picker(selection: $options.solidBlockSize) {
            automaticEntry().tag(UInt64?.none)
            Text("Non-solid", comment: "Solid block choice: every file compressed on its own")
                .tag(UInt64?.some(0))
            ForEach(options.solidBlockSizes.filter { $0 != .max }, id: \.self) { size in
                Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
            }
            Text("Solid", comment: "Solid block choice: all files compressed as one block")
                .tag(UInt64?.some(.max))
        } label: {
            EmptyView()
        }
        .labelsHidden()
    }
}

/// The entry that leaves a setting to the format and the level.
func automaticEntry() -> Text {
    Text("Automatic", comment: "Picker entry that leaves a compression setting to the archive format and level")
}

/// Format picker, the same in the panel and in the sheet.
private struct FormatPicker<Label: View>: View {
    @ObservedObject var options: ArchiveSaveOptions
    @ViewBuilder var label: Label

    var body: some View {
        Picker(selection: $options.format) {
            ForEach(ArchiveSaveOptions.Format.allCases, id: \.self) { format in
                Text(verbatim: format.rawValue).tag(format)
            }
        } label: {
            label
        }
    }
}

/// Compression level picker, with 7-Zip's names for the levels. The save panel,
/// its options sheet and the Quick Compress window all use this one.
struct LevelPicker<Label: View>: View {
    @ObservedObject var options: ArchiveSaveOptions
    @ViewBuilder var label: Label

    var body: some View {
        Picker(selection: $options.level) {
            ForEach(options.levels, id: \.self) { level in
                Text(verbatim: compressionLevelName(level)).tag(level)
            }
        } label: {
            label
        }
    }
}

/// 7-Zip's name for a compression level.
func compressionLevelName(_ level: UInt32) -> String {
    switch level {
    case 0: String(localized: "Store", comment: "Compression level: no compression")
    case 1: String(localized: "Fastest", comment: "Compression level: fastest")
    case 3: String(localized: "Fast", comment: "Compression level: fast")
    case 7: String(localized: "Maximum", comment: "Compression level: maximum")
    case 9: String(localized: "Ultra", comment: "Compression level: ultra, the strongest")
    default: String(localized: "Normal", comment: "Compression level: normal")
    }
}

/// "64 KB", "16 MB": 7-Zip's sizes are binary, BZip2's block sizes decimal.
private func sizeName(_ bytes: UInt64) -> String {
    Int64(clamping: bytes).formatted(.byteCount(style: bytes % 1024 == 0 ? .memory : .decimal))
}

private extension SevenZipCompressionOptions.Method {
    /// How 7-Zip spells the codec in its own UI.
    var displayName: String {
        switch self {
        case .lzma2: return "LZMA2"
        case .lzma: return "LZMA"
        case .deflate: return "Deflate"
        case .bzip2: return "BZip2"
        case .ppmd: return "PPMd"
        case .copy: return "Copy"
        }
    }
}

private extension SevenZipCompressionOptions.Encryption {
    var displayName: String {
        switch self {
        case .aes256: return "AES-256"
        case .zipCrypto: return "ZipCrypto"
        }
    }
}

extension ArchiveSaveOptions.PasswordProblem {
    var message: String {
        switch self {
        case .mismatch:
            String(localized: "The passwords do not match.", comment: "Save options: the password and its verification differ")
        case .notASCII:
            String(localized: "A zip password can only use letters A–Z, digits, spaces and common symbols. 7z takes any password.", comment: "Save options: the zip password has characters zip encryption cannot take")
        case .tooLong:
            String(localized: "With AES-256, a zip password can be at most \(SevenZipCompressionOptions.zipAESPasswordLimit) characters long.", comment: "Save options: the zip password is too long; the number is the limit")
        }
    }
}

/// Keeps Save from going ahead with a password the format cannot take. The sheet
/// does not close on one, but switching the panel to zip after typing a 7z
/// password can still leave one.
@MainActor
private final class SavePanelValidator: NSObject, NSOpenSavePanelDelegate {
    let options: ArchiveSaveOptions

    init(options: ArchiveSaveOptions) {
        self.options = options
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard let problem = options.passwordProblem else { return }
        throw NSError(domain: "app.MacPacker.save", code: 1, userInfo: [
            NSLocalizedDescriptionKey: problem.message,
            NSLocalizedRecoverySuggestionErrorKey: String(localized: "Change the password under Options…", comment: "How to fix a password the save panel refused")
        ])
    }
}

/// Shows the archive save panel — for a new archive, and for Save As — and
/// writes the archive to the picked location.
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
        let options = ArchiveSaveOptions()
        // Save As starts from the archive's own format, a new archive from the
        // format saved last.
        if let own = state.url.flatMap({ ArchiveSaveOptions.Format(rawValue: $0.pathExtension.lowercased()) }) {
            options.format = own
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = String(localized: "New Archive", comment: "Title of the save panel used to create a new archive")
        // Save As opens where the archive is, as documents do
        panel.directoryURL = state.url?.deletingLastPathComponent()

        // The name keeps its base and takes the format's extension; the panel
        // then holds the name to it, so a zip is never written as x.7z.
        let useFormat = { (format: ArchiveSaveOptions.Format, base: String) in
            panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
            panel.nameFieldStringValue = base + "." + format.rawValue
        }
        let baseName = state.name ?? String(localized: "New Archive", comment: "Default file name of a new archive")
        useFormat(options.format, (baseName as NSString).deletingPathExtension)

        let accessory = NSHostingView(rootView: ArchiveSavePanelAccessoryView(
            options: options,
            onFormatChange: { newFormat in
                useFormat(newFormat, (panel.nameFieldStringValue as NSString).deletingPathExtension)
            },
            onOptions: { [weak panel] in
                guard let panel else { return }
                presentOptions(on: panel, options: options)
            }))
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory

        let validator = SavePanelValidator(options: options)
        panel.delegate = validator

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            withExtendedLifetime(validator) {}
            guard response == .OK, let url = panel.url else {
                onSave?(nil)
                return
            }
            options.remember()
            let task = state.save(
                to: url,
                options: options.compressionOptions,
                excludeDSStore: options.excludeDSStore)
            onSave?(task)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// Sheet on the save panel, or on the Quick Compress window. Under the App
    /// Sandbox the save panel is a Powerbox window hosted out of process — this
    /// is the call that has to hold up.
    ///
    /// The sheet goes on screen first and gets its content after. Built before
    /// the sheet was on screen, its switches showed no knob until first clicked.
    static func presentOptions(on window: NSWindow, options: ArchiveSaveOptions) {
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: ArchiveSaveOptionsView.width, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.beginSheet(sheet) { _ in
            _ = sheet   // keep the sheet alive until it is dismissed
        }
        let content = NSHostingView(rootView: ArchiveSaveOptionsView(options: options) { [weak window, weak sheet] in
            guard let window, let sheet else { return }
            window.endSheet(sheet)
        })
        // Constraints, not a frame: 7z shows rows zip does not, and the sheet has
        // to follow when the format changes under it.
        content.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        sheet.contentView = container
        sheet.setContentSize(content.fittingSize)
    }
}
