import AuthenticationServices
import CryptoKit
import FeatureSupport
import UIKit
import UserNotifications

/// Sign in with Apple through the system sheet. The raw nonce goes to Supabase; Apple gets its SHA-256.
struct SystemAppleSignIn: AppleSignInProviding {
    @MainActor
    func credential() async throws -> AppleCredential {
        let nonce = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let delegate = Delegate()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            delegate.continuation = continuation
            controller.performRequests()
        }
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { throw SignInError.failed }
        let name = apple.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        return AppleCredential(idToken: token, nonce: nonce, fullName: (name?.isEmpty ?? true) ? nil : name)
    }

    @MainActor
    private final class Delegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var continuation: CheckedContinuation<ASAuthorization, Error>?

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            continuation?.resume(returning: authorization)
            continuation = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            continuation?.resume(throwing: cancelled ? SignInError.cancelled : SignInError.failed)
            continuation = nil
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

/// Notification permission and push registration.
struct SystemNotifications: NotificationServicing {
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return granted
    }

    func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
}
