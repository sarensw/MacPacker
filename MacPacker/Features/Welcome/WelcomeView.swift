//
//  WelcomeView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation

import SwiftUI

struct WelcomeView: View {
    @Environment(\.openURL) private var openURL

    /// The app's own icon at the size shown. The system renders it for exactly
    /// that size, so it stays sharp; a scaled-down bitmap blurs the zipper teeth.
    /// It carries the standard macOS margin (the body is 824 of 1024), so 60pt
    /// draws a 48pt body, with the margin padded away.
    private var appIcon: NSImage {
        let icon = NSApp.applicationIconImage.copy() as! NSImage
        icon.size = NSSize(width: 60, height: 60)
        return icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .padding(-6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(.welcomeTitle(Bundle.main.displayName))
                        .font(.largeTitle.bold())
                    Text(.commonWhatsNew)
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

                VStack(alignment: .leading, spacing: 0) {
                    WelcomeMoreFromLeanBytesView()
                    Divider()
                        .padding(.vertical, 20)
                    WelcomeNewsletterView()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // both columns as tall as the taller one, so "Coming next" sits at the bottom
            .fixedSize(horizontal: false, vertical: true)

            #if !STORE
            Divider()
            HStack(spacing: 16) {
                Image(systemName: "heart")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(.welcomeSupportTitle)
                        .font(.title3.weight(.semibold))
                    Text(.welcomeSupportSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openURL(URL(string: "https://www.buymeacoffee.com/sarensw")!)
                } label: {
                    Text(.welcomeSupportButton)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.orange.opacity(0.08))
            #endif

            Divider()

            WelcomeFooterView()
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    WelcomeView()
        .frame(width: 800)
}
