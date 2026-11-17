//
//  WelcomeView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation

import SwiftUI

struct WelcomeView: View {
    /// The app's own icon at the size shown. It carries the standard macOS
    /// margin (the body is 824 of 1024), so 60pt draws a 48pt body, with the
    /// margin padded away.
    private var appIcon: NSImage { .appIcon(size: 60) }

    /// Names the version whose highlights the window lists.
    private var whatsNew: LocalizedStringResource {
        if let version = ChangelogLoader.versions.first?.version {
            .welcomeWhatsNewInVersion(version)
        } else {
            .commonWhatsNew
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .padding(-6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(.welcomeTitle(Bundle.main.displayName))
                        .font(.largeTitle.bold())
                    Text(whatsNew)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 24)

            HStack(spacing: 0) {
                WelcomeChangelogView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .padding(.vertical, 24)

                WelcomeMoreFromLeanBytesView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // as tall as the taller column, which the divider spans
            .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.horizontal, 24)

            WelcomeFooterView()
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    WelcomeView()
        .frame(width: 800)
}
