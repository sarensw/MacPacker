//
//  NewsletterSignupTests.swift
//  Modules
//
//  The request the welcome window's newsletter form sends to Gumroad, and how
//  its answer is read. Nothing here goes over the network.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    struct NewsletterSignupTests {

        @Test func theRequestPostsTheFollowFormAndAsksForJSON() {
            let request = NewsletterSignup.request(email: "me@example.com")
            #expect(request.url?.absoluteString == "https://app.gumroad.com/follow_from_embed_form")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        }

        /// A raw "+" in a form body arrives as a space, which would turn
        /// me+news@example.com into an address that does not exist.
        @Test func theBodyEncodesPlusSigns() throws {
            let body = try #require(NewsletterSignup.request(email: "me+news@example.com").httpBody)
            #expect(String(decoding: body, as: UTF8.self) == "seller_id=3352614167061&email=me%2Bnews%40example.com")
        }

        @Test(arguments: [
            (200, #"{"success":true,"message":"Check your inbox to confirm your follow request."}"#, true),
            (422, #"{"success":false,"message":"Email invalid."}"#, false),
            (404, #"{"success":false,"error":"Not found"}"#, false),
            (200, "<html></html>", false),
        ])
        func onlyASuccessAnswerCounts(status: Int, body: String, accepted: Bool) throws {
            let response = try #require(HTTPURLResponse(
                url: NewsletterSignup.endpoint, statusCode: status, httpVersion: nil, headerFields: nil))
            #expect(NewsletterSignup.accepted(Data(body.utf8), response) == accepted)
        }

        @Test(arguments: [
            ("  me@example.com \n", "me@example.com"),
            ("me@example", nil),
            ("example.com", nil),
            ("@example.com", nil),
            ("me@exa mple.com", nil),
            ("a@b@example.com", nil),
            ("", nil),
        ] as [(String, String?)])
        func onlyAddressLikeTextIsSent(text: String, email: String?) {
            #expect(NewsletterSignup.normalizedEmail(text) == email)
        }
    }
}
