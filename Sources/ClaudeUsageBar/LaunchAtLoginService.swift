import Foundation
import ServiceManagement

/// Toggles "open at login" via `SMAppService.mainApp`. The framework writes a
/// per-user LaunchAgent that re-launches this exact bundle on login. The
/// registration is tied to the bundle's current path — if the .app is moved,
/// the user needs to toggle off and on again.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var lastError: String?

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
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = Self.readCurrentStatus()
    }

    private static func readCurrentStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
