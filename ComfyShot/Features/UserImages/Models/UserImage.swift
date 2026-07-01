//
//  UserImage.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit

struct UserImage: Identifiable {
    let id = UUID()
    let image: CGImage
    let size: NSSize
}
