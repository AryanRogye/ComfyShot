//
//  CGSTypes.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

/// Private WindowServer APIs that allow a background menu-bar app to control
/// cursor visibility. The public hide call alone can be ignored while another
/// application remains active, which ComfyShot requires for transient UI.
typealias CGSConnectionID = Int32
