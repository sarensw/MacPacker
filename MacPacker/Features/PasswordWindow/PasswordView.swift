//
//  PasswordView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.03.26.
//

import Core
import SwiftUI

struct PasswordView: View {
    @State private var password: String = ""

    /// The request being answered. `attempt > 1` means the password we last
    /// submitted was rejected — without saying so, a retry prompt looks
    /// identical to the first one and the user has no idea what went wrong.
    var request: ArchivePasswordRequest?

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var isRetry: Bool { (request?.attempt ?? 1) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = request?.url.lastPathComponent {
                Text("“\(name)” is password protected.", comment: "Explains that the named archive requires a password")
                    .font(.callout)
            }

            HStack(spacing: 4) {
                Text("Password:", comment: "Label for the password field")
                PasswordFieldView(password: $password)
                    .onSubmit { onSubmit?(password) }
            }

            if isRetry {
                Label {
                    Text("That password is incorrect. Try again.", comment: "Shown after an incorrect password is entered")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button {
                    onCancel?()
                } label: {
                    Text("Cancel", comment: "Cancels password entry")
                }

                Button {
                    onSubmit?(password)
                } label: {
                    Text("OK", comment: "Submits the entered password")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        // A rejected password should not be sitting in the field on the retry.
        .onChange(of: request?.attempt) { password = "" }
    }
}
