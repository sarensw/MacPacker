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
            if archiveState.hasArchive == false {
                HStack(spacing: 4) {
                    Button {
                        guard let gitHubURL = URL(string: Constants.gitHubLink) else {
                            fatalError("Expected a valid URL")
                        }
                        
                        openURL(gitHubURL)
                    } label: {
                        Image("github.fill")
                        Text(.feedbackStar)
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
                        Text(.feedbackReview)
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
                        Text(.feedbackFollow)
                    }
                    .controlSize(.small)
                    
                    Button {
                        guard let translateURL = URL(string: Constants.translateLink) else {
                            fatalError("Expected a valid URL")
                        }
                        
                        openURL(translateURL)
                    } label: {
                        Image(systemName: "flag")
                        Text(.feedbackTranslate)
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
                        Text(.commonItemCount(archiveState.itemCount))
                        if let uncompressedSize = archiveState.uncompressedSize {
                            Text(verbatim: " • \(SystemHelper.shared.format(bytes: uncompressedSize))")
                        }
                        if let nameEncoding = archiveState.nameEncoding {
                            Text(verbatim: " • ")
                            NameEncodingMenu(current: nameEncoding)
                        }
                        
                        Spacer()
                        
                        if archiveState.selectedItems.count == 0 {
                            Text(verbatim: "\(typeName ?? "")")
                            if let isEncrypted = archiveState.isEncrypted, isEncrypted {
                                Text(verbatim: " • ")
                                Image(systemName: "lock.fill")
                            }
                        } else {
                            Text(.commonSelectedCount(archiveState.selectedItems.count))
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

/// What the names of an archive that does not say itself are read in, and the
/// way to read them in something else when detection got it wrong. Only an
/// archive like that has this: for all others there is nothing to choose.
private struct NameEncodingMenu: View {
    @EnvironmentObject var archiveState: ArchiveState
    let current: ArchiveNameEncoding

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { archiveState.chosenNameEncoding },
                set: { archiveState.readNames(as: $0) }
            )) {
                Text(.archiveContentViewerAutomatic).tag(ArchiveNameEncoding?.none)
                Divider()
                ForEach(ArchiveNameEncoding.allCases) { encoding in
                    Text(verbatim: encoding.localizedName).tag(ArchiveNameEncoding?.some(encoding))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 2) {
                Text(verbatim: current.localizedName)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        // Plain, so the label takes the look of the status bar around it. It
        // then has no indicator of its own.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        // Reading the names again lists the archive anew, and pending changes
        // are about the listing there is now.
        .disabled(archiveState.hasPendingChanges)
        .accessibilityIdentifier(AccessibilityIdentifier.nameEncodingMenu)
    }
}
