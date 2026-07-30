import Foundation

extension String {
    /// A credential with surrounding whitespace and newlines removed.
    ///
    /// `.whitespaces` alone leaves the trailing newline that a copy from a web
    /// console usually carries, which then reaches the Keychain and makes the
    /// token request fail for no visible reason.
    var sanitizedCredential: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Shape checks for developer credentials pasted from a provider's console.
///
/// Deliberately loose about format — providers issue UUIDs, hex strings and
/// opaque tokens, and rejecting a valid key is worse than accepting an invalid
/// one. It is strict about the mistakes people actually make: pasting the
/// redirect URI, the console URL, or a whole line of surrounding text.
enum CredentialValidator {

    enum Problem: Equatable {
        case empty
        case looksLikeURL
        case containsWhitespace
        case tooShort

        var message: String {
            switch self {
            case .empty:
                return "Paste the value from the provider's console."
            case .looksLikeURL:
                return "That looks like a URL — you've probably pasted the redirect address instead of the key."
            case .containsWhitespace:
                return "This has a space in it, so part of another value may have come along with it."
            case .tooShort:
                return "That looks too short to be a complete key."
            }
        }
    }

    /// The minimum plausible length for an issued credential. Oura and Withings
    /// client IDs are well above this; the check only catches obvious truncation.
    private static let minimumLength = 12

    static func problem(with raw: String) -> Problem? {
        let value = raw.sanitizedCredential
        if value.isEmpty { return .empty }
        if value.contains("://") || value.lowercased().hasPrefix("www.") { return .looksLikeURL }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return .containsWhitespace }
        if value.count < minimumLength { return .tooShort }
        return nil
    }

    static func isValid(_ raw: String) -> Bool { problem(with: raw) == nil }
}
