//
//  ChangelogView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import Core
import Foundation
import SwiftUI

enum ChangelogLoader {
    // Source of truth is the bundled product file (Config/products/macpacker.json,
    // flattened to macpacker.json in the app bundle), which nests the changelog
    // under a `changelog` key alongside build identity.
    static let changelog: Changelog? = {
        struct ProductFile: Decodable { let changelog: Changelog }
        guard let url = Bundle.main.url(forResource: "macpacker", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ProductFile.self, from: data).changelog
    }()

    /// Every version this build has shipped, newest first.
    static var versions: [ChangelogVersion] {
        changelog?.versions(upTo: Bundle.main.appVersionLong) ?? []
    }
}

func localizedChangelogText(_ values: [String: String]) -> String {
    let preferred = Bundle.main.preferredLocalizations

    for language in preferred {
        if let value = values[language] {
            return value
        }

        let baseLanguage = language.split(separator: "-").first.map(String.init)

        if let baseLanguage, let value = values[baseLanguage] {
            return value
        }
    }

    return values["en"] ?? values.values.first ?? ""
}

/// Link text with a trailing arrow, like "View all changes →". `arrow.forward`
/// flips for right-to-left languages.
struct WelcomeArrowLabel: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "arrow.forward")
        }
    }
}

struct WelcomeChangelogView: View {
    private let versions = ChangelogLoader.versions
    private let comingNext = ChangelogLoader.changelog?.comingNext ?? [:]
    @State private var showsAllChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.welcomeReleaseHighlights)
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                ForEach(versions.first?.highlights ?? []) { item in
                    ChangelogPillView(item: item)
                }
            }
            .padding(.top, 14)

            Button {
                showsAllChanges = true
            } label: {
                WelcomeArrowLabel(.welcomeViewAllChanges)
            }
            .buttonStyle(.link)
            .padding(.top, 16)
            .popover(isPresented: $showsAllChanges, arrowEdge: .bottom) {
                WelcomeAllChangesView(versions: versions)
            }

            Spacer(minLength: 16)

            if !comingNext.isEmpty {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "clock")
                    Text(.welcomeComingNext)
                        .fontWeight(.semibold)
                    Text(localizedChangelogText(comingNext))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
        }
    }
}

/// Every version this build has shipped, for "View all changes".
struct WelcomeAllChangesView: View {
    let versions: [ChangelogVersion]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(versions, id: \.version) { version in
                    Text(verbatim: "v\(version.version)")
                        .font(.headline)
                        .padding(.top, 10)
                    ForEach(version.items) { item in
                        ChangelogPillView(item: item)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 480)
    }
}

struct ChangelogPillView: View {
    let item: ChangelogItem

    private var pill: PillStyle {
        switch item.type {
        case "feat": .feature
        case "fix": .fix
        case "release": .release
        case "lang": .lang
        default: .core
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            PillView(pill)
            Text(localizedChangelogText(item.title))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
