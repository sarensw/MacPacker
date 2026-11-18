//
//  OpenArchivesInTabsTests.swift
//  Modules
//
//  Archives open as tabs of the front window unless the user turns it off in
//  Settings ▸ General.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct OpenArchivesInTabsTests {

        /// What the app registers as it starts is what a first launch reads.
        @Test func archivesOpenInTabsUntilTurnedOff() {
            Keys.registerDefaults()
            let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
            #expect(registered[Keys.openArchivesInTabs] as? Bool == true)
        }
    }
}
