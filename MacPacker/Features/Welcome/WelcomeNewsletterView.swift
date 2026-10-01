//
//  WelcomeNewsletterView.swift
//  MacPacker
//
//  "Stay in the loop": the welcome window's newsletter signup. The address
//  goes to Gumroad, which mails a confirmation before it subscribes anyone.
//

import Core
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "welcome")

struct WelcomeNewsletterView: View {
    private enum Status { case idle, sending, sent, failed }

    @State private var email = ""
    @State private var status = Status.idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.LeanBytes.welcomeNewsletterTitle)
                .font(.title2.bold())
            Text(.LeanBytes.welcomeNewsletterSubtitle(Constants.appName))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack {
                TextField(String(localized: .LeanBytes.welcomeNewsletterEmail), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .onSubmit(subscribe)
                Button(action: subscribe) {
                    Text(.LeanBytes.welcomeNewsletterSubscribe)
                }
                .disabled(NewsletterSignup.normalizedEmail(email) == nil)
            }
            .controlSize(.large)
            .disabled(status == .sending || status == .sent)
            .padding(.top, 14)

            // only the note changes, so the fixed-size window keeps its layout
            Text(note)
                .font(.footnote)
                .foregroundStyle(noteStyle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var note: LocalizedStringResource {
        switch status {
        case .sent: .LeanBytes.welcomeNewsletterConfirm
        case .failed: .LeanBytes.welcomeNewsletterFailed
        case .idle, .sending: .LeanBytes.welcomeNewsletterUnsubscribe
        }
    }

    private var noteStyle: Color {
        switch status {
        case .sent: .green
        case .failed: .red
        case .idle, .sending: .secondary
        }
    }

    private func subscribe() {
        guard status != .sending, let address = NewsletterSignup.normalizedEmail(email) else { return }
        status = .sending
        Task {
            if await NewsletterSignup.subscribe(email: address) {
                log.info("Newsletter signup accepted")
                status = .sent
            } else {
                log.error("Newsletter signup failed")
                status = .failed
            }
        }
    }
}
