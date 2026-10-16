import Foundation

/// Where Beacon keeps its files, and where the app kept them before the rename.
public enum Paths {
    public static let legacyDefaultsSuite = "com.avivhadar.github-notifications"

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/beacon/config.json")
    }

    public static var legacyConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/github-notifications/config.json")
    }

    public static var stateURL: URL {
        applicationSupport.appendingPathComponent("Beacon/state.json")
    }

    public static var legacyStateURL: URL {
        applicationSupport.appendingPathComponent("GitHubNotifications/state.json")
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// One-time copy from the pre-rename locations. The old files stay, so a rollback still has them.
public enum Migration {
    /// Copies config, state, and the two remembered lists when the new copies are missing.
    public static func migrateIfNeeded(
        fileManager: FileManager = .default,
        configURL: URL = Paths.configURL,
        legacyConfigURL: URL = Paths.legacyConfigURL,
        stateURL: URL = Paths.stateURL,
        legacyStateURL: URL = Paths.legacyStateURL,
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: Paths.legacyDefaultsSuite)
    ) {
        copyIfMissing(from: legacyConfigURL, to: configURL, fileManager: fileManager)
        copyIfMissing(from: legacyStateURL, to: stateURL, fileManager: fileManager)
        if let legacyDefaults {
            copyDefaults(from: legacyDefaults, to: defaults)
        }
    }

    static func copyIfMissing(from source: URL, to destination: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.copyItem(at: source, to: destination)
    }

    /// `hiddenPRs` and `collapsedRepos` lived in the old bundle's defaults. Copy a key only when the new domain has none.
    private static let defaultsKeys = ["hiddenPRs", "collapsedRepos"]

    static func copyDefaults(from legacy: UserDefaults, to defaults: UserDefaults) {
        for key in defaultsKeys {
            guard defaults.object(forKey: key) == nil else { continue }
            guard let value = legacy.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
    }
}
