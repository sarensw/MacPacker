//
//  SendSmileView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 15.08.25.
//

import StoreKit
import SwiftUI

struct SendSmileView: View {
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Menu {
            Button {
                openURL(URL(string: "https://github.com/sarensw/MacPacker")!)
            } label: {
                Text("Star the repository on GitHub", comment: "Opens the GitHub page of the MacPacker repository for the user to star it.")
            }
            
            #if STORE
            Button {
                let url = "https://apps.apple.com/app/id6473273874?action=write-review"

                guard let writeReviewURL = URL(string: url) else {
                    fatalError("Expected a valid URL")
                }

                openURL(writeReviewURL)
            } label: {
                Text("Leave a review in the App Store", comment: "Opens the App Store review page for the MacPacker app for the user to write a review.")
            }
            #endif
        } label: {
            Label {
                Text("Send a smile", comment: "This is the menu in the 'More' menu of the archive window to give customers a hint on how to support the developer. The user has the option to open the MacPacker repository on GitHub or leave a review in the App Store.")
            } icon: {
                Image(systemName: "face.smiling")
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
