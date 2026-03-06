import Foundation

class ToneManager {
    static let shared = ToneManager()

    // No hardcoded defaults — all apps use the user's base tone.
    // Users can set per-app overrides in Settings.
    private let defaultToneMap: [String: String] = [:]

    private let overridesKey = "toneOverrides"

    private var userOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overridesKey) }
    }

    func tone(forBundleID bundleID: String?) -> String {
        guard let bundleID else { return baseTone }

        // User overrides take precedence
        if let override = userOverrides[bundleID] {
            return override
        }

        // Default mapping
        if let defaultTone = defaultToneMap[bundleID] {
            return defaultTone
        }

        // Everything else uses user's base tone
        return baseTone
    }

    var baseTone: String {
        UserDefaults.standard.string(forKey: "baseTone") ?? "neutral"
    }

    func setOverride(bundleID: String, tone: String) {
        var overrides = userOverrides
        overrides[bundleID] = tone
        userOverrides = overrides
    }

    func removeOverride(bundleID: String) {
        var overrides = userOverrides
        overrides.removeValue(forKey: bundleID)
        userOverrides = overrides
    }

    var allOverrides: [String: String] { userOverrides }

    /// All known apps with their current effective tone
    var effectiveMapping: [String: String] {
        var map = defaultToneMap
        for (key, value) in userOverrides {
            map[key] = value
        }
        return map
    }
}
