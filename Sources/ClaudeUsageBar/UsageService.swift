import Foundation
import SwiftUI

@MainActor
final class UsageService: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Usage)
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published var refreshIntervalSeconds: TimeInterval {
        didSet {
            guard refreshIntervalSeconds != oldValue else { return }
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Self.intervalKey)
            restartTimer()
        }
    }

    static let intervalKey = "refreshIntervalSeconds"
    static let minimumInterval: TimeInterval = 60
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

    func refresh() async {
        // Don't flip back to .loading once we have data — keeps the UI from blinking on every tick.
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
