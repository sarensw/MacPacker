//
//  MoreFromLeanBytesView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import Core
import SwiftUI

/// One of the other apps the welcome window can present.
struct OtherApp {
    let name: String
    let icon: String
    let summary: LocalizedStringResource
    let url: URL

    static let fileFillet = OtherApp(name: Constants.otherAppFileFillet, icon: "AppIcon_FileFillet", summary: .LeanBytes.fileFillet, url: Constants.otherAppFileFilletURL)

    static let all = [
        OtherApp(name: Constants.otherAppFlowMoose, icon: "AppIcon_FlowMoose", summary: .LeanBytes.flowMoose, url: Constants.otherAppFlowMooseURL),
        fileFillet,
        OtherApp(name: Constants.otherAppFrameBeast, icon: "AppIcon_FrameBeast", summary: .LeanBytes.frameBeastShort, url: Constants.otherAppFrameBeastURL),
    ]
}

extension BlackFridayDeal {
    /// Whether the welcome window and the More Apps menu show the deal. The
    /// App Store build leaves it out, as it does "Support MacPacker".
    static var isShown: Bool {
        #if STORE
        return false
        #else
        return isActive()
        #endif
    }
}

struct WelcomeMoreFromLeanBytesView: View {
    private let showsDeal = BlackFridayDeal.isShown
    /// A different app each time the window opens; "See all my apps" has the
    /// rest. While the Black Friday deal runs, always FileFillet.
    @State private var app = BlackFridayDeal.isShown ? OtherApp.fileFillet : OtherApp.all.randomElement()!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.LeanBytes.welcomeFromTheMaker(Constants.appName))
                .font(.title2.bold())

            if showsDeal {
                Link(destination: Constants.blackFridayWelcomeURL) {
                    BlackFridayBanner()
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }

            HStack(alignment: .top, spacing: 14) {
                Image(app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(verbatim: app.name)
                            .font(.title3.weight(.semibold))
                        if showsDeal {
                            PillView(.deal)
                        }
                    }
                    Text(app.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: app.url) {
                        WelcomeArrowLabel(.LeanBytes.welcomeExploreApp(app.name))
                    }
                    .padding(.top, 3)
                }
            }
            .padding(.top, showsDeal ? 16 : 14)

            Link(destination: Constants.otherAppsURL) {
                WelcomeArrowLabel(.LeanBytes.welcomeSeeAllApps)
            }
            .padding(.top, 16)
        }
    }
}

/// The deal under the column's title. The whole banner is the link.
private struct BlackFridayBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(.LeanBytes.blackFridayDeal)
                    .fontWeight(.semibold)
                Text(.LeanBytes.welcomeBlackFridayUntil(BlackFridayDeal.lastDayText()))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            WelcomeArrowLabel(.LeanBytes.welcomeGetTheDeal)
                .fontWeight(.medium)
                .foregroundStyle(.link)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.4))
        }
        .contentShape(.rect(cornerRadius: 10))
    }
}
