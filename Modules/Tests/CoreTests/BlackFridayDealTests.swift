//
//  BlackFridayDealTests.swift
//  Modules
//
//  The welcome window and the More Apps menu show the Black Friday deal
//  through its last day in the user's own time zone, and name that day the
//  way the user's region writes dates.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    struct BlackFridayDealTests {

        private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

        private func date(_ iso8601: String) throws -> Date {
            try Date(iso8601, strategy: .iso8601)
        }

        /// The last evening in Los Angeles is already Dec 3 in UTC: the deal
        /// ends at the user's midnight, not at UTC's.
        @Test func theDealRunsThroughItsLastDayInTheUsersTimeZone() throws {
            #expect(BlackFridayDeal.isActive(at: try date("2026-11-27T09:00:00-08:00"), timeZone: losAngeles))
            #expect(BlackFridayDeal.isActive(at: try date("2026-12-02T23:59:59-08:00"), timeZone: losAngeles))
            #expect(!BlackFridayDeal.isActive(at: try date("2026-12-03T00:00:00-08:00"), timeZone: losAngeles))
        }

        @Test(arguments: [("en_US", "Dec 2"), ("de_DE", "2. Dez."), ("ja_JP", "12月2日")])
        func theLastDayReadsAsTheRegionWritesDates(locale: String, text: String) {
            #expect(BlackFridayDeal.lastDayText(locale: Locale(identifier: locale), timeZone: losAngeles) == text)
        }
    }
}
