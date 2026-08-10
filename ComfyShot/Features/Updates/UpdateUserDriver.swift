//
//  UpdateUserDriver.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import Combine
import Sparkle
import SwiftUI

final class UpdateUserDriver: NSObject, SPUUserDriver {

    let vm: UpdaterViewModel

    init(vm: UpdaterViewModel) {
        self.vm = vm
    }

    // MARK: - Show
    /**
     * Show an updater permission request to the user
     *
     * Ask the user for their permission regarding update checks.
     * This is typically only called once per app installation.
     * This is what asks the user "Check Updates Automatically?"
     *
     * @param request The update permission request.
     * @param reply A reply with a update permission response.
     */
    func show(
        _ request: SPUUpdatePermissionRequest
    ) async -> SUUpdatePermissionResponse {
        /// Send Request to VM, VM will handle showing it, and setting it back
        return await withCheckedContinuation { cont in
            vm.presentPermission(request, cont: cont)
        }
    }

    // MARK: - showUserInitiatedUpdateCheck
    /**
     * When we click "Check for Updates"
     * Mostly in Settings
     *
     * @param cancellation Invoke this cancellation block to cancel the update check before the update check is completed.
     */
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        vm.showUserInitiatedUpdate(cancellation)
    }

    // MARK: - showUpdateFound
    /**
     * Trigger for when a Update is found, we use this
     * To show something in our UI
     *
     * @param appcastItem The Appcast Item containing information that reflects the new update.
     * @param state The current state of the user update. See above discussion for notable properties.
     */
    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        return await withCheckedContinuation { cont in
            vm.presentUpdateFound(
                appcast: appcastItem,
                state: state,
                cont: cont
            )
        }
    }

    // MARK: - showUpdateReleaseNotes
    // TODO: Show Update Release Notes in UI
    /**
     * Show the user the release notes for the new update
     *
     * Display the release notes to the user. This will be called after showing the new update.
     * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
     * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
     *
     * @param downloadData The data for the release notes that was downloaded from the new update's appcast.
     */
    func showUpdateReleaseNotes(
        with downloadData: SPUDownloadData
    ) {
        // Store for future use, not currently displayed in UI
        vm.releaseNotesData = downloadData
    }

    // MARK: - showUpdateReleaseNotesFailedToDownloadWithError
    // TODO: Show Release Notes Error After Above is Done
    /**
     * Show the user that the new update's release notes could not be downloaded
     *
     * This will be called after showing the new update.
     * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
     * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
     *
     * @param error The error associated with why the new update's release notes could not be downloaded.
     */
    func showUpdateReleaseNotesFailedToDownloadWithError(
        _ error: any Error
    ) {
        vm.showUpdateReleaseNotesError = true
    }

    // MARK: - showUpdateNotFoundWithError
    /**
     * Show the user a new update was not found
     *
     * Let the user know a new update was not found after they tried initiating an update check.
     *
     * @param error The error associated with why a new update was not found. See above discussion for more details.
     * @param acknowledgement Acknowledge to the updater that no update found error was shown.
     */
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        vm.showUserInitiatedUpdate = false  // Must reset this first so phase shows .noUpdate
        vm.showUpdateNotFoundError = true
        vm.updateNotFoundError = error.localizedDescription
        acknowledgement()
    }

    // MARK: - showUpdaterError
    /**
     * Show the user an update error occurred
     *
     * Let the user know that the updater failed with an error. This will not be invoked without the user having been
     * aware that an update was in progress.
     *
     * Before this point, any of the non-error user driver methods may have been invoked.
     *
     * @param error The error associated with what update error occurred.
     * @param acknowledgement Acknowledge to the updater that the error was shown.
     */
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        vm.showUpdateError = true
        vm.updateErrorMessage = error.localizedDescription
        vm.resetProgressKeepUIVisible()

        acknowledgement()
    }

    // MARK: - showDownloadInitiated
    /**
     * Show the user that downloading the new update initiated
     *
     * Let the user know that downloading the new update started.
     *
     * @param cancellation Invoke this cancellation block to cancel the download at any point before `-showDownloadDidStartExtractingUpdate` is invoked.
     */
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        vm.startedDownload(cancel: cancellation)
    }

    // MARK: - showDownloadDidReceiveExpectedContentLength
    /**
     * Show the user the content length of the new update that will be downloaded
     *
     * @param expectedContentLength The expected content length of the new update being downloaded.
     * An implementor should be able to handle if this value is invalid (more or less than actual content length downloaded).
     * Additionally, this method may be called more than once for the same download in rare scenarios.
     */
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        vm.receivedDownloadContentSize(expectedContentLength)
    }

    // MARK: - showDownloadDidReceiveData
    /**
     * Show the user that the update download received more data
     *
     * This may be an appropriate time to advance a visible progress indicator of the download
     * @param length The length of the data that was just downloaded
     */
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        vm.updateDownloadReceive(length: length)
    }

    // MARK: - showDownloadDidStartExtractingUpdate
    /**
     * Show the user that the update finished downloading and started extracting
     *
     * Sparkle uses this to show an indeterminate progress bar.
     *
     * Before this point, `showDownloadDidReceiveDataOfLength:` or `showUpdateFoundWithAppcastItem:state:reply:` may be called.
     * An update can potentially resume at this point after having been automatically downloaded in the background (without the user driver)  before.
     *
     * After extraction starts, the user may be shown an authorization prompt to install the update if authorization is required for installation.
     * For example, this may occur if the update on disk is owned by a different user (e.g. root or admin for non-admin users), or if the update is a package install.
     */
    func showDownloadDidStartExtractingUpdate() {
        vm.startedExtraction()
    }

    // MARK: - showExtractionReceivedProgress
    /**
     * Show the user that the update is extracting with progress
     *
     * Let the user know how far along the update extraction is.
     *
     * Before this point, `-showDownloadDidStartExtractingUpdate` is called.
     *
     * @param progress The progress of the extraction from a 0.0 to 1.0 scale
     */
    func showExtractionReceivedProgress(_ progress: Double) {
        vm.updateExtraction(progress: progress)
    }

    // MARK: - showReadyToInstallAndRelaunch
    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        /// for now just install it
        return .install
    }

    // MARK: - showInstallingUpdate
    /**
     * Show the user that the update is installing
     *
     * Let the user know that the update is currently installing.
     *
     * Before this point, `-showReadyToInstallAndRelaunch:` or  `-showUpdateFoundWithAppcastItem:state:reply:` will be called.
     *
     * @param applicationTerminated Indicates if the application has been terminated already.
     * If the application hasn't been terminated, a quit event is sent to the running application before installing the update.
     * If the application or user delays or cancels termination, there may be an indefinite period of time before the application fully quits.
     * It is up to the implementor whether or not to decide to continue showing installation progress in this case.
     *
     * @param retryTerminatingApplication This handler gives a chance for the application to re-try sending a quit event to the running application before installing the update.
     * The application may cancel or delay termination. This handler gives the user driver another chance to allow the user to try terminating the application again.
     * If the application does not delay or cancel application termination, there is no need to invoke this handler. This handler may be invoked multiple times.
     * Note this handler should not be invoked if @c applicationTerminated is already @c YES
     */
    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        vm.startedInstalling()
    }

    // MARK: - showUpdateInstalledAndRelaunched
    /**
     * Show the user that the update installation finished
     *
     * Let the user know that the update finished installing.
     *
     * This will only be invoked if the updater process is still alive, which is typically not the case if
     * the updater's lifetime is tied to the application it is updating. This implementation must not try to reference
     * the old bundle prior to the installation, which will no longer be around.
     *
     * Before this point, `-showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:` will be called.
     *
     * @param relaunched Indicates if the update was relaunched.
     * @param acknowledgement Acknowledge to the updater that the finished installation was shown.
     */
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void)
    {
        vm.resetUpdateUI()
        acknowledgement()
    }

    // MARK: - dismissUpdateInstallation
    /**
     * Dismiss the current update installation
     *
     * Stop and tear down everything.
     * Dismiss all update windows, alerts, progress, etc from the user.
     * Basically, stop everything that could have been started. Sparkle may invoke this when aborting or finishing an update.
     */
    func dismissUpdateInstallation() {
        // Preserve "no update found" error so user can acknowledge it
        let preserveNoUpdateError = vm.showUpdateNotFoundError
        let preserveNoUpdateMessage = vm.updateNotFoundError

        vm.resetUpdateUI()

        // Restore the error state if it was set
        if preserveNoUpdateError {
            vm.showUpdateNotFoundError = true
            vm.updateNotFoundError = preserveNoUpdateMessage
        }
    }
}
