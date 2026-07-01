//
//  ComfyShotApp.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

@main
struct ComfyShotApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup { EmptyView().destroyViewWindow() }
    }
}
