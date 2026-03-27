//
//  PasswordView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.03.26.
//

import SwiftUI

struct PasswordView: View {
    @State private var password: String = ""
    
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(verbatim: "Password:")
                PasswordFieldView(password: $password)
            }
            
            HStack {
                Spacer()
                
                Button {
                    onCancel?()
                } label: {
                    Text(verbatim: "Cancel")
                }
                
                Button {
                    onSubmit?(password)
                } label: {
                    Text(verbatim: "OK")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
