import SwiftUI
import InsightKit

/// "View & add" — one section, **one button**, on every card that takes
/// something from the user.
///
/// What each card offers comes from its model's `contributions`
/// (`ContributionRoute` in InsightKit), which is derived from the requirements
/// the model already declares — so this view never decides *what* a card takes,
/// only how it looks.
///
/// ## Why the card shows status and a single way in
///
/// The first version of this section rendered every route at full size — a
/// header, a summary sentence, a prominent button and sometimes a link, per
/// route. On a card with one route that read fine. Body Composition has four,
/// and grew four stacked blocks with four identical red buttons — the user,
/// from a screenshot of it: *"It should just be one add button, and this should
/// show you the ability to add new data and view all previous data and
/// inputs."*
///
/// So the split is now:
///
/// - **The card** says where you stand: one status line per route — a seal and
///   the route's figure — and one button.
/// - **The button opens `ViewAndAddHubView`**, which holds the full anatomy for
///   every route: the guidance, the add affordances, and the way into what has
///   already been given.
///
/// The card grows a *line* per new kind of data, not a block — which is what
/// keeps this extensible as doses, goals, scans and whatever comes next each
/// add a route. A new `ContributionRoute` case fails to build until
/// `ContributionRouteStatus` says what its row shows and the hub says what its
/// section offers.
struct ViewAndAddSection: View {
    /// The card's own name, for the consolidated data screen's title.
    let cardTitle: String
    /// The signals this card reads, passed through to the consolidated data
    /// screen so it can list them.
    let metrics: [MetricType]
    let routes: [ContributionRoute]
    /// Carried so a missing fact can show the model's own reason for wanting it,
    /// which is the sentence that used to live on "Add these for a better
    /// estimate".
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @State private var showingHub = false

    var body: some View {
        if !routes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("View & add", systemImage: "plus.circle")
                        .font(.headline)
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                        statusRow(ContributionRouteStatus(
                            route: route, model: model,
                            unmetRequirements: unmetRequirements))
                    }
                    Button {
                        showingHub = true
                    } label: {
                        Label("Add or view your data", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .sheet(isPresented: $showingHub) {
                ViewAndAddHubView(cardTitle: cardTitle, metrics: metrics,
                                  routes: routes, unmetRequirements: unmetRequirements)
            }
        }
    }

    /// One line per route: the seal, the name, the figure. The figure is the
    /// thing that makes the section worth glancing at when there is nothing to
    /// add; everything longer than a line lives in the hub.
    private func statusRow(_ status: ContributionRouteStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: status.summary.isGrounded ? "checkmark.seal.fill" : "target")
                .font(.footnote)
                .foregroundStyle(status.summary.isGrounded ? Theme.good : Theme.accent)
            Text(status.title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(status.summary.figure)
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// A route's name and its tested state, resolved against the model — the one
/// switch both the card's status rows and the hub's sections read, so the two
/// can never describe the same route differently.
///
/// Exhaustive over `ContributionRoute`: a new kind of data does not build until
/// it says what its row is called and where its numbers come from.
struct ContributionRouteStatus {
    let title: String
    let summary: ContributionSummary

    @MainActor
    init(route: ContributionRoute, model: AppModel,
         unmetRequirements: [GroundingRequirement]) {
        switch route {
        case .groundingFacts(let kinds):
            let unmetKinds = Set(unmetRequirements.map(\.kind))
            title = "Your details"
            summary = .facts(set: kinds.filter { !unmetKinds.contains($0) }.count,
                             of: kinds.count)
        case .bloodPressureReadings:
            title = "Cuff readings"
            summary = .bloodPressure(model.bloodPressureCalibration)
        case .substanceLog:
            title = "Substance log"
            summary = .substances(logged: model.substanceEvents.count)
        case .fileImport:
            title = "Import from another app"
            summary = .fileImport(lastReceived: ShotsyIntegration.lastImportDate?
                .formatted(.relative(presentation: .named)))
        case .medication:
            let medication = model.activeMedication
            title = "Medication"
            summary = .medication(hasRegimen: medication != nil,
                                  doses: medication?.doses.count ?? 0,
                                  sideEffects: model.sideEffects.count)
        case .bodyMeasurements:
            title = "Body measurements"
            let latest = model.bodyScans.first
            summary = .bodyMeasurements(
                sitesMeasured: latest?.measurements.sites.count ?? 0,
                hasWaist: latest?.measurements.mean(.waist) != nil,
                lastMeasured: latest?.capturedAt.formatted(.relative(presentation: .named)),
                isOverdue: BodyScanCadence.state(lastScan: latest?.capturedAt,
                                                 now: Date()) == .overdue)
        case .bodyType:
            title = "Your build"
            summary = .bodyType(estimated: model.estimatedBuildName,
                                override: model.buildOverrideName)
        case .screenTime:
            title = "Screen time"
            summary = .screenTime(
                daysRecorded: model.screenTimeDaysRecorded,
                needed: SleepOnsetModel.minimumNights,
                lastEntered: model.lastScreenTimeEntry.map {
                    $0.formatted(.relative(presentation: .named))
                })
        case .symptomLog:
            // Safe to read from a view only because `AppModel.symptoms` is a
            // stored, observed property — see its doc comment.
            title = "Symptom tags"
            summary = .symptoms(
                tagged: model.symptoms.filter(\.severity.isPresent).count,
                recordedAbsences: model.symptoms.filter { !$0.severity.isPresent }.count)
        case .supplementStack:
            title = "Supplements"
            // Safe to read from a view only because `supplementEntries` is a
            // stored, observed property — see its doc comment.
            let stack = model.supplementStackSummary
            summary = .supplementStack(
                products: model.supplementEntries.count,
                nutrients: stack?.totals.count ?? 0,
                unresolved: stack?.unresolvedCount ?? 0)
        case .readerIdentity:
            title = "Name & emails"
            summary = .readerIdentity(name: model.readerIdentity.name,
                                      emails: model.readerIdentity.allEmails.count)
        case .holidayLog:
            title = "Holidays & leave"
            // The merged ledger, not `holidayEntries`: what the cards score is
            // detected *and* entered leave together, and a row counting only
            // what was typed would under-report a reader whose calendar already
            // says it.
            let ledger = model.holidayLedger
            let recency = LeaveRecency.read(ledger)
            summary = .holidays(recorded: ledger.periods.count,
                                daysSinceLastLeave: recency.daysSinceLastLeave,
                                nextInDays: recency.nextLeaveInDays)
        }
    }
}

/// The green seal, the sentence, and a bar while there is something left to
/// fill. Modelled on `CalibrationProgress`, which was the one route that had
/// this and is now what all routes look like.
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
