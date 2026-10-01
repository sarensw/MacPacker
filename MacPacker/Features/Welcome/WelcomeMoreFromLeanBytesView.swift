//
//  MoreFromLeanBytesView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import SwiftUI

/// One of the other apps the welcome window can present.
struct OtherApp {
    let name: String
    let icon: String
    let summary: LocalizedStringResource
    let url: URL

    static let all = [
        OtherApp(name: Constants.otherAppFlowMoose, icon: "AppIcon_FlowMoose", summary: .LeanBytes.flowMoose, url: Constants.otherAppFlowMooseURL),
        OtherApp(name: Constants.otherAppFileFillet, icon: "AppIcon_FileFillet", summary: .LeanBytes.fileFillet, url: Constants.otherAppFileFilletURL),
        OtherApp(name: Constants.otherAppFrameBeast, icon: "AppIcon_FrameBeast", summary: .LeanBytes.frameBeastShort, url: Constants.otherAppFrameBeastURL),
    ]
}

struct WelcomeMoreFromLeanBytesView: View {
    /// A different app each time the window opens; "See all my apps" has the rest.
    @State private var app = OtherApp.all.randomElement()!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.LeanBytes.welcomeFromTheMaker(Constants.appName))
                .font(.title2.bold())
            Text(.LeanBytes.welcomeOtherAppsFund)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(alignment: .top, spacing: 14) {
                Image(app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: app.name)
                        .font(.title3.weight(.semibold))
                    Text(app.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: app.url) {
                        WelcomeArrowLabel(.LeanBytes.welcomeExploreApp(app.name))
                    }
                    .padding(.top, 3)
                }
            }
            .padding(.top, 16)

            Link(destination: Constants.otherAppsURL) {
                WelcomeArrowLabel(.LeanBytes.welcomeSeeAllApps)
            }
            .padding(.top, 16)
        }
    }
}
