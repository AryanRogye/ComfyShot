//
//  SettingsView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

struct SettingsView: View {
    
    @Bindable var defaultsManager: DefaultsManager
    
    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Toggle("Capture Area over macOS Screenshot UI", isOn: $defaultsManager.captureOverAppleScreenshotUI)
                Text("""
                Experimental. Allows ComfyShot to appear above Apple's Screenshot UI.
                
                Moving or resizing an existing selection may not work correctly while Apple's Screenshot UI is open.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)

            }
        }
        .formStyle(.grouped)
    }
}
