import Foundation
import Testing
@testable import FinderMenu

extension AllCoreTests {
    struct FinderOperationSessionTests {
        @Test func onlyDirectOperationsSupportProgressOnly() {
            for action: AppUrlAction in [.extractHere, .extractToFolder, .extractTo, .compress, .compressEach, .compressContents] {
                #expect(action.supportsProgressOnly)
            }
            #expect(!AppUrlAction.open.supportsProgressOnly)
            #expect(!AppUrlAction.addToArchive.supportsProgressOnly)
        }

        @Test func progressOnlyIsOptInAndCanBeDisabled() {
            let defaults = isolatedDefaults()
            #expect(!FinderMenuSettings.isProgressOnly(in: defaults))
            defaults.set(true, forKey: FinderMenuSettings.progressOnlyKey)
            #expect(FinderMenuSettings.isProgressOnly(in: defaults))
            defaults.set(false, forKey: FinderMenuSettings.progressOnlyKey)
            #expect(!FinderMenuSettings.isProgressOnly(in: defaults))
        }

        @Test func aColdLaunchWaitsForItsURLAndWholeBatch() {
            var session = FinderOperationSession(isTransient: true)
            #expect(!session.shouldTerminate(hasProgress: false, hasWindows: false))
            let first = session.begin()
            let second = session.begin()
            session.finish(first)
            #expect(!session.shouldTerminate(hasProgress: false, hasWindows: false), "Includes time between files and permission prompts")
            session.finish(first) // a duplicated completion cannot finish another request
            #expect(session.hasPendingRequests)
            session.finish(second)
            #expect(!session.shouldTerminate(hasProgress: true, hasWindows: false), "Leave errors visible until dismissed")
            #expect(!session.shouldTerminate(hasProgress: false, hasWindows: true), "Do not close the completion window early")
            #expect(session.shouldTerminate(hasProgress: false, hasWindows: false))
        }

        @Test func normalAndExplicitlyReopenedSessionsKeepRunning() {
            var normal = FinderOperationSession()
            let request = normal.begin()
            normal.finish(request)
            #expect(!normal.shouldTerminate(hasProgress: false, hasWindows: false))
            var transient = FinderOperationSession(isTransient: true)
            let work = transient.begin()
            transient.keepRunning()
            transient.finish(work)
            #expect(!transient.shouldTerminate(hasProgress: false, hasWindows: false))
        }
    }
}
