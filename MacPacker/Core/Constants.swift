//
//  Constants.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.09.25.
//

import Foundation

class Constants {
    static let appName: String = "MacPacker"
    
    static let supportMail: String = "apps@sarensw.com"
    static let otherAppGitHub: String = "GitHub"
    
    static let appStoreReviewLink: String = "https://apps.apple.com/app/id6473273874?action=write-review"
    static let gitHubLink: String = "https://github.com/sarensw/MacPacker"
    static let translateLink: String = "https://poeditor.com/join/project/J2Qq2SUzYr"
    static let twitterLink: String = "https://x.com/macpackerapp"
    static let discordURL: URL = URL(string: "https://discord.gg/dTawuWEvBx")!
    
    static let homepageURL: URL = URL(string: "https://macpacker.app")!
    /// Docs, opened from the start page of an empty window. Tagged so Plausible
    /// shows how much traffic the app itself sends over.
    static let docsURL: URL = URL(string: "https://macpacker.app/docs?utm_source=macpacker&utm_medium=ui&utm_content=startpage")!
    static let changelogURL: URL = URL(string: "https://github.com/sarensw/MacPacker/releases")!
    static let privacyURL: URL = URL(string: "https://github.com/sarensw/MacPacker/blob/main/PRIVACY.md")!
    static let termsURL: URL = URL(string: "https://github.com/sarensw/MacPacker/blob/main/TERMS.md")!
    static let imprintURL: URL = URL(string: "https://macpacker.app/imprint")!
    
    // MARK: Other products
    public static let otherAppMacPacker: String = "MacPacker"
    public static let otherAppMacPackerURL: URL = URL(string: "https://macpacker.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!
    public static let otherAppFlowMoose: String = "FlowMoose"
    public static let otherAppFlowMooseURL: URL = URL(string: "https://flowmoose.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!
    public static let otherAppFileFillet: String = "FileFillet"
    public static let otherAppFileFilletURL: URL = URL(string: "https://filefillet.com/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!
    public static let otherAppFrameBeast: String = "FrameBeast"
    /// The utm query has to sit before the fragment, otherwise it becomes part
    /// of the anchor and the section is not scrolled to.
    public static let otherAppFrameBeastURL: URL = URL(string: "https://leanbytes.io/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui#framebeast")!
    /// The app; tailbeat.dev is the command-line tool (LeanBytes/tailbeat#113).
    public static let otherAppTailBeat: String = "TailBeat UI"
    public static let otherAppTailBeatURL: URL = URL(string: "https://ui.tailbeat.dev/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!
    /// Every app, including the ones MacPacker itself does not name.
    public static let otherAppsURL: URL = URL(string: "https://leanbytes.io/?utm_source=macpacker&utm_content=welcome&utm_medium=ui#products")!
    /// The Black Friday deal (`BlackFridayDeal`), from the welcome window's
    /// banner and from the More Apps menu.
    public static let blackFridayWelcomeURL: URL = URL(string: "https://leanbytes.io/?utm_source=macpacker&utm_content=welcome&utm_medium=ui&utm_campaign=blackfriday")!
    public static let blackFridayMenuURL: URL = URL(string: "https://leanbytes.io/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui&utm_campaign=blackfriday")!
}
