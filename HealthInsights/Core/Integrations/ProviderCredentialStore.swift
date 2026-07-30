import Foundation

/// OAuth tokens for a provider, persisted in the Keychain.
struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// The scopes the provider actually granted, as reported on the OAuth
    /// callback. Oura warns that this "may be different than the scopes that
    /// were requested" — the consent screen lets the user switch individual
    /// scopes off — and a token missing a scope fails only the endpoints that
    /// need it, with a 401. Optional so tokens stored by earlier builds still
    /// decode.
    var grantedScopes: [String]? = nil

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Refresh a little early to avoid edge-of-expiry failures.
        return Date() >= expiresAt.addingTimeInterval(-60)
    }

    /// A human-readable summary for the diagnostics log.
    var scopeSummary: String {
        guard let grantedScopes else { return "unknown (granted before this build recorded them)" }
        return grantedScopes.isEmpty ? "none reported" : grantedScopes.joined(separator: " ")
    }
}

/// The user-entered developer credentials for a provider.
struct ProviderCredentials {
    var clientID: String
    var clientSecret: String
}

/// Keychain-backed store of per-provider credentials and tokens. Because this is
/// the user's own personal app with their own developer credentials on their own
/// device, storing the client secret here (Keychain) is appropriate and removes
/// the need for a server to hold it.
struct ProviderCredentialStore {
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    // MARK: Developer credentials

    /// Only the client ID is required.
    ///
    /// A PKCE provider (Oura) has no client secret, and `KeychainStore.set`
    /// deletes empty values — so requiring both here meant Oura never reported
    /// having credentials and `connect()` always bailed with "Add your Oura API
    /// keys first", whatever the user pasted.
    func credentials(for providerID: String) -> ProviderCredentials? {
        guard let id = keychain.get("\(providerID).clientID")?.sanitizedCredential,
              !id.isEmpty else { return nil }
        let secret = keychain.get("\(providerID).clientSecret")?.sanitizedCredential ?? ""
        return ProviderCredentials(clientID: id, clientSecret: secret)
    }

    func hasCredentials(for providerID: String) -> Bool {
        credentials(for: providerID) != nil
    }

    /// Sanitises on the way in as well as on the way out, so a stray newline
    /// from a paste can't reach the Keychain by any route.
    func setCredentials(_ credentials: ProviderCredentials, for providerID: String) {
        keychain.set(credentials.clientID.sanitizedCredential, for: "\(providerID).clientID")
        keychain.set(credentials.clientSecret.sanitizedCredential, for: "\(providerID).clientSecret")
    }

    // MARK: Tokens

    func tokens(for providerID: String) -> OAuthTokens? {
        guard let raw = keychain.get("\(providerID).tokens"),
              let data = raw.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data)
        else { return nil }
        return tokens
    }

    func setTokens(_ tokens: OAuthTokens?, for providerID: String) {
        guard let tokens, let data = try? JSONEncoder().encode(tokens),
              let raw = String(data: data, encoding: .utf8) else {
            keychain.delete("\(providerID).tokens")
            return
        }
        keychain.set(raw, for: "\(providerID).tokens")
    }

    /// Remove tokens (disconnect) but keep the developer credentials so the user
    /// doesn't have to re-enter them to reconnect.
    func clearTokens(for providerID: String) {
        keychain.delete("\(providerID).tokens")
    }

    func clearAll(for providerID: String) {
        keychain.delete("\(providerID).clientID")
        keychain.delete("\(providerID).clientSecret")
        keychain.delete("\(providerID).tokens")
    }
}
