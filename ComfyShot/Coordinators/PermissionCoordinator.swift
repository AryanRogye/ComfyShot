//
//  PermissionCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

class PermissionCoordinator {
    let windowCoordinator: WindowCoordinator
    let permissionSerivce: PermissionService
    
    init(
        permissionSerivce: PermissionService,
        windowCoordinator: WindowCoordinator
    ) {
        self.permissionSerivce = permissionSerivce
        self.windowCoordinator = windowCoordinator
    }
    
    let id = UUID().uuidString
    
    public func open() {
        windowCoordinator.showWindow(
            id: id,
            title: "Permissions",
            content: PermissionView(permissionService: permissionSerivce)
        )
    }
}
