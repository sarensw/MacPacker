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
                guard let gitHubURL = URL(string: Constants.gitHubLink) else {
                    fatalError("Expected a valid URL")
                }
                
                openURL(gitHubURL)
            } label: {
                Text(.feedbackStarRepo)
            }
            
            #if STORE
            Button {
                guard let writeReviewURL = URL(string: Constants.appStoreReviewLink) else {
                    fatalError("Expected a valid URL")
                }

                openURL(writeReviewURL)
            } label: {
                Text(.feedbackAppStoreReview)
            }
            #endif
        } label: {
            Label {
                Text(.feedbackSendSmile)
            } icon: {
                Image(systemName: "face.smiling")
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
