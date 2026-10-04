//
//  ExportImageView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/18/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportImageView: View {
    
    let image: NSImage
    @Binding var isPresented: Bool
    @State private var error: String?
    @State private var showError: Bool = false
    
    
    var body: some View {
        VStack(spacing: 16) {
            ExportImageHeader(isPresented: $isPresented, onSave: saveImage)
                .padding([.top, .horizontal])
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 360, height: 200)
                .padding(.bottom)
        }
        .frame(width: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
        .shadow(radius: 30, y: 12)
        .padding()
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text("\(error, default: "Unknown Error")")
            )
        }
    }
    
    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Untitled.png"
        panel.canCreateDirectories = true
        panel.title = "Save Image"
        
        // beginSheetModal(for:) is better if you have a window to attach to
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    guard let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try data.write(to: url)
                    isPresented = false
                } catch {
                    self.error = "Error Saving: \(error.localizedDescription)"
                    self.showError = true
                }
            } else {
                /// User Cancelled do nothing
            }
        }
    }
}

private struct ExportImageHeader: View {
    @Binding var isPresented: Bool
    let onSave: () -> Void
    
    var body: some View {
        ZStack {
            Text("Export Image")
                .font(.headline)
            
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
                
                Spacer()
                
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
