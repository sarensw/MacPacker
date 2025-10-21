//
//  WelcomeView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation
import SwiftUI

struct WhatsNewPill: View {
    enum PillType {
        case feature
        case bug
        case core
    }
    
    var title: LocalizedStringResource
    var type: PillType
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            switch type {
            case .feature:
                Capsule()
                    .fill(.green.opacity(0.4))
                    .overlay(
                        Capsule()
                            .stroke(Color.green, lineWidth: 1)
                    )
                    .frame(width: 32, height: 16)
                    .overlay {
                        Text(verbatim: "feat")
                            .font(.footnote)
                    }
            case .bug:
                Capsule()
                    .fill(.red.opacity(0.4))
                    .overlay(
                        Capsule()
                            .stroke(Color.red, lineWidth: 1)
                    )
                    .frame(width: 32, height: 16)
                    .overlay {
                        Text(verbatim: "bug")
                            .font(.footnote)
                    }
            case .core:
                Capsule()
                    .fill(.blue.opacity(0.4))
                    .overlay(
                        Capsule()
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .frame(width: 32, height: 16)
                    .overlay {
                        Text(verbatim: "core")
                            .font(.footnote)
                    }
            }
            
            Text(title)
        }
        
    }
}

struct WelcomeWhatsNewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WhatsNewPill(title: "Use system preview instead of internal previewer", type: .feature)
            WhatsNewPill(title: "Navigate the archive using keys similar to Finder", type: .feature)
            WhatsNewPill(title: "Crash when using the open with option", type: .bug)
            WhatsNewPill(title: "Quick look extension missing in App Store version", type: .bug)
            WhatsNewPill(title: "Re-enable macOS 13 as minimum deployment target", type: .core)
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
                Link(destination: URL(string: "https://filefillet.com/?utm_source=macpacker&utm_content=welcome&utm_medium=ui")!) {
                    Text(Constants.otherAppFileFillet)
                }
                Text("Organize files without tons of Finder windows.", comment: "Short description of the app FileFillet which is referenced in the 'Other projects' section of the 'Welcome' view")
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
                            Text("Please support the archive type ...", comment: "Hint on what to ask for in the feedback form")
                            Text("I found the following bug ...", comment: "Hint on what to ask for in the feedback form")
                            Text("Please add feature ...", comment: "Hint on what to ask for in the feedback form")
                        }
                    }
                    TextEditor(text: $feedbackText)
                        .frame(maxHeight: .infinity)
                        .opacity(feedbackText.isEmpty ? 0.25 : 1)
                }
                Button {
                    var urlc = URLComponents(string: "mailto:\(Constants.supportMail)")
                    urlc?.queryItems = [
                        URLQueryItem(name: "subject", value: "MacPacker Feedback \(UUID())"),
                        URLQueryItem(name: "body", value: feedbackText)
                    ]
                    if let url = urlc?.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Send", comment: "Button label to send feedback")
                }
            }
            
            Spacer()
            HStack(spacing: 14) {
                Text("Or reach out via...", comment: "Hint on how to contact the developer")
                Link(destination: URL(string: "mailto:\(Constants.supportMail)")!) {
                    Text(verbatim: "\(Constants.supportMail)")
                }
                Link(destination: URL(string: "https://twitter.com/sarensw")!) {
                    Text(verbatim: "@sarensw")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct WelcomeView: View {
    @Environment(\.openURL) private var openURL
    @State private var defaultTab = 1
    
    var styledString: AttributedString {
        var string = AttributedString(
            localized: "Welcome to \(Bundle.main.appName)",
            comment: "'Welcome to <app name>'. The order of the greeting might be different in different languages. For example: English: Welcome to MacPacker, Japanese: MacPackerへようこそ. This is up to the translator to decide."
        )
        string.foregroundColor = .secondary
        string.font = .system(size: 42, weight: .medium)
        
        if let range = string.range(of: Bundle.main.appName) {
            string[range].foregroundColor = .primary
        }
        
        return string
    }
    
    var body: some View {
        VStack (alignment: .center, spacing: 8) {
            Group {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, alignment: .center)
                Text(styledString)
                Text("Version v\(Bundle.main.appVersionLong)", comment: "This text shows the current version of the app in Welcome and About window")
                    .foregroundColor(.secondary)
            }
            
            if #available(macOS 15.0, *) {
                TabView(selection: $defaultTab) {
                    WelcomeWhatsNewView()
                        .tabItem {
                            Text("What's new", comment: "Title of the tab in the welcome screen that shows the user what's new in this version.")
                        }
                        .tag(1)
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps", comment: "Title of the tab in the welcome screen that links to other projects.")
                        }
                        .tag(2)
                    WelcomeFeedbackView()
                        .tabItem {
                            Text("Feedback", comment: "Title of the tab in the welcome screen that lets the user give feedback")
                        }
                        .tag(3)
                }
                .tabViewStyle(.grouped)
                .padding(.top, 16)
            } else {
                TabView(selection: $defaultTab) {
                    WelcomeWhatsNewView()
                        .tabItem {
                            Text("What's new", comment: "Title of the tab in the welcome screen that shows the user what's new in this version.")
                        }
                        .tag(1)
                    WelcomeOtherProjects()
                        .tabItem {
                            Text("More apps", comment: "Title of the tab in the welcome screen that links to other projects.")
                        }
                        .tag(2)
                    WelcomeFeedbackView()
                        .tabItem {
                            Text("Feedback", comment: "Title of the tab in the welcome screen that lets the user give feedback")
                        }
                        .tag(3)
                }
                .tabViewStyle(.automatic)
                .padding(.top, 16)
            }
            
            #if !STORE
            Text("Support the development...")
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
            
            Text(verbatim: "AI-generated translations. Reach out for corrections or suggestions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .padding()
    }
}

#Preview {
    WelcomeView()
        .frame(width: 480, height: 480)
}
