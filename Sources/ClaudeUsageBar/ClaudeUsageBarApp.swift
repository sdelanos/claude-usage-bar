import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var launchAtLogin = LaunchAtLoginService()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(service: service, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: UsageService

    private static let icon = MenuBarIcon.load(size: 18)

    var body: some View {
        HStack(spacing: 4) {
            if let icon = Self.icon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
            Text(text)
                .monospacedDigit()
        }
    }

    private var text: String {
        switch service.state {
        case .loading:
            return "…"
        case .loaded(let usage):
            let fiveHour = Int((usage.fiveHour.utilization * 100).rounded())
            let sevenDay = Int((usage.sevenDay.utilization * 100).rounded())
            return "\(fiveHour)% · \(sevenDay)%"
        case .needsSetup:
            return "Setup"
        case .error:
            return "!"
        }
    }
}
