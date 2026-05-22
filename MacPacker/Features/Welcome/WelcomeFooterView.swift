//
//  WelcomeFooterView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.05.26.
//

import SwiftUI

struct WelcomeFooterView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Button {
                        openURL(URL(string: "https://macpacker.app")!)
                    } label: {
                        HStack(spacing: 2) {
                            Text(verbatim: "macpacker.app")
                            Image(systemName: "link")
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        openURL(URL(string: "mailto:\(Constants.supportMail)")!)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "envelope")
                            Text(verbatim: Constants.supportMail)
                                .textSelection(.disabled)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 16) {
                    Button {
                        openURL(Constants.privacyURL)
                    } label: {
                        HStack(spacing: 2) {
                            Text(verbatim: "Privacy")
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        openURL(Constants.termsURL)
                    } label: {
                        HStack(spacing: 2) {
                            Text(verbatim: "Terms")
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        openURL(Constants.imprintURL)
                    } label: {
                        HStack(spacing: 2) {
                            Text(verbatim: "Imprint")
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Text(verbatim: "@ 2026 Stephan Arenswald · Stuttgart, Germany")
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                dismissWindow()
//                    StartupFlowCoordinator.shared.completed(.updateInfo)
            } label: {
                Text("Continue")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
