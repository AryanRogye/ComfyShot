//
//  SettingsView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

struct SettingsView: View {
    
    @Bindable var defaultsManager: DefaultsManager
    @AppStorage("SelectedTab") private var selectedTab: SettingsTab = .general
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.label)
                }
            }
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .general:
                    GeneralSettings(defaultsManager: defaultsManager)
                case .shortcuts:
                    ShortcutSettings()
                case .editor:
                    EditorSettings(defaultsManager: defaultsManager)
                }
            }
            .navigationTitle("General")
        }
    }
}
