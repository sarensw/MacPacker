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
            Text("macOS lets \(Constants.appName) open and write files only where you allow it, which is why a folder-access panel shows up now and then. A grant covers everything inside the folder you pick, so allowing these two puts an end to the asking.", comment: "Explains, in the Permissions settings, why the app asks for folder access and what granting these two folders achieves")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            grantRow(
                label: Text("Home folder:", comment: "Label of the home-folder row in the Permissions settings"),
                help: Text("Covers the Desktop, Documents, Downloads and everything else in your home folder.", comment: "Explains what granting access to the home folder covers"),
                folder: home,
                granted: homeGranted
            ) { homeGranted = true }

            grantRow(
                label: Text("External volumes:", comment: "Label of the external-volumes row in the Permissions settings"),
                help: Text("Covers USB drives, memory cards and network shares, which appear in /Volumes.", comment: "Explains what granting access to the /Volumes folder covers"),
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
                        Text("Access granted", comment: "Shown in the Permissions settings once the app has access to a folder")
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
                        Text("Grant Access", comment: "Confirmation button in the file- and folder-access panel")
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
