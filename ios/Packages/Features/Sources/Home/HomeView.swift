import Core
import DesignSystem
import FeatureSupport
import SwiftUI

/// Wording for the activity feed. Only things the app itself creates; always neutral or warm.
public enum ActivityText {
    public static func line(_ item: ActivityItem, myID: UUID?, partnerName: String?) -> String {
        let mine = item.actorID == myID
        let name = partnerName ?? L("Your partner")
        let minutes = item.minutes.map(MinutesText.short) ?? ""
        switch item.kind {
        case .unlock: return mine ? L("You unlocked \(minutes)") : L("\(name) unlocked \(minutes)")
        case .emergencyUnlock: return mine ? L("You used an emergency unlock") : L("\(name) used an emergency unlock.")
        case .requestApproved: return mine ? L("You said go for it") : L("\(name) said go for it")
        case .requestDeclined: return mine ? L("You said let's wait") : L("\(name) said let's wait")
        case .challengeDone:
            let title = item.text ?? L("a challenge")
            return mine ? L("You did “\(title)”") : L("\(name) did “\(title)”")
        case .challengeConfirmed:
            let title = item.text ?? L("a challenge")
            return L("“\(title)” confirmed · +\(minutes)")
        case .kudos: return mine ? L("You gave kudos · +\(minutes)") : L("\(name) gave you kudos · +\(minutes)")
        case .minutesExpired: return L("\(minutes) expired")
        case .reset: return L("Balances reset to \(minutes)")
        case .paired: return L("You two paired")
        }
    }

    public static func symbol(_ kind: ActivityItem.Kind) -> String {
        switch kind {
        case .unlock: "lock.open"
        case .emergencyUnlock: "lifepreserver"
        case .requestApproved: "hand.thumbsup"
        case .requestDeclined: "hourglass"
        case .challengeDone, .challengeConfirmed: "checkmark.seal"
        case .kudos: "sparkles"
        case .minutesExpired: "clock.arrow.circlepath"
        case .reset: "arrow.counterclockwise"
        case .paired: "heart"
        }
    }

    /// Today's items, newest first.
    public static func today(_ items: [ActivityItem], now: Date, timeZone: TimeZone) -> [ActivityItem] {
        let calendar = Calendar.gregorian(in: timeZone)
        return items.filter { calendar.isDate($0.date, inSameDayAs: now) }.sorted { $0.date > $1.date }
    }
}

/// "Tonight": the home scene. A sky that follows the day and protected time, with the two
/// lights in it: you (Hearth) and your partner (Glow), always the same size. The lights hold
/// the two balances, the arc above them is protected time passing, and the paper below is today.
public struct HomeView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var justUnlocked = false
    @State private var confirmingEnd = false

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let now = app.deps.now()
            let zone = app.deps.timeZone()
            let state = app.deps.store.load()
            let status = RingStatus.make(state: state, needsAccess: app.protectionNeedsAttention, now: now, timeZone: zone)
            let moment = app.protectionNeedsAttention ? SkyMoment.daylight : SkyChoice.moment(for: state.phase(at: now, timeZone: zone), now: now)
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    header(status)
                    scene(status)
                    statusText(status)
                    actions(status)
                    notes
                    today(now: now, zone: zone)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, 96) // room for the floating place bar
            }
            .onSky(moment)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.screen")
        .refreshable { await app.refresh() }
        .onChange(of: app.unlockStartCount) { _, _ in
            // Signature moment 2: protected time gently opens. The lights ease apart and glow.
            Haptics.meet()
            justUnlocked = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                justUnlocked = false
            }
        }
    }

    // MARK: Pieces

    private func header(_ status: RingStatus) -> some View {
        VStack(spacing: Spacing.xxs) {
            SkyText(app.deps.brand.displayName, role: .label, muted: true)
            SkyText(headline(status.mode), role: .display)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.headline")
        }
        .frame(maxWidth: .infinity)
    }

    /// One calm line that says where the evening is.
    func headline(_ mode: RingStatus.Mode) -> String {
        switch mode {
        case .protected: app.isPaired ? L("Tonight is yours, together.") : L("Tonight is yours.")
        case .unlocked: L("A little time, opened.")
        case .open: L("The evening is on its way.")
        case .off: L("Protected time is resting.")
        }
    }

    /// The two lights under the arc of the evening. Close during protected time; apart in the day.
    private func scene(_ status: RingStatus) -> some View {
        let large = typeSize.isAccessibilitySize
        let diameter: CGFloat = large ? 132 : 148
        let closeness: Double = switch status.mode {
        case .protected: justUnlocked ? 0.55 : 1
        case .unlocked: 0.55
        case .open: 0.2
        case .off: 0
        }
        return VStack(spacing: -diameter * 0.28) {
            EveningArc(
                progress: status.progress,
                tint: .glow, // a light travelling through the evening
                track: SkyInkColor.track,
                accessibilityText: status.spoken
            )
            .frame(height: diameter * 0.95)
            .padding(.horizontal, Spacing.md)
            // Tapping the protected-time status opens the schedule (P28).
            .contentShape(Rectangle())
            .onTapGesture { openSchedule() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("Opens protected time"))
            .accessibilityAction { openSchedule() }
            .accessibilityIdentifier("home.ring.\(status.mode)")

            TwoLights(closeness: closeness, diameter: diameter, overlap: 0.14, glow: status.mode == .protected ? 0.9 : (justUnlocked ? 1 : 0.4)) {
                balance(name: L("You"), minutes: app.myMinutes?.balance, identifier: "home.myBalance")
            } theirs: {
                if app.isPaired {
                    balance(name: app.partnerName ?? "", minutes: app.partnerMinutes?.balance, identifier: "home.partnerBalance")
                } else {
                    // The partner's light is already there, waiting.
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .accessibilityLabel(L("Your partner's place"))
                }
            }
            .opacity(app.isPaired ? 1 : 0.92)
        }
        .frame(maxWidth: .infinity)
    }

    private func balance(name: String, minutes: Int?, identifier: String) -> some View {
        VStack(spacing: 0) {
            Text(name).textRole(.caption).lineLimit(1).minimumScaleFactor(0.7)
            Text((minutes ?? 0).formatted())
                .textRole(.numeral)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(L("min")).textRole(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(name): \(MinutesText.short(minutes ?? 0))"))
        .accessibilityIdentifier(identifier)
    }

    private func openSchedule() {
        app.usDestination = .schedule
        app.place = .us
    }

    private func statusText(_ status: RingStatus) -> some View {
        VStack(spacing: Spacing.xxs) {
            Button { openSchedule() } label: {
                VStack(spacing: Spacing.xxs) {
                    SkyText(status.value, role: .numeralLarge)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    SkyText(status.caption, role: .callout, muted: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Opens protected time"))
            .accessibilityIdentifier("home.status")
            if app.isPaired {
                // The only "cost" in the app is a streak that starts again, and it is never red (§9).
                SkyReader { ink in
                    Label(
                        app.streak.currentLength > 0
                            ? L("\(app.streak.currentLength.formatted()) evenings in a row, together")
                            : L("New streak starts today."),
                        systemImage: "leaf"
                    )
                    .textRole(.callout)
                    .foregroundStyle(ink.primary)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 36)
                    .glass()
                }
                .padding(.top, Spacing.xs)
                .accessibilityIdentifier("home.streak")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ status: RingStatus) -> some View {
        VStack(spacing: Spacing.xs) {
            switch status.mode {
            case .protected:
                Button(L("Unlock")) {
                    Haptics.touch()
                    app.sheet = .unlock
                }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("home.unlock")
                // The emergency unlock is always one tap from home (feature spec §6.4, §16).
                Button(L("Emergency unlock")) { app.sheet = .unlock }
                    .buttonStyle(.dsQuiet)
                    .accessibilityIdentifier("home.emergency")
            case .unlocked:
                Button(L("Add more time")) { app.sheet = .unlock }
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("home.unlock")
                // A confirmation says what happens to the unused time first (P26).
                Button(L("End unlock now")) { confirmingEnd = true }
                    .buttonStyle(.dsQuiet)
                    .accessibilityIdentifier("home.endUnlock")
                    .confirmationDialog(L("End this unlock now?"), isPresented: $confirmingEnd, titleVisibility: .visible) {
                        Button(L("End now")) { Task { await app.endUnlockEarly() } }
                            .accessibilityIdentifier("home.endUnlock.confirm")
                        Button(L("Keep it open"), role: .cancel) {}
                    } message: {
                        Text(app.endEarlySummary ?? L("Protected time comes back now."))
                    }
            case .open, .off:
                EmptyView()
            }
            if app.isPaired {
                Button {
                    app.sheet = .showMyCode
                } label: {
                    Label(L("Show my code"), systemImage: "qrcode")
                }
                .buttonStyle(.dsQuiet)
                .accessibilityIdentifier("home.showCode")
            }
        }
    }

    @ViewBuilder private var notes: some View {
        if app.isOffline {
            NoteBanner(L("You're offline. Protected time and in-person unlocks still work."), systemImage: "wifi.slash")
        }
        if app.protectionNeedsAttention { reenableCard }
        if !app.isPaired { inviteCard }
        if let name = app.partnerName, app.partnerProtectionIsOff {
            NoteBanner(L("Protected time is off on \(name)'s phone."), systemImage: "moon.zzz")
                .accessibilityIdentifier("home.partnerOff")
        }
        ForEach(app.incomingUnlockRequests) { request in
            Button {
                app.sheet = .incomingRequest(request)
            } label: {
                Card(tone: .glow) {
                    DSRow(
                        L("\(app.partnerName ?? "") asks for \(MinutesText.short(request.minutes))"),
                        subtitle: request.reason.map { "“\($0)”" }, systemImage: "bubble.left.and.bubble.right"
                    ) { Image(systemName: "chevron.right").foregroundStyle(Color.glowStrong) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.incomingRequest")
        }
    }

    private var inviteCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(L("Waiting for your partner"))
                    .textRole(.heading)
                    .foregroundStyle(Color.hearth)
                Text(L("Protected time and your emergency unlock already work. Asking each other, challenges and kudos start when your partner joins."))
                    .textRole(.callout)
                    .foregroundStyle(Color.ink)
                Button(L("Invite your partner")) { app.sheet = .invite }
                    .buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("home.invite")
            }
        }
    }

    private var reenableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(L("Protected time is off"))
                    .textRole(.heading)
                    .foregroundStyle(Color.ink)
                Text(L("Screen Time access is off on this phone, so nothing is being paused. Turn it back on whenever you're ready."))
                    .textRole(.callout)
                    .foregroundStyle(Color.inkMuted)
                AsyncButton(L("Turn on Screen Time access"), kind: .secondary) {
                    try await app.requestScreenTimeAccess()
                } onError: { app.notice = $0 }
                .accessibilityIdentifier("home.reenable")
            }
        }
    }

    @ViewBuilder private func today(now: Date, zone: TimeZone) -> some View {
        let items = ActivityText.today(app.activity, now: now, timeZone: zone)
        Card(radius: Radius.sheet) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(L("Today")).textRole(.label).foregroundStyle(Color.inkMuted).accessibilityAddTraits(.isHeader)
                if items.isEmpty {
                    Text(L("Nothing yet today. A quiet day is a good day."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                } else {
                    ForEach(items.prefix(8)) { item in
                        DSRow(
                            ActivityText.line(item, myID: app.myID, partnerName: app.partnerName),
                            subtitle: ScheduleText.clock(item.date, timeZone: zone),
                            systemImage: ActivityText.symbol(item.kind)
                        )
                    }
                }
                #if DEBUG
                if app.deps.blocking.kind == .mock {
                    Button(L("Preview the pause screen")) { app.sheet = .mockShield }
                        .buttonStyle(.ds(.quiet, fullWidth: false))
                        .accessibilityIdentifier("home.previewShield")
                }
                #endif
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.activity")
    }
}

/// Colors for scene furniture that sits on any sky.
enum SkyInkColor {
    /// The dotted track of the evening arc: visible on cream and on dusk alike.
    static let track = Color.inkMuted.opacity(0.45)
}
