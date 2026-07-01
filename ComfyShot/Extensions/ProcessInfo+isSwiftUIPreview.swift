//
//  ProcessInfo+isSwiftUIPreview.swift
//  ComfyTile
//
//  Created by Aryan Rogye on 6/10/26.
//

import Foundation

extension ProcessInfo {
    static var isSwiftUIPreview: Bool {
        let environment = processInfo.environment

        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}
