//
//  MoreFromLeanBytesView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import SwiftUI

struct MoreFromLeanBytesProductView: View {
    @Environment(\.openURL) private var openURL
    
    let logo: String
    let title: String
    let description: String
    let openSource: Bool
    let url: URL
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack {
            Button {
                openURL(url)
            } label: {
                HStack {
                    Image(logo)
                        .resizable()
                        .frame(width: 24, height: 24, alignment: .center)
                    
                    VStack(alignment: .leading) {
                        Text(title)
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            //        .padding(.bottom, 16)
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(8)
        .onHover { _ in
            isHovered.toggle()
        }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }
        }
    }
}

struct WelcomeMoreFromLeanBytesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "MacPacker is sponsored by my own work at LeanBytes. Supporting the apps below directly supports this open-source tool.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            
            MoreFromLeanBytesProductView(logo: "AppIcon_FlowMoose", title: Constants.otherAppFlowMoose, description: "Voice-2-Text to reduce stress on wrists and arms in the age of AI chats. Offline, local only.", openSource: false, url: Constants.otherAppFlowMooseURL)
            
            MoreFromLeanBytesProductView(logo: "AppIcon_FileFillet", title: Constants.otherAppFileFillet, description: "Copy or move files to your favorite folders and their sub-folders. No need to open new Finder windows.", openSource: true, url: Constants.otherAppMacPackerURL)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}
