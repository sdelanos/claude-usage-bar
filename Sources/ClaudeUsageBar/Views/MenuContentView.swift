import SwiftUI

/// Refresh-cadence options exposed in the dropdown picker. Centralized as a
/// data-driven enum so the picker stays declarative and adding / removing
/// a value is a one-line change.
enum RefreshInterval: TimeInterval, CaseIterable, Identifiable {
    case manual = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: TimeInterval {
        rawValue
    }

    var label: String {
        switch self {
        case .manual: "Manual only"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var launchAtLogin: LaunchAtLoginService

    private static let dropdownWidth: CGFloat = 320
    private static let outerSpacing: CGFloat = 14
    private static let outerPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Self.outerSpacing) {
            header
            statusBody
            Divider()
            controls
        }
        .padding(Self.outerPadding)
        .frame(
            minWidth: Self.dropdownWidth,
            idealWidth: Self.dropdownWidth,
            maxWidth: Self.dropdownWidth * 1.2
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = MenuBarIcon.image(size: 16) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3)
            }
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if case .loaded(let usage) = service.state {
                Text(usage.fetchedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if !isSetupActive {
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Refresh now")
            }
        }
    }

    // MARK: - State body

    @ViewBuilder
    private var statusBody: some View {
        switch service.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Fetching usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .loaded(let usage):
            VStack(alignment: .leading, spacing: 18) {
                UsageRow(
                    title: "Current session",
                    resetAt: usage.fiveHour.resetAt,
                    percent: usage.fiveHour.percent,
                    fraction: usage.fiveHour.utilization
                )
                UsageRow(
                    title: "Weekly limit",
                    resetAt: usage.sevenDay.resetAt,
                    percent: usage.sevenDay.percent,
                    fraction: usage.sevenDay.utilization
                )
                if usage.overage == .rejected {
                    OverageBanner(reason: usage.humanOverageReason)
                }
            }

        case .needsSetup(let reason):
            SetupView(service: service, reason: reason)

        case .error(let userFacing):
            ErrorRow(error: userFacing) {
                Task { await service.refresh() }
            }
        }
    }

    private var isSetupActive: Bool {
        if case .needsSetup = service.state { return true }
        return false
    }

    private var isAuthenticated: Bool {
        switch service.state {
        case .loaded, .error: true
        case .loading: service.state == .loading
        case .needsSetup: false
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            refreshIntervalRow
            launchAtLoginRow
            footer
        }
    }

    private var refreshIntervalRow: some View {
        HStack {
            Text("Refresh every")
                .font(.subheadline)
            Spacer()
            Picker("", selection: $service.refreshIntervalSeconds) {
                ForEach(RefreshInterval.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )) {
                Text("Launch at login")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if launchAtLogin.requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(launchAtLogin.lastError ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if let err = launchAtLogin.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            if isAuthenticated, !isSetupActive {
                Button("Sign out") {
                    service.signOut()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Forget the saved token and return to setup")
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.top, 2)
    }
}

// MARK: - Usage row

private struct UsageRow: View, Equatable {
    let title: String
    let resetAt: Date
    let percent: Int
    let fraction: Double

    private static let rowSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text("Resets \(ResetFormatter.format(resetAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(percent) %")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.claudeBlue)
            }
            CapsuleBar(fraction: fraction)
        }
    }
}

// MARK: - Capsule bar

private struct CapsuleBar: View, Equatable {
    let fraction: Double

    private static let barHeight: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.claudeTrack)
                Capsule()
                    .fill(Color.claudeBlue)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: Self.barHeight)
    }
}

// MARK: - Overage banner

private struct OverageBanner: View, Equatable {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Overage not allowed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.claudeWarnBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.claudeWarnBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Error row

private struct ErrorRow: View {
    let error: UserFacingError
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 8) {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if error.isRetryable {
                    Button("Retry") { onRetry() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
