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

struct HomeView: View {
    @EnvironmentObject private var state: ArchiveState

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

                    learnSection
                        .frame(width: 220, alignment: .leading)

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
        .onAppear { recents = Array(RecentArchives.urls.prefix(maxRecents)) }
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

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, trailing: AnyView? = nil,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let trailing { trailing.font(.callout) }
            }
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
