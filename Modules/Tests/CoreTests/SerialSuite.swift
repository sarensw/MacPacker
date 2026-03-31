//
//  SerialSuite.swift
//  Modules
//
//  Created by Stephan Arenswald on 31.03.26.
//

import Testing

/// All CoreTests run serially because the CSevenZip C library
/// has global mutable state and is not thread-safe.
@Suite(.serialized)
enum AllCoreTests {}
