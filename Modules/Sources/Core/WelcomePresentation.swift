import Foundation

/// Automatic welcome is first-run onboarding, not a per-version announcement.
/// Reuse the existing record so established installations are already onboarded.
public enum WelcomePresentation {
    public static func shouldShow(defaults: UserDefaults) -> Bool {
        guard let shownVersion = defaults.string(forKey: "welcomeScreenShownInVersion") else { return true }
        return shownVersion.isEmpty || shownVersion == "0.0"
    }
}
