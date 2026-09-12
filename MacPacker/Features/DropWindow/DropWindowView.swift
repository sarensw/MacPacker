//
//  DropWindowView.swift
//  MacPacker
//
//  Drop files on the window; each drop writes one archive next to them. Format
//  and pin live in the titlebar (the controller puts them there).
//

import AppKit
import Core
import Swift7zip
import SwiftUI
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

struct DropWindowView: View {
    @AppStorage(Keys.dropWindowOptionsExpanded) private var optionsExpanded = false
    @ObservedObject private var options = CompressSettings.shared

    @State private var isTargeted = false

    /// Owns both the writing and the list of rows shown below the drop area.
    @ObservedObject var compressor: DropCompressor

    var body: some View {
        VStack(spacing: 0) {
            dropTarget
            if !visibleJobs.isEmpty { jobRows }
            Divider().opacity(0.5)
            optionsBar
            // Always built, collapsed to zero height — a control inserted
            // mid-animation flashes its opaque backing before it picks up the
            // window's vibrancy. No animation: the window resizes instantly and
            // anything easing here runs against it.
            optionsPanel
                .frame(height: optionsExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(optionsExpanded ? 1 : 0)
                .allowsHitTesting(optionsExpanded)
        }
        // clears the titlebar, which `.fullSizeContentView` runs the content under
        .padding(.top, 28)
        // wide enough for the options while they are open, narrow again after
        .frame(width: optionsExpanded ? 420 : 300)
        .background(WindowDragArea(canMove: true))
        // The drag lights the whole window — the window *is* the target. One fill
        // whose opacity animates, never two fills swapped: swapping the shape
        // style rebuilt the layer each time, which is the flicker on entry. Neutral
        // rather than the accent colour, so it reads as the surface responding and
        // not as a selection.
        .background(Color.primary.opacity(isTargeted ? 0.07 : 0))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
        // ~5 frames at 60Hz: a fade, not a switch
        .animation(.easeOut(duration: 0.08), value: isTargeted)
    }

    // MARK: - Drop target

    private var dropTarget: some View {
        VStack(spacing: 10) {
            Image(systemName: CompressDropIcon.name)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text("Drop here to compress",
                 comment: "Caption of the Quick Compress window. Releasing files on the window creates an archive next to them.")
                .font(.callout.weight(.medium))
        }
        // Hung from the top, not centred: centring drags the icon and caption
        // along as the window grows and shrinks.
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 46)
        .accessibilityIdentifier("quickCompress.dropArea")
    }

    /// Everything except finished successes — those announce themselves by
    /// appearing in the Finder window the files came from. A running job keeps its
    /// row so the write has a progress bar, and a failure has nowhere else to show.
    private var visibleJobs: [DropJob] {
        compressor.jobs.filter { !$0.succeeded }
    }

    private var jobRows: some View {
        VStack(spacing: 4) {
            ForEach(visibleJobs) { DropJobRow(job: $0) }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(WindowDragArea(canMove: false))
    }

    // MARK: - Options

    /// Collapsed, still says what a drop would do.
    private var optionsBar: some View {
        HStack(spacing: 6) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                        .font(.caption2)
                    Text("Options", comment: "Shows or hides the compression settings of the Quick Compress window.")
                }
            }
            .buttonStyle(.plain)
            .background(WindowDragArea(canMove: false))

            Spacer(minLength: 8)

            if !optionsExpanded {
                HStack(spacing: 4) {
                    // a password applies to every drop until it is cleared: say so
                    if !options.password.isEmpty {
                        Image(systemName: "lock.fill")
                            .imageScale(.small)
                    }
                    Text(verbatim: compressionLevelName(options.level))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// Every setting the save panel offers, in the window itself: a drop happens
    /// in one gesture, so the settings behind it should not need a second one.
    ///
    /// Menus, not segmented controls: segmented needs room for every label at
    /// once, and translated names blow past this card's width (Italian wants
    /// 643pt against 248pt). A menu is bounded by the longest single name.
    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(Text("Compression", comment: "Label of the compression level picker in the archive options")) {
                LevelPicker(options: options) {
                    EmptyView()   // the row already carries the label
                }
                .labelsHidden()
                .fixedSize()
            }
            row(Text("Split into volumes", comment: "Label of the picker that writes the archive as several files of a given size")) {
                VolumeControl(options: options)
                    .fixedSize()
                    .accessibilityIdentifier("quickCompress.volumePicker")
            }

            Divider()

            row(Text("Password", comment: "Label of the password field in the archive options")) {
                SecureField(text: $options.password) { EmptyView() }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier("quickCompress.password")
            }
            row(Text("Verify", comment: "Label of the field that repeats the archive password")) {
                SecureField(text: $options.passwordConfirmation) { EmptyView() }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier("quickCompress.passwordVerify")
            }
            if options.encryptions.count > 1 {
                row(Text("Encryption method", comment: "Label of the picker between AES-256 and ZipCrypto")) {
                    EncryptionControl(options: options).fixedSize()
                }
            }
            if options.canEncryptFileNames {
                row(Text("Encrypt file names", comment: "Toggle that hides a 7z archive's file list behind the password")) {
                    Toggle(isOn: $options.encryptFileNames) { EmptyView() }
                        .labelsHidden()
                }
            }
            if let problem = options.passwordProblem {
                Text(verbatim: problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("quickCompress.passwordProblem")
            }

            Divider()

            Group {
                row(Text("Method", comment: "Label of the compression method picker in the archive options")) {
                    MethodControl(options: options).fixedSize()
                }
                if !options.dictionarySizes.isEmpty {
                    row(Text("Dictionary size", comment: "Label of the compression dictionary size picker in the archive options")) {
                        DictionaryControl(options: options).fixedSize()
                    }
                }
                if !options.wordSizes.isEmpty {
                    row(Text("Word size", comment: "Label of the compression word size picker in the archive options (7-Zip's term)")) {
                        WordSizeControl(options: options).fixedSize()
                    }
                }
                if options.hasSolidBlocks {
                    row(Text("Solid block size", comment: "Label of the 7z solid block size picker in the archive options")) {
                        SolidControl(options: options).fixedSize()
                    }
                }
            }
            // at Store nothing is compressed, so these do nothing
            .disabled(!options.compresses)

            row(Text("Exclude .DS_Store files", comment: "Toggle that leaves Finder's hidden .DS_Store files out of the archive")) {
                Toggle(isOn: $options.excludeDSStore) { EmptyView() }
                    .labelsHidden()
                    .accessibilityIdentifier("quickCompress.excludeDSStore")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .background(WindowDragArea(canMove: false))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    /// Label left, control right, as every row in this card.
    @ViewBuilder
    private func row<Control: View>(_ label: Text, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 8)
            control()
        }
    }

    private var fieldWidth: CGFloat { 170 }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        let settings = CompressSettings.current
        loadDroppedFileURLs(from: providers) { urls in
            log.notice("Drop window received \(urls.count) url(s)")
            compressor.compress(files: urls, options: settings.options, excludeDSStore: settings.excludeDSStore)
        }
    }
}

/// Whether a press here drags the window.
///
/// `isMovableByWindowBackground` on the window is what enables dragging at all —
/// `mouseDownCanMoveWindow` only lets a view opt *out*. But SwiftUI renders the
/// whole tree into one `NSHostingView`, so that is one answer for everything and
/// a press on a button slid the window. A real `NSView` per region gets AppKit
/// asking per region, and the nearer view wins.
private struct WindowDragArea: NSViewRepresentable {
    let canMove: Bool

    final class DragView: NSView {
        var canMove = true
        override var mouseDownCanMoveWindow: Bool { canMove }
    }

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.canMove = canMove
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.canMove = canMove
    }
}

/// One row per archive: its name and what became of it. Click reveals it in Finder.
struct DropJobRow: View {
    @ObservedObject var job: DropJob
    /// The writer publishes byte progress here.
    @ObservedObject private var state: ArchiveState

    init(job: DropJob) {
        self.job = job
        self.state = job.state
    }

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: job.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .running = job.outcome {
                    ProgressView(value: Double(state.progress ?? 0), total: 100)
                        .progressViewStyle(.linear)
                } else if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard case .done(let url) = job.outcome else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch job.outcome {
        case .running: Image(systemName: "shippingbox").foregroundStyle(.secondary)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .denied: Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
        }
    }

    private var detail: String? {
        switch job.outcome {
        case .running: return nil
        case .done: return nil   // the check and the name already say it
        case .failed(let message): return message
        case .denied: return String(localized: "Cancelled — no access to that folder",
                                    comment: "Status shown in the drop window when the user declined the permission panel that grants MacPacker access to the folder the archive would be written to.")
        }
    }
}
