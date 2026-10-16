import AppKit
import Sparkle

/// Sparkle for a Dock-less app. A scheduled find does not open a window over
/// whatever the user is doing. The status strip shows an amber readout instead.
/// The feed URL and the public key live in Info.plist. Both are permanent.
@MainActor
final class Updater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    @Published private(set) var updateReady = false

    /// The panel sits at status-bar level, so it has to move before Sparkle's window can be seen.
    var prepareForUpdateUI: (() -> Void)?

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
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

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        #if DEBUG
        guard CommandLine.arguments.contains("--check-updates") else { return }
        let nsError = error as NSError
        let userInitiated = (nsError.userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool) ?? false
        print("updates: user=\(userInitiated)")
        print("updates: \(nsError.localizedDescription)")
        if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
            print("updates: \(suggestion)")
        }
        fflush(stdout)
        #endif
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        #if DEBUG
        guard CommandLine.arguments.contains("--check-updates") else { return }
        print("updates: found \(item.displayVersionString) (\(item.versionString))")
        fflush(stdout)
        #endif
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateReady = false
        #if DEBUG
        if CommandLine.arguments.contains("--check-updates") {
            print("updates: session finished")
            fflush(stdout)
        }
        #endif
    }

    /// Menu item and the readout. Activate first: with no Dock icon the window can open behind other apps.
    func checkForUpdates() {
        prepareForUpdateUI?()
        NSApp.activate()
        #if DEBUG
        if CommandLine.arguments.contains("--check-updates") {
            print("updates: checking")
            fflush(stdout)
        }
        #endif
        controller?.checkForUpdates(nil)
    }
}
