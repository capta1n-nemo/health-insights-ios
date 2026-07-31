import SwiftUI
import InsightKit

/// "View & add" — one section, one anatomy, on every card that takes something
/// from the user.
///
/// Before this there were three unrelated experiences: a one-fact sheet behind
/// "Add these for a better estimate", a blood-pressure chart and add-button
/// hidden behind a link to a different screen, and a substance log reachable
/// only from a toolbar button on a tab that never mentions it. Body composition
/// had no route at all.
///
/// What each card offers comes from its model's `contributions`
/// (`ContributionRoute` in InsightKit), which is derived from the requirements
/// the model already declares — so this view never decides *what* a card takes,
/// only how it looks.
///
/// The anatomy is fixed whatever the route: a header with a status figure, what
/// you have already given, what is still missing, and one prominent way to add.
struct ViewAndAddSection: View {
    let routes: [ContributionRoute]
    /// Carried so a missing fact can show the model's own reason for wanting it,
    /// which is the sentence that used to live on "Add these for a better
    /// estimate".
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var addingBloodPressure = false
    @State private var showingSubstanceLog = false

    var body: some View {
        if !routes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                        if index > 0 { Divider() }
                        section(for: route)
                    }
                }
            }
            .sheet(item: $groundingKind) { GroundingSheet(kind: $0) }
            .sheet(isPresented: $addingBloodPressure) {
                AddBloodPressureView { systolic, diastolic, date in
                    model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
                }
            }
            .sheet(isPresented: $showingSubstanceLog) { SubstanceLogView() }
        }
    }

    @ViewBuilder private func section(for route: ContributionRoute) -> some View {
        switch route {
        case .bloodPressureReadings: bloodPressureRoute
        case .substanceLog: substanceRoute
        case .groundingFacts(let kinds): factsRoute(kinds)
        }
    }

    // MARK: - Header

    /// The same header everywhere: what this is, and one figure saying where you
    /// are. The figure is the thing that makes the section worth looking at when
    /// there is nothing to add.
    private func header(_ title: String, status: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: "plus.circle")
                .font(.headline)
            Spacer()
            if let status {
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Blood pressure

    /// Readings, calibration progress, and the add button — on the card that
    /// talks about blood pressure, rather than two taps away on a screen that
    /// also holds the full history.
    private var bloodPressureRoute: some View {
        let readings = model.bloodPressureReadings
        let status = model.bloodPressureCalibration
        return VStack(alignment: .leading, spacing: 10) {
            header("View & add readings",
                   status: "\(status.recentReadings) in 30 days")

            CalibrationProgress(status: status)

            if readings.isEmpty {
                Text("No readings yet. Add one from a cuff, or log some in Apple Health — they'll show here automatically with their dates.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Three, not the whole log: the full dated history is a screen
                // of its own and this is a card about today's number.
                ForEach(readings.prefix(3)) { reading in
                    HStack(spacing: 8) {
                        Text("\(Int(reading.systolic.rounded()))/\(Int(reading.diastolic.rounded()))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(reading.category)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(reading.date.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            Button { addingBloodPressure = true } label: {
                Label("Add a reading", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if readings.count > 3 {
                NavigationLink {
                    MetricDetailView(subject: .bloodPressure)
                } label: {
                    HStack(spacing: 4) {
                        Text("All \(readings.count) readings and calibration detail")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Substance log

    private var substanceRoute: some View {
        let events = model.substanceEvents
        return VStack(alignment: .leading, spacing: 10) {
            header("View & add entries",
                   status: events.isEmpty ? nil : "\(events.count) logged")

            if events.isEmpty {
                Text("Nothing logged yet. Logging what you have — and when — is what lets the app compare the hours afterwards against your ordinary days.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(events.prefix(3)) { event in
                    HStack(spacing: 8) {
                        Text(event.substance.displayName).font(.subheadline)
                        Spacer()
                        Text(event.timestamp.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            Button { showingSubstanceLog = true } label: {
                Label("Log something", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Private and on-device. Recorded so the app can show how your body responds — no judgement, and no amounts.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Grounding facts

    /// One row per fact this card's model asks for, whether or not it is set.
    ///
    /// Showing the satisfied ones too is the "view" half, and it is what the old
    /// requirements card could not do — it listed only what was missing, so a
    /// card you had fully grounded simply lost the section and with it any way
    /// to correct a value you had mistyped.
    private func factsRoute(_ kinds: [GroundingKind]) -> some View {
        let unmetKinds = Set(unmetRequirements.map(\.kind))
        let setCount = kinds.filter { !unmetKinds.contains($0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            header("View & add details", status: "\(setCount) of \(kinds.count) set")

            ForEach(kinds) { kind in
                factRow(kind, isUnmet: unmetKinds.contains(kind))
            }

            if setCount < kinds.count {
                Text("The more of these the app has, the less it has to assume. Tap any row to set or change it.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func factRow(_ kind: GroundingKind, isUnmet: Bool) -> some View {
        let input = model.profile.input(kind)
        let rationale = unmetRequirements.first { $0.kind == kind }?.rationale
        return Button {
            groundingKind = kind
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isUnmet ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(isUnmet ? Color.secondary : Theme.good)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName).font(.subheadline)
                    // A stale value is still the best number available and is
                    // still used — what it has stopped buying is confidence. So
                    // it reads as "worth repeating", never as missing.
                    if let input {
                        Text(input.isFresh()
                             ? kind.formatted(input.value)
                             : "\(kind.formatted(input.value)) · worth repeating")
                            .font(.caption)
                            .foregroundStyle(input.isFresh() ? Color.secondary : Theme.warn)
                    } else if let rationale {
                        Text(rationale)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                // Both branches are `Color`. `.tertiary` here would be a
                // `HierarchicalShapeStyle`, and a ternary whose arms are two
                // different ShapeStyle types has nothing to unify to.
                Image(systemName: isUnmet ? "plus.circle.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(isUnmet ? Theme.accent : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
