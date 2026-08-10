//
//  UpdaterViewModel.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import Foundation
import Sparkle
import AppKit

@Observable
@MainActor
final class UpdaterViewModel {

    enum UpdaterChoice {
        /// Downloads (if needed) and installs the update.
        case install
        /// Dismisses the update and skips being notified of it in the future.
        case skip
        /// Dismisses the update until Sparkle reminds the user of it at a later time
        case dismiss
    }

    /// Most likely will only be shown once, 2nd run of the app
    var showPermissionAlert: Bool = false

    /// When User Initiates a "Check Update Exists"
    var showUserInitiatedUpdate: Bool = false

    var showUpdateFound: Bool = false

    /// Update Error if triggered "Check if Update"
    var showUpdateNotFoundError: Bool = false
    var updateNotFoundError: String? = nil

    /// Downloading Related
    var updateDownloadStarted = false
    var downloadContentSize: UInt64?
    var downloadCurrentProgress: UInt64?

    /// Update Error if downloading Error
    var showUpdateError: Bool = false
    var updateErrorMessage: String? = nil

    /// Extraction Related
    var updateExtractionStarted = false
    let maxExtraction: Double = 1.0
    var currentExtraction: Double? = nil

    var installing: Bool = false

    var appcast: SUAppcastItem?
    var updateState: SPUUserUpdateState?

    /// Release notes data (stored for future use, not currently displayed)
    var releaseNotesData                : SPUDownloadData?
    var showUpdateReleaseNotesError     : Bool = false
    var updateReleaseNotesErrorMessage  : String? = nil

    @ObservationIgnored
    private var permissionContinuation: CheckedContinuation<SUUpdatePermissionResponse, Never>?

    @ObservationIgnored
    private var updateFoundContinuation: CheckedContinuation<SPUUserUpdateChoice, Never>?

    @ObservationIgnored
    private var updateReadyToInstallAndRelaunch: CheckedContinuation<SPUUserUpdateChoice, Never>?

    /// Use to Cancel User Initiated Update
    @ObservationIgnored
    var cancelUserInitiatedUpdate: () -> Void = { }

    @ObservationIgnored
    var cancelDownloadInstall: () -> Void = { }

    @ObservationIgnored
    var openMenuBar: () -> Void = { }

    @ObservationIgnored
    var closeMenuBar: () -> Void = { }

    public func startedInstalling() {
        installing = true
    }
    
    /// Updates Title
    public var checkForUpdatesTitle: String {
        return showUserInitiatedUpdate
        ? "Checking for Updates"
        : "Check for Updates"
    }

    /// Status Line For View's
    public var updateStatusLine: String? {
        switch phase {
        case .downloading(let progress, let total):
            /// Downloading (show download percentage)
            if let total, total > 0 {
                let percent = min(Double(progress) / Double(total), 1.0)
                return "Downloading update \(Int(percent * 100))%"
            }
            return "Downloading update..."
        case .extracting(let progress):
            /// Extracting (show progress of extracting
            if let progress {
                return "Preparing update \(Int(progress * 100))%"
            }
            return "Preparing update..."
        case .installing:
            /// Installing Update
            return "Installing update..."
        default:
            return nil
        }
    }

    public func resetProgressKeepUIVisible() {
        updateDownloadStarted = false
        downloadContentSize = nil
        downloadCurrentProgress = nil
        updateExtractionStarted = false
        currentExtraction = nil
        installing = false
    }

    public func resetUpdateUI() {
        permissionContinuation = nil
        updateFoundContinuation = nil
        updateReadyToInstallAndRelaunch = nil
        cancelUserInitiatedUpdate = {}
        cancelDownloadInstall = {}
        appcast = nil
        updateState = nil
        showPermissionAlert = false
        showUserInitiatedUpdate = false
        showUpdateFound = false
        showUpdateNotFoundError = false
        updateNotFoundError = nil
        showUpdateError = false
        updateErrorMessage = nil
        updateDownloadStarted = false
        downloadContentSize = nil
        downloadCurrentProgress = nil
        updateExtractionStarted = false
        currentExtraction = nil
        installing = false
    }

    public func acknowledgeNoUpdateFound() {
        showUpdateNotFoundError = false
        updateNotFoundError = nil
    }

    public func acknowledgeUpdateError() {
        showUpdateError = false
        updateErrorMessage = nil
    }
}

// MARK: - UI Related
extension UpdaterViewModel {
    public func presentPermissionAlert() {
        let alert = AlertMaker.makeAlert(
            messageText: "Enable Automatic Updates?",
            informativeText: "ComfyShot can automatically check for new versions in the background.",
            style: .informational,
            buttons: ["Enable", "Not Now"]
        )
        
        let response = alert.runModal()
        completePermission(
            automaticUpdateChecks: response == .alertFirstButtonReturn
        )
    }
    public func presentNoUpdateAlert() {
        let alert = AlertMaker.makeAlert(
            messageText: "You're Up to Date",
            informativeText: updateNotFoundError ?? "No updates are available right now.",
            style: .informational,
            buttons: ["OK"]
        )
        
        alert.runModal()
        acknowledgeNoUpdateFound()
    }
    public func presentUpdateErrorAlert() {
        let alert = AlertMaker.makeAlert(
            messageText: "Update Failed",
            informativeText: updateErrorMessage ?? "Something went wrong while checking for updates.",
            style: .warning,
            buttons: ["OK"]
        )
        
        alert.runModal()
        acknowledgeUpdateError()
    }
    public func presentUpdateFoundAlert() {
        guard let appcast = appcast else { return }
        
        let version = appcast.displayVersionString
        let title = version.isEmpty
        ? "Update Available"
        : "Version \(version) Is Available"
        
        let body: String = {
            guard let raw = appcast.itemDescription, !raw.isEmpty else {
                return "A new version of ComfyShot is ready to install."
            }
            // Strip HTML tags if Sparkle gives you rich release notes
            return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }()
        
        let alert = AlertMaker.makeAlert(
            messageText: title,
            informativeText: body,
            style: .informational,
            buttons: ["Install", "Skip This Version", "Later"]
        )
        
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            completeUpdateFound(choice: .install)
        case .alertSecondButtonReturn:
            completeUpdateFound(choice: .skip)
        default:
            completeUpdateFound(choice: .dismiss)
        }
    }
}

// MARK: - Extraction
extension UpdaterViewModel {

    public func startedExtraction() {
        updateExtractionStarted = true
        updateDownloadStarted = false
        downloadContentSize = nil
        downloadCurrentProgress = nil
        openMenuBar()
    }

    public func updateExtraction(progress: Double) {
        currentExtraction = progress
    }

}

// MARK: - Downloading
extension UpdaterViewModel {

    /**
     * Started Download Flag
     */
    public func startedDownload(cancel: @escaping () -> Void) {
        updateDownloadStarted = true
        downloadCurrentProgress = 0
        downloadContentSize = nil
        updateExtractionStarted = false
        currentExtraction = nil
        installing = false
        showUpdateError = false
        updateErrorMessage = nil
        openMenuBar()

        cancelDownloadInstall = { [weak self] in
            self?.updateDownloadStarted = false
            cancel()
        }
    }

    /**
     * What the max size of what we're going to download
     *
     * @param size the max size
     */
    public func receivedDownloadContentSize(_ size: UInt64) {
        // Previous behavior:
        // downloadContentSize = size
        guard size > 0, size < UInt64.max else {
            downloadContentSize = nil
            return
        }
        downloadContentSize = size
    }

    public func updateDownloadReceive(length: UInt64) {
        // Previous behavior:
        // if let downloadCurrentProgress {
        //     self.downloadCurrentProgress! += length
        // } else {
        //     downloadCurrentProgress = length
        // }
        if let current = downloadCurrentProgress {
            downloadCurrentProgress = current + length
        } else {
            downloadCurrentProgress = length
        }

        if let total = downloadContentSize,
            let progress = downloadCurrentProgress,
           progress > total {
            downloadContentSize = progress
        }
    }
}

// MARK: - Update Found {
extension UpdaterViewModel {

    /**
     * Present when a update is found
     * @param appcast info about the appcast we will install
     * @param state of the update for example
     */
    public func presentUpdateFound(
        appcast: SUAppcastItem,
        state: SPUUserUpdateState,
        cont: CheckedContinuation<SPUUserUpdateChoice, Never>?
    ) {
        precondition(updateFoundContinuation == nil, "UpdateFound already pending")
        self.appcast = appcast
        self.updateState = state
        updateFoundContinuation = cont

        /// If User Initiated Update Cancel It
        if showUserInitiatedUpdate {
            cancelUserInitiatedUpdate()
        }
        /// Open Menubar When Found
        openMenuBar()
    }
    /**
     * Let user click in UI
     * different case for choice
     */
    public func completeUpdateFound(
        choice: UpdaterChoice
    ) {
        guard let cont = updateFoundContinuation else { return }


        let result: SPUUserUpdateChoice = switch choice {
            case .install: .install
            case .skip: .skip
            case .dismiss: .dismiss
            }

        cont.resume(returning: result)
        updateFoundContinuation = nil

        if choice != .install {
            appcast = nil
            updateState = nil
        }
    }
}

// MARK: - Check Update
extension UpdaterViewModel {
    /// We Initiated a "Is there a Update"
    public func showUserInitiatedUpdate(_ completion: @escaping () -> Void) {
        showUserInitiatedUpdate = true

        cancelUserInitiatedUpdate = { [weak self] in
            guard let self else { return }
            completion()
            self.showUserInitiatedUpdate = false
        }
    }
}

// MARK: - Onboarding
extension UpdaterViewModel {

    /**
     * Intro: How user wants to update our app
     * @param request unused
     * @param cont stored so when user verifies how they want to update our app we can send it back
     */
    public func presentPermission(
        _ request: SPUUpdatePermissionRequest,
        cont: CheckedContinuation<SUUpdatePermissionResponse, Never>?
    ) {
        precondition(permissionContinuation == nil, "Permission already pending")
        showPermissionAlert = true
        permissionContinuation = cont
        /// Open Menubar as prompt is there
        openMenuBar()
    }
    /**
     * We send this back when user has decided how they want to update the app
     * @param automaticUpdateChecks what the user decides they want to update the app
     */
    public func completePermission(
        automaticUpdateChecks: Bool,
    ) {
        guard let cont = permissionContinuation else { return }

        let result = SUUpdatePermissionResponse(
            automaticUpdateChecks: automaticUpdateChecks,
            sendSystemProfile: false
        )

        cont.resume(returning: result)
        permissionContinuation = nil
        showPermissionAlert = false
    }
}


// MARK: - View Helper
extension UpdaterViewModel {
    enum Phase: Equatable {
        case idle

        case permissionRequest
        case checkingUserInitiated

        case updateFound(appcast: SUAppcastItem, state: SPUUserUpdateState)

        case downloading(progress: UInt64, total: UInt64?)
        case extracting(progress: Double?)
        case installing

        case noUpdate(message: String)
        case error(message: String)
    }

    var phase: Phase {

        /// Update Error if downloading Error "Happens Most Likely During Download"
        if showUpdateError, let msg = updateErrorMessage {
            return .error(message: msg)
        }

        /// If Installing
        if installing {
            return .installing
        }

        /// If Extracting
        if updateExtractionStarted {
            return .extracting(progress: currentExtraction)
        }

        /// If Downloading
        if updateDownloadStarted {
            let p = downloadCurrentProgress ?? 0
            return .downloading(
                progress: p,
                total: downloadContentSize
            )
        }

        /// Update Found
        if let a = appcast, let s = updateState {
            return .updateFound(appcast: a, state: s)
        }

        /// User Initiated Update
        if showUserInitiatedUpdate {
            return .checkingUserInitiated
        }

        /// No Update Found
        if showUpdateNotFoundError {
            return .noUpdate(message: updateNotFoundError ?? "No update found")
        }

        /// Show how user wants to check for updates, most likely this will be automatic
        if showPermissionAlert { return .permissionRequest }

        return .idle
    }
}
