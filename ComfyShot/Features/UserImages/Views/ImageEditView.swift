//
//  ImageEditView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/18/26.
//

import DrawKit
import SwiftUI

struct ImageEditView: View {
    let image: UserImage
    @Bindable var defaultSelection: DefaultSelection
    @State private var editor: DrawEditor?
    
    var body: some View {
        if let editor {
            NavigationStack {
                UserImageEditor(editor: editor)
            }
        } else {
            ProgressView()
                .task {
                    let cgImage = image.image
                    let size = NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
                    let nsImage = NSImage(cgImage: cgImage, size: size)
                    editor = .init(image: nsImage, defaultSelection: defaultSelection)
                }
        }
    }
}

private struct UserImageEditor: View {
    
    @Bindable var editor: DrawEditor
    @State private var save: Bool = false
    
    @State private var imageExportOptionsPresented: Bool = false
    @State private var onImageExportRequested: NSImage?
    
    var body: some View {
        ZStack {
            VStack {
                DrawCanvas(editor: editor, save: $save) { image in
                    onImageExportRequested = image
                }
                DrawCanvasControls(editor: editor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button {
                        editor.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .keyboardShortcut(.init("z"), modifiers: [.command])
                    .help("Undo (⌘Z)")
                    
                    Button {
                        editor.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .keyboardShortcut(.init("z"), modifiers: [.command, .shift])
                    .help("Redo (⇧⌘Z)")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        save = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .keyboardShortcut(.init("s"), modifiers: [.command])
                    .help("Save Image (⌘S)")
                }
            }
            .onChange(of: imageExportOptionsPresented) { _, newValue in
                if !newValue {
                    onImageExportRequested = nil
                }
            }
            .onChange(of: onImageExportRequested) { _, newValue in
                if onImageExportRequested != nil {
                    withAnimation(.spring) {
                        imageExportOptionsPresented = true
                    }
                }
            }
            
            if let onImageExportRequested, imageExportOptionsPresented {
                Color.black.opacity(0.3)
                    .onTapGesture {
                        withAnimation(.spring) {
                            imageExportOptionsPresented = false
                        }
                    }
                
                ExportImageView(
                    image: onImageExportRequested,
                    isPresented: $imageExportOptionsPresented
                )
            }
        }
    }
}
