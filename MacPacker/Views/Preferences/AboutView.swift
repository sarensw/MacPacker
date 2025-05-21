//
//  AboutView.swift
//  FileFillet
//
//  Created by Arenswald, Stephan (059) on 03.11.22.
//

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
            Text("MacPacker")
                .font(.system(size: 42, weight: .medium, design: .default))
            Text("Version v\(Bundle.main.appVersionLong)")
                .foregroundColor(.secondary)
            
            Text("MacPacker has been brought to you by")
                .fontWeight(.semibold)
                .padding(.top, 14)
            HStack(spacing: 14) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Stephan Arenswald")
//                    Text("Community")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("idea, code")
//                    Text("coding")
                }
            }
            .font(.caption2)
            
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
            
            Text("Reach out...")
                .fontWeight(.semibold)
                .padding(.top, 14)
            HStack(spacing: 14) {
                Link("apps@sarensw.com", destination: URL(string: "mailto:apps@sarensw.com")!)
                Link("@sarensw", destination: URL(string: "https://twitter.com/sarensw")!)
                Link("filefillet.com", destination: URL(string: "https://macpacker.app/?ref=about")!)
            }
            
            Text("2025 Stephan Arenswald. Published as Open Source under GPL.")
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
