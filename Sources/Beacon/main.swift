import AppKit
import Core

// Before any read: copy the pre-rename config, state, and remembered lists.
Migration.migrateIfNeeded()

#if DEBUG
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot-signin"), CommandLine.arguments.count > flag + 1 {
    let directory = CommandLine.arguments[flag + 1]
    MainActor.assumeIsolated {
        Snapshotter.captureSignIn(directory: directory)
    }
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let directory = CommandLine.arguments[flag + 1]
    MainActor.assumeIsolated {
        Snapshotter.run(directory: directory)
    }
    exit(0)
}
#endif

// `--dump` runs one refresh against a throwaway state and prints the result, for checking the rules.
if CommandLine.arguments.contains("--dump") {
    let engine = FeedEngine(state: FeedState(), persist: false)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let snapshot = try await engine.refresh()
            for item in engine.state.items {
                print("\(item.read ? " " : "•") \(item.createdAt.formatted(date: .abbreviated, time: .shortened))  \(item.actor) \(item.verb) \(item.pr.key)  \(item.prTitle)")
                if !item.snippet.isEmpty { print("    \(item.snippet.prefix(120))") }
            }
            for category in snapshot.categories {
                print("\(category.name): \(category.count)\(category.note.map { " (\($0))" } ?? "")")
                for pr in category.prs where pr.isSkipped {
                    print("    not counted: \(pr.repo)#\(pr.number) [\(pr.skipLabels.map(\.name).joined(separator: ", "))]  \(pr.title)")
                }
            }
            for group in snapshot.mine {
                print("mine/\(group.name): \(group.count)")
                for pr in group.prs {
                    print("    \(pr.repo)#\(pr.number) [\(pr.isDraft ? "draft " : "")\(pr.reviewDecision ?? "-") ci:\(pr.ciState ?? "-")]  \(pr.title)")
                }
            }
            print("merged: \(snapshot.merged.count)")
            for pr in snapshot.merged {
                let when = pr.mergedAt?.formatted(date: .abbreviated, time: .shortened) ?? "-"
                print("    \(when)  \(pr.repo)#\(pr.number)  \(pr.title)")
            }
            snapshot.errors.forEach { print("error: \($0)") }
        } catch {
            print("error: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
