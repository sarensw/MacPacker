//
//  ArchiveContentToolbarView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import Core
import SwiftUI

extension NSImage {
    static func menuIcon(named name: String, pointSize: CGFloat = 24) -> NSImage {
        let src = NSImage(imageLiteralResourceName: name)
        src.size = NSSize(width: pointSize, height: pointSize)
        return src
    }
}

struct ArchiveContentToolbarView: ToolbarContent {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openQuickCompressWindow) private var openQuickCompressWindow
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings
    @State private var isExportingItem: Bool = false
    @State private var isExportingAll: Bool = false
    
    @ObservedObject var archiveState: ArchiveState
    let contentService: ArchiveContentService = ArchiveContentService()
    
    /// Lets the user pick files/folders and adds them to the current
    /// archive at the currently shown path.
    private func addFilesViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add", comment: "Prompt of the open panel used to add files to an archive")
        let state = archiveState
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                for url in panel.urls {
                    state.add(url: url)
                }
            }
        }
    }

    private var moreAppsTitle: AttributedString {
        var title = AttributedString(localized: LocalizedStringResource("More Apps", table: "LeanBytes", comment: "Hint to the user that the submenu contains links for more apps that they might like."))
        title.append(AttributedString(stringLiteral: " "))
        
//        var dot = AttributedString(stringLiteral: "●")
//        dot.foregroundColor = .accentColor
//        dot.font = .system(size: 7)
//        dot.baselineOffset = 2
//        title.append(dot)
        return title
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                addFilesViaOpenPanel()
            } label: {
                Label {
                    Text("Add", comment: "Button in the tooblar that allows the user to add a file to the current archive path.")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .help("Add files or folders to the archive")
            .disabled(!archiveState.canBeEdited || archiveState.isSaving)

            Button {
                archiveState.remove(items: archiveState.selectedItems)
            } label: {
                Label {
                    Text("Delete", comment: "Button in the toolbar that deletes the selected files from the archive.")
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .help("Delete the selected items from the archive")
            .disabled(!archiveState.canBeEdited || archiveState.selectedItems.isEmpty || archiveState.isSaving)

            Spacer()
            
            Button {
                archiveState.updateSelectedItemForQuickLook()
            } label: {
                Label {
                    Text("Preview", comment: "Button in the tooblar that allows the user to preview the selected file.")
                } icon: {
                    Image("custom.document.badge.eye")
                }
            }
            .help("Quick Look")
            
            Button {
                isExportingItem.toggle()
            } label: {
                Label {
                    Text("Extract selected", comment: "Button in the tooblar that allows the user to extract the selected files.")
                } icon: {
                    Image("custom.document.badge.arrow.down")
                }
            }
            .help("Extract selected")
            .fileImporter(
                isPresented: $isExportingItem,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                        archiveState.extract(
                            items: archiveState.selectedItems,
                            to: folderURL)
                }
            }
            
            Button {
                isExportingAll.toggle()
            } label: {
                Label {
                    Text("Extract archive", comment: "Button in the toolbar that allows the user to extract the full archive to a target directory.")
                } icon: {
                    Image("custom.shippingbox.badge.arrow.down")
                }
            }
            .help("Extract archive")
            .fileImporter(
                isPresented: $isExportingAll,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                        archiveState.extract(
                            to: folderURL)
                }
            }
            
            Spacer()
            
            Menu {
                Button {
                    openQuickCompressWindow()
                } label: {
                    Label {
                        Text("Quick Compress Window", comment: "Opens the small floating window that compresses whatever is dropped on it. Used in the File menu and in the More menu of the archive window.")
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                    .labelStyle(.titleAndIcon)
                }

                Divider()

                Button {
                    appState.selectedSettingsTab = .general
                    openSettings()
                } label: {
                    Label {
                        Text("Settings...", comment: "Used to open the settings/preferences window")
                    } icon: {
                        Image(systemName: "gear")
                    }
                    .labelStyle(.titleAndIcon)
                }
                
                Divider()
                
                Button {
                    if let url = archiveState.url {
                        contentService.openGetInfoWnd(for: [url])
                    }
                } label: {
                    Label {
                        Text("Archive info", comment: "Used to open Quick Look feature for the current archive file")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .labelStyle(.titleAndIcon)
                }
                
                Divider()
                
                SendSmileView()
                
                Button {
                    openURL(URL(string: "https://poeditor.com/join/project/J2Qq2SUzYr")!)
                } label: {
                    Label {
                        Text("Help with translation", comment: "Menu item that opens the translation contribution page")
                    } icon: {
                        Image(systemName: "flag")
                    }
                    .labelStyle(.titleAndIcon)
                }
                
                Menu {
                    Button {
                        openURL(URL(string: "https://github.com/sarensw/MacPacker/issues/new?assignees=&labels=enhancement&projects=&template=&title=")!)
                    } label: {
                        Label {
                            Text("... request a Feature", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev.")
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    
                    Button {
                        openURL(URL(string: "https://github.com/sarensw/MacPacker/issues/new?assignees=&labels=bug&projects=&template=bug_report.md&title=")!)
                    } label: {
                        Label {
                            Text("... raise a Bug", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev.")
                        } icon: {
                            Image(systemName: "ladybug")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    
                    Button {
                        openURL(URL(string: "mailto:\(Constants.supportMail)")!)
                    } label: {
                        Label {
                            Text("... send a mail to \(Constants.supportMail)", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev.")
                        } icon: {
                            Image(systemName: "mail")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                } label: {
                    Label {
                        Text("Go here to ...", comment: "This is the menu in the 'More' menu of the archive window to give customers a hint what they can do to reach the dev. A submenu will open with links to GitHub, a bug report form, and a mail to the developer.")
                    } icon: {
                        Image(systemName: "exclamationmark.bubble")
                    }
                    .labelStyle(.titleAndIcon)
                }
                
                Divider()
                
                Menu {
                    Button {
                        openURL(Constants.otherAppFlowMooseURL)
                    } label: {
                        Label {
                            Text(verbatim: "\(Constants.otherAppFlowMoose)")
                        } icon: {
                            Image(nsImage: .menuIcon(named: "AppIcon_FlowMoose"))
                        }
                        .labelStyle(.titleAndIcon)
                        Text("Do more with your voice", tableName: "LeanBytes", comment: "Short description of the FlowMoose app")
                    }
                    
                    Button {
                        openURL(Constants.otherAppFileFilletURL)
                    } label: {
                        Label {
                            Text(verbatim: "\(Constants.otherAppFileFillet)")
                        } icon: {
                            Image(nsImage: .menuIcon(named: "AppIcon_FileFillet"))
                        }
                        .labelStyle(.titleAndIcon)
                        Text("Organize files. Fast.", tableName: "LeanBytes", comment: "Short description of the FileFillet app")
                    }

                    Button {
                        openURL(Constants.otherAppFrameBisonURL)
                    } label: {
                        Label {
                            Text(verbatim: "\(Constants.otherAppFrameBison)")
                        } icon: {
                            Image(nsImage: .menuIcon(named: "AppIcon_FrameBison"))
                        }
                        .labelStyle(.titleAndIcon)
                        // Deliberately untranslated, see WelcomeMoreFromLeanBytesView.
                        Text("MacPackers app store & social media assets are made with this app", tableName: "LeanBytes", comment: "Short description of the FrameBison app")
                    }
                } label: {
                    Label {
                        Text(moreAppsTitle)
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                .labelStyle(.titleAndIcon)
                
                Button {
                    openURL(URL(string: "https://macpacker.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!)
                } label: {
                    Text("Website", comment: "Hint to the user that the button links to the app's website.")
                }
                
                Button {
                    openURL(URL(string: "https://github.com/sarensw/MacPacker/")!)
                } label: {
                    Text(verbatim: Constants.otherAppGitHub)
                }
                
                Button {
                    appState.selectedSettingsTab = .about
                    openSettings()
                } label: {
                    Label {
                        Text("About \(Bundle.main.displayName)")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .labelStyle(.titleAndIcon)
                }
            } label: {
                Label {
                    Text("More", comment: "The 'More' menu in the archive window")
                } icon: {
                    Image(systemName: "ellipsis")
                }
            }
            .menuIndicator(.hidden)

        }
    }
}
