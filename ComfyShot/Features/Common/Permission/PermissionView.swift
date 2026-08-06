//
//  PermissionView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import SwiftUI

struct PermissionView: View {
    @Bindable var permissionService: PermissionService
    let onClose: () -> Void
    
    @State private var showRestartNotice: Bool = false
    
    private var allGranted: Bool {
        permissionService.isAccessibilityEnabled && permissionService.isScreenRecordingEnabled
    }
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            if allGranted {
                successState
            } else {
                requestState
            }
        }
        .frame(width: 420, height: 380) // Slightly increased height for the new text
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: allGranted)
        .animation(.default, value: permissionService.isAccessibilityEnabled)
        .animation(.default, value: permissionService.isScreenRecordingEnabled)
    }
    
    // MARK: - Request State
    private var requestState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.blue)
                    .padding(.top, 24)
                
                Text("Permissions Required")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                
                Text("ComfyShot needs these permissions to see and capture your windows.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                permissionRow(
                    title: "Accessibility",
                    icon: "macwindow.badge.plus",
                    isGranted: permissionService.isAccessibilityEnabled,
                    onRequest: { permissionService.requestAccessibilityPermission() },
                    onReset: { try? permissionService.resetAccessibility() }
                )
                
                permissionRow(
                    title: "Screen Recording",
                    icon: "record.circle",
                    isGranted: permissionService.isScreenRecordingEnabled,
                    onRequest: {
                        withAnimation { showRestartNotice = true }
                        permissionService.requestScreenRecordingPermission()
                    },
                    onReset: { try? permissionService.resetScreenRecording() }
                )
                
                if showRestartNotice && !permissionService.isScreenRecordingEnabled {
                    Text("macOS may require you to restart the app after granting Screen Recording.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func permissionRow(title: String, icon: String, isGranted: Bool, onRequest: @escaping () -> Void, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            } else {
                HStack(spacing: 12) {
                    // Visible reset button when not granted
                    Button(action: onReset) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset \(title) permission if macOS is stuck")
                    
                    Button("Grant") {
                        onRequest()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Success State
    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
            
            Text("You're all set")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onClose()
            }
        }
    }
}
