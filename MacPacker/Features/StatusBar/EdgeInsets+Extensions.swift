//
//  EdgeInsets+Extensions.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 06.02.26.
//

import Core
import SwiftUI

extension EdgeInsets {
    static var windowSafeHorizontal: EdgeInsets {
        if #available(macOS 26, *) {
            return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        } else {
            return EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        }
    }
}
