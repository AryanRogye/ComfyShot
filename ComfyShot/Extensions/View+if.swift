//
//  View+if.swift
//  ComfyTile
//
//  Created by Aryan Rogye on 4/15/26.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
