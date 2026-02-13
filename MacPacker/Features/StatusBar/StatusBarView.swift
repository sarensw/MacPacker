//
//  StatusBarView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 06.02.26.
//

import Core
import SwiftUI

struct StatusBarView: View {
    @Environment(\.openURL) var openURL
    @EnvironmentObject var archiveState: ArchiveState
    
    var typeName: String? {
        if let comp = archiveState.compositionType {
            return comp.name
        }
        if let type = archiveState.type {
            return type.name
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .center) {
            if archiveState.url == nil {
                HStack(spacing: 4) {
                    Button {
                        guard let gitHubURL = URL(string: Constants.gitHubLink) else {
                            fatalError("Expected a valid URL")
                        }
                        
                        openURL(gitHubURL)
                    } label: {
                        Image("github.fill")
                        Text("Star")
                    }
                    .controlSize(.small)
                    
                    #if STORE
                    Button {
                        guard let writeReviewURL = URL(string: Constants.appStoreReviewLink) else {
                            fatalError("Expected a valid URL")
                        }

                        openURL(writeReviewURL)
                    } label: {
                        Image(systemName: "star")
                        Text("Review")
                    }
                    .controlSize(.small)
                    #endif
                    
                    Button {
                        guard let twitterURL = URL(string: Constants.twitterLink) else {
                            fatalError("Expected a valid URL")
                        }
                        
                        openURL(twitterURL)
                    } label: {
                        Image("x-twitter")
                        Text("Follow")
                    }
                    .controlSize(.small)
                    
                    Button {
                        guard let translateURL = URL(string: Constants.translateLink) else {
                            fatalError("Expected a valid URL")
                        }
                        
                        openURL(translateURL)
                    } label: {
                        Image(systemName: "flag")
                        Text("Translate")
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if archiveState.isBusy {
                        CancelEngineActionButtonView() {
                            archiveState.cancelCurrentOperation()
                        }
                        
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(height: 14)
                            .progressViewStyle(.circular)
                        
                        Text(verbatim: "\(archiveState.statusText ?? "")")
                        
                        if let progress = archiveState.progress {
                            Text(verbatim: "\(progress)%")
                                .padding(.leading, 4)
                        }
                        
                        Spacer()
                    } else {
                        Text("\(archiveState.entries.count) items")
                        if let uncompressedSize = archiveState.uncompressedSize {
                            Text(verbatim: " • \(SystemHelper.shared.format(bytes: uncompressedSize))")
                        }
                        
                        Spacer()
                        
                        if archiveState.selectedItems.count == 0 {
                            Text(verbatim: "\(typeName ?? "")")
                            if let isEncrypted = archiveState.isEncrypted, isEncrypted {
                                Text(verbatim: " • ")
                                Image(systemName: "lock.fill")
                            }
                        } else {
                            Text("\(archiveState.selectedItems.count) selected")
                            Text(verbatim: " • ")
                            Text(verbatim: "\(SystemHelper.shared.format(bytes: archiveState.selectedItems.reduce(into: 0) { $0 += $1.uncompressedSize }))")
                        }
                    }
                }
                .fontWeight(.light)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.windowSafeHorizontal)
        .frame(height: 27)
    }
}
