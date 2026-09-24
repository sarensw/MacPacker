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
                Text(.commonPasswordProtectedMessage(name))
                    .font(.callout)
            }

            HStack(spacing: 4) {
                Text(.commonPassword)
                PasswordFieldView(password: $password)
                    .onSubmit { onSubmit?(password) }
            }

            if isRetry {
                Label {
                    Text(.errorPasswordIncorrect)
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
                    Text(.commonCancel)
                }

                Button {
                    onSubmit?(password)
                } label: {
                    Text(.commonOk)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        // A rejected password should not be sitting in the field on the retry.
        .onChange(of: request?.attempt) { password = "" }
    }
}
