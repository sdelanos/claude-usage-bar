import Foundation
import OSLog
import SwiftUI

/// The single source of truth the SwiftUI views observe.
///
/// Owns the refresh loop, drives `TokenStoring` + `UsageFetching` +
/// `NotificationService` on each tick, and publishes a `State` enum the views
/// observe (including `.needsSetup` for first-launch and 401 recovery).
///
/// Pinned to `@MainActor` because it publishes to SwiftUI. Network and
/// keychain work happens off the main thread; only the state mutation
/// happens here.
@MainActor
final class UsageService: ObservableObject {

    /// What the UI shows. Equatable so SwiftUI can diff it cheaply.
    enum State: Equatable {
        case loading
        case loaded(Usage)
        /// No usable token: show the setup sheet entry point.
        case needsSetup(SetupReason)
        case error(UserFacingError)
    }

    enum SetupReason: Equatable, Sendable {
        /// First launch (or after `signOut()`): no token has ever been saved.
        case notConfigured
        /// The API returned 401 — the cached token is expired or revoked.
        case tokenRejected
    }

    @Published private(set) var state: State = .loading

    /// How often `refresh()` is invoked by the timer.
    ///
    /// `0` disables polling (manual-only mode). Otherwise the value is
    /// clamped to `minimumInterval` on use.
    @Published var refreshIntervalSeconds: TimeInterval {
        didSet {
            guard refreshIntervalSeconds != oldValue else { return }
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Self.intervalKey)
            schedulePollLoop()
        }
    }

    /// UserDefaults key for the persisted refresh interval.
    static let intervalKey = "refreshIntervalSeconds"
    /// Lower bound on the refresh interval — anything tighter than this
    /// costs noticeable quota for no perceptible benefit. Values strictly
    /// between 0 and this floor get rounded up.
    static let minimumInterval: TimeInterval = 60
    /// Sentinel: poll loop is disabled, refresh only on user demand.
    static let manualOnly: TimeInterval = 0
    /// What new users get on first launch.
    static let defaultInterval: TimeInterval = 300

    private let tokenStore: TokenStoring
    private let usageFetcher: UsageFetching
    private let bootstrapNotifications: @MainActor () async -> Void
    private let evaluateNotifications: @MainActor (Usage) async -> Void
    private let log = Logger(subsystem: "dev.claude-usage-bar.app", category: "usage-service")

    private var pollTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?

    /// Designated init with full dependency injection. Production uses the
    /// convenience `init()` that wires the real keychain + URLSession.
    init(
        tokenStore: TokenStoring,
        usageFetcher: UsageFetching,
        bootstrapNotifications: @escaping @MainActor () async -> Void,
        evaluateNotifications: @escaping @MainActor (Usage) async -> Void
    ) {
        self.tokenStore = tokenStore
        self.usageFetcher = usageFetcher
        self.bootstrapNotifications = bootstrapNotifications
        self.evaluateNotifications = evaluateNotifications

        // We have to distinguish "key never set" (→ default) from "user
        // picked manual-only / 0" (→ keep as 0). Reading via `double` gives
        // `0` for both; `object(forKey:) as? Double` is `nil` for unset.
        let saved = UserDefaults.standard.object(forKey: Self.intervalKey) as? Double
        self.refreshIntervalSeconds = Self.normalizedInterval(fromStoredValue: saved)
    }

    /// Production wiring. Tests should use the designated init.
    convenience init() {
        self.init(
            tokenStore: KeychainTokenStore(),
            usageFetcher: UsageClient(),
            bootstrapNotifications: NotificationService.bootstrap,
            evaluateNotifications: NotificationService.evaluate(usage:)
        )
    }

    /// Called once from the `App` scene's `.task` modifier. Bootstraps
    /// notification permission, fires a first refresh, and starts the poll
    /// loop. Idempotent — calling twice is harmless (cancels the first
    /// bootstrap task).
    func start() {
        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrapNotifications()
            await self.refresh()
            self.schedulePollLoop()
        }
    }

    /// Pulls a fresh usage snapshot from the API and updates `state`.
    ///
    /// Outcomes:
    /// - No token saved → `.needsSetup(.notConfigured)`.
    /// - Token rejected by Anthropic (401) → `.needsSetup(.tokenRejected)`.
    /// - Network / header errors → `.error(UserFacingError)`.
    /// - Success → `.loaded` plus a notification-threshold check.
    func refresh() async {
        let rawToken: String
        do {
            guard let stored = try tokenStore.load(), !stored.isEmpty else {
                state = .needsSetup(.notConfigured)
                return
            }
            rawToken = stored
        } catch {
            state = .error(UserFacingError.translate(error))
            return
        }
        let token = SecretToken(rawToken)

        // Cosmetic: stay on the current displayable state between cycles so
        // the dropdown doesn't blink on every tick. Only flash `.loading`
        // when transitioning from a non-displayable state.
        switch state {
        case .loaded, .needsSetup:
            break
        case .loading, .error:
            state = .loading
        }

        do {
            let usage = try await usageFetcher.fetch(accessToken: token)
            state = .loaded(usage)
            await evaluateNotifications(usage)
        } catch UsageClientError.unauthorized {
            log.notice("API returned 401; transitioning to .needsSetup(.tokenRejected)")
            state = .needsSetup(.tokenRejected)
        } catch is CancellationError {
            // Loop was cancelled mid-flight; don't clobber the state.
            log.debug("refresh cancelled mid-flight")
        } catch {
            log.error("refresh failed: \(String(describing: error), privacy: .public)")
            state = .error(UserFacingError.translate(error))
        }
    }

    /// Persists a new token from the setup sheet and verifies it by
    /// triggering a refresh. The view awaits this so it can keep the sheet
    /// open until the token is confirmed working.
    func saveToken(_ rawToken: String) async throws {
        try tokenStore.save(rawToken)
        state = .loading
        await refresh()
    }

    /// Discards the stored token and returns to the setup CTA. Cancels the
    /// poll loop so we don't hammer the keychain with reads that all return
    /// nil. Surfaced as "Sign out" in the menu.
    func signOut() {
        do {
            try tokenStore.delete()
        } catch {
            log.error("signOut delete failed: \(String(describing: error), privacy: .public)")
        }
        pollTask?.cancel()
        pollTask = nil
        state = .needsSetup(.notConfigured)
    }

    // MARK: - Polling

    /// Cancels any in-flight poll loop and starts a new one matching the
    /// current `refreshIntervalSeconds`. Manual-only mode (interval == 0)
    /// leaves the loop cancelled.
    private func schedulePollLoop() {
        pollTask?.cancel()
        pollTask = nil

        let interval = Self.normalizedInterval(fromStoredValue: refreshIntervalSeconds)
        guard interval >= Self.minimumInterval else { return }  // 0 = manual only

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    /// Normalizes a (possibly-absent) stored interval.
    ///
    /// - `nil` (key never set) → `defaultInterval`.
    /// - `0` (user picked manual-only) → preserved as-is.
    /// - Otherwise: clamped to at least `minimumInterval`.
    /// - Non-finite or negative values are treated as junk → `defaultInterval`.
    static func normalizedInterval(fromStoredValue value: Double?) -> TimeInterval {
        guard let value else { return defaultInterval }
        if value == manualOnly { return manualOnly }
        guard value.isFinite, value > 0 else { return defaultInterval }
        return max(minimumInterval, value)
    }
}
