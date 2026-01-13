//
//  AcknowledgementsEntryView.swift
//  FileFillet
//
//  Created by Arenswald, Stephan (059) on 12.04.25.
//

import SwiftUI

struct AcknowledgementsEntryView: View {
    var lib: String
    var author: String
    var link: String
    var license: String
    var licenseText: String
    
    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lib)
                
                HStack(spacing: 0) {
                    Text(verbatim: "Copyright @ \(author) (")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Link(destination: URL(string: link)!, label: {
                        Text(link)
                            .font(.caption)
                    })
                    
                    Text(verbatim: ") (\(license))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                
                Text(licenseText)
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
            }
            
            Spacer()
        }
        .padding(.bottom, 16)
    }
}
