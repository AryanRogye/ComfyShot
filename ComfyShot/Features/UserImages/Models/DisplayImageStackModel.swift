//
//  DisplayImageStackModel.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import Observation

@Observable
@MainActor
final class DisplayImageStackModel {
    var images: [UserImage] = []

    func remove(_ image: UserImage) {
        images.removeAll { $0.id == image.id }
    }
}
