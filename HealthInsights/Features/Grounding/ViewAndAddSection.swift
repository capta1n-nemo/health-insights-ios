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
/// ## The anatomy, and what it stopped being
///
/// The doc comment here used to claim the anatomy was fixed whatever the route.
/// It was not. Blood pressure had a grounded summary and the other two did not;
/// the grounding-facts route had no add button at all, so its rows were the only
/// way in; the "all readings" link appeared only once there were more than
/// three; and all three routes **previewed their own contents** on the card —
/// three readings, three events, and every fact with its value.
///
/// It is now, everywhere:
///
/// 1. A header, and one figure saying where you are.
/// 2. The grounded / not-grounded summary — a seal, a sentence, and a bar while
///    there is something left to fill.
/// 3. One prominent button into the sub-menu that holds adding *and* what has
///    been added.
/// 4. A link to the fuller screen, where one exists beyond that sub-menu. Only
///    blood pressure has one; see `ContributionSummary.detailLabel`.
///
/// **No previews.** A card is for where you stand; the sub-menu is for what you
/// gave. Listing the last three readings on the card duplicated the first rows
/// of the screen the button opens, and the fact values did the same for the
/// grounding list. The state — how many, how recent, whether that is enough — is
/// the part that belongs out here, and `ContributionSummary` computes it in
/// InsightKit where it is tested.
struct ViewAndAddSection: View {
    let routes: [ContributionRoute]
    /// Carried so a missing fact can show the model's own reason for wanting it,
    /// which is the sentence that used to live on "Add these for a better
    /// estimate".
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @State private var addingBloodPressure = false
    @State private var showingSubstanceLog = false
    @State private var showingGroundingDetail: GroundingKindList?

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
            .sheet(isPresented: $addingBloodPressure) {
                AddBloodPressureView { systolic, diastolic, date in
                    model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
                }
            }
            .sheet(isPresented: $showingSubstanceLog) { SubstanceLogView() }
            .sheet(item: $showingGroundingDetail) { kinds in
                GroundingDetailView(kinds: kinds.values,
                                    unmetRequirements: unmetRequirements)
            }
        }
    }

    @ViewBuilder private func section(for route: ContributionRoute) -> some View {
        switch route {
        case .bloodPressureReadings: bloodPressureRoute
        case .substanceLog: substanceRoute
        case .groundingFacts(let kinds): factsRoute(kinds)
        }
    }

    // MARK: - The one anatomy

    /// Every route is this. The only per-route parts are the destination the
    /// button opens and the destination the link pushes.
    private func routeBody<Link: View>(
        title: String,
        summary: ContributionSummary,
        add: @escaping () -> Void,
        @ViewBuilder link: () -> Link
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, status: summary.figure)
            GroundedSummary(summary: summary)

            Button(action: add) {
                Label(summary.addLabel, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            link()
        }
    }

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

    private func detailLink<Destination: View>(
        _ summary: ContributionSummary,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        Group {
            if let label = summary.detailLabel {
                NavigationLink(destination: destination()) {
                    HStack(spacing: 4) {
                        Text(label).font(.caption.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Blood pressure

    /// The one route with somewhere further to go: the sheet takes a reading,
    /// the metric screen holds the dated history, the chart and the calibration
    /// detail. The link used to appear only past three readings, so the screen
    /// was unreachable from here exactly while a user was learning the feature.
    private var bloodPressureRoute: some View {
        let summary = ContributionSummary.bloodPressure(model.bloodPressureCalibration)
        return routeBody(
            title: "View & add readings",
            summary: summary,
            add: { addingBloodPressure = true },
            link: {
                detailLink(summary) { MetricDetailView(subject: .bloodPressure) }
            })
    }

    // MARK: - Substance log

    /// `SubstanceLogView` is already both halves — the chips add, and the
    /// entries below can be re-timed or removed — so the button is the whole
    /// route and there is nothing for a link to reach past it.
    private var substanceRoute: some View {
        let summary = ContributionSummary.substances(logged: model.substanceEvents.count)
        return routeBody(
            title: "View & add entries",
            summary: summary,
            add: { showingSubstanceLog = true },
            link: { detailLink(summary) { EmptyView() } })
    }

    // MARK: - Grounding facts

    /// The route that had no button. Its rows were the only way to reach a
    /// value, which meant the "add" half of "View & add" was a thing you had to
    /// already know was there.
    private func factsRoute(_ kinds: [GroundingKind]) -> some View {
        let unmetKinds = Set(unmetRequirements.map(\.kind))
        let setCount = kinds.filter { !unmetKinds.contains($0) }.count
        let summary = ContributionSummary.facts(set: setCount, of: kinds.count)
        return routeBody(
            title: "View & add details",
            summary: summary,
            add: { showingGroundingDetail = GroundingKindList(values: kinds) },
            link: { detailLink(summary) { EmptyView() } })
    }
}

/// The green seal, the sentence, and a bar while there is something left to
/// fill. Modelled on `CalibrationProgress`, which was the one route that had
/// this and is now what all three look like.
struct GroundedSummary: View {
    let summary: ContributionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = summary.progress {
                ProgressView(value: progress).tint(Theme.accent)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: summary.isGrounded ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(summary.isGrounded ? Theme.good : Theme.accent)
                Text(summary.guidance)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// `sheet(item:)` needs an `Identifiable`, and `[GroundingKind]` is not one.
///
/// A wrapper rather than a retroactive conformance on `Array`: conforming a
/// standard-library type to a protocol it does not own is a change every other
/// file in the target inherits, for one sheet's benefit.
struct GroundingKindList: Identifiable {
    let values: [GroundingKind]
    var id: String { values.map(\.rawValue).joined(separator: "|") }
}
