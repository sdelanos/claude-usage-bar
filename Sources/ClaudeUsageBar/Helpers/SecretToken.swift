import Foundation

/// Wraps an OAuth bearer string in a type that refuses to print itself.
///
/// Plain `String` tokens are easy to leak: `"\(token)"`, `String(describing:)`,
/// SwiftUI's `debugDescription`, `os_log` with default privacy, an
/// over-eager `print` in a draft refactor — any of them ship the bearer to
/// Console.app or a crash report. `SecretToken` forces the call site to call
/// `reveal()` explicitly, which makes accidental leaks grep-able and review-
/// catchable.
///
/// The wrapper is intentionally tiny: no zeroization, no `mlock`. Swift makes
/// heap zeroing of `String` storage impossible from user code; treating the
/// type as un-loggable is the realistic guarantee.
struct SecretToken: Equatable, Hashable {
    private let value: String

    init(_ value: String) {
        self.value = value
    }

    /// Returns the raw bearer for use as a `Bearer ` header. Call sites that
    /// invoke `reveal()` are the audit surface — grep for them.
    func reveal() -> String {
        value
    }

    /// `true` if the wrapped string is empty. Useful for guards without
    /// calling `reveal()`.
    var isEmpty: Bool {
        value.isEmpty
    }
}

extension SecretToken: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        "sk-ant-***"
    }

    var debugDescription: String {
        "sk-ant-***"
    }
}
