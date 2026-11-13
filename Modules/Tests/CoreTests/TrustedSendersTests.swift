//
//  TrustedSendersTests.swift
//  Modules
//
//  A Finder action is carried out only when MacPacker's own Finder extension
//  asked for it (#286). Any app, and a web page once the user lets it, can
//  open MacPacker's urls, and every request used to be carried out under the
//  folder grants the user gave MacPacker.
//
//  This test process stands in for the sender: its own audit token, checked
//  against its own code's requirement or another program's.
//

import Foundation
import Security
import Testing
@testable import Core

extension AllCoreTests {

    @MainActor struct TrustedSendersTests {

        private let url = "app.macpacker://compress?files=/Users/me/Documents/taxes.pdf&target=/Users/me/Public"

        /// The audit token of this test process, as the Apple event of a url
        /// it opened would carry it.
        private func ownAuditToken() -> Data {
            var token = audit_token_t()
            var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &token) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
                }
            }
            #expect(result == KERN_SUCCESS)
            return Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        }

        /// What this test process's code meets: it is the trusted app here.
        private func ownRequirement() throws -> SecRequirement {
            let executable = try #require(Bundle.main.executableURL)
            return try #require(CodeSignature.designatedRequirement(ofCodeAt: executable))
        }

        /// What another program's code meets, and this test process does not.
        private func otherRequirement() throws -> SecRequirement {
            try #require(CodeSignature.designatedRequirement(ofCodeAt: URL(fileURLWithPath: "/usr/bin/true")))
        }

        @Test func aRequestFromTheTrustedAppIsCarriedOut() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])

            #expect(senders.note(url, sentBy: ownAuditToken()))
            #expect(senders.sentByTrustedSender(try #require(URL(string: url))))
        }

        /// Another app sends exactly what the Finder extension would.
        @Test func aRequestFromAnotherAppIsRefused() throws {
            let senders = TrustedSenders(trusting: [try otherRequirement()])

            #expect(!senders.note(url, sentBy: ownAuditToken()))
            #expect(!senders.sentByTrustedSender(try #require(URL(string: url))))
        }

        /// An event that does not say who sent it.
        @Test func aRequestWithoutASenderIsRefused() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])

            #expect(!senders.note(url, sentBy: nil))
            #expect(!senders.sentByTrustedSender(try #require(URL(string: url))))
        }

        /// A sender that has quit cannot be checked any more, and a process
        /// that got its pid since is not it: the token's pid version differs.
        @Test func aSenderThatHasQuitIsRefused() throws {
            var token = ownAuditToken()
            // audit_token_t.val[7] is the pid version
            token.withUnsafeMutableBytes { $0.storeBytes(of: $0.load(fromByteOffset: 28, as: UInt32.self) &+ 1, toByteOffset: 28, as: UInt32.self) }
            let senders = TrustedSenders(trusting: [try ownRequirement()])

            #expect(!senders.note(url, sentBy: token))
        }

        /// A url that only looks like one the trusted app sent.
        @Test func aUrlNobodyTrustedSentIsRefused() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])
            senders.note(url, sentBy: ownAuditToken())

            let other = "app.macpacker://compress?files=/Users/me/Documents&target=/Users/me/Public"
            #expect(!senders.sentByTrustedSender(try #require(URL(string: other))))
        }

        /// One check lets one request through, not a second one with the same url.
        @Test func eachRequestIsCarriedOutOnce() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])
            senders.note(url, sentBy: ownAuditToken())
            let request = try #require(URL(string: url))

            #expect(senders.sentByTrustedSender(request))
            #expect(!senders.sentByTrustedSender(request))
        }

        /// The same menu entry chosen twice in a row.
        @Test func theSameRequestSentTwiceIsCarriedOutTwice() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])
            senders.note(url, sentBy: ownAuditToken())
            senders.note(url, sentBy: ownAuditToken())
            let request = try #require(URL(string: url))

            #expect(senders.sentByTrustedSender(request))
            #expect(senders.sentByTrustedSender(request))
        }

        /// Urls that arrive while the app launches are handed over together,
        /// and only the first is carried out. Each of them uses up its note:
        /// one left over would let the same url from another app through later.
        @Test func everyUrlHandedOverTogetherUsesUpItsNote() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])
            let other = "app.macpacker://extractHere?files=/Users/me/Downloads/photos.zip&target=/Users/me/Downloads"
            senders.note(url, sentBy: ownAuditToken())
            senders.note(other, sentBy: ownAuditToken())
            let dropped = try #require(URL(string: other))

            #expect(senders.sentByTrustedSender(firstOf: [try #require(URL(string: url)), dropped]))
            #expect(!senders.sentByTrustedSender(dropped))
        }

        /// A file opened while the app launches can come first. Nobody noted
        /// it, and the Finder action after it still uses up its note.
        @Test func aFinderActionAfterAFileUsesUpItsNote() throws {
            let senders = TrustedSenders(trusting: [try ownRequirement()])
            senders.note(url, sentBy: ownAuditToken())
            let request = try #require(URL(string: url))

            #expect(!senders.sentByTrustedSender(firstOf: [URL(fileURLWithPath: "/Users/me/Downloads/photos.zip"), request]))
            #expect(!senders.sentByTrustedSender(request))
        }

        /// Any one of the requirements will do.
        @Test func aSenderMeetingOneOfTheRequirementsIsTrusted() throws {
            let senders = TrustedSenders(trusting: [try otherRequirement(), try ownRequirement()])

            #expect(senders.note(url, sentBy: ownAuditToken()))
        }
    }
}
