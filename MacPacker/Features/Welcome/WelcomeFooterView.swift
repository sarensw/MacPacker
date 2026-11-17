//
//  WelcomeFooterView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.05.26.
//

import SwiftUI

/// Website, privacy, legal notice and contact live in Settings › About.
struct WelcomeFooterView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow

    /// Discord's brand color, #5865F2.
    private static let discordBlurple = Color(red: 88 / 255, green: 101 / 255, blue: 242 / 255)

    var body: some View {
        HStack(spacing: 12) {
            Button {
                openURL(Constants.discordURL)
            } label: {
                Image("discord")
                    .foregroundStyle(Self.discordBlurple)
                Text(.welcomeJoinDiscord)
            }

            #if !STORE
            Button {
                openURL(URL(string: "https://www.buymeacoffee.com/sarensw")!)
            } label: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.orange)
                Text(.welcomeSupportButton(Constants.appName))
            }
            #endif

            Spacer()

            Button {
                dismissWindow()
            } label: {
                Text(.commonContinue)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.extraLarge)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        // Drawn only: a background that takes clicks keeps the window from
        // being dragged by this band, as it can be by the rest of the window.
        .background {
            Rectangle()
                .fill(.fill.secondary)
                .allowsHitTesting(false)
        }
    }
}
