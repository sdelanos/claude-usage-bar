import SwiftUI

struct MenuContentView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var launchAtLogin: LaunchAtLoginService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusBody
            Divider()
            controls
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header

    private static let headerIcon = MenuBarIcon.load(size: 16)

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = Self.headerIcon {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                    fraction: usage.fiveHour.utilization
                )
                UsageRow(
                    title: "Weekly limit",
                    resetAt: usage.sevenDay.resetAt,
                    fraction: usage.sevenDay.utilization
                )
                if usage.overage == .rejected {
                    OverageBanner(reason: usage.humanOverageReason)
                }
            }

        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Refresh every")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $service.refreshIntervalSeconds) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                }
                .labelsHidden()
                .frame(width: 110)
            }

            Toggle(isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            )) {
                Text("Launch at login")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            if let err = launchAtLogin.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    Task { await service.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Usage row

private struct UsageRow: View {
    let title: String
    let resetAt: Date
    let fraction: Double

    private var percent: Int {
        Int((max(0, min(1, fraction)) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            CapsuleBar(fraction: fraction, color: .claudeBlue)
        }
    }
}

extension Color {
    /// Claude's brand blue — same hue claude.ai uses for usage bars.
    static let claudeBlue = Color(red: 0.235, green: 0.357, blue: 0.898)
}

// MARK: - Capsule bar

private struct CapsuleBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Overage banner

private struct OverageBanner: View {
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
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }
}
