//
//  InternalEditorView.swift
//  MacPacker
//
//  Created by Arenswald, Stephan (059) on 22.11.23.
//

import Foundation
import SwiftUI

struct InternalEditorView: View {
    let url: URL?
    @State var fileContents: String = ""
    
    init(for url: URL?) {
        self.url = url
    }
    
    var body: some View {
        HStack {
            TextEditor(text: .constant(fileContents))
                .font(Font.callout.monospaced())
        }
        .frame(width: 600, height: 600)
        .padding()
        .task {
            if let url {
                await loadTextAsync(from: url)
            }
        }
    }
    
    func loadTextAsync(from url: URL?) async {
        do {
            if let url {
                if let fileContents = try? String(contentsOf: url, encoding: .utf8) {
                    self.fileContents = fileContents
                }
                if let fileContents = try? String(contentsOf: url, encoding: .macOSRoman) {
                    self.fileContents = fileContents
                }
            }
        }
    }
}
