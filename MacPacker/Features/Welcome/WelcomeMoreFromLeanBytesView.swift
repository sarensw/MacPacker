//
//  MoreFromLeanBytesView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import SwiftUI

struct MoreFromLeanBytesProductView: View {
    @Environment(\.openURL) private var openURL
    
    let logo: String
    let title: String
    let description: String
    let openSource: Bool
    let url: URL
    /// Shown next to the title, e.g. `.earlyAccess` for a product that is not GA yet.
    var pill: PillStyle? = nil
    /// When set, a small "Watch" link opens a short video about the product.
    var videoURL: URL? = nil

    @State private var isHovered: Bool = false
    @State private var isVideoHovered: Bool = false
    /// Height of the product button, so the video button next to it can match.
    /// `maxHeight: .infinity` cannot do this — the row never receives a definite
    /// height proposal, so the flexible child just resolves to its own ideal.
    @State private var rowHeight: CGFloat = 0

    /// Hover highlight for one target. Each button carries its own, so a row
    /// with a video button reads as two separate actions rather than one.
    private func highlight(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                openURL(url)
            } label: {
                HStack {
                    Image(logo)
                        .resizable()
                        .frame(width: 32, height: 32, alignment: .center)

                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text(verbatim: title)
                            if let pill {
                                PillView(pill)
                            }
                        }
                        Text(verbatim: description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Stretch the label across the row and make the gap part of
                    // it, so the whole row is clickable — not just the icon and
                    // the text.
                    Spacer(minLength: 0)
                }
                .padding(8)
                .contentShape(Rectangle())
                .background { highlight(isHovered) }
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
            .onHover { isHovered = $0 }
            .help(Text(verbatim: url.host() ?? ""))

            if let videoURL {
                Button {
                    openURL(videoURL)
                } label: {
                    // ponytail: SF Symbol in YouTube red instead of the real
                    // wordmark — the play-in-a-rounded-rect shape is what makes
                    // people read "video", and it needs no licensed artwork.
                    Label {
                        Text(verbatim: "Watch")
                    } icon: {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(red: 1, green: 0, blue: 0))
                    }
                    .labelStyle(.iconOnly)
                    .padding(8)
                    // Sizing has to happen inside the label: a Button's hit area
                    // is its label, so growing the frame around the Button would
                    // highlight more than it clicks. A definite height is fine
                    // here — only `maxHeight: .infinity` would be circular.
                    .frame(height: rowHeight > 0 ? rowHeight : nil)
                    .contentShape(Rectangle())
                    .background { highlight(isVideoHovered) }
                }
                .buttonStyle(.plain)
                .onHover { isVideoHovered = $0 }
                .help(Text(verbatim: "Watch on YouTube"))
            }
        }
    }
}

struct WelcomeMoreFromLeanBytesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MacPacker is sponsored by my own work at LeanBytes. Supporting the apps below directly supports this open-source tool.", comment: "Explains that supporting the listed LeanBytes apps supports MacPacker")
                .foregroundStyle(.secondary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            
            MoreFromLeanBytesProductView(logo: "AppIcon_FlowMoose", title: Constants.otherAppFlowMoose, description: String(localized: "Voice-2-Text to reduce stress on wrists and arms in the age of AI chats. Offline, local only.", comment: "Description of the FlowMoose app"), openSource: false, url: Constants.otherAppFlowMooseURL)
            
            MoreFromLeanBytesProductView(logo: "AppIcon_FileFillet", title: Constants.otherAppFileFillet, description: String(localized: "Copy or move files to your favorite folders and their sub-folders. No need to open new Finder windows.", comment: "Description of the FileFillet app"), openSource: true, url: Constants.otherAppFileFilletURL)

            // Deliberately untranslated: FrameBison is early access and its
            // pitch still changes, so it stays out of POEditor for now.
            MoreFromLeanBytesProductView(logo: "AppIcon_FrameBison", title: Constants.otherAppFrameBison, description: "I made the App Store screenshots with this tool.", openSource: false, url: Constants.otherAppFrameBisonURL, pill: .earlyAccess, videoURL: Constants.otherAppFrameBisonVideoURL)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}
