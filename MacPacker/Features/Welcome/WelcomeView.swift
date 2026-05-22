//
//  WelcomeView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation

import SwiftUI

struct WelcomeView: View {
    @Environment(\.openURL) private var openURL
    
    var styledString: AttributedString {
        var string = AttributedString(
            localized: "Welcome to \(Bundle.main.displayName)",
            comment: "'Welcome to <app name>'. The order of the greeting might be different in different languages. For example: English: Welcome to MacPacker, Japanese: MacPackerへようこそ. This is up to the translator to decide."
        )
        string.foregroundColor = .secondary
        string.font = .system(size: 24, weight: .medium)
        
        if let range = string.range(of: Bundle.main.displayName) {
            string[range].foregroundColor = .primary
        }
        
        return string
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack  {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image("AppIcon_MacPacker")
                            .resizable()
                            .frame(width: 40, height: 40, alignment: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(styledString)
                        }
                        
                        Spacer()
                    }
                    
                    WelcomeChangelogView()
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                
                Divider()
                
                VStack(alignment: .leading) {
                    WelcomeMoreFromLeanBytesView()
                    
                    Divider()
                        .padding(.top, 22)
                        .padding(.bottom, 22)
                    
                    Text(verbatim: "❤️ Many thanks to all the PR contributors, translators and sponsors of this project!")
                        .padding(.horizontal, 16)
                    
                    #if !STORE
                    HStack {
                        Image("BuyMeCoffee")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                            .onTapGesture {
                                openURL(URL(string: "https://www.buymeacoffee.com/sarensw")!)
                            }
                        Image("Paypal")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                            .onTapGesture {
                                openURL(URL(string: "https://www.paypal.com/donate/?hosted_button_id=KM8GA7MJMYNQN")!)
                            }
                    }
                    .padding(16)
                    #else
                    Spacer()
                    #endif
                }
                .frame(maxWidth: .infinity)
            }
            
            Divider()
                .padding(.top, 22)
                .padding(.bottom, 0)
            
            WelcomeFooterView()
        }
        .padding(0)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    WelcomeView()
        .frame(width: 900)
}
