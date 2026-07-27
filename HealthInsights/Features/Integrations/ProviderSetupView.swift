import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Plain-language, non-technical setup for an OAuth provider (Oura / Withings).
/// The user creates a free developer app on the provider's site, copies the
/// redirect address from here, pastes their Client ID + Secret, then connects.
struct ProviderSetupView: View {
    let provider: OAuthIntegration
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text(intro)
                    .font(.subheadline)
                Link(destination: provider.consoleURL) {
                    Label("Open the \(provider.displayName) developer site", systemImage: "safari")
                }
            }

            Section("Step by step") {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(Theme.accent.opacity(0.15), in: Circle())
                            .foregroundStyle(Theme.accent)
                        Text(step).font(.subheadline)
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redirect / Callback URL").font(.caption).foregroundStyle(.secondary)
                        Text(provider.redirectURI).font(.footnote.monospaced())
                    }
                    Spacer()
                    Button {
                        copyRedirect()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                }
            } footer: {
                Text("Paste this exactly into the provider's \u{201C}Redirect URI\u{201D} field.")
            }

            Section("Your keys") {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Client Secret", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.bad)
                }
            }

            Section {
                Button {
                    Task { await saveAndConnect() }
                } label: {
                    HStack {
                        if isConnecting { ProgressView().padding(.trailing, 6) }
                        Text(isConnecting ? "Connecting…" : "Save & Connect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(clientID.isEmpty || clientSecret.isEmpty || isConnecting)

                if provider.hasCredentials {
                    Button("Remove keys & disconnect", role: .destructive) {
                        Task { await model.disconnect(provider); provider.forget() }
                        clientID = ""; clientSecret = ""
                    }
                }
            } footer: {
                Text("Your keys are stored securely in the iPhone Keychain and never leave your device. Signing in opens \(provider.displayName)'s own website.")
            }
        }
        .navigationTitle("Connect \(provider.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let creds = provider.currentCredentials {
                clientID = creds.clientID
                clientSecret = creds.clientSecret
            }
        }
    }

    private func saveAndConnect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        provider.saveCredentials(clientID: clientID.trimmingCharacters(in: .whitespaces),
                                 clientSecret: clientSecret.trimmingCharacters(in: .whitespaces))
        await model.connect(provider)
        if case .error(let msg) = provider.status {
            errorMessage = msg
        } else if case .connected = provider.status {
            dismiss()
        }
    }

    private func copyRedirect() {
        #if canImport(UIKit)
        UIPasteboard.general.string = provider.redirectURI
        #endif
        withAnimation { copied = true }
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
    }

    private var intro: String {
        "Connecting \(provider.displayName) takes a few minutes and is a one-off. You'll create a free developer app on \(provider.displayName)'s website, then paste two codes back here."
    }

    private var steps: [String] {
        switch provider.id {
        case "oura":
            return [
                "Open the Oura developer site above and sign in with your normal Oura account.",
                "Choose \u{201C}Create New Application\u{201D}.",
                "In the \u{201C}Redirect URIs\u{201D} box, paste the address below (use the Copy button).",
                "Copy the Client ID and Client Secret shown on that page.",
                "Paste them into the boxes below and tap Save & Connect."
            ]
        case "withings":
            return [
                "Open the Withings developer site above and sign in (a free developer account is fine).",
                "Create a new application.",
                "Set the Callback URL to the address below (use the Copy button).",
                "Copy your Client ID and Consumer Secret.",
                "Paste them into the boxes below and tap Save & Connect.",
                "Note: if Withings won't accept the address below, see the app's help — a small optional helper is available."
            ]
        case "whoop":
            return [
                "Open the Whoop developer site above and sign in with your Whoop account.",
                "Create a new app in the developer dashboard.",
                "Set the Redirect URI to the address below (use the Copy button).",
                "Copy your Client ID and Client Secret.",
                "Paste them into the boxes below and tap Save & Connect."
            ]
        default:
            return ["Enter your Client ID and Client Secret, then tap Save & Connect."]
        }
    }
}
