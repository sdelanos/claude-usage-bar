import Foundation
import SwiftUI

/// The single source of truth the SwiftUI views observe. Owns the refresh
/// timer, drives `UsageClient` + `KeychainReader`, and forwards every
/// successful refresh to `NotificationService` for threshold-crossing alerts.
///
/// Pinned to `@MainActor` because it publishes to SwiftUI and manipulates a
/// `Timer` scheduled on the main `RunLoop`. The actual network call is `async`
/// and runs off the main thread; only the state mutation happens here.
@MainActor
final class UsageService: ObservableObject {

    /// What the UI shows. Equatable so SwiftUI can diff it cheaply.
    enum State: Equatable {
        case loading
        case loaded(Usage)
        case error(String)
    }

    @Published private(set) var state: State = .loading

    /// How often `refresh()` is invoked by the timer. The setter persists the
    /// new value and reschedules the timer so a user picking "1 min" doesn't
    /// have to wait a full default cycle to see the change take effect.
    @Published var refreshIntervalSeconds: TimeInterval {
        didSet {
            guard refreshIntervalSeconds != oldValue else { return }
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Self.intervalKey)
            restartTimer()
        }
    }

    /// UserDefaults key for the persisted refresh interval.
    static let intervalKey = "refreshIntervalSeconds"
    /// Lower bound on the refresh interval — anything tighter than this costs
    /// noticeable quota for no perceptible benefit.
    static let minimumInterval: TimeInterval = 60
    /// What new users get on first launch.
    static let defaultInterval: TimeInterval = 300

    private let client = UsageClient()
    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.intervalKey)
        self.refreshIntervalSeconds = saved >= Self.minimumInterval ? saved : Self.defaultInterval
        restartTimer()
        Task {
            await NotificationService.bootstrap()
            await self.refresh()
        }
    }

    /// Pulls a fresh usage snapshot from the API and updates `state`. Called
    /// both manually (from the dropdown's Refresh button) and periodically by
    /// the timer.
    func refresh() async {
        // Stay on .loaded between ticks instead of flashing back to .loading,
        // otherwise the dropdown blinks every cycle.
        if case .loaded = state {} else {
            state = .loading
        }
        do {
            let token = try KeychainReader.readAccessToken()
            let usage = try await client.fetch(accessToken: token)
            state = .loaded(usage)
            await NotificationService.evaluate(usage: usage)
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(Self.minimumInterval, refreshIntervalSeconds)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
