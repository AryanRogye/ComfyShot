//
//  PermissionView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

struct PermissionView: View {
    
    @Bindable var permissionService: PermissionService
    
    var body: some View {
        VStack {
            Button(action: {
                permissionService.requestPermission()
            }) {
                Text("Request Accessibility")
            }
        }
    }
}
