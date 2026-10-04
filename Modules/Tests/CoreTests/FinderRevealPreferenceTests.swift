import Foundation
import Testing
@testable import Core

struct FinderRevealPreferenceTests {
    @Test func extractionRevealDefaultsOnAndCanBeDisabled() {
        let name = "MacPacker-FinderReveal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(Keys.revealsExtractedFilesInFinder(in: defaults))
        defaults.set(false, forKey: Keys.revealExtractedFilesInFinder)
        #expect(!Keys.revealsExtractedFilesInFinder(in: defaults))
        defaults.set(true, forKey: Keys.revealExtractedFilesInFinder)
        #expect(Keys.revealsExtractedFilesInFinder(in: defaults))
    }
}
