//
//  ArchiveAnalysisView.swift
//  MacPacker
//
//  Created by Claude on 16.11.26.
//

import AppKit
import Core
import SwiftUI

/// What Settings › Advanced › Analyze Archive finds out about an archive, for
/// a bug report about one the user cannot share (#413). Shown as it is made:
/// an archive that hangs a step still shows everything up to it, and which
/// step that is.
struct ArchiveAnalysisView: View {
    let url: URL
    let analyzer: ArchiveAnalyzer

    @Environment(\.dismiss) private var dismiss
    @State private var analysis = ArchiveAnalysis()
    @State private var isRunning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.analyzeArchiveTitle)
                .font(.headline)

            ScrollView {
                // The report is for us, so it stays in English, like the logs.
                Text(verbatim: analysis.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(analysis.text, forType: .string)
                } label: {
                    Text(.commonCopy)
                }
                Button {
                    dismiss()
                } label: {
                    Text(.commonDone)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 520)
        .task {
            for await progress in analyzer.analyze(url) {
                analysis.apply(progress)
            }
            analysis.finish()
            isRunning = false
        }
    }
}
