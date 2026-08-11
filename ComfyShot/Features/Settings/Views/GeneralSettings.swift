//
//  GeneralSettings.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI

struct GeneralSettings: View {
    
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
                
                Divider()
                
                Slider(value: $defaultsManager.selectionRectOpacity, in: 0.1...0.9, step: 0.1) {
                    Text("Selection Rect Opacity: \(Int(defaultsManager.selectionRectOpacity * 100))%")
                }
                
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
