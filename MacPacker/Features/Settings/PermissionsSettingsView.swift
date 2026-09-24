//
//  PermissionsSettingsView.swift
//  MacPacker
//
//  Two grants, given once, instead of a panel per folder. macOS lets MacPacker
//  read and write only where you allow it, and a grant covers everything below
//  the folder you pick — so one on the home folder and one on /Volumes is
//  effectively everything an archive is ever opened from.
//

import Core
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var homeGranted = false
    @State private var volumesGranted = false

    private let home = FolderAccessStore.homeFolder
    private let volumes = FolderAccessStore.volumesFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.settingsFolderAccessHint(Constants.appName))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            grantRow(
                label: Text(.settingsHomeFolder),
                help: Text(.settingsHomeFolderScopeHint),
                folder: home,
                granted: homeGranted
            ) { homeGranted = true }

            grantRow(
                label: Text(.settingsExternalVolumes),
                help: Text(.settingsExternalVolumesScopeHint),
                folder: volumes,
                granted: volumesGranted
            ) { volumesGranted = true }

            Spacer()
        }
        .padding()
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func grantRow(
        label: Text,
        help: Text,
        folder: URL?,
        granted: Bool,
        onGranted: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            label
                .frame(width: 160, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                if granted {
                    Label {
                        Text(.settingsAccessGranted)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    Button {
                        guard let folder else { return }
                        Task { @MainActor in
                            if await FolderAccessStore.shared.grantAccess(to: folder) { onGranted() }
                        }
                    } label: {
                        Text(.commonGrantAccess)
                    }
                    .disabled(folder == nil)
                }

                help
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 320, alignment: .leading)
        }
    }

    private func refresh() {
        let store = FolderAccessStore.shared
        homeGranted = home.map { store.hasAccess(to: $0) } ?? false
        volumesGranted = store.hasAccess(to: volumes)
    }
}

#Preview {
    PermissionsSettingsView()
}
