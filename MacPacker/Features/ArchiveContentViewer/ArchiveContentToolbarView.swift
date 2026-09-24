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
        panel.prompt = String(localized: .commonAdd)
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
        ToolbarItem(placement: .navigation) {
            Button {
                archiveState.openParent()
            } label: {
                Label {
                    Text(.commonBack)
                } icon: {
                    Image(systemName: "chevron.backward")
                }
            }
            .help(Text(.archiveBrowseEnclosingFolder))
            .disabled(!archiveState.canGoUp)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                addFilesViaOpenPanel()
            } label: {
                Label {
                    Text(.commonAdd)
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .help(.archiveContentViewerAddHint)
            .disabled(!archiveState.canAddHere)

            Button {
                archiveState.remove(items: archiveState.selectedItems)
            } label: {
                Label {
                    Text(.commonDelete)
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .help(.archiveBrowseDeleteSelectedHint)
            .disabled(!archiveState.canRemove(archiveState.selectedItems))

            Spacer()
            
            Button {
                archiveState.updateSelectedItemForQuickLook()
            } label: {
                Label {
                    Text(.commonPreview)
                } icon: {
                    Image("custom.document.badge.eye")
                }
            }
            .help(.archiveBrowseQuickLook)
            
            Button {
                isExportingItem.toggle()
            } label: {
                Label {
                    Text(.commonExtractSelected)
                } icon: {
                    Image("custom.document.badge.arrow.down")
                }
            }
            .help(.commonExtractSelected)
            .fileImporter(
                isPresented: $isExportingItem,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                        archiveState.extract(
                            items: archiveState.selectedItems,
                            to: folderURL,
                            smart: Keys.smartExtractionEnabled())
                }
            }
            
            Button {
                isExportingAll.toggle()
            } label: {
                Label {
                    Text(.commonExtractArchive)
                } icon: {
                    Image("custom.shippingbox.badge.arrow.down")
                }
            }
            .help(.commonExtractArchive)
            .fileImporter(
                isPresented: $isExportingAll,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                        archiveState.extract(
                            to: folderURL,
                            smart: Keys.smartExtractionEnabled())
                }
            }
            
            Spacer()
            
            Menu {
                Button {
                    openQuickCompressWindow()
                } label: {
                    Label {
                        Text(.commonQuickCompressWindow)
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
                        Text(.commonSettings)
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
                        Text(.archiveContentViewerArchiveInfo)
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
                        Text(.commonHelpWithTranslation)
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
                            Text(.contactFeature)
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    
                    Button {
                        openURL(URL(string: "https://github.com/sarensw/MacPacker/issues/new?assignees=&labels=bug&projects=&template=bug_report.md&title=")!)
                    } label: {
                        Label {
                            Text(.contactBug)
                        } icon: {
                            Image(systemName: "ladybug")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    
                    Button {
                        openURL(URL(string: "mailto:\(Constants.supportMail)")!)
                    } label: {
                        Label {
                            Text(.contactEmail(Constants.supportMail))
                        } icon: {
                            Image(systemName: "mail")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                } label: {
                    Label {
                        Text(.contactMenuIntro)
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
                        openURL(Constants.otherAppFrameBeastURL)
                    } label: {
                        Label {
                            Text(verbatim: "\(Constants.otherAppFrameBeast)")
                        } icon: {
                            Image(nsImage: .menuIcon(named: "AppIcon_FrameBeast"))
                        }
                        .labelStyle(.titleAndIcon)
                        // Deliberately untranslated, see WelcomeMoreFromLeanBytesView.
                        Text("MacPackers app store & social media assets are made with this app", tableName: "LeanBytes", comment: "Short description of the FrameBeast app")
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
                    Text(.commonWebsite)
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
                        Text(.commonAbout(Bundle.main.displayName))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .labelStyle(.titleAndIcon)
                }
            } label: {
                Label {
                    Text(.commonMore)
                } icon: {
                    Image(systemName: "ellipsis")
                }
            }
            .menuIndicator(.hidden)

        }
    }
}
