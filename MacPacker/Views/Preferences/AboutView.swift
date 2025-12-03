//
//  AboutView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 03.11.22.
//

import App
import SwiftUI

extension Bundle {
    public var appName: String { getInfo("CFBundleName")  }
    public var displayName: String {getInfo("CFBundleDisplayName")}
    public var language: String {getInfo("CFBundleDevelopmentRegion")}
    public var identifier: String {getInfo("CFBundleIdentifier")}
    public var copyright: String {getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\\\n", with: "\n") }
    
    public var appBuild: String { getInfo("CFBundleVersion") }
    public var appVersionLong: String { getInfo("CFBundleShortVersionString") }
    //public var appVersionShort: String { getInfo("CFBundleShortVersion") }
    
    fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack (alignment: .center, spacing: 8) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, alignment: .center)
            Text(Bundle.main.appName)
                .font(.system(size: 42, weight: .medium, design: .default))
            Text("Version v\(Bundle.main.appVersionLong)", comment: "This text shows the current version of the app in Welcome and About window")
                .foregroundColor(.secondary)
            
            Text("\(Bundle.main.appName) has been brought to you by", comment: "Below of this text is a list of people who contributed to the development of this app")
                .fontWeight(.semibold)
                .padding(.top, 14)
            HStack(spacing: 14) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "Stephan Arenswald")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("idea, code", comment: "This text describes the role of one of the app's developers")
                }
            }
            .font(.caption2)
            
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
            
            Text("Reach out...", comment: "Hint in the About view to let the user contact the developer. The various ways to contact the developer are listed below.")
                .fontWeight(.semibold)
                .padding(.top, 14)
            HStack(spacing: 14) {
                Link(destination: URL(string: "mailto:\(Constants.supportMail)")!) {
                    Text(verbatim: "\(Constants.supportMail)")
                }
                Link(destination: URL(string: "https://twitter.com/sarensw")!) {
                    Text(verbatim: "@sarensw")
                }
                Link(destination: URL(string: "https://macpacker.app/?ref=about")!) {
                    Text(verbatim: "macpacker.app")
                }
            }
            
            HStack(spacing: 0) {
                Text(verbatim: "\(Calendar.current.component(.year, from: Date())) Stephan Arenswald. ")
                Text("Published as Open Source under GPL.", comment: "Hint about how the app is published as Open Source using the GPL license")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.top, 14)
        }
        .padding()
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
            .frame(width: 460, height: 480)
    }
}
