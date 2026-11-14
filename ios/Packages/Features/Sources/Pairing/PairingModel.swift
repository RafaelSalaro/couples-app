import Backend
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Inviting a partner, joining with a code, link or QR, and unpairing (feature spec §3).
@MainActor @Observable
public final class PairingModel {
    public let app: AppModel
    public private(set) var invite: Invite?
    public var codeEntry = ""
    public var message: String?
    public private(set) var isWorking = false

    public init(app: AppModel) {
        self.app = app
        if let pending = app.pendingInvite { codeEntry = pending }
    }

    public var isPaired: Bool { app.isPaired }

    /// The invite code as typed: letters and digits only, upper-cased.
    public static func normalizedCode(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Invite.codeLength))
    }

    public var canJoin: Bool {
        let entry = codeEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        return entry.count >= Invite.codeLength && !isWorking
    }

    /// What a scanned invite QR or pasted text means: an invite link gives its token, anything else is tried as a code.
    public func token(from scanned: String) -> String {
        let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), case .invite(let token)? = DeepLink.parse(url, scheme: app.deps.brand.urlScheme, domain: app.deps.brand.websiteDomain) {
            return token
        }
        return text.count == Invite.codeLength ? Self.normalizedCode(text) : text
    }

    public func createInvite() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            invite = try await app.deps.backend.createInvite()
            message = nil
            await app.deps.backend.logEvent("invite_created", props: [:])
        } catch {
            message = Friendly.message(for: error)
            if (error as? BackendError)?.code == .alreadyPaired { await app.handle(.pairChanged) }
        }
    }

    public func revokeInvite() async {
        do {
            try await app.deps.backend.revokeInvite()
            invite = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func join() async {
        // A token that arrived by invite link is used as it is; typed text is treated as a code.
        if let token = app.pendingInvite, token == codeEntry {
            await accept(token)
        } else {
            await join(with: codeEntry)
        }
    }

    public func join(with scannedOrTyped: String) async { await accept(token(from: scannedOrTyped)) }

    private func accept(_ codeOrToken: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await app.deps.backend.acceptInvite(codeOrToken: codeOrToken)
            app.pendingInvite = nil
            message = nil
            await app.handle(.pairChanged)
            await app.deps.backend.logEvent("invite_accepted", props: [:])
        } catch let error as BackendError where error.code == .invalid {
            message = L("That code didn't match. Check it with your partner and try again.")
        } catch let error as BackendError where error.code == .expired {
            message = L("That invite has expired. Ask your partner for a new one.")
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Text for the share sheet. The link opens the app, or the website with an App Store link.
    public func shareText(for invite: Invite) -> String {
        L("Join me on \(app.deps.brand.displayName) so we can protect our time together: \(invite.link.absoluteString)")
    }

    /// Either partner can unpair at any time, instantly, with one confirmation.
    public func unpair() async {
        do {
            try await app.unpair()
            invite = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Replaces the pair's QR secret (lost phone).
    public func rotateSecret() async {
        do {
            let secret = try await app.deps.backend.rotateQRSecret()
            app.deps.qrSecrets.save(secret)
            app.notice = L("Your unlock code was renewed on both phones.")
        } catch {
            message = Friendly.message(for: error)
        }
    }
}
