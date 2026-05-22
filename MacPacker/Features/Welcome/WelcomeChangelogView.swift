//
//  ChangelogView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import Foundation
import SwiftUI

enum ChangelogType: String {
    case feat
    case fix
    case core
    case release
}

struct Changelog: Decodable {
    let comingNext: [String: String]
    let versions: [ChangelogVersion]
}

struct ChangelogVersion: Decodable {
    let version: String
    let items: [ChangelogItem]
}

struct ChangelogItem: Decodable, Identifiable {
    var id: String { "\(type)-\(title.values.joined())" }

    let type: String
    let title: [String: String]
    let pr: Int?
}

final class ChangelogLoader {
    private static func loadChangelog() -> Changelog? {
        guard let url = Bundle.main.url(forResource: "Changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let changelog = try? JSONDecoder().decode(Changelog.self, from: data)
        return changelog
    }
    
    static func loadComingNext() -> [String: String] {
        guard let changelog = loadChangelog() else {
            return ["": ""]
        }
        return changelog.comingNext
    }
    
    static func loadCurrentItems() -> [ChangelogItem] {
        guard let changelog = loadChangelog() else {
            return []
        }

        let bundleVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let isDevVersion =
            bundleVersion.contains("dev") ||
            bundleVersion.contains("snapshot") ||
            bundleVersion.contains("beta")
        
        if isDevVersion {
            return changelog.versions
                .max { AppVersion($0.version) < AppVersion($1.version) }?
                .items ?? []
        }

        let currentVersion = AppVersion(bundleVersion)

        return changelog.versions
            .filter { AppVersion($0.version) <= currentVersion }
            .max { AppVersion($0.version) < AppVersion($1.version) }?
            .items ?? []
    }
}

struct AppVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ string: String) {
        let parts = string.split(separator: ".").map { Int($0) ?? 0 }

        self.major = parts.indices.contains(0) ? parts[0] : 0
        self.minor = parts.indices.contains(1) ? parts[1] : 0
        self.patch = parts.indices.contains(2) ? parts[2] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
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

extension Color {
    static let limeGreen = Color(
        red: 135.0 / 255.0,
        green: 183.0 / 255.0,
        blue: 86.0 / 255.0
    )
    
    static let softRed = Color(
        red: 201.0 / 255.0,
        green: 92.0 / 255.0,
        blue: 92.0 / 255.0
    )
    
    static let softYellow = Color(
        red: 219.0 / 255.0,
        green: 184.0 / 255.0,
        blue: 84.0 / 255.0
    )
    
    static let softBlue = Color(
        red: 91.0 / 255.0,
        green: 145.0 / 255.0,
        blue: 201.0 / 255.0
    )
    
    static let softPurple = Color(
        red: 151.0 / 255.0,
        green: 113.0 / 255.0,
        blue: 184.0 / 255.0
    )
}

struct WelcomeChangelogView: View {
    private let items = ChangelogLoader.loadCurrentItems()
    private let comingNext = ChangelogLoader.loadComingNext()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("What's new", comment: "Header of the changelog shown in the welcome page.")
                    .font(.body)
                    .fontWeight(.bold)
                
                Text(verbatim: "v\(Bundle.main.appVersionLong)")
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(items) { item in
                    ChangelogPillView(item: item)
                }
            }
            .padding(.top, 12)
            
            HStack(alignment: .firstTextBaseline) {
                Text("Coming next", comment: "Header of the upcoming big changes shown in the welcome page")
                    .font(.body)
                    .fontWeight(.bold)
                Text(localizedChangelogText(comingNext))
                    .font(.body)
                    .fontWeight(.light)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
    }
}

struct ChangelogPillView: View {
    let item: ChangelogItem

    private var type: ChangelogType {
        ChangelogType(rawValue: item.type) ?? .core
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            switch type {
            case .feat: PillView(.feature)
            case .fix: PillView(.fix)
            case .release: PillView(.release)
            case .core: PillView(.core)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(localizedChangelogText(item.title))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 10)
            
            Spacer()
        }
    }
}
