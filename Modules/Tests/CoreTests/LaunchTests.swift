//
//  LaunchTests.swift
//  Modules
//
//  What a launch shows on its own, and when the app quits again, both
//  decided by what the launch was started for.
//

import Testing
@testable import Core

extension AllCoreTests {

    struct LaunchTests {

        // MARK: - The launch window and the welcome window

        /// An action from Finder's menu starts the app to extract or compress,
        /// and leaves the screen as it was. The launch window used to come up
        /// with it (#279, #312).
        @Test func aFinderActionShowsNoLaunchWindows() {
            var launch = Launch()
            let shown = launch.started(for: .finderExtension)
            #expect(!shown)
        }

        @Test func openingTheAppShowsTheLaunchWindows() {
            var launch = Launch()
            let shown = launch.started(for: .app)
            #expect(shown)
        }

        /// Open With keeps what it had: the launch window, which the archive
        /// then takes, and the welcome window.
        @Test func openingAnArchiveShowsTheLaunchWindows() {
            var launch = Launch()
            let shown = launch.started(for: .openWith)
            #expect(shown)
        }

        @Test func launchParametersWithTheirOwnWindowShowNoLaunchWindows() {
            var launch = Launch()
            let shown = launch.started(for: .launchParameters)
            #expect(!shown)
        }

        /// Only the launch decides. A Finder action sent to the running app
        /// does not bring the launch windows up a second time, and an archive
        /// opened after a Finder launch does not bring them up at all.
        @Test(arguments: [Launch.Reason.app, .openWith, .finderExtension, .launchParameters])
        func whatComesAfterTheLaunchShowsNoLaunchWindows(first: Launch.Reason) {
            var launch = Launch()
            _ = launch.started(for: first)

            let later = [
                launch.started(for: .app),
                launch.started(for: .openWith),
                launch.started(for: .finderExtension),
            ]
            #expect(later == [false, false, false])
            #expect(launch.reason == first)
        }

        // MARK: - Quitting when the work is done

        /// A Finder action that had to start the app leaves nothing behind
        /// once it is done: the app quits, and its Dock icon goes with it.
        @Test func aLaunchForAFinderActionIsOverWhenTheActionIsDone() {
            var launch = Launch()
            _ = launch.started(for: .finderExtension)
            #expect(launch.isOver(usedAsApp: false, actionUnderWay: false, somethingOnScreen: false))
        }

        /// Not in the middle of the work, not under a progress window, an
        /// error or a question, and not once the app has had a window of its
        /// own: then it is in use, and stays like one the user opened.
        @Test func aLaunchForAFinderActionIsNotOverWhileTheAppIsNeeded() {
            var launch = Launch()
            _ = launch.started(for: .finderExtension)
            #expect(!launch.isOver(usedAsApp: false, actionUnderWay: true, somethingOnScreen: false))
            #expect(!launch.isOver(usedAsApp: false, actionUnderWay: false, somethingOnScreen: true))
            #expect(!launch.isOver(usedAsApp: true, actionUnderWay: false, somethingOnScreen: false))
        }

        /// An app the user opened stays, whatever Finder asks of it later.
        @Test(arguments: [Launch.Reason.app, .openWith, .launchParameters])
        func anyOtherLaunchIsNeverOver(reason: Launch.Reason) {
            var launch = Launch()
            _ = launch.started(for: reason)
            // a Finder action arrives, and gets done
            _ = launch.started(for: .finderExtension)
            #expect(!launch.isOver(usedAsApp: false, actionUnderWay: false, somethingOnScreen: false))
        }

        /// A launch that does not know yet what it was started for is not
        /// over: the url of a Finder action can still be on its way.
        @Test func aLaunchThatDoesNotKnowYetIsNotOver() {
            let launch = Launch()
            #expect(!launch.isOver(usedAsApp: false, actionUnderWay: false, somethingOnScreen: false))
        }

        // MARK: - Checking for updates

        /// An app that a Finder action started quits a moment later. A check
        /// for updates begun there is cut off, counts as made all the same,
        /// and puts the next one off by a day: no update would ever be seen.
        @Test func aLaunchForAFinderActionChecksForNoUpdates() {
            var launch = Launch()
            _ = launch.started(for: .finderExtension)
            #expect(!launch.checksForUpdates(usedAsApp: false))
        }

        /// Once it has a window of its own it is an app in use, and checks.
        @Test func aLaunchForAFinderActionChecksOnceTheAppIsInUse() {
            var launch = Launch()
            _ = launch.started(for: .finderExtension)
            #expect(launch.checksForUpdates(usedAsApp: true))
        }

        @Test(arguments: [Launch.Reason.app, .openWith, .launchParameters])
        func anyOtherLaunchChecksForUpdates(reason: Launch.Reason) {
            var launch = Launch()
            _ = launch.started(for: reason)
            #expect(launch.checksForUpdates(usedAsApp: false))
        }

        /// Not before it is known what the launch was started for: the url of
        /// a Finder action can still be on its way.
        @Test func aLaunchThatDoesNotKnowYetChecksForNoUpdates() {
            let launch = Launch()
            #expect(!launch.checksForUpdates(usedAsApp: false))
        }
    }
}
