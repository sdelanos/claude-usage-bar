import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var launchAtLogin = LaunchAtLoginService()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(service: service, launchAtLogin: launchAtLogin)
                .task { service.start() }
                .onAppear { launchAtLogin.refreshStatus() }
        } label: {
            MenuBarLabel(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: UsageService

    var body: some View {
        HStack(spacing: 4) {
            if let icon = MenuBarIcon.image(size: 18) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .loading:
            Text("…").monospacedDigit()
        case .loaded(let usage):
            Text("\(usage.fiveHour.percent)% · \(usage.sevenDay.percent)%")
                .monospacedDigit()
        case .needsSetup:
            Image(systemName: "gearshape.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
