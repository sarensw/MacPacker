//
//  WelcomeView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation
import SwiftUI

struct WelcomeWhatsNewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• feat: hit space to open internal preview")
            Text("• feat: setting to change the breadcrumb position")
            Text("• chore: add support for macOS 14")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct WelcomeOtherProjects: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image("FileFillet")
                    .resizable()
                    .frame(width: 32, height: 32)
                Link(destination: URL(string: "https://filefillet.com/?ref=mpwelcome")!) {
                    Text("FileFillet")
                }
                Text("Organize files without tons of Finder windows.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct WelcomeFeedbackView: View {
    @State private var feedbackText: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                ZStack {
                    if feedbackText.isEmpty {
                        VStack {
                            Text("Please support the archive type ...")
                            Text("I found the following bug")
                            Text("Please add feature ...")
                        }
                    }
                    TextEditor(text: $feedbackText)
                        .frame(maxHeight: .infinity)
                        .opacity(feedbackText.isEmpty ? 0.25 : 1)
                }
                Button("Send") {
                    var urlc = URLComponents(string: "mailto:hej@sarensx.com")
                    urlc?.queryItems = [
                        URLQueryItem(name: "subject", value: "MacPacker Feedback \(UUID())"),
                        URLQueryItem(name: "body", value: feedbackText)
                    ]
                    if let url = urlc?.url {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            Spacer()
            HStack(spacing: 14) {
                Text("Or reach out via...")
                Link("apps@sarensw.com", destination: URL(string: "mailto:apps@sarensw.com")!)
                Link("@sarensw", destination: URL(string: "https://twitter.com/sarensw")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct WelcomeView: View {
    @Environment(\.openURL) private var openURL
    @State private var defaultTab = 1

    var body: some View {
        VStack (alignment: .center, spacing: 8) {
            Group {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, alignment: .center)
                Text("Welcome to")
                    .font(.system(size: 42, weight: .medium, design: .default))
                    .foregroundColor(.secondary) +
                Text(" MacPacker")
                    .font(.system(size: 42, weight: .medium, design: .default))
                Text("Version v\(Bundle.main.appVersionLong)")
                    .foregroundColor(.secondary)
            }
            
            if #available(macOS 15.0, *) {
                TabView(selection: $defaultTab) {
                    WelcomeWhatsNewView()
                        .tabItem {
                            Text("What's new")
                        }
                        .tag(1)
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps")
                        }
                        .tag(2)
                    WelcomeFeedbackView()
                        .tabItem {
                            Text("Feedback")
                        }
                        .tag(3)
                }
                .tabViewStyle(.grouped)
                .padding(.top, 16)
            } else {
                TabView(selection: $defaultTab) {
                    WelcomeWhatsNewView()
                        .tabItem {
                            Text("What's new")
                        }
                        .tag(1)
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps")
                        }
                        .tag(2)
                    WelcomeFeedbackView()
                        .tabItem {
                            Text("Feedback")
                        }
                        .tag(3)
                }
                .tabViewStyle(.automatic)
                .padding(.top, 16)
            }
            
            #if !STORE
            Text("Support this Open Source project...")
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
            
            
//            Text("2023 SarensX OÜ, Stephan Arenswald. Published as Open Source under GPL.")
//                .font(.footnote)
//                .foregroundColor(.secondary)
//                .padding(.top, 14)
        }
        .padding()
    }
}

#Preview {
    WelcomeView()
        .frame(width: 480, height: 480)
}
