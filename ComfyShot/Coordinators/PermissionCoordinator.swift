//
//  PermissionCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

class PermissionCoordinator {
    let windowCoordinator: WindowCoordinator
    let permissionService: PermissionService
    let onClose: () -> Void

    init(
        permissionService: PermissionService,
        windowCoordinator: WindowCoordinator,
        onClose: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.windowCoordinator = windowCoordinator
        self.onClose = onClose
    }
    
    let id = UUID().uuidString
    
    public func open() {
        windowCoordinator.showWindow(
            id: id,
            title: "Permissions",
            content: PermissionView(
                permissionService: permissionService,
                onClose: { [weak self] in
                    guard let self else { return }
                    self.windowCoordinator.closeWindow(id: id)
                    self.onClose()
                }
            ),
            onClose: { [weak self] in
                guard let self else { return }
                if !permissionService.isAccessibilityEnabled || !permissionService.isScreenRecordingEnabled {
                    NSApp.terminate(nil)
                }
            }
        )
    }
}
