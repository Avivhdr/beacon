import Foundation
import Testing
@testable import Core

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("beacon-migration-\(UUID().uuidString)", isDirectory: true)
}

@Test func copiesLegacyFilesAndDefaultsWhenTheNewOnesAreMissing() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyConfig = root.appendingPathComponent("old/config.json")
    let config = root.appendingPathComponent("new/config.json")
    let legacyState = root.appendingPathComponent("old-state/state.json")
    let state = root.appendingPathComponent("new-state/state.json")
    try FileManager.default.createDirectory(at: legacyConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: legacyState.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"pollIntervalSeconds":15}"#.utf8).write(to: legacyConfig)
    try Data(#"{"items":[]}"#.utf8).write(to: legacyState)

    let legacyName = "beacon.legacy.\(UUID().uuidString)"
    let newName = "beacon.new.\(UUID().uuidString)"
    let legacy = UserDefaults(suiteName: legacyName)!
    let defaults = UserDefaults(suiteName: newName)!
    defer {
        legacy.removePersistentDomain(forName: legacyName)
        defaults.removePersistentDomain(forName: newName)
    }
    legacy.set(["pr-1": "octo-org/frontend#1"], forKey: "hiddenPRs")
    legacy.set(["octo-org/frontend"], forKey: "collapsedRepos")

    Migration.migrateIfNeeded(
        configURL: config,
        legacyConfigURL: legacyConfig,
        stateURL: state,
        legacyStateURL: legacyState,
        defaults: defaults,
        legacyDefaults: legacy
    )

    #expect(try String(contentsOf: config, encoding: .utf8).contains("15"))
    #expect(try String(contentsOf: legacyConfig, encoding: .utf8).contains("15"))
    #expect(try String(contentsOf: state, encoding: .utf8).contains("items"))
    #expect(FileManager.default.fileExists(atPath: legacyState.path))
    let hidden = defaults.dictionary(forKey: "hiddenPRs") as? [String: String]
    #expect(hidden == ["pr-1": "octo-org/frontend#1"])
    #expect(defaults.stringArray(forKey: "collapsedRepos") == ["octo-org/frontend"])
}

@Test func doesNotOverwriteAConfigOrADefaultThatAlreadyExists() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyConfig = root.appendingPathComponent("old/config.json")
    let config = root.appendingPathComponent("new/config.json")
    let legacyState = root.appendingPathComponent("old-state/state.json")
    let state = root.appendingPathComponent("new-state/state.json")
    for url in [legacyConfig, config, legacyState, state] {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try Data("legacy-config".utf8).write(to: legacyConfig)
    try Data("current-config".utf8).write(to: config)
    try Data("legacy-state".utf8).write(to: legacyState)
    try Data("current-state".utf8).write(to: state)

    let legacyName = "beacon.legacy.\(UUID().uuidString)"
    let newName = "beacon.new.\(UUID().uuidString)"
    let legacy = UserDefaults(suiteName: legacyName)!
    let defaults = UserDefaults(suiteName: newName)!
    defer {
        legacy.removePersistentDomain(forName: legacyName)
        defaults.removePersistentDomain(forName: newName)
    }
    legacy.set(["old": "old"], forKey: "hiddenPRs")
    legacy.set(["old/repo"], forKey: "collapsedRepos")
    defaults.set(["kept": "kept"], forKey: "hiddenPRs")

    Migration.migrateIfNeeded(
        configURL: config,
        legacyConfigURL: legacyConfig,
        stateURL: state,
        legacyStateURL: legacyState,
        defaults: defaults,
        legacyDefaults: legacy
    )

    #expect(try String(contentsOf: config, encoding: .utf8) == "current-config")
    #expect(try String(contentsOf: state, encoding: .utf8) == "current-state")
    #expect(try String(contentsOf: legacyConfig, encoding: .utf8) == "legacy-config")
    let hidden = defaults.dictionary(forKey: "hiddenPRs") as? [String: String]
    #expect(hidden == ["kept": "kept"])
    #expect(defaults.stringArray(forKey: "collapsedRepos") == ["old/repo"])
}

@Test func doesNothingWhenThereIsNoLegacyData() {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appendingPathComponent("new/config.json")
    let state = root.appendingPathComponent("new/state.json")
    let newName = "beacon.empty.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: newName)!
    defer { defaults.removePersistentDomain(forName: newName) }

    Migration.migrateIfNeeded(
        configURL: config,
        legacyConfigURL: root.appendingPathComponent("missing-config.json"),
        stateURL: state,
        legacyStateURL: root.appendingPathComponent("missing-state.json"),
        defaults: defaults,
        legacyDefaults: UserDefaults(suiteName: "beacon.empty.legacy.\(UUID().uuidString)")
    )

    #expect(!FileManager.default.fileExists(atPath: config.path))
    #expect(!FileManager.default.fileExists(atPath: state.path))
    #expect(defaults.object(forKey: "hiddenPRs") == nil)
    #expect(defaults.object(forKey: "collapsedRepos") == nil)
}
