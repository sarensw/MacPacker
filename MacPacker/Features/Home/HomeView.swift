//
//  HomeView.swift
//  MacPacker
//
//  What an empty window shows: the two things you can do, the archives you opened
//  last, and where to read up. Same start-page shape as TailBeat's (VS Code style):
//  left-aligned, laid out in columns rather than stacked down the middle.
//  Dropping a file anywhere on it opens that file — the drop itself is handled by
//  `ArchiveView`, which shows this view while no archive is loaded.
//

import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "home")

/// Numbers the home screen and the drag overlay both need: the overlay draws its
/// "compress" card exactly over the compress column, so the two can't disagree
/// about where dropping compresses.
enum HomeLayout {
    /// Wide enough for a long section title beside the header controls. German
    /// "Schnelles Komprimieren" is the measure: 153pt at `.headline` vs 104pt en.
    static let sideColumnWidth: CGFloat = 264

    /// One height for every header, text or control — otherwise the column with a
    /// control in its header starts lower and nothing below lines up.
    /// ponytail: one number rather than measuring; raise it if a control needs more.
    static let sectionHeaderHeight: CGFloat = 22
}

struct HomeView: View {
    @EnvironmentObject private var state: ArchiveState
    @EnvironmentObject private var compressor: DropCompressor
    @Environment(\.openQuickCompressWindow) private var openQuickCompressWindow

    /// SwiftUI owns this binding and resets it when no drag is in flight, so the
    /// screenshot pin has to be a separate flag.
    @State private var isDropTargeted = false
    /// Screenshot-only: forces the marked state with no drag in flight.
    @State private var pinnedTarget = false

    private var isCompressTargeted: Bool { isDropTargeted || pinnedTarget }

    /// Read once when the window appears: a window showing this view has no
    /// archive, so opening one from here replaces the view anyway.
    @State private var recents: [URL] = []

    private let maxRecents = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 24) {
                        startSection
                        recentSection
                    }
                    .frame(maxWidth: 460, alignment: .leading)

                    VStack(alignment: .leading, spacing: 24) {
                        compressSection
                        learnSection
                    }
                    .frame(width: HomeLayout.sideColumnWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
            }
            // room to breathe, but the whole page still has to clear a 500pt window
            // (less toolbar, tab bar and status bar) without scrolling
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            recents = Array(RecentArchives.urls.prefix(maxRecents))
            #if DEBUG
            // -DropZone compress pins the marked state for a screenshot: no drag
            // is in flight, so nothing would arm it.
            if LaunchParameters.pinsCompressArea { pinnedTarget = true }
            #endif
        }
    }

    // MARK: - Sections

    private var startSection: some View {
        section("Start") {
            VStack(spacing: 10) {
                StartCard(
                    icon: "folder",
                    title: String(localized: "Open Archive…", comment: "Start-page card that shows the open panel")
                ) { openUsingPanel() }

                // Also the name the new archive carries until it is saved.
                let newArchive = String(localized: "New Archive", comment: "Start-page card that starts a new, empty archive in this window")
                StartCard(icon: "doc.badge.plus", title: newArchive) { state.create(named: newArchive) }
            }
        }
    }

    private var recentSection: some View {
        section("Recent", trailing: recents.isEmpty ? nil : AnyView(
            Button("Clear", action: clearRecents).buttonStyle(.link)
        )) {
            if recents.isEmpty {
                Text("No recent archives.", comment: "Shown in place of the recents list on the start page when nothing has been opened yet")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            } else {
                ForEach(recents, id: \.self) { url in
                    RecentRow(url: url) { open(url) }
                }
            }
        }
    }

    /// The quick path: drop files, get an archive next to them. Its own drop
    /// target — SwiftUI hit-tests to the innermost target that accepts, so a
    /// release here compresses and a release anywhere else opens.
    private var compressSection: some View {
        section("Quick Compress", trailing: AnyView(compressHeaderControls), pinTrailingRight: true) {
            Image(systemName: CompressDropIcon.name)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isCompressTargeted ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(isCompressTargeted ? 0.09 : 0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(isCompressTargeted ? 0.42 : 0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: isCompressTargeted ? [] : [5])))
                .overlay(alignment: .bottom) {
                    if isCompressTargeted {
                        Text("Compress here",
                             comment: "Drop zone shown while dragging files over the compress area: releasing here writes an archive next to those files, without opening a window.")
                            .font(.callout.weight(.medium))
                            .padding(.bottom, 10)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: isCompressTargeted)
                .accessibilityIdentifier("home.compressDropArea")
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleCompressDrop(providers)
                    return true
                }
                .padding(.horizontal, 8)

            // Progress and failures stay here rather than opening a window: a drop
            // on the start page should report on the start page.
            CompressJobList(compressor: compressor)
                .padding(.horizontal, 8)
        }
    }

    /// One drop is one archive, so the urls are collected and handed over together.
    private func handleCompressDrop(_ providers: [NSItemProvider]) {
        let options = CompressSettings.current
        let compressor = self.compressor
        loadDroppedFileURLs(from: providers) { urls in
            log.notice("Start page compress drop", context: ["files": "\(urls.count)"])
            compressor.compress(files: urls, options: options)
        }
    }

    private var compressHeaderControls: some View {
        HStack(spacing: 2) {
            CompressFormatMenu()

            Button {
                showDropWindow()
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            // .plain, not .borderless: a borderless button carries its own
            // trailing inset, which pushes the icon past the right edge of the
            // drop area below it.
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help(Text("Quick Compress Window",
                       comment: "Opens the small floating window that compresses whatever is dropped on it. Used in the File menu and in the More menu of the archive window."))
        }
    }

    private var learnSection: some View {
        section("Learn") {
            DocLinkRow(icon: "book", title: String(localized: "Learn to use \(Bundle.main.displayName)"),
                       detail: String(localized: "Guides & documentation", comment: "Detail line of the documentation link on the start page"),
                       url: Constants.docsURL)
            DocLinkRow(icon: "sparkles", title: String(localized: "What's new", comment: "Start-page link to the release notes"),
                       detail: String(localized: "Release notes", comment: "Detail line of the release-notes link on the start page"),
                       url: Constants.changelogURL)
        }
    }

    /// `pinTrailingRight` puts the trailing view at the column's right edge, where
    /// a control belongs; "Recent ▸ Clear" reads as title and stays put.
    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, trailing: AnyView? = nil,
                                        pinTrailingRight: Bool = false,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if pinTrailingRight { Spacer(minLength: 4) }
                if let trailing { trailing.font(.callout) }
            }
            .controlSize(.small)
            .frame(height: HomeLayout.sectionHeaderHeight)
            .padding(.horizontal, 8)
            content()
        }
    }

    // MARK: - Actions

    /// Opens in *this* window — it's empty, that's why the start page is up.
    private func open(_ url: URL) {
        if state.isSupportedArchive(url: url) { RecentArchives.note(url) }
        state.openDropped(url: url)
    }

    private func showDropWindow() {
        openQuickCompressWindow()
    }

    private func clearRecents() {
        RecentArchives.clear()
        recents = []
    }

    private func openUsingPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in open(url) }
        }
    }
}

/// The primary call to action: a card-style button (glyph + title, bordered,
/// hover-lit) so it reads as something to click, not a text line.
private struct StartCard: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Everything except finished successes: a running compress keeps its row so the
/// write has a progress bar, a failure has nowhere else to show, and a finished
/// archive announces itself by appearing in the Finder window the files came from.
/// A type rather than inline lines because `@ObservedObject` needs a view.
private struct CompressJobList: View {
    @ObservedObject var compressor: DropCompressor

    var body: some View {
        let visible = compressor.jobs.filter { !$0.succeeded }
        if !visible.isEmpty {
            VStack(spacing: 4) {
                ForEach(visible) { DropJobRow(job: $0) }
            }
        }
    }
}

/// A "Learn" link: glyph + tinted title with a muted detail beneath it.
private struct DocLinkRow: View {
    let icon: String
    let title: String
    let detail: String
    let url: URL

    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button { openURL(url) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(.tint)
                    Text(verbatim: detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: url.absoluteString))
        .onHover { hovering = $0 }
    }
}

/// One recent archive: its Finder icon, the file name as a link, and its dimmed
/// directory.
private struct RecentRow: View {
    let url: URL
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(verbatim: url.lastPathComponent)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Text(verbatim: folderLabel)
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: url.path))
        .onHover { hovering = $0 }
    }

    /// `~/Downloads` rather than `/Users/me/Downloads`. NSString's tilde
    /// abbreviation would use the sandbox *container* as home, so the real one is
    /// read from the password database (as `FolderAccessStore` does).
    private var folderLabel: String {
        let path = url.deletingLastPathComponent().path
        guard let pw = getpwuid(getuid()) else { return path }
        let home = String(cString: pw.pointee.pw_dir)
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
