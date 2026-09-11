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
        VStack(alignment: .trailing, spacing: 4) {
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
            // Always there, so what the sheet set shows where Save is clicked. The
            // panel sizes the accessory once, so this line never comes and goes.
            summary
                .font(.caption)
                .lineLimit(1)
                .accessibilityIdentifier("saveOptionsSummary")
        }
        .padding(10)
        .onChange(of: options.format) { _, newFormat in
            onFormatChange(newFormat)
        }
    }

    @ViewBuilder private var summary: some View {
        if let problem = options.passwordProblem {
            Text(verbatim: problem.message).foregroundStyle(.red)
        } else {
            Text(verbatim: summaryParts.joined(separator: " · ")).foregroundStyle(.secondary)
        }
    }

    private var summaryParts: [String] {
        var parts: [String] = []
        if options.password.isEmpty {
            parts.append(String(localized: "No password", comment: "Save panel summary: the archive is not encrypted"))
        } else if options.format == .zip && options.encryption == .zipCrypto {
            parts.append(String(localized: "Encrypted with ZipCrypto", comment: "Save panel summary: zip password using the old, weak ZipCrypto"))
        } else if options.canEncryptFileNames && options.encryptFileNames {
            parts.append(String(localized: "Encrypted, names too", comment: "Save panel summary: 7z password that also hides the file names"))
        } else {
            parts.append(String(localized: "Encrypted", comment: "Save panel summary: the archive gets a password"))
        }
        if let size = options.volumeSize {
            parts.append(String(localized: "Split into \(sizeName(size)) volumes", comment: "Save panel summary: the archive is written as several files of this size"))
        }
        if options.excludeDSStore {
            parts.append(String(localized: "Without .DS_Store files", comment: "Save panel summary: Finder's .DS_Store files are left out"))
        }
        return parts
    }
}

/// Everything else, as a sheet over the save panel: a grouped form, the System
/// Settings arrangement, instead of 7-Zip's everything-at-once grid. Only what
/// works on macOS is here — no self-extracting archives, update modes, thread
/// counts or raw 7-Zip parameters.
struct ArchiveSaveOptionsView: View {
    @ObservedObject var options: ArchiveSaveOptions
    var onDone: () -> Void

    private let automatic = Text("Automatic", comment: "Picker entry that leaves a compression setting to the archive format and level")

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    FormatPicker(options: options) {
                        Text("Format", comment: "Label of the archive format picker in the archive options")
                    }
                    .accessibilityIdentifier("saveOptionsFormatPicker")

                    LevelPicker(options: options) {
                        Text("Compression", comment: "Label of the compression level picker in the archive options")
                    }
                    .accessibilityIdentifier("saveOptionsLevelPicker")

                    Picker(selection: $options.volumeSize) {
                        Text("Don't split", comment: "Split choice: write the archive as a single file")
                            .tag(UInt64?.none)
                        ForEach(options.volumeSizes, id: \.self) { size in
                            Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
                        }
                    } label: {
                        Text("Split into volumes", comment: "Label of the picker that writes the archive as several files of a given size")
                    }
                    .accessibilityIdentifier("saveVolumePicker")
                }

                Section {
                    SecureField(text: $options.password) {
                        Text("Password", comment: "Label of the password field in the archive options")
                    }
                    .accessibilityIdentifier("savePasswordField")

                    SecureField(text: $options.passwordConfirmation) {
                        Text("Verify", comment: "Label of the field that repeats the archive password")
                    }
                    .accessibilityIdentifier("savePasswordVerifyField")

                    // zip can still use ZipCrypto for old tools; 7z is AES-256 only
                    if options.encryptions.count > 1 {
                        Picker(selection: $options.encryption) {
                            ForEach(options.encryptions, id: \.self) { encryption in
                                Text(verbatim: encryption.displayName).tag(encryption)
                            }
                        } label: {
                            Text("Encryption method", comment: "Label of the picker between AES-256 and ZipCrypto")
                        }
                        .accessibilityIdentifier("saveEncryptionPicker")
                    }

                    // a zip always lists its file names in the clear
                    if options.canEncryptFileNames {
                        Toggle(isOn: $options.encryptFileNames) {
                            Text("Encrypt file names", comment: "Toggle that hides a 7z archive's file list behind the password")
                        }
                        .accessibilityIdentifier("saveEncryptNamesToggle")
                    }
                } header: {
                    Text("Encryption", comment: "Section header of the password settings in the archive options")
                } footer: {
                    encryptionFooter
                }

                Section {
                    // At Store nothing is compressed, so these do nothing.
                    Group {
                        Picker(selection: $options.method) {
                            automatic.tag(SevenZipCompressionOptions.Method?.none)
                            ForEach(options.methods, id: \.self) { method in
                                Text(verbatim: method.displayName).tag(SevenZipCompressionOptions.Method?.some(method))
                            }
                        } label: {
                            Text("Method", comment: "Label of the compression method picker in the archive options")
                        }
                        .accessibilityIdentifier("saveMethodPicker")

                        if !options.dictionarySizes.isEmpty {
                            Picker(selection: $options.dictionarySize) {
                                automatic.tag(UInt64?.none)
                                ForEach(options.dictionarySizes, id: \.self) { size in
                                    Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
                                }
                            } label: {
                                Text("Dictionary size", comment: "Label of the compression dictionary size picker in the archive options")
                            }
                            .accessibilityIdentifier("saveDictionaryPicker")
                        }

                        if !options.wordSizes.isEmpty {
                            Picker(selection: $options.wordSize) {
                                automatic.tag(UInt32?.none)
                                ForEach(options.wordSizes, id: \.self) { size in
                                    Text(verbatim: "\(size)").tag(UInt32?.some(size))
                                }
                            } label: {
                                Text("Word size", comment: "Label of the compression word size picker in the archive options (7-Zip's term)")
                            }
                            .accessibilityIdentifier("saveWordSizePicker")
                        }

                        if options.hasSolidBlocks {
                            Picker(selection: $options.solidBlockSize) {
                                automatic.tag(UInt64?.none)
                                Text("Non-solid", comment: "Solid block choice: every file compressed on its own")
                                    .tag(UInt64?.some(0))
                                ForEach(options.solidBlockSizes.filter { $0 != .max }, id: \.self) { size in
                                    Text(verbatim: sizeName(size)).tag(UInt64?.some(size))
                                }
                                Text("Solid", comment: "Solid block choice: all files compressed as one block")
                                    .tag(UInt64?.some(.max))
                            } label: {
                                Text("Solid block size", comment: "Label of the 7z solid block size picker in the archive options")
                            }
                            .accessibilityIdentifier("saveSolidPicker")
                        }
                    }
                    .disabled(!options.compresses)

                    Toggle(isOn: $options.excludeDSStore) {
                        Text("Exclude .DS_Store files", comment: "Toggle that leaves Finder's hidden .DS_Store files out of the archive")
                    }
                    .accessibilityIdentifier("saveExcludeDSStoreToggle")
                } header: {
                    Text("Advanced", comment: "Advanced settings")
                }
            }
            .formStyle(.grouped)

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
        .frame(width: 460, height: 540)
    }

    @ViewBuilder private var encryptionFooter: some View {
        if let problem = options.passwordProblem {
            Text(verbatim: problem.message)
                .foregroundStyle(.red)
                .accessibilityIdentifier("savePasswordProblem")
        } else if !options.password.isEmpty && options.format == .zip {
            if options.encryption == .zipCrypto {
                Text("ZipCrypto is easily broken. Pick it only for tools that cannot open AES-256.", comment: "Footer under the archive password when the weak ZipCrypto is picked")
            } else {
                Text("File names stay readable in a zip archive. 7z can encrypt them too.", comment: "Footer under the archive password for zip archives")
            }
        }
    }
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

/// Compression level picker, with 7-Zip's names for the levels.
private struct LevelPicker<Label: View>: View {
    @ObservedObject var options: ArchiveSaveOptions
    @ViewBuilder var label: Label

    var body: some View {
        Picker(selection: $options.level) {
            ForEach(options.levels, id: \.self) { level in
                name(of: level).tag(level)
            }
        } label: {
            label
        }
    }

    private func name(of level: UInt32) -> Text {
        switch level {
        case 0: Text("Store", comment: "Compression level: no compression")
        case 1: Text("Fastest", comment: "Compression level: fastest")
        case 3: Text("Fast", comment: "Compression level: fast")
        case 7: Text("Maximum", comment: "Compression level: maximum")
        case 9: Text("Ultra", comment: "Compression level: ultra, the strongest")
        default: Text("Normal", comment: "Compression level: normal")
        }
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

    /// Sheet on the save panel. Under the App Sandbox the panel is a Powerbox
    /// window hosted out of process — this is the call that has to hold up.
    static func presentOptions(on panel: NSSavePanel, options: ArchiveSaveOptions) {
        var sheet: NSWindow!
        let controller = NSHostingController(rootView: ArchiveSaveOptionsView(options: options) {
            panel.endSheet(sheet)
        })
        sheet = NSWindow(contentViewController: controller)
        sheet.styleMask = [.titled]
        sheet.setContentSize(controller.view.fittingSize)
        panel.beginSheet(sheet) { _ in
            _ = sheet   // keep the sheet alive until it is dismissed
        }
    }
}
