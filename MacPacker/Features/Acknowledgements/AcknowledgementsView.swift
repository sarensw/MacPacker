//
//  AcknowledgementsView.swift
//  FileFillet
//
//  Created by Arenswald, Stephan (059) on 12.04.25.
//

import SwiftUI

struct AcknowledgementsView: View {
    let acknowledgements = AcknowledgementsLoader.load()

    var body: some View {
        ScrollView {
            ForEach(acknowledgements) { item in
                AcknowledgementsEntryView(
                    lib: item.lib,
                    author: item.author,
                    link: item.link,
                    license: item.license,
                    licenseText: item.licenseText
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }
}
