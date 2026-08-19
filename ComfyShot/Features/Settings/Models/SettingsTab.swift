//
//  SettingsTab.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case editor = "Editor"
    
    var label: String {
        switch self {
        case .general:
            "gear"
        case .shortcuts:
            "keyboard"
        case .editor:
            "pencil.and.outline"
        }
    }
}
