//
//  AboutView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 11.01.26.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @State private var defaultTab = 1
    
    var body: some View {
        VStack (alignment: .center, spacing: 8) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, alignment: .center)
            Text(verbatim: Bundle.main.displayName)
                .font(.system(size: 42, weight: .medium, design: .default))
            Text("Version v\(Bundle.main.appVersionLong)", comment: "This text shows the current version of the app in Welcome and About window")
                .foregroundColor(.secondary)
            
            if #available(macOS 15.0, *) {
                TabView(selection: $defaultTab) {
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps")
                        }
                        .tag(1)
                }
                .tabViewStyle(.grouped)
                .padding(.top, 16)
            } else {
                TabView(selection: $defaultTab) {
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps")
                        }
                        .tag(1)
                }
                .tabViewStyle(.automatic)
                .padding(.top, 16)
            }
            
            #if !STORE
            Text("Support the development...", comment: "Hint to the user to support the app's development via some donation")
                .fontWeight(.semibold)
                .padding(.top, 14)
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
            #else
            Spacer()
            #endif
            
            Button {
                AckWindowController().show()
            } label: {
                Text("Acknowledgements")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
