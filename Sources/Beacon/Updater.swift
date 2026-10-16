import AppKit
import Sparkle

/// Sparkle for a Dock-less app. A scheduled find does not open a window over
/// whatever the user is doing. The status strip shows an amber readout instead.
/// The feed URL and the public key live in Info.plist. Both are permanent.
@MainActor
final class Updater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var updateReady = false

    /// The panel sits at status-bar level, so it has to move before Sparkle's window can be seen.
    var prepareForUpdateUI: (() -> Void)?

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // The delegate asked to show this one itself. User-initiated checks still use Sparkle's window.
        if !handleShowingUpdate {
            updateReady = true
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateReady = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateReady = false
    }

    /// Menu item and the readout. Activate first: with no Dock icon the window can open behind other apps.
    func checkForUpdates() {
        prepareForUpdateUI?()
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
