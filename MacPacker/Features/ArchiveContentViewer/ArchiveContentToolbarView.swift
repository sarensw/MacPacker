//
//  ArchiveContentToolbarView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import Core
import SwiftUI

extension NSImage {
    static func menuIcon(named name: String, pointSize: CGFloat = 16) -> NSImage {
        let src = NSImage(imageLiteralResourceName: name)
        src.size = NSSize(width: pointSize, height: pointSize)
        return src
    }
}

struct ArchiveContentToolbarView: ToolbarContent {
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.openURL) var openURL
    @State private var isExportingItem: Bool = false
    @State private var isExportingAll: Bool = false
    
    let archiveState: ArchiveState
    let contentService: ArchiveContentService = ArchiveContentService()
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                archiveState.updateSelectedItemForQuickLook()
            } label: {
                Label {
                    Text("Preview", comment: "Button in the tooblar that allows the user to preview the selected file.")
                } icon: {
                    Image("custom.document.badge.eye")
                }
            }
            
            Button {
                isExportingItem.toggle()
            } label: {
                Label {
                    Text("Extract selected", comment: "Button in the tooblar that allows the user to extract the selected files.")
                } icon: {
                    Image("custom.document.badge.arrow.down")
                }
            }
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
        
            Menu {
                if #available(macOS 14, *) {
                    SettingsLink() {
                        Label {
                            Text("Settings...", comment: "Used to open the settings/preferences window")
                        } icon: {
                            Image(systemName: "gear")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label {
                            Text("Settings...", comment: "Used to open the settings/preferences window")
                        } icon: {
                            Image(systemName: "gear")
                        }
                        .labelStyle(.titleAndIcon)
                    }
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
                        Text(verbatim: "Help with translation")
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
                        openURL(URL(string: "https://filefillet.com/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!)
                    } label: {
                        Label {
                            Text(Constants.otherAppFileFillet)
                        } icon: {
                            Image(nsImage: .menuIcon(named: "FileFillet", pointSize: 16))
                        }
                        .labelStyle(.titleAndIcon)
                    }
                } label: {
                    Label {
                        Text("More Apps")
                    } icon: {
                        Image(systemName: "plus.square.dashed")
                    }
                }
                .labelStyle(.titleAndIcon)
                
                Button {
                    openURL(URL(string: "https://macpacker.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!)
                } label: {
                    Label {
                        Text("Website", comment: "Hint to the user that the button links to the app's website.")
                    } icon: {
                        Image(systemName: "link")
                    }
                        .labelStyle(.titleAndIcon)
                }
                
                Button {
                    openURL(URL(string: "https://github.com/sarensw/MacPacker/")!)
                } label: {
                    Label(Constants.otherAppGitHub, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                }
                
                Button {
                    appDelegate.openAboutWindow()
                } label: {
                    Label {
                        Text("About \(Bundle.main.appName)")
                    } icon: {
                        Image(systemName: "info.square")
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
            
            
        }
    }
}
