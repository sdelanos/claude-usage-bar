import AppKit
import Foundation
import OSLog
import ServiceManagement

/// Toggles "open at login" via `SMAppService.mainApp`.
///
/// The framework writes a per-user LaunchAgent that re-launches this exact
/// bundle on login. The registration is tied to the bundle's current path —
/// moving the .app requires toggling off and on again.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    /// Whether the app is currently registered as a login item.
    @Published private(set) var isEnabled: Bool
    /// Last attempt's user-facing message, or `nil` if everything went well.
    @Published var lastError: String?
    /// `true` when macOS requires the user to approve the entry in
    /// System Settings → General → Login Items. Drives a deep-link in the UI.
    @Published var requiresApproval: Bool = false

    private let log = Logger(subsystem: "dev.claude-usage-bar.app", category: "launch-at-login")

    init() {
        self.isEnabled = Self.readCurrentStatus()
    }

    func setEnabled(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
            requiresApproval = false
        } catch {
            log.error("setEnabled(\(wanted)) failed: \(error.localizedDescription, privacy: .public)")
            (lastError, requiresApproval) = Self.translate(error)
        }
        isEnabled = Self.readCurrentStatus()
    }

    /// Re-reads the status from `SMAppService`. Useful when the dropdown
    /// opens, since the user can flip the toggle from System Settings
    /// behind our back.
    func refreshStatus() {
        isEnabled = Self.readCurrentStatus()
        if isEnabled {
            requiresApproval = false
        }
    }

    /// Opens the Login Items pane in System Settings — exposed so the UI
    /// can deep-link the user there when `requiresApproval` is true.
    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Internals

    private static func readCurrentStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Converts an `SMAppService` error into a user-facing message and a
    /// `requiresApproval` flag so the view can show a deep-link button.
    /// `SMAppService` doesn't expose typed errors, so we match by
    /// `SMAppServiceErrorDomain` codes.
    private static func translate(_ error: Error) -> (message: String, requiresApproval: Bool) {
        let nsError = error as NSError
        // SMAppServiceErrorDomain code 1 = "Operation not permitted" /
        // requires approval. We don't want to depend on a non-public error
        // enum, but matching on (domain, code) is stable.
        if nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1 {
            return (
                "Enable Claude Usage Bar in System Settings → General → Login Items.",
                true
            )
        }
        return ("Couldn't update the login-item setting. Try again.", false)
    }
}
