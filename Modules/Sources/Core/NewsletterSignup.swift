//
//  NewsletterSignup.swift
//  Modules
//
//  The welcome window's newsletter form. It posts to the follow form of
//  sarensw's Gumroad profile: Gumroad mails the address once to confirm
//  (double opt-in) and owns the unsubscribe link, so nothing is kept here.
//

import Foundation

public enum NewsletterSignup {
    static let endpoint = URL(string: "https://app.gumroad.com/follow_from_embed_form")!
    /// The `seller_id` of the follow form on sarensw.gumroad.com.
    static let sellerID = "3352614167061"

    /// The trimmed address when it looks like one, nil otherwise. Gumroad does
    /// the real validation; this only keeps Subscribe off for obvious typos.
    public static func normalizedEmail(_ text: String) -> String? {
        let email = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !email.contains(where: \.isWhitespace) else { return nil }
        return email
    }

    /// True once Gumroad took the address. It then sends the confirmation mail.
    public static func subscribe(email: String, session: URLSession = .shared) async -> Bool {
        guard let (data, response) = try? await session.data(for: request(email: email)) else { return false }
        return accepted(data, response)
    }

    static func request(email: String) -> URLRequest {
        // A form body reads "+" as a space, so encode everything but the unreserved set.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        // JSON instead of Gumroad's HTML confirmation page
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("seller_id=\(sellerID)&email=\(encodedEmail)".utf8)
        return request
    }

    /// Gumroad answers `{"success": true, …}`, or a 4xx with `success: false`
    /// and a message when it refuses the address.
    static func accepted(_ data: Data, _ response: URLResponse) -> Bool {
        struct Answer: Decodable { let success: Bool }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return false }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.success == true
    }
}
