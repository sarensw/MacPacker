//
//  SettingUpdateCheck.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 22.04.26.
//


enum SettingUpdateCheck: Int, CaseIterable, Identifiable, Codable {
    static let defaultKey = "checkForUpdates"
    static let defaultValue = SettingUpdateCheck.automatically
    
    case automatically = 0
    case manually = 1
    
    var id: Int {
        self.rawValue
    }
    
    var label: String {
        switch self {
        case .automatically:
            return "Automatically"
        case .manually:
            return "Manually"
        }
    }
}

