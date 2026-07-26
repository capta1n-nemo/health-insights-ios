import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Drives the interactive OAuth consent step with `ASWebAuthenticationSession`
/// and returns the redirect callback URL. Runs on the main actor because it
/// presents UI.
@MainActor
final class OAuthWebFlow: NSObject {

    enum FlowError: LocalizedError {
        case unavailable
        case cancelled
        case noCallback
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Web sign-in isn't available on this device."
            case .cancelled: return "Sign-in was cancelled."
            case .noCallback: return "The provider didn't return a valid response."
            }
        }
    }

    /// Present the authorize URL and wait for the redirect to `callbackScheme`.
    func start(authorizeURL: URL, callbackScheme: String) async throws -> URL {
        #if canImport(AuthenticationServices)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: FlowError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? FlowError.noCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: FlowError.unavailable)
            }
        }
        #else
        throw FlowError.unavailable
        #endif
    }
}

#if canImport(AuthenticationServices)
extension OAuthWebFlow: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
