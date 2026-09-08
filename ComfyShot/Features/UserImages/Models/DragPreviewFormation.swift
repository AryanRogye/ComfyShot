//
//  DragPreviewFormation.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/8/26.
//

import SwiftUI
import Defaults

enum DragPreviewFormation: String, CaseIterable, Defaults.Serializable {

    case `default` = "Default"
    case none = "None"
    case pile = "Pile"
    case list = "List"
    case stack = "Stack"

    var formation: DragDropPreviewsFormation {
        switch self {
        case .default:
            return DragDropPreviewsFormation.default
        case .none:
            return DragDropPreviewsFormation.none
        case .pile:
            return DragDropPreviewsFormation.pile
        case .list:
            return DragDropPreviewsFormation.list
        case .stack:
            return DragDropPreviewsFormation.stack
        }
    }
}
