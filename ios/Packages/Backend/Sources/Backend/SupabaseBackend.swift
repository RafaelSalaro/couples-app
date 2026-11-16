import Core
import Foundation
import Supabase

/// The real backend: Supabase Auth, table reads under Row Level Security, and Edge Functions
/// for every write that touches minutes, pairs, requests or approvals (doc 05).
///
/// Written against the contracts in `docs/05-data-model-and-api.md` and the schema migration.
/// It compiles but has not yet run against the finished Edge Functions; response field
/// names follow the table columns and are decoded leniently where the contract is open.
public final class SupabaseBackend: Backend, @unchecked Sendable {
    private let client: SupabaseClient
    private let redirectURL: URL?
    private let timeZone: @Sendable () -> TimeZone

    public init(url: URL, anonKey: String, redirectURL: URL?, timeZone: @escaping @Sendable () -> TimeZone = { .current }) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        self.redirectURL = redirectURL
        self.timeZone = timeZone
    }

    // MARK: Plumbing

    private func userID() throws -> UUID {
        guard let id = client.auth.currentSession?.user.id else { throw BackendError(.notSignedIn) }
        return id
    }

    @discardableResult
    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw error
        } catch let error as FunctionsError {
            if case .httpError(_, let data) = error,
               let envelope = try? BackendJSON.decoder.decode(FunctionEnvelope<Empty>.self, from: data), let failure = envelope.error {
                throw BackendError(rawCode: failure.code, message: failure.message ?? "")
            }
            throw BackendError(.unknown, message: error.localizedDescription)
        } catch let error as URLError {
            throw BackendError(.offline, message: error.localizedDescription)
        } catch let error as AuthError {
            throw Self.translate(error)
        } catch {
            throw BackendError(.unknown, message: error.localizedDescription)
        }
    }

    /// Supabase Auth errors become codes the app can explain (P29: specific messages).
    static func translate(_ error: AuthError) -> BackendError {
        if case .pkceGrantCodeExchange = error { return BackendError(.expired, message: error.localizedDescription) }
        if case .implicitGrantRedirect = error { return BackendError(.expired, message: error.localizedDescription) }
        switch error.errorCode.rawValue {
        case "otp_expired", "flow_state_expired", "flow_state_not_found", "bad_code_verifier":
            return BackendError(.expired, message: error.localizedDescription)
        case "over_email_send_rate_limit", "over_request_rate_limit":
            return BackendError(.rateLimited, message: error.localizedDescription)
        case "validation_failed", "email_address_invalid":
            return BackendError(.invalid, message: error.localizedDescription)
        default:
            return BackendError(.unknown, message: error.localizedDescription)
        }
    }

    private func call<T: Decodable>(_ function: String, _ body: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        try await mapped {
            let data: Data = try await client.functions.invoke(function, options: FunctionInvokeOptions(body: body)) { data, _ in data }
            return try FunctionEnvelope<T>.unwrap(data)
        }
    }

    private func call(_ function: String, _ body: [String: JSONValue] = [:]) async throws {
        _ = try await call(function, body, as: Empty.self)
    }

    private func rows<T: Decodable>(_ type: T.Type, _ data: Data) throws -> [T] {
        do {
            return try BackendJSON.decoder.decode([T].self, from: data)
        } catch {
            throw BackendError(.unknown, message: "Unreadable rows: \(error)")
        }
    }

    private func activePair() async throws -> (pairID: UUID, partnerID: UUID)? {
        let me = try userID()
        struct Member: Decodable {
            var pairID: UUID
            var userID: UUID
        }
        return try await mapped {
            let mine = try rows(Member.self, try await client.from("pair_members").select("pair_id,user_id").eq("user_id", value: me).is("left_at", value: nil).execute().data)
            guard let pairID = mine.first?.pairID else { return nil }
            let all = try rows(Member.self, try await client.from("pair_members").select("pair_id,user_id").eq("pair_id", value: pairID).is("left_at", value: nil).execute().data)
            guard let partner = all.first(where: { $0.userID != me })?.userID else { return nil }
            return (pairID, partner)
        }
    }

    private func session(_ session: Session) -> AuthSession { AuthSession(userID: session.user.id, email: session.user.email) }

    // MARK: Auth

    public func currentSession() async -> AuthSession? {
        (try? await client.auth.session).map(session)
    }

    public func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession {
        let result = try await mapped {
            try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        }
        // Apple only shares the name on the very first sign-in; keep it as the display name.
        if let fullName, !fullName.isEmpty, (try? await fetchProfile())?.displayName == nil {
            _ = try? await updateProfile(displayName: fullName, timeZone: timeZone().identifier)
        }
        return session(result)
    }

    public func sendMagicLink(email: String) async throws {
        try await mapped { try await client.auth.signInWithOTP(email: email, redirectTo: redirectURL) }
    }

    public func completeMagicLink(url: URL) async throws -> AuthSession {
        session(try await mapped { try await client.auth.session(from: url) })
    }

    public func signOut() async throws { try await mapped { try await client.auth.signOut() } }

    // MARK: Profile and settings

    public func fetchProfile() async throws -> UserProfile {
        let me = try userID()
        return try await mapped {
            let found = try rows(UserProfile.self, try await client.from("profiles").select().eq("id", value: me).execute().data)
            if let profile = found.first { return profile }
            // The profile row is created with the account (database trigger); clients cannot
            // insert one. Until it is visible, work from the defaults.
            return UserProfile(id: me, timeZone: timeZone().identifier, locale: Locale.current.identifier)
        }
    }

    public func updateProfile(displayName: String?, timeZone: String?) async throws -> UserProfile {
        var profile = try await fetchProfile()
        if let displayName { profile.displayName = displayName }
        if let timeZone { profile.timeZone = timeZone }
        var change: [String: JSONValue] = ["time_zone": .string(profile.timeZone)]
        if let name = profile.displayName { change["display_name"] = .string(name) }
        try await mapped { try await client.from("profiles").update(change).eq("id", value: profile.id).execute() }
        return profile
    }

    public func setProtectedTimeOff(_ isOff: Bool) async throws {
        let me = try userID()
        let value: JSONValue = isOff ? .string(ISO8601DateFormatter().string(from: Date())) : .null
        try await mapped { try await client.from("profiles").update(["protected_time_off_since": value]).eq("id", value: me).execute() }
    }

    public func fetchSettings() async throws -> UserSettings {
        let me = try userID()
        return try await mapped {
            try rows(UserSettings.self, try await client.from("user_settings").select().eq("user_id", value: me).execute().data).first ?? UserSettings()
        }
    }

    public func updateSettings(_ settings: UserSettings) async throws {
        let me = try userID()
        var row: [String: JSONValue] = [
            "daily_max_minutes": .int(settings.dailyMaxMinutes),
            "emergency_allowance_minutes": .int(settings.emergencyAllowanceMinutes),
            "starting_minutes": .int(settings.startingMinutes),
            "notification_prefs": .from(settings.notificationPrefs),
        ]
        if let onboardedAt = settings.onboardedAt { row["onboarded_at"] = .string(ISO8601DateFormatter().string(from: onboardedAt)) }
        // An update, not an upsert: the settings row is created with the account, and clients
        // may update their own row but not insert one.
        try await mapped { try await client.from("user_settings").update(row).eq("user_id", value: me).execute() }
    }

    // MARK: Pairing

    public func fetchPairState() async throws -> PairState? {
        guard let (pairID, partnerID) = try await activePair() else { return nil }
        return try await mapped {
            guard let pair = try rows(Pair.self, try await client.from("pairs").select().eq("id", value: pairID).execute().data).first,
                  let partner = try rows(UserProfile.self, try await client.from("profiles").select().eq("id", value: partnerID).execute().data).first
            else { return nil }
            return PairState(pair: pair, partner: partner)
        }
    }

    private struct SecretRow: Decodable {
        var pairID: UUID
        var secret: String
        var version: Int
        var value: QRSecret { QRSecret(pairID: pairID, secret: BackendJSON.secretData(secret), version: version) }
    }

    public func fetchQRSecret() async throws -> QRSecret? {
        guard let (pairID, _) = try await activePair() else { return nil }
        return try await mapped {
            try rows(SecretRow.self, try await client.from("pair_secrets").select().eq("pair_id", value: pairID).execute().data).first?.value
        }
    }

    private struct InviteResponse: Decodable {
        var id: UUID?
        var code: String
        var link: URL
        var expiresAt: Date?
    }

    public func createInvite() async throws -> Invite {
        let response: InviteResponse = try await call("create_invite")
        return Invite(id: response.id ?? UUID(), code: response.code, link: response.link, expiresAt: response.expiresAt ?? Date().addingTimeInterval(Invite.validity))
    }

    public func revokeInvite() async throws { try await call("revoke_invite") }

    public func acceptInvite(codeOrToken: String) async throws -> PairState {
        let key = codeOrToken.count == Invite.codeLength ? "code" : "link_token"
        try await call("accept_invite", [key: .string(codeOrToken)])
        guard let state = try await fetchPairState() else { throw BackendError(.unknown) }
        return state
    }

    public func unpair() async throws { try await call("unpair") }

    public func rotateQRSecret() async throws -> QRSecret {
        try await call("rotate_qr_secret")
        guard let secret = try await fetchQRSecret() else { throw BackendError(.notPaired) }
        return secret
    }

    // MARK: Schedules

    public func fetchSchedules() async throws -> [ProtectedSchedule] {
        let me = try userID()
        return try await mapped {
            try rows(ProtectedSchedule.self, try await client.from("schedules").select().eq("user_id", value: me).order("created_at").execute().data)
        }
    }

    private struct ScheduleChangeResponse: Decodable {
        var applied: Bool?
        var request: ScheduleChangeRequest?
    }

    public func submitScheduleChange(scheduleID: UUID?, proposal: ScheduleProposal) async throws -> ScheduleChangeOutcome {
        var body: [String: JSONValue] = ["proposed": .from(proposal)]
        if let scheduleID { body["schedule_id"] = .string(scheduleID.uuidString) }
        let response: ScheduleChangeResponse = try await call("propose_schedule_change", body)
        if let request = response.request, response.applied != true { return .pending(request) }
        return .applied(try await fetchSchedules())
    }

    public func respondScheduleChange(requestID: UUID, approve: Bool) async throws {
        try await call("respond_schedule_change", ["request_id": .string(requestID.uuidString), "approve": .bool(approve)])
    }

    public func fetchScheduleChangeRequests() async throws -> [ScheduleChangeRequest] {
        guard let (pairID, _) = try await activePair() else { return [] }
        return try await mapped {
            try rows(ScheduleChangeRequest.self, try await client.from("schedule_change_requests").select().eq("pair_id", value: pairID).eq("status", value: "pending").execute().data)
        }
    }

    // MARK: Minutes

    private func summary(for user: UUID) async throws -> MinutesSummary {
        struct Debt: Decodable { var debt: Int }
        struct Spend: Decodable { var minutes: Int }
        struct Max: Decodable { var dailyMaxMinutes: Int }
        let today = LocalDay(Date(), calendar: .gregorian(in: timeZone())).description
        return try await mapped {
            let lots = try rows(MinuteLot.self, try await client.from("minute_lots").select().eq("user_id", value: user).is("closed_at", value: nil).order("expires_at").execute().data)
            let debt = try rows(Debt.self, try await client.from("minute_debt").select("debt").eq("user_id", value: user).execute().data).first?.debt ?? 0
            let spends = try rows(Spend.self, try await client.from("minute_ledger").select("minutes").eq("user_id", value: user).eq("type", value: "spend_unlock").eq("local_day", value: today).execute().data)
            let dailyMax = (try? rows(Max.self, try await client.from("user_settings").select("daily_max_minutes").eq("user_id", value: user).execute().data).first?.dailyMaxMinutes) ?? MinutesRules.defaultDailyMax
            return MinutesSummary(userID: user, lots: lots.filter { $0.remaining > 0 && $0.expiresAt > Date() }, debt: debt, spentToday: -spends.reduce(0) { $0 + $1.minutes }, dailyMax: dailyMax)
        }
    }

    public func fetchMinutes() async throws -> (mine: MinutesSummary, partner: MinutesSummary?) {
        let me = try userID()
        let mine = try await summary(for: me)
        guard let (_, partnerID) = try await activePair() else { return (mine, nil) }
        return (mine, try await summary(for: partnerID))
    }

    public func fetchLedger(limit: Int) async throws -> [LedgerEntry] {
        let me = try userID()
        return try await mapped {
            try rows(LedgerEntry.self, try await client.from("minute_ledger").select().eq("user_id", value: me).order("created_at", ascending: false).limit(limit).execute().data)
        }
    }

    public func proposeReset(standardMinutes: Int) async throws -> ResetProposal {
        try await call("propose_reset", ["standard_minutes": .int(standardMinutes)])
    }

    public func respondReset(proposalID: UUID, accept: Bool) async throws {
        try await call("respond_reset", ["proposal_id": .string(proposalID.uuidString), "accept": .bool(accept)])
    }

    public func fetchResetProposals() async throws -> [ResetProposal] {
        guard let (pairID, _) = try await activePair() else { return [] }
        return try await mapped {
            try rows(ResetProposal.self, try await client.from("reset_proposals").select().eq("pair_id", value: pairID).eq("status", value: "pending").execute().data)
        }
    }

    // MARK: Unlocks

    public func createUnlockRequest(minutes: Int, reason: String?) async throws -> UnlockRequest {
        var body: [String: JSONValue] = ["minutes": .int(minutes)]
        if let reason, !reason.isEmpty { body["reason"] = .string(reason) }
        return try await call("create_unlock_request", body)
    }

    public func respondUnlockRequest(id: UUID, approve: Bool) async throws {
        try await call("respond_unlock_request", ["request_id": .string(id.uuidString), "approve": .bool(approve)])
    }

    public func redeemAccountabilityCode(requestID: UUID, code: String) async throws -> Unlock {
        try await call("redeem_accountability_code", ["request_id": .string(requestID.uuidString), "code": .string(code)])
    }

    public func spendMinutesUnlock(minutes: Int, clientEventID: UUID) async throws -> Unlock {
        try await call("spend_minutes_unlock", ["minutes": .int(minutes), "client_event_id": .string(clientEventID.uuidString)])
    }

    public func emergencyUnlock(clientEventID: UUID) async throws -> Unlock {
        try await call("emergency_unlock", ["client_event_id": .string(clientEventID.uuidString)])
    }

    public func endUnlockEarly(unlockID: UUID) async throws -> Unlock {
        try await call("end_unlock_early", ["unlock_id": .string(unlockID.uuidString), "client_event_id": .string(UUID().uuidString)])
    }

    public func syncQRUnlocks(_ events: [QRUnlockEvent]) async throws {
        guard !events.isEmpty else { return }
        try await call("sync_qr_unlocks", ["unlocks": .from(events)])
    }

    public func fetchPendingUnlockRequests() async throws -> [UnlockRequest] {
        guard let (pairID, _) = try await activePair() else { return [] }
        return try await mapped {
            try rows(UnlockRequest.self, try await client.from("unlock_requests").select().eq("pair_id", value: pairID).eq("status", value: "pending").gt("expires_at", value: ISO8601DateFormatter().string(from: Date())).execute().data)
        }
    }

    public func fetchUnlock(requestID: UUID) async throws -> Unlock? {
        try await mapped {
            try rows(Unlock.self, try await client.from("unlocks").select().eq("request_id", value: requestID).execute().data).first
        }
    }

    public func emergencyStatus() async throws -> EmergencyAllowance {
        let me = try userID()
        let settings = try await fetchSettings()
        // All of the person's emergency sessions: the window's start depends on the whole chain.
        let sessions = try await mapped {
            try rows(Unlock.self, try await client.from("unlocks").select().eq("user_id", value: me).eq("method", value: "emergency").order("started_at").execute().data)
        }
        return EmergencyRules.status(allowance: settings.emergencyAllowanceMinutes, sessions: sessions, now: Date())
    }

    // MARK: Challenges and kudos

    public func fetchChallenges() async throws -> [Challenge] {
        try await mapped {
            // Row Level Security returns the presets plus this pair's custom challenges.
            try rows(Challenge.self, try await client.from("challenges").select().neq("status", value: "archived").order("created_at").execute().data)
        }
    }

    public func completeChallenge(id: UUID, note: String?) async throws -> ChallengeCompletion {
        var body: [String: JSONValue] = ["challenge_id": .string(id.uuidString)]
        if let note, !note.isEmpty { body["note"] = .string(note) }
        return try await call("complete_challenge", body)
    }

    public func confirmCompletion(id: UUID) async throws {
        try await call("confirm_completion", ["completion_id": .string(id.uuidString)])
    }

    public func fetchCompletions() async throws -> [ChallengeCompletion] {
        guard let (pairID, _) = try await activePair() else { return [] }
        return try await mapped {
            try rows(ChallengeCompletion.self, try await client.from("challenge_completions").select().eq("pair_id", value: pairID).order("created_at", ascending: false).limit(50).execute().data)
        }
    }

    public func createCustomChallenge(title: String, description: String, minutes: Int, category: ChallengeCategory, isShared: Bool) async throws -> Challenge {
        try await call("create_custom_challenge", [
            "title": .string(title), "description": .string(description), "minutes": .int(minutes),
            "category": .string(category.rawValue), "is_shared": .bool(isShared),
        ])
    }

    public func respondChallengeValue(challengeID: UUID, approve: Bool, counterMinutes: Int?) async throws -> Challenge {
        var body: [String: JSONValue] = ["challenge_id": .string(challengeID.uuidString), "approve": .bool(approve)]
        if let counterMinutes { body["counter_minutes"] = .int(counterMinutes) }
        return try await call("respond_challenge_value", body)
    }

    public func giveKudos(minutes: Int, message: String, challengeID: UUID?) async throws -> Kudos {
        guard let (_, partnerID) = try await activePair() else { throw BackendError(.notPaired) }
        var body: [String: JSONValue] = ["receiver_id": .string(partnerID.uuidString), "minutes": .int(minutes), "message": .string(message)]
        if let challengeID { body["challenge_id"] = .string(challengeID.uuidString) }
        return try await call("give_kudos", body)
    }

    public func fetchKudos(limit: Int) async throws -> [Kudos] {
        guard let (pairID, _) = try await activePair() else { return [] }
        return try await mapped {
            try rows(Kudos.self, try await client.from("kudos").select().eq("pair_id", value: pairID).order("created_at", ascending: false).limit(limit).execute().data)
        }
    }

    // MARK: Streak, reports, activity

    public func fetchStreak() async throws -> Streak {
        guard let (pairID, _) = try await activePair() else { return Streak() }
        return try await mapped {
            try rows(Streak.self, try await client.from("streaks").select().eq("pair_id", value: pairID).execute().data).first ?? Streak()
        }
    }

    public func fetchWeeklyReports() async throws -> [WeeklyReport] {
        guard let (pairID, _) = try await activePair() else { return [] }
        struct Row: Decodable {
            var weekStart: LocalDay
            var data: WeeklyReportBody?
        }
        struct WeeklyReportBody: Decodable {
            var members: [String: WeeklyMemberStats]?
            var totalEarnedTogether: Int?
            var sharedChallengesDone: Int?
            var protectedHours: Int?
            var streak: Int?
            var mostGenerousUserID: UUID?
        }
        return try await mapped {
            let data = try await client.from("weekly_reports").select().eq("pair_id", value: pairID).order("week_start", ascending: false).limit(52).execute().data
            return try rows(Row.self, data).map { row in
                WeeklyReport(
                    weekStart: row.weekStart, members: row.data?.members ?? [:], totalEarnedTogether: row.data?.totalEarnedTogether ?? 0,
                    sharedChallengesDone: row.data?.sharedChallengesDone ?? 0, protectedHours: row.data?.protectedHours ?? 0,
                    streak: row.data?.streak ?? 0, mostGenerousUserID: row.data?.mostGenerousUserID
                )
            }
        }
    }

    public func fetchActivity(limit: Int) async throws -> [ActivityItem] {
        let me = try userID()
        let pair = try await activePair()
        return try await mapped {
            var items: [ActivityItem] = []
            let unlockQuery = client.from("unlocks").select()
            let unlockData = try await (pair.map { unlockQuery.eq("pair_id", value: $0.pairID) } ?? unlockQuery.eq("user_id", value: me)).order("started_at", ascending: false).limit(limit).execute().data
            items += try rows(Unlock.self, unlockData).map {
                ActivityItem(id: $0.id, kind: $0.method == .emergency ? .emergencyUnlock : .unlock, actorID: $0.userID, minutes: $0.minutes, date: $0.startedAt)
            }
            if let pair {
                let kudos = try rows(Kudos.self, try await client.from("kudos").select().eq("pair_id", value: pair.pairID).order("created_at", ascending: false).limit(limit).execute().data)
                items += kudos.map { ActivityItem(id: $0.id, kind: .kudos, actorID: $0.giverID, minutes: $0.minutes, text: $0.message, date: $0.createdAt) }
                let completions = try rows(ChallengeCompletion.self, try await client.from("challenge_completions").select().eq("pair_id", value: pair.pairID).order("created_at", ascending: false).limit(limit).execute().data)
                items += completions.filter { $0.status != .expired }.map {
                    ActivityItem(id: $0.id, kind: $0.status == .confirmed ? .challengeConfirmed : .challengeDone, actorID: $0.completedBy, date: $0.createdAt)
                }
            }
            return Array(items.sorted { $0.date > $1.date }.prefix(limit))
        }
    }

    // MARK: Premium

    public func fetchPremium() async throws -> PremiumState {
        let me = try userID()
        struct Coverage: Decodable {
            var payerID: UUID
            var lastChangedAt: Date?
        }
        struct Entitlement: Decodable {
            var userID: UUID
            var kind: EntitlementKind
            var active: Bool
            var expiresAt: Date?
        }
        struct PremiumRow: Decodable { var pairID: UUID }
        struct Trial: Decodable { var trialStartedAt: Date? }
        return try await mapped {
            let pair = try await activePair()
            let entitlements = (try? rows(Entitlement.self, try await client.from("entitlements").select().eq("active", value: true).execute().data)) ?? []
            guard let pair else {
                let own = entitlements.first { $0.userID == me }
                return PremiumState(isPremium: own != nil, payerID: own?.userID, kind: own?.kind, expiresAt: own?.expiresAt, trialUsed: own?.kind == .trial)
            }
            let premiumRows = (try? rows(PremiumRow.self, try await client.from("pair_premium").select("pair_id").eq("pair_id", value: pair.pairID).execute().data)) ?? []
            let coverage = (try? rows(Coverage.self, try await client.from("pair_coverage").select().eq("pair_id", value: pair.pairID).execute().data))?.first
            let trial = (try? rows(Trial.self, try await client.from("pairs").select("trial_started_at").eq("id", value: pair.pairID).execute().data))?.first
            let payer = entitlements.first { $0.userID == coverage?.payerID }
            return PremiumState(
                isPremium: !premiumRows.isEmpty, payerID: coverage?.payerID, kind: payer?.kind, expiresAt: payer?.expiresAt,
                trialUsed: trial?.trialStartedAt != nil, coverageLastChangedAt: coverage?.lastChangedAt
            )
        }
    }

    // MARK: Account

    public func exportMyData() async throws -> Data {
        try await mapped {
            try await client.functions.invoke("export_my_data") { data, _ in data }
        }
    }

    public func deleteAccount() async throws {
        try await call("delete_account")
        try? await client.auth.signOut()
    }

    public func registerPushToken(_ token: String, sandbox: Bool) async throws {
        let me = try userID()
        let row: [String: JSONValue] = [
            "user_id": .string(me.uuidString), "platform": .string("ios"), "token": .string(token),
            "environment": .string(sandbox ? "sandbox" : "production"),
        ]
        try await mapped { try await client.from("push_tokens").upsert(row, onConflict: "user_id,token").execute() }
    }

    public func logEvent(_ name: String, props: [String: String]) async {
        guard let me = try? userID() else { return }
        let row: [String: JSONValue] = ["user_id": .string(me.uuidString), "name": .string(name), "props": .object(props.mapValues(JSONValue.string))]
        _ = try? await client.from("events").insert(row).execute()
    }

    // MARK: Realtime

    /// Maps a changed table on the `pair:<pair_id>` channel to the event the app refreshes on.
    static func event(forTable table: String) -> BackendEvent? {
        switch table {
        case "minute_lots", "minute_ledger", "minute_debt", "balances": .minutesChanged
        case "pairs", "pair_members": .pairChanged
        case "entitlements", "pair_coverage": .premiumChanged
        case "profiles": .partnerStatusChanged
        case "pair_secrets": .qrSecretRotated
        default: nil
        }
    }

    public func events() -> AsyncStream<BackendEvent> {
        AsyncStream { continuation in
            let task = Task { [self] in
                guard let pair = try? await activePair() else {
                    continuation.finish()
                    return
                }
                let channel = client.realtimeV2.channel("pair:\(pair.pairID.uuidString.lowercased())")
                let stream = channel.broadcastStream(event: "change")
                try? await channel.subscribeWithError()
                for await message in stream {
                    let payload = message["payload"]?.objectValue ?? message
                    let table = payload["table"]?.stringValue ?? ""
                    let id = payload["id"]?.stringValue.flatMap(UUID.init(uuidString:))
                    if let event = await self.event(table: table, id: id) { continuation.yield(event) }
                }
                await channel.unsubscribe()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func event(table: String, id: UUID?) async -> BackendEvent? {
        if let simple = Self.event(forTable: table) { return simple }
        func row<T: Decodable>(_ type: T.Type, from table: String, key: String = "id") async -> T? {
            guard let id else { return nil }
            guard let data = try? await client.from(table).select().eq(key, value: id).execute().data else { return nil }
            return try? rows(T.self, data).first
        }
        switch table {
        case "unlock_requests":
            guard let request = await row(UnlockRequest.self, from: table) else { return nil }
            let unlock = [.approved, .redeemed].contains(request.status) ? try? await fetchUnlock(requestID: request.id) : nil
            return .unlockRequestChanged(request, unlock: unlock)
        case "challenge_completions": return await row(ChallengeCompletion.self, from: table).map(BackendEvent.completionChanged)
        case "challenges": return await row(Challenge.self, from: table).map(BackendEvent.challengeChanged)
        case "kudos":
            guard let kudos = await row(Kudos.self, from: table), kudos.receiverID == (try? userID()) else { return .minutesChanged }
            return .kudosReceived(kudos)
        case "schedule_change_requests": return await row(ScheduleChangeRequest.self, from: table).map(BackendEvent.scheduleChangeChanged)
        case "reset_proposals": return await row(ResetProposal.self, from: table).map(BackendEvent.resetProposalChanged)
        case "streaks": return await row(Streak.self, from: table, key: "pair_id").map(BackendEvent.streakChanged)
        default: return nil
        }
    }
}
