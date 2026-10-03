import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct WelcomePresentationTests {
        @Test func welcomeIsShownOnceAcrossRestartsAndUpdates() {
            let name = "WelcomePresentationTests." + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            #expect(WelcomePresentation.shouldShow(defaults: defaults))
            defaults.set("0.0.0-dev", forKey: "welcomeScreenShownInVersion")
            #expect(!WelcomePresentation.shouldShow(defaults: UserDefaults(suiteName: name)!))
            #expect(!WelcomePresentation.shouldShow(defaults: defaults))
        }
        @Test func releasedUsersAlreadySawWelcome() {
            let name = "WelcomePresentationTests." + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("1.0", forKey: "welcomeScreenShownInVersion")
            #expect(!WelcomePresentation.shouldShow(defaults: defaults))
        }
    }
}
