import Foundation

enum DictationLocale: String, CaseIterable, Codable, Identifiable {
    case deDE = "de-DE"
    case enUS = "en-US"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .deDE:
            return "Deutsch (de-DE)"
        case .enUS:
            return "English (en-US)"
        }
    }
}

enum STTRoutingMode: String, CaseIterable, Codable, Identifiable {
    case auto
    case local
    case cloud

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .local:
            return "Lokal"
        case .cloud:
            return "Cloud"
        }
    }

    var ffiPreferenceMode: UInt8 {
        switch self {
        case .local:
            return 0
        case .cloud:
            return 1
        case .auto:
            return 2
        }
    }
}

struct AppSettingsSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let defaults = AppSettingsSnapshot(
        schemaVersion: currentSchemaVersion,
        locale: .deDE,
        routingMode: .auto,
        sensitiveModeEnabled: false
    )

    var schemaVersion: Int
    var locale: DictationLocale
    var routingMode: STTRoutingMode
    var sensitiveModeEnabled: Bool

    func normalized() -> AppSettingsSnapshot {
        var normalized = self
        normalized.schemaVersion = Self.currentSchemaVersion
        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case locale
        case routingMode
        case sensitiveModeEnabled
    }

    init(
        schemaVersion: Int,
        locale: DictationLocale,
        routingMode: STTRoutingMode,
        sensitiveModeEnabled: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.locale = locale
        self.routingMode = routingMode
        self.sensitiveModeEnabled = sensitiveModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion

        let localeRaw = try container.decodeIfPresent(String.self, forKey: .locale) ?? DictationLocale.deDE.rawValue
        locale = DictationLocale(rawValue: localeRaw) ?? .deDE

        let routingModeRaw = try container.decodeIfPresent(String.self, forKey: .routingMode) ?? STTRoutingMode.auto.rawValue
        routingMode = STTRoutingMode(rawValue: routingModeRaw) ?? .auto

        sensitiveModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .sensitiveModeEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(locale.rawValue, forKey: .locale)
        try container.encode(routingMode.rawValue, forKey: .routingMode)
        try container.encode(sensitiveModeEnabled, forKey: .sensitiveModeEnabled)
    }
}

struct AppSettingsLoadResult {
    let snapshot: AppSettingsSnapshot
    let warningMessage: String?
}

protocol AppSettingsPersisting {
    var settingsFileURL: URL { get }
    func load() throws -> AppSettingsLoadResult
    func save(_ snapshot: AppSettingsSnapshot) throws
}

struct FileAppSettingsStore: AppSettingsPersisting {
    private let fileManager: FileManager
    let settingsFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        settingsFileURL = appSupportURL
            .appendingPathComponent("Syntic", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    func load() throws -> AppSettingsLoadResult {
        try ensureParentDirectory()

        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            try save(AppSettingsSnapshot.defaults)
            return AppSettingsLoadResult(snapshot: AppSettingsSnapshot.defaults, warningMessage: nil)
        }

        let data = try Data(contentsOf: settingsFileURL)
        let decoder = JSONDecoder()

        do {
            let decoded = try decoder.decode(AppSettingsSnapshot.self, from: data).normalized()
            try save(decoded)
            return AppSettingsLoadResult(snapshot: decoded, warningMessage: nil)
        } catch is DecodingError {
            let recovered = try recoverFromCorruptSettings()
            return AppSettingsLoadResult(snapshot: AppSettingsSnapshot.defaults, warningMessage: recovered)
        }
    }

    func save(_ snapshot: AppSettingsSnapshot) throws {
        try ensureParentDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot.normalized())
        try data.write(to: settingsFileURL, options: .atomic)
    }

    private func ensureParentDirectory() throws {
        let directoryURL = settingsFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func recoverFromCorruptSettings() throws -> String {
        let timestamp = Self.corruptTimestampFormatter.string(from: Date())
        let backupURL = settingsFileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")

        try? fileManager.removeItem(at: backupURL)
        try fileManager.moveItem(at: settingsFileURL, to: backupURL)
        try save(AppSettingsSnapshot.defaults)
        return "Ungültige Settings-Datei erkannt. Backup erstellt: \(backupURL.path)"
    }

    private static let corruptTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

@MainActor
final class AppSettingsController: ObservableObject {
    @Published var locale: DictationLocale {
        didSet { schedulePersistIfReady() }
    }

    @Published var routingMode: STTRoutingMode {
        didSet { schedulePersistIfReady() }
    }

    @Published var sensitiveModeEnabled: Bool {
        didSet { schedulePersistIfReady() }
    }

    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var lastLoadWarning: String?
    @Published private(set) var lastPersistError: String?

    let settingsFilePath: String

    private let store: AppSettingsPersisting
    private var isApplyingSnapshot = false
    private var pendingPersistTask: Task<Void, Never>?

    init(store: AppSettingsPersisting = FileAppSettingsStore()) {
        self.store = store
        settingsFilePath = store.settingsFileURL.path

        let defaults = AppSettingsSnapshot.defaults
        locale = defaults.locale
        routingMode = defaults.routingMode
        sensitiveModeEnabled = defaults.sensitiveModeEnabled

        reloadFromDisk()
    }

    deinit {
        pendingPersistTask?.cancel()
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            schemaVersion: AppSettingsSnapshot.currentSchemaVersion,
            locale: locale,
            routingMode: routingMode,
            sensitiveModeEnabled: sensitiveModeEnabled
        )
    }

    var persistenceSummary: String {
        if let lastPersistError {
            return "save-error: \(lastPersistError)"
        }
        if let warning = lastLoadWarning {
            return "warning: \(warning)"
        }
        if let lastSavedAt {
            return "saved: \(Self.savedAtFormatter.string(from: lastSavedAt))"
        }
        return "not-saved-yet"
    }

    func reloadFromDisk() {
        pendingPersistTask?.cancel()

        do {
            let result = try store.load()
            apply(snapshot: result.snapshot)
            lastLoadWarning = result.warningMessage
            lastPersistError = nil
            lastSavedAt = Date()
        } catch {
            lastPersistError = "Load failed: \(error.localizedDescription)"
        }
    }

    func resetToDefaults() {
        apply(snapshot: AppSettingsSnapshot.defaults)
        persistNow()
    }

    private func apply(snapshot: AppSettingsSnapshot) {
        isApplyingSnapshot = true
        locale = snapshot.locale
        routingMode = snapshot.routingMode
        sensitiveModeEnabled = snapshot.sensitiveModeEnabled
        isApplyingSnapshot = false
    }

    private func schedulePersistIfReady() {
        guard !isApplyingSnapshot else {
            return
        }

        pendingPersistTask?.cancel()
        pendingPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.persistNow()
        }
    }

    private func persistNow() {
        do {
            try store.save(snapshot)
            lastPersistError = nil
            lastSavedAt = Date()
        } catch {
            lastPersistError = "Save failed: \(error.localizedDescription)"
        }
    }

    private static let savedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
