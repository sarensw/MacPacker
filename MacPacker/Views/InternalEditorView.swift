//
//  InternalEditorView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.11.23.
//

import Foundation
import SwiftUI

struct InternalEditorView: View {
    @State private var keyDownMonitor: Any?
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
        .onAppear {
            loadKeyObserver()
        }
        .onDisappear {
            if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        }
    }
    
    func loadKeyObserver() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { (event: NSEvent) -> NSEvent? in
            if event.keyCode == 53 || event.keyCode == 49 { // esc
                if let window = NSApp.keyWindow {
                    window.performClose(nil)
                    return nil // swallow the event
                }
            }
            return event
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
