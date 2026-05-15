import AppKit
import SwiftUI

/// Inline setup card shown in the dropdown when the user has no usable token.
///
/// Walks them through `claude setup-token`, lets them paste the result, and
/// hands the token to `UsageService.saveToken` for verification.
///
/// Lives in the dropdown rather than a separate sheet because sheets
/// attached to a `MenuBarExtra` window misbehave (focus loss closes the
/// popover).
struct SetupView: View {
    @ObservedObject var service: UsageService
    let reason: UsageService.SetupReason

    @State private var tokenInput: String = ""
    @State private var inlineError: String?
    @State private var isSaving: Bool = false
    @State private var didCopyCommand: Bool = false

    private static let command = "claude setup-token"
    private static let copyFeedbackDelay: Duration = .milliseconds(1500)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline

            Step(number: 1) {
                Text("Run this in Terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(Self.command)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button(action: copyCommand) {
                        Image(systemName: didCopyCommand ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                }
            }

            Step(number: 2) {
                Text("Approve in your browser when prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Step(number: 3) {
                Text("Paste the printed token:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-…", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSaving)
                    .onSubmit(saveIfReady)
            }

            if let inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text("Verifying…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: saveIfReady) {
                    Text(isSaving ? "Saving…" : "Save")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!TokenFormat.looksValid(tokenInput) || isSaving)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .onDisappear {
            // Drop any in-flight pasted token from the view's @State when
            // the user dismisses the dropdown.
            tokenInput = ""
            inlineError = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headline: some View {
        switch reason {
        case .notConfigured:
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up authentication")
                    .font(.subheadline.weight(.semibold))
                Text(
                    "Claude Usage Bar uses a long-lived token from your Claude subscription. One-time setup, no keychain prompts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        case .tokenRejected:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Token expired or revoked")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Anthropic rejected the saved token. Re-run setup-token to mint a new one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func copyCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Self.command, forType: .string)
        didCopyCommand = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.copyFeedbackDelay)
            didCopyCommand = false
        }
    }

    private func saveIfReady() {
        let candidate = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokenFormat.looksValid(candidate), !isSaving else { return }
        inlineError = nil
        isSaving = true

        Task { @MainActor in
            defer {
                isSaving = false
                // Wipe the paste regardless of outcome — failure shouldn't
                // leave a real token sitting in @State.
                tokenInput = ""
            }
            do {
                try await service.saveToken(candidate)
                if case .needsSetup(.tokenRejected) = service.state {
                    inlineError = "Anthropic rejected that token. Double-check you pasted the full output of `claude setup-token`."
                } else if case .error(let userFacing) = service.state {
                    inlineError = userFacing.message
                }
            } catch TokenStoreError.invalidFormat {
                inlineError = TokenStoreError.invalidFormat.userFacing.message
            } catch let error as TokenStoreError {
                inlineError = error.userFacing.message
            } catch {
                inlineError = "Couldn't save the token. Try again."
            }
        }
    }
}

// MARK: - Helpers

private struct Step<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
