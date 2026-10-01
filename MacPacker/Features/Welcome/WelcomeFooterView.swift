//
//  WelcomeFooterView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.05.26.
//

import SwiftUI

struct WelcomeFooterView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        openURL(Constants.homepageURL)
                    } label: {
                        Text(.commonWebsite)
                    }
                    Text(verbatim: "·")
                    Button {
                        openURL(Constants.privacyURL)
                    } label: {
                        Text(.commonPrivacy)
                    }
                    Text(verbatim: "·")
                    Button {
                        openURL(Constants.imprintURL)
                    } label: {
                        Text(.commonImprint)
                    }
                    Text(verbatim: "·")
                    Button {
                        openURL(URL(string: "mailto:\(Constants.supportMail)")!)
                    } label: {
                        Text(verbatim: Constants.supportMail)
                    }
                }
                Text(verbatim: "© 2026 Stephan Arenswald · Stuttgart, Germany")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismissWindow()
            } label: {
                Text(.commonContinue)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}
