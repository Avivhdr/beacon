import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    /// When the panel last closed because it lost focus. A click on the menu bar icon closes it that way
    /// first, and shouldn't then reopen it.
    private var lastResignClose = Date.distantPast
    private var outsideClickMonitor: Any?
    private var filtersWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        panel = FloatingPanel(size: PanelView.size)
        let host = NSHostingView(rootView: PanelView(model: model) { [weak self] in self?.openFilters() })
        host.frame = NSRect(origin: .zero, size: PanelView.size)
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.hidePanel() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.lastResignClose = Date()
                self.hidePanel()
            }
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon() }
            .store(in: &cancellables)

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.start() }
        }

        updateIcon()
        model.start()
    }

    private func updateIcon() {
        let badge = model.reviewBadge
        statusItem.button?.image = StatusIcon.render(notifications: model.unreadCount, reviews: badge.count, reviewsDimmed: badge.dim)
    }

    private func openFilters() {
        hidePanel()
        if let window = filtersWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        // A new view each time, so the editor starts from the config on disk.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Review filters"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.ink)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: FiltersView(model: model) { [weak window] in window?.close() })
        window.center()
        filtersWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else if Date().timeIntervalSince(lastResignClose) > 0.3 {
            showPanel()
        }
    }

    /// Where the panel goes: hanging under the menu bar of the screen that was clicked, centered on the icon.
    /// The status item's own window can't be trusted for this. On recent macOS it reports a frame above the
    /// top of the display and no screen.
    private func panelOrigin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        var iconX = mouse.x
        if let button = statusItem.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            if anchor.midX >= screen.frame.minX && anchor.midX <= screen.frame.maxX { iconX = anchor.midX }
        }
        let visible = screen.visibleFrame
        let size = PanelView.size
        let x = min(max(iconX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        return NSPoint(x: x, y: visible.maxY - size.height - 6)
    }

    private func showPanel() {
        model.panelWillOpen()
        let origin = panelOrigin()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Drops in from just under the menu bar.
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + (reduceMotion ? 0 : 10)))
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }
        // If macOS doesn't hand us focus, losing key never fires, so clicks in other apps close the panel too.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
        model.refreshOnOpen()
    }

    private func hidePanel() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Skip if the panel was reopened while fading out.
                guard let panel = self?.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        })
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        Task { @MainActor in
            if id.hasPrefix("summary-") {
                self.showPanel()
            } else {
                self.model.open(itemId: id)
            }
        }
        completionHandler()
    }
}

/// The borderless window the panel lives in. Can take focus, closes on Escape.
final class FloatingPanel: NSPanel {
    var onCancel: () -> Void = {}

    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isReleasedWhenClosed = false
        // Panels hide whenever their app is inactive, and a menu bar app usually is when its icon is clicked.
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

enum StatusIcon {
    /// Draws "bell N  pull M" as one template image. A dimmed level is drawn at lower alpha,
    /// which the menu bar keeps for template images.
    static func render(notifications: Int, reviews: Int, reviewsDimmed: Bool) -> NSImage {
        var segments: [(symbol: String, text: String?, alpha: CGFloat)] = []
        if notifications > 0 { segments.append(("bell.fill", "\(notifications)", 1)) }
        if reviews > 0 { segments.append(("arrow.triangle.pull", "\(reviews)", reviewsDimmed ? 0.45 : 1)) }
        if segments.isEmpty {
            if let idle = idleImage { return idle }
            segments.append(("bell", nil, 1))
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let height: CGFloat = 18, iconGap: CGFloat = 3, segmentGap: CGFloat = 9

        let pieces = segments.map { segment -> (NSImage, NSAttributedString?, CGFloat) in
            let image = NSImage(systemSymbolName: segment.symbol, accessibilityDescription: nil)!.withSymbolConfiguration(symbolConfig)!
            let text = segment.text.map {
                NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(segment.alpha)])
            }
            return (image, text, segment.alpha)
        }
        let width = pieces.reduce(0) { total, piece in
            total + piece.0.size.width + (piece.1.map { iconGap + $0.size().width } ?? 0)
        } + segmentGap * CGFloat(pieces.count - 1)

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (symbol, text, alpha) in pieces {
                let size = symbol.size
                symbol.draw(in: NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: alpha)
                x += size.width
                if let text {
                    x += iconGap
                    let textSize = text.size()
                    text.draw(at: NSPoint(x: x, y: (height - textSize.height) / 2))
                    x += textSize.width
                }
                x += segmentGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// GitHub's mark from Octicons (MIT, github.com/primer/octicons), shown when nothing needs you.
    private static let githubMarkSVG = #"""
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"/></svg>
    """#

    private static let idleImage: NSImage? = {
        guard let mark = NSImage(data: Data(githubMarkSVG.utf8)), mark.isValid else { return nil }
        let image = NSImage(size: NSSize(width: 16, height: 18), flipped: false) { _ in
            mark.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Beacon, nothing needs you"
        return image
    }()
}
