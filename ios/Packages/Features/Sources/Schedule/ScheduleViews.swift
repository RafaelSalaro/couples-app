import Blocking
import Core
import DesignSystem
import FeatureSupport
import SwiftUI

public struct ScheduleView: View {
    @State private var model: ScheduleModel
    @State private var editing: ProtectedSchedule?
    @State private var choosingApps = false

    public init(app: AppModel) { _model = State(initialValue: ScheduleModel(app: app)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                approvals
                SectionHeader(L("When"))
                ForEach(model.schedules) { schedule in
                    Button {
                        editing = schedule
                    } label: {
                        Card(tone: model.isResting(schedule) ? .sunken : .raised) {
                            DSRow(
                                schedule.enabled ? ScheduleText.range(schedule) : L("Off"),
                                subtitle: subtitle(schedule), systemImage: "moon.stars"
                            ) { Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("schedule.row")
                }
                if model.canAdd {
                    Button {
                        editing = ProtectedSchedule(name: "", startLocal: LocalTime(hour: 12), endLocal: LocalTime(hour: 13))
                    } label: {
                        Label(L("Add another protected time"), systemImage: "plus")
                    }
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("schedule.add")
                } else if !model.app.isPremium {
                    Button {
                        model.app.sheet = .paywall
                    } label: {
                        Text(L("Up to 3 protected times with premium")).textRole(.callout)
                    }
                    .buttonStyle(.dsQuiet)
                    .accessibilityIdentifier("schedule.premium")
                }
                SectionHeader(L("What"))
                Button {
                    choosingApps = true
                } label: {
                    Card {
                        DSRow(L("Paused apps"), subtitle: model.selectionSummary, systemImage: "app.badge") {
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("schedule.apps")
                Text(L("Which apps you pause stays on your phone. Your partner never sees it."))
                    .textRole(.caption)
                    .foregroundStyle(Color.inkMuted)
                if let note = model.savedNote {
                    NoteBanner(note, systemImage: "checkmark", tone: .calm).accessibilityIdentifier("schedule.saved")
                }
                if let message = model.message { NoteBanner(message, tone: .neutral) }
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Protected time"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.screen")
        .task { await model.load() }
        .sheet(item: $editing) { schedule in ScheduleEditor(model: model, draft: schedule) }
        .sheet(isPresented: $choosingApps) { PausedAppsEditor(model: model) }
    }

    private func subtitle(_ schedule: ProtectedSchedule) -> String {
        var parts = [ScheduleText.days(schedule.weekdays)]
        if !schedule.name.isEmpty { parts.insert(schedule.name, at: 0) }
        if model.isResting(schedule) { parts.append(L("resting until premium returns")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var approvals: some View {
        ForEach(model.toAnswer) { request in
            Card(tone: .glow) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(model.describe(request))
                        .textRole(.heading)
                        .foregroundStyle(Color.ink)
                        .accessibilityIdentifier("change.question")
                    AsyncButton(L("Approve")) { await model.respond(request, approve: true) }
                        .accessibilityIdentifier("change.approve")
                    AsyncButton(L("Let's talk"), kind: .secondary) { await model.respond(request, approve: false) }
                        .accessibilityIdentifier("change.talk")
                }
            }
        }
        ForEach(model.waiting) { request in
            NoteBanner(L("\(model.describe(request)) Waiting for \(model.partnerName)."), systemImage: "hourglass")
                .accessibilityIdentifier("change.waiting")
        }
    }
}

struct ScheduleEditor: View {
    let model: ScheduleModel
    @State var draft: ProtectedSchedule
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !model.schedules.contains { $0.id == draft.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if model.app.isPremium {
                        TextField(L("Name (optional)"), text: $draft.name).dsField()
                    }
                    ScheduleTimesEditor(schedule: $draft)
                    SectionHeader(L("Days"))
                    // Seven days in a row; two rows at accessibility sizes so no day is cut off.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xxs),
                                             count: typeSize.isAccessibilitySize ? 4 : 7),
                              alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(1...7, id: \.self) { day in
                            let on = draft.weekdays.contains(day)
                            Chip(String(ScheduleText.shortWeekday(day).prefix(2)), isSelected: on) {
                                Haptics.tick()
                                if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                            }
                            .accessibilityLabel(ScheduleText.shortWeekday(day))
                            .accessibilityIdentifier("day.\(day)")
                        }
                    }
                    Card {
                        Toggle(L("Protected time on"), isOn: $draft.enabled)
                            .textRole(.body)
                            .foregroundStyle(Color.ink)
                            .tint(Color.sage)
                            .accessibilityIdentifier("schedule.enabled")
                    }
                    if let line = model.effectLine(model.effect(of: draft)) {
                        NoteBanner(line, tone: model.effect(of: draft) == .needsPartner ? .warm : .calm)
                            .accessibilityIdentifier("schedule.effect")
                    }
                    if let message = model.message { NoteBanner(message, tone: .neutral) }
                    AsyncButton(model.effect(of: draft) == .needsPartner ? L("Ask \(model.partnerName)") : L("Save")) {
                        if await model.save(draft) { dismiss() }
                    }
                    .disabled(!model.isValid(draft) || model.effect(of: draft) == .nothing)
                    .accessibilityIdentifier("schedule.save")
                    if !isNew, model.schedules.count > 1 {
                        AsyncButton(L("Remove this protected time"), kind: .quiet) {
                            await model.remove(draft)
                            dismiss()
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .pageBackground()
            .navigationTitle(isNew ? L("New protected time") : L("Edit protected time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { BarButton(L("Close")) { dismiss() } } }
        }
    }
}

struct PausedAppsEditor: View {
    let model: ScheduleModel
    @State private var selection: PausedAppsSelection?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(L("Tap Social, and add any other apps you want paused. Phone, Messages, Maps and your bank are best left out."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                    PausedAppsPicker(service: model.app.deps.blocking, selection: $selection)
                        .frame(minHeight: model.app.deps.blocking.kind == .screenTime ? 420 : nil)
                    if let line = model.selectionEffectLine(model.selectionEffect(selection)) {
                        NoteBanner(line, tone: model.selectionEffect(selection) == .needsPartner ? .warm : .calm)
                            .accessibilityIdentifier("apps.effect")
                    }
                    if let message = model.message { NoteBanner(message, tone: .neutral) }
                    AsyncButton(model.selectionEffect(selection) == .needsPartner ? L("Ask \(model.partnerName)") : L("Save")) {
                        if let selection, await model.saveSelection(selection) { dismiss() }
                    }
                    .disabled(model.selectionEffect(selection) == .nothing || (selection?.isEmpty ?? true))
                    .accessibilityIdentifier("apps.save")
                }
                .padding(Spacing.md)
            }
            .pageBackground()
            .navigationTitle(L("Paused apps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { BarButton(L("Close")) { dismiss() } } }
            .onAppear { selection = model.app.deps.blocking.currentSelection() }
        }
    }
}
