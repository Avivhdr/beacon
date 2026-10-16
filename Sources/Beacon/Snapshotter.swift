#if DEBUG
import AppKit
import Core
import SwiftUI

/// Writes panel PNGs for the README and the website. Sample names are fictional.
@MainActor
enum Snapshotter {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()

        capture(dir, "unread.png", tab: .notifications, model: populated(now: now))
        capture(dir, "to-review.png", tab: .reviews, model: populated(now: now))
        capture(dir, "mine.png", tab: .mine, model: populated(now: now))
        capture(dir, "unread-empty.png", tab: .notifications, model: quiet(now: now))
        capture(dir, "unread-all-clear.png", tab: .notifications, model: allRead(now: now))
        capture(dir, "to-review-empty.png", tab: .reviews, model: quiet(now: now))
        capture(dir, "to-review-queue-empty.png", tab: .reviews, model: emptyQueues(now: now))
        capture(dir, "mine-empty.png", tab: .mine, model: quiet(now: now))
        print("wrote snapshots to \(dir.path)")
    }

    /// The two sign-in panels. Screen Recording is not required: this draws off screen.
    static func captureSignIn(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missing = AppModel()
        missing.previewMissingGitHubCLI()
        capture(dir, "signin-missing.png", tab: .notifications, model: missing)
        let rejected = AppModel()
        rejected.previewSignInError("GitHub 401 on /user: Bad credentials")
        capture(dir, "signin-rejected.png", tab: .notifications, model: rejected)
    }

    private static func capture(_ dir: URL, _ name: String, tab: PanelView.Tab, model: AppModel) {
        let size = PanelView.size
        let host = NSHostingView(rootView: PanelView(model: model, updater: Updater(), openFilters: {}, initialTab: tab))
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(1.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let png = image(of: host, window: window, size: size)
        let url = dir.appendingPathComponent(name)
        try? png?.write(to: url)
        window.orderOut(nil)
        print(png == nil ? "failed \(name)" : "wrote \(name)")
    }

    private static func image(of view: NSView, window: NSWindow, size: CGSize) -> Data? {
        let scale: CGFloat = 2
        let pixels = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        if !hasInk(rep), let cg = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// cacheDisplay sometimes returns a clear bitmap for a SwiftUI host. A real panel is ink, not clear.
    private static func hasInk(_ rep: NSBitmapImageRep) -> Bool {
        guard let cg = rep.cgImage else { return false }
        let width = cg.width
        let height = cg.height
        guard width > 8, height > 8 else { return false }
        guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let row = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        guard bpp >= 4 else { return false }
        let samples = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.15), CGPoint(x: 0.8, y: 0.8)]
        for point in samples {
            let x = min(width - 1, Int(CGFloat(width) * point.x))
            let y = min(height - 1, Int(CGFloat(height) * point.y))
            let p = bytes + y * row + x * bpp
            if p[3] > 20 { return true }
        }
        return false
    }

    private static func quiet(now: Date) -> AppModel {
        let model = AppModel()
        model.loadPreview(items: [], categories: [], mine: [], lastUpdated: now.addingTimeInterval(-40))
        return model
    }

    private static func allRead(now: Date) -> AppModel {
        let model = AppModel()
        model.loadPreview(
            items: [item("read-1", .comment, actor: "mona", repo: "frontend", number: 12, title: "Rename the status lamp", snippet: "Landed. Thanks.", at: now.addingTimeInterval(-86_400), read: true)],
            categories: [],
            mine: [],
            lastUpdated: now.addingTimeInterval(-40)
        )
        return model
    }

    private static func emptyQueues(now: Date) -> AppModel {
        let model = AppModel()
        model.loadPreview(
            items: [],
            categories: [
                CategoryResult(name: "Direct", count: 0, prs: []),
                CategoryResult(name: "Team", count: 0, prs: []),
            ],
            mine: [],
            lastUpdated: now.addingTimeInterval(-40)
        )
        return model
    }

    private static func populated(now: Date) -> AppModel {
        let model = AppModel()
        let items = [
            item("m1", .mention, actor: "mona", repo: "frontend", number: 128, title: "Tighten the radar beam on the empty state", snippet: "The trail fades too fast at 16pt. Can you keep one more ring?", at: now.addingTimeInterval(-1_800)),
            item("m2", .reply, actor: "hubot", repo: "docs", number: 44, title: "Document the three tabs", snippet: "Replied in the thread about the Mine layers.", at: now.addingTimeInterval(-7_200)),
            item("m3", .changesRequested, actor: "octocat", owner: "octocat", repo: "hello-world", number: 7, title: "Add a copy button for the brew command", snippet: "Please match the hairline weight on the pill.", at: now.addingTimeInterval(-26 * 3_600)),
            item("m4", .approvedWithComment, actor: "mona", repo: "frontend", number: 121, title: "Roll the counters up on open", snippet: "Approved. The ease looks right.", at: now.addingTimeInterval(-50 * 3_600), read: true),
        ]
        let direct = [
            pr("d1", repo: "octo-org/frontend", number: 210, title: "Draw the amber beam with a fading trail", author: "mona", ci: "SUCCESS", at: now.addingTimeInterval(-2 * 3_600)),
            pr("d2", repo: "octo-org/frontend", number: 198, title: "Fold long repo lists in the Mine tab", author: "hubot", ci: "FAILURE", at: now.addingTimeInterval(-3 * 86_400)),
            pr("d3", repo: "octo-org/docs", number: 60, title: "Release notes draft", author: "octocat", ci: nil, at: now.addingTimeInterval(-5 * 3_600), skip: true),
        ]
        let team = [
            pr("t1", repo: "octo-org/docs", number: 51, title: "Document the config file", author: "octocat", ci: "PENDING", at: now.addingTimeInterval(-5 * 3_600)),
        ]
        let mineWork = [
            pr("w1", repo: "octo-org/frontend", number: 214, title: "Keep the panel open when the app resigns", author: "octocat", ci: "SUCCESS", at: now.addingTimeInterval(-4 * 3_600), decision: "APPROVED"),
            pr("w2", repo: "octo-org/frontend", number: 209, title: "Ask for notification permission under the new id", author: "octocat", ci: "FAILURE", at: now.addingTimeInterval(-30 * 3_600), decision: "CHANGES_REQUESTED"),
            pr("w3", repo: "octo-org/docs", number: 48, title: "Write the privacy section", author: "octocat", ci: "SUCCESS", at: now.addingTimeInterval(-8 * 3_600), draft: true),
        ]
        let minePersonal = [
            pr("p1", repo: "octocat/hello-world", number: 3, title: "Try the snapshot tool on a clean tree", author: "octocat", ci: "EXPECTED", at: now.addingTimeInterval(-90 * 60), decision: "REVIEW_REQUIRED"),
        ]
        model.loadPreview(
            items: items,
            categories: [
                CategoryResult(name: "Direct", count: 2, prs: direct),
                CategoryResult(name: "Team", count: 1, prs: team),
                CategoryResult(name: "Teammates", count: 0, prs: [], note: "Add teammates in the config when you want this category."),
            ],
            mine: [
                CategoryResult(name: "Work", count: 3, prs: mineWork),
                CategoryResult(name: "Personal", count: 1, prs: minePersonal),
            ],
            lastUpdated: now.addingTimeInterval(-40)
        )
        return model
    }

    private static func item(
        _ id: String,
        _ kind: FeedKind,
        actor: String,
        owner: String = "octo-org",
        repo: String,
        number: Int,
        title: String,
        snippet: String,
        at: Date,
        read: Bool = false
    ) -> FeedItem {
        FeedItem(
            id: id,
            kind: kind,
            actor: actor,
            pr: PRRef(owner: owner, name: repo, number: number),
            prTitle: title,
            prState: "OPEN",
            onMyPR: true,
            snippet: snippet,
            url: "https://github.com/\(owner)/\(repo)/pull/\(number)",
            createdAt: at,
            read: read
        )
    }

    private static func pr(
        _ id: String,
        repo: String,
        number: Int,
        title: String,
        author: String,
        ci: String?,
        at: Date,
        skip: Bool = false,
        draft: Bool = false,
        decision: String? = nil
    ) -> ReviewPR {
        ReviewPR(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: "https://github.com/\(repo)/pull/\(number)",
            author: author,
            createdAt: at,
            ciState: ci,
            skipLabels: skip ? [PRLabel(name: "DO NOT REVIEW", color: "F4A93B")] : [],
            isDraft: draft,
            reviewDecision: decision
        )
    }
}
#endif
