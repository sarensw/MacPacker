//
//  FinderRequestSenders.swift
//  MacPacker
//

import AppKit
import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Which of the urls that reach the app MacPacker's own Finder extension sent:
/// only those are carried out (#286).
///
/// macOS notes in a url's get-url Apple event which process asked Launch
/// Services to open it: the Finder extension, not the agent that delivers the
/// event. That process can be checked only while it runs, and only while the
/// event is being handled: AppKit hands the url to `application(_:open:)` once
/// it has restored windows, which on some launches is after the event was
/// handled, and the event is gone by then. So this goes in front of AppKit's
/// own handler for the event, notes the sender, and passes the event on as it
/// came.
@MainActor
enum FinderRequestSenders {
    private static let senders = TrustedSenders(trusting: trustedRequirements())

    private static var appKitHandler: AEEventHandlerUPP?
    private static var appKitRefCon: UnsafeMutableRawPointer?

    /// Goes in front of AppKit's get-url handler. Called from
    /// `applicationWillFinishLaunching`: AppKit has installed its handler by
    /// then, and no event has been handled yet.
    static func install() {
        let eventClass = AEEventClass(kInternetEventClass)
        let eventID = AEEventID(kAEGetURL)
        guard AEGetEventHandler(eventClass, eventID, &appKitHandler, &appKitRefCon, false) == noErr,
              appKitHandler != nil else {
            log.error("AppKit's get-url handler not found — every Finder action will be refused")
            return
        }
        let installed = AEInstallEventHandler(eventClass, eventID, { event, reply, _ in
            MainActor.assumeIsolated {
                if let event {
                    FinderRequestSenders.noteSender(of: event)
                }
                return FinderRequestSenders.appKitHandler?(event, reply, FinderRequestSenders.appKitRefCon)
                    ?? OSErr(errAEEventNotHandled)
            }
        }, nil, false)
        log.info("Checking who sends get-url events", context: ["installed": "\(installed == noErr)"])
    }

    /// Whether the Finder extension sent the first of `urls`, the one carried
    /// out. Each url sent answers once.
    static func sentByFinderExtension(firstOf urls: [URL]) -> Bool {
        senders.sentByTrustedSender(firstOf: urls)
    }

    private static func noteSender(of event: UnsafePointer<AppleEvent>) {
        var copy = AEDesc()
        guard AEDuplicateDesc(event, &copy) == noErr else { return }
        let descriptor = NSAppleEventDescriptor(aeDescNoCopy: &copy)
        guard let url = descriptor.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        let token = descriptor.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data
        // checked first: the sender has to be running still
        let trusted = senders.note(url, sentBy: token)
        let sender = token.flatMap(CodeSignature.identifier(ofProcess:)) ?? "unknown or gone"
        if trusted {
            log.info("Url from the Finder extension", context: ["sender": sender])
        } else {
            log.warning("Url from another sender", context: ["sender": sender])
        }
    }

    /// The Finder extension inside this very app, in this build or any later
    /// one: its designated requirement.
    private static func trustedRequirements() -> [SecRequirement] {
        var requirements: [SecRequirement] = []
        if let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("FinderExtension.appex"),
           let requirement = CodeSignature.designatedRequirement(ofCodeAt: appex) {
            requirements.append(requirement)
        } else {
            log.error("No Finder extension to trust — every Finder action will be refused")
        }
#if DEBUG
        // The UI tests send Finder actions as XCTest opens urls in the app
        // under test: through Apple's testmanagerd. Debug builds only.
        var testManager: SecRequirement?
        if SecRequirementCreateWithString("identifier \"com.apple.testmanagerd\" and anchor apple" as CFString, [], &testManager) == errSecSuccess,
           let testManager {
            requirements.append(testManager)
        }
#endif
        return requirements
    }
}
