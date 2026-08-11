//
//  ShortcutSettings.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI

struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.label) {
                        CustomShortcutRecorder(action: action)
                            .frame(width: 176, height: 28)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
