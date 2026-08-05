import Foundation

/// OAuth tokens for a provider, persisted in the Keychain.
///
/// ⚠️ **Deliberately NOT `Codable`, and that is the whole point** (backlog Q10,
/// 2026-08-06). The reader approved building the four missing export fields with
/// one condition: *"do not include tokens."* Omitting them from an export is a
/// promise kept by whoever writes the next export; **removing the conformance
/// makes it a compile error instead.**
///
/// A token can no longer be a stored property of any `Encodable` type anywhere
/// in the app without the build failing. `ProviderCredentialStore` converts
/// through a private `StoredTokens` at the two Keychain sites and nowhere else,
/// so the serialisable form exists for exactly as long as it takes to write it
/// to the Keychain and cannot escape this file.
///
/// **This repo is public.** `docs/privacy-and-ip.md` records what was found
/// exposed once and why git history cannot be redacted in place. The difference
/// between "the export happens not to contain tokens today" and "an export
/// containing tokens does not compile" is the difference between a convention
/// and a guarantee.
struct OAuthTokens {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// The scopes the provider actually granted, as reported on the OAuth
    /// callback. Oura warns that this "may be different than the scopes that
    /// were requested" — the consent screen lets the user switch individual
    /// scopes off — and a token missing a scope fails only the endpoints that
    /// need it, with a 401.
    ///
    /// `nil` means *unknown*, and an empty list must be stored as `nil` rather
    /// than `[]`: not every provider returns `scope` on the callback (Oura
    /// often doesn't, despite documenting it), and treating "didn't say" as
    /// "granted nothing" is how this field turns from a diagnostic into a
    /// liar. Nothing may ever withhold a request on the strength of it.
    var grantedScopes: [String]? = nil

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Refresh a little early to avoid edge-of-expiry failures.
        return Date() >= expiresAt.addingTimeInterval(-60)
    }

    /// A human-readable summary for the diagnostics log.
    var scopeSummary: String {
        guard let grantedScopes, !grantedScopes.isEmpty else {
            return "unknown — the provider didn't list them on the callback"
        }
        return grantedScopes.joined(separator: " ")
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

    /// The **only** serialisable shape a token ever takes, and it is private to
    /// this store.
    ///
    /// `OAuthTokens` gave up `Codable` so that a token cannot be a stored
    /// property of anything encodable — see the note on that type. The Keychain
    /// still needs bytes, so the conversion happens here, in two functions, and
    /// the encodable form never leaves this file.
    ///
    /// Keeping the coding keys identical to the old synthesised ones is
    /// load-bearing: a reader who is already connected has tokens in their
    /// Keychain written by the previous shape, and changing a key name here
    /// would silently log them out of every provider on upgrade.
    private struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var grantedScopes: [String]?

        init(_ tokens: OAuthTokens) {
            accessToken = tokens.accessToken
            refreshToken = tokens.refreshToken
            expiresAt = tokens.expiresAt
            grantedScopes = tokens.grantedScopes
        }

        var tokens: OAuthTokens {
            OAuthTokens(accessToken: accessToken, refreshToken: refreshToken,
                        expiresAt: expiresAt, grantedScopes: grantedScopes)
        }
    }

    func tokens(for providerID: String) -> OAuthTokens? {
        guard let raw = keychain.get("\(providerID).tokens"),
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredTokens.self, from: data)
        else { return nil }
        return stored.tokens
    }

    func setTokens(_ tokens: OAuthTokens?, for providerID: String) {
        guard let tokens, let data = try? JSONEncoder().encode(StoredTokens(tokens)),
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
