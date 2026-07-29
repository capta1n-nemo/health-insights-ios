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

            Section {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)   // let iOS offer to save/fill it
                SecureField(secretRequired ? "Client Secret" : "Client Secret (optional)", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)   // saved in the iCloud Keychain
            } header: {
                Text("Your keys")
            } footer: {
                if !secretRequired {
                    Text("\(provider.displayName) shows its secret only once and doesn't need it here — it signs in securely with just the Client ID. Paste the secret only if you still have it.")
                } else {
                    Text("iOS can save these to your iCloud Keychain and offer to fill them next time.")
                }
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
                .disabled(clientID.isEmpty || (secretRequired && clientSecret.isEmpty) || isConnecting)

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

    /// Whether this provider needs a Client Secret. PKCE providers (Oura) don't —
    /// the secret is single-use and not required for the on-device flow.
    private var secretRequired: Bool { !provider.config.usesPKCE }

    private func saveAndConnect() async {
        dismissKeyboard()   // the keyboard used to linger over the connecting UI
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

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
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
                "Tap the button above and sign in with your normal Oura account (the same one as the Oura app).",
                "You'll land on the OAuth Applications page. Click \u{201C}Create New Application\u{201D}.",
                "Give it any name (e.g. \u{201C}My Health Insights\u{201D}).",
                "In \u{201C}Redirect URIs\u{201D}, paste the address below with the Copy button, then press Enter/Add so it's saved in the list.",
                "Make sure the data scopes are ticked: Daily, Heart Rate, Personal, Session, Workout (tick all available).",
                "Save the application. Copy the \u{201C}Client ID\u{201D} and \u{201C}Client Secret\u{201D} it shows.",
                "Paste both below and tap Save & Connect."
            ]
        case "withings":
            return [
                "You need a normal Withings account first (the one in the Withings app). Tap the button above and sign in.",
                "Apply for a free developer account if prompted — approval is usually instant.",
                "In the Dashboard, create a new application and choose the \u{201C}Public API\u{201D} / OAuth 2.0 type.",
                "For \u{201C}Registered URLs\u{201D} / Callback URL, paste the address below EXACTLY (Copy button) — even a trailing slash difference makes it fail.",
                "Fill any required app name, description and logo (anything is fine).",
                "Save, then open the app to copy its \u{201C}Client ID\u{201D} and \u{201C}Secret\u{201D}.",
                "Paste both below and tap Save & Connect.",
                "If Withings rejects the address for not being https://, tell me — there's an optional helper for that one case."
            ]
        case "whoop":
            return [
                "Tap the button above and sign in with your Whoop account, then join the developer platform if prompted (free).",
                "Create a new app in the developer dashboard; give it any name.",
                "In \u{201C}Redirect URIs\u{201D}, paste the address below with the Copy button and add it to the list.",
                "Tick the scopes: read:recovery, read:cycles, read:sleep, read:workout, read:profile, read:body_measurement.",
                "Save, then copy the \u{201C}Client ID\u{201D} and \u{201C}Client Secret\u{201D}.",
                "Paste both below and tap Save & Connect."
            ]
        default:
            return ["Enter your Client ID and Client Secret, then tap Save & Connect."]
        }
    }
}
