import Foundation
import SwiftUI

/// The single source of truth the SwiftUI views observe. Owns the refresh
/// timer, drives `UsageClient` + `TokenStore`, and forwards every successful
/// refresh to `NotificationService` for threshold-crossing alerts.
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
        /// No usable token: show the setup sheet entry point.
        case needsSetup(SetupReason)
        case error(String)
    }

    enum SetupReason: Equatable {
        /// First launch (or after `signOut()`): no token has ever been saved.
        case notConfigured
        /// The API returned 401 — the cached token is expired or revoked.
        case tokenRejected
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
    ///
    /// Outcomes:
    /// - No token saved → `.needsSetup(.notConfigured)`. Timer stays running
    ///   so saving a token from the sheet recovers automatically.
    /// - Token rejected by Anthropic (401) → `.needsSetup(.tokenRejected)`.
    /// - Network/header errors → `.error` with a user-visible message.
    /// - Success → `.loaded` plus a notification-threshold check.
    func refresh() async {
        let token: String?
        do {
            token = try TokenStore.load()
        } catch {
            state = .error(String(describing: error))
            return
        }
        guard let token, !token.isEmpty else {
            state = .needsSetup(.notConfigured)
            return
        }

        // Stay on .loaded between ticks instead of flashing back to .loading,
        // otherwise the dropdown blinks every cycle.
        if case .loaded = state {} else if case .needsSetup = state {
            // Keep showing setup CTA until the request resolves.
        } else {
            state = .loading
        }

        do {
            let usage = try await client.fetch(accessToken: token)
            state = .loaded(usage)
            await NotificationService.evaluate(usage: usage)
        } catch UsageClientError.unauthorized {
            state = .needsSetup(.tokenRejected)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// Persists a new token from the setup sheet and immediately verifies it
    /// by triggering a refresh. The view layer awaits this so it can keep the
    /// sheet open until the token is confirmed working.
    ///
    /// Throws `TokenStoreError.invalidFormat` synchronously for obvious paste
    /// mistakes so the sheet can surface a clean inline error without taking
    /// a network round-trip.
    func saveToken(_ token: String) async throws {
        try TokenStore.save(token)
        state = .loading
        await refresh()
    }

    /// Discards the stored token and returns to the setup CTA. Surfaced as
    /// "Sign out" in the menu.
    func signOut() {
        try? TokenStore.delete()
        state = .needsSetup(.notConfigured)
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
