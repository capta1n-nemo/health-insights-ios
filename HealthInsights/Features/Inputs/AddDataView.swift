import SwiftUI
import InsightKit

/// **The master input list.** Every way into this app, on one screen, generated
/// from `InputKind`.
///
/// Settings used to carry a hand-written array of nine grounding facts plus a
/// row for the blood-test photo, and that was the whole of it — while the app
/// also accepted substances, cuff readings, a medication regimen, doses, side
/// effects and a shared file, each reachable from exactly one other place. The
/// user, looking at the stale version: *"so many new things that could be input
/// are missing, make sure it gets updated every time a new input is in the app,
/// also collapse this into a sub menu because it will get too long."*
///
/// Both halves of that are structural here. It is a sub-menu — one Settings row
/// pushes to it — and it is **exhaustive over `InputKind`**, so the way to add
/// an input is to add a case, and the way to forget to list it is a build
/// failure.
struct AddDataView: View {
    @Environment(AppModel.self) private var model
    @State private var active: InputKind?

    var body: some View {
        List {
            ForEach(InputGroup.allCases) { group in
                Section {
                    ForEach(group.kinds) { kind in
                        row(kind)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text(group.footer)
                }
            }
        }
        .navigationTitle("Add or update data")
        .navigationBarTitleDisplayMode(.inline)
        .inputSheet($active)
    }

    /// A row says what the input is, what it's for, and where you stand on it.
    ///
    /// The standing figure is the part that makes the screen worth opening when
    /// there is nothing to add — the same reasoning as `ViewAndAddSection`'s
    /// header figure, which this screen is the app-wide sibling of.
    @ViewBuilder private func row(_ kind: InputKind) -> some View {
        let blocked = isBlocked(kind)
        Button {
            if !blocked { active = kind }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.symbolName)
                    .font(.body)
                    .foregroundStyle(blocked ? Color.secondary : Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind.title).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if let standing = standing(kind) {
                            Text(standing)
                                .font(.caption).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    // The unavailable reason wins over the description: if the
                    // row can't be used, why is the only thing worth saying.
                    // One colour, not a ternary — `.disabled` already dims the
                    // row, and a ternary over two `ShapeStyle`s is a compile
                    // failure this repo has already paid for once.
                    Text(blocked ? (kind.unavailableReason ?? "") : kind.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    /// Only doses are conditional, and `InputKind` says so rather than this
    /// view deciding — the view's job is to read the condition, not to own it.
    private func isBlocked(_ kind: InputKind) -> Bool {
        kind.unavailableReason != nil && model.activeMedication == nil
    }

    /// Where the reader stands on this input, in one short phrase.
    ///
    /// Exhaustive, so a new input has to say what its standing figure is — or
    /// say explicitly that it hasn't got one, which two of these do.
    private func standing(_ kind: InputKind) -> String? {
        switch kind {
        case .profileFacts:
            let all = GroundingKind.directlyEntered
            let set = all.filter { model.profile.value($0) != nil }.count
            return "\(set) of \(all.count)"
        case .cuffBloodPressure:
            guard let latest = model.bloodPressureReadings.first else { return nil }
            return "\(Int(latest.systolic.rounded()))/\(Int(latest.diastolic.rounded()))"
        case .substanceEvent:
            let count = model.substanceEvents.count
            return count == 0 ? nil : "\(count) logged"
        case .medicationRegimen:
            guard let medication = model.activeMedication else { return nil }
            return medication.brandName ?? medication.compound?.displayName
        case .medicationDose:
            guard let count = model.activeMedication?.doses.count, count > 0 else { return nil }
            return count == 1 ? "1 dose" : "\(count) doses"
        case .sideEffect:
            let count = model.sideEffects.count
            return count == 0 ? nil : "\(count) recorded"
        case .bloodTestPhoto:
            // No standing: a photographed report becomes cholesterol facts, and
            // those are counted on the profile row. Counting them twice would
            // read as two separate sets of numbers.
            return nil
        case .fileImport:
            return ShotsyIntegration.lastImportDate.map {
                $0.formatted(.relative(presentation: .named))
            }
        case .bodyType:
            // The reader's word first, the app's estimate second and marked as
            // such — the row must not read as though they chose something they
            // didn't.
            if let chosen = model.buildOverrideName { return chosen }
            return model.estimatedBuildName.map { "\($0) (estimated)" }
        }
    }
}

/// The `+` menu's contents, from the same list as the screen above.
///
/// A menu and a screen showing different sets of inputs is exactly the drift
/// this is meant to end, so neither of them owns a list — `InputKind` does.
/// The menu shows only what can be used right now (a blocked row is a dead
/// entry in a menu, where the screen has room to say why).
struct AddInputMenu: View {
    @Binding var active: InputKind?
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(InputGroup.allCases) { group in
            Section(group.title) {
                ForEach(group.kinds) { kind in
                    if kind.unavailableReason == nil || model.activeMedication != nil {
                        Button {
                            active = kind
                        } label: {
                            Label(kind.title, systemImage: kind.symbolName)
                        }
                    }
                }
            }
        }
    }
}

extension View {
    /// Attach every input sheet to a surface, once.
    ///
    /// One `switch` for the whole app: a new `InputKind` fails to build until
    /// it says what it opens, and it then works on every surface that offers
    /// inputs rather than on the one whose author remembered.
    func inputSheet(_ active: Binding<InputKind?>) -> some View {
        sheet(item: active) { kind in
            InputSheet(kind: kind)
        }
    }
}

/// What each input opens. The single exhaustive switch behind `inputSheet`.
private struct InputSheet: View {
    let kind: InputKind
    @Environment(AppModel.self) private var model

    var body: some View {
        switch kind {
        case .profileFacts:
            GroundingDetailView(kinds: GroundingKind.directlyEntered,
                                unmetRequirements: outstandingRequirements)
        case .cuffBloodPressure:
            GroundingSheet(kind: .cuffSystolic)
        case .substanceEvent:
            SubstanceLogView()
        case .medicationRegimen:
            MedicationSetupSheet()
        case .medicationDose:
            if let compound = model.activeMedication?.compound {
                DoseEntrySheet(compound: compound)
            } else {
                // Unreachable from either surface — both gate on the regimen —
                // but a sheet that can present nothing is a blank card, so it
                // says what to do instead.
                MedicationSetupSheet()
            }
        case .sideEffect:
            SideEffectEntrySheet()
        case .bloodTestPhoto:
            PushedInSheet(title: "Import") { ImportLabView() }
        case .fileImport:
            PushedInSheet(title: "Shotsy") { ShotsyIntegrationView() }
        case .bodyType:
            BodyTypeSheet()
        }
    }

    /// The reasons the models give for wanting a fact, gathered from the
    /// results rather than restated here, so a row explains itself in the
    /// model's own words.
    private var outstandingRequirements: [GroundingRequirement] {
        var seen = Set<GroundingKind>()
        return model.results.flatMap(\.unmetRequirements).filter { seen.insert($0.kind).inserted }
    }
}

/// A screen written to be pushed, presented as a sheet.
///
/// `ImportLabView` and `ShotsyIntegrationView` are both Settings destinations
/// with no navigation chrome of their own. Rather than give every input its own
/// presentation style, they get a stack and a Done button here — the master
/// list opens everything the same way.
private struct PushedInSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Setting your own build, over the app's estimate.
///
/// This was a picker inside the somatotype chart and was named nowhere else —
/// one of the three inputs the user found on the Body Composition card that its
/// "View & add" did not mention. The picker stays where it is (changing your
/// build while looking at the chart is the natural place to do it); what
/// changed is that this is no longer the *only* way to reach it.
///
/// **Nothing scores off it**, which is why it can be a free choice rather than
/// a grounding fact with a freshness window.
struct BodyTypeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Somatotype.Component?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        choice = nil
                    } label: {
                        row(title: "Use the app's estimate",
                            detail: model.estimatedBuildName
                                .map { "Currently \($0.lowercased())." }
                                ?? "Needs a height and a recent weight first.",
                            isSelected: choice == nil)
                    }
                    ForEach(Somatotype.Component.allCases) { component in
                        Button {
                            choice = component
                        } label: {
                            row(title: component.displayName,
                                detail: component.meaning,
                                isSelected: choice == component)
                        }
                    }
                } header: {
                    Text("Your build")
                } footer: {
                    Text("Nothing is scored off this — it changes how the app describes you, not what it measures. Set it if you disagree with the estimate.")
                }
            }
            .navigationTitle("Your build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.setBuildOverride(choice)
                        dismiss()
                    }
                }
            }
            .onAppear { choice = model.buildOverride }
        }
    }

    private func row(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Recording a side effect by hand.
///
/// Side effects could previously only arrive inside a Shotsy backup, so the app
/// held a kind of data it gave the reader no way to add — the input-side twin
/// of the bug `DataDomain` closed on the display side one commit earlier.
///
/// The names are Shotsy's own vocabulary so imported and hand-entered records
/// group together; free text is still allowed, because a fixed list of symptoms
/// is a list of the ones somebody else thought of.
struct SideEffectEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Nausea"
    @State private var customName = ""
    @State private var severity = 3.0
    @State private var date = Date()

    private static let common = ["Nausea", "Fatigue", "Constipation", "Diarrhoea",
                                 "Heartburn", "Headache", "Injection-site pain",
                                 "Loss of appetite", "Vomiting", "Something else"]

    private var resolvedName: String {
        name == "Something else"
            ? customName.trimmingCharacters(in: .whitespacesAndNewlines)
            : name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    Picker("Side effect", selection: $name) {
                        ForEach(Self.common, id: \.self) { Text($0).tag($0) }
                    }
                    if name == "Something else" {
                        TextField("Name it", text: $customName)
                    }
                }
                Section {
                    // 1–10, Shotsy's scale, kept as the reader chose it. A
                    // slider rather than a picker because the number means
                    // "how bad", which is a magnitude, not a category.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Severity")
                            Spacer()
                            Text("\(Int(severity))/10")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $severity, in: 1...10, step: 1)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                } footer: {
                    Text("Recorded against your dose history, so a pattern after a dose increase is visible rather than remembered.")
                }
            }
            .navigationTitle("Side effect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.logSideEffect(name: resolvedName,
                                            severity: Int(severity), at: date)
                        dismiss()
                    }
                    .disabled(resolvedName.isEmpty)
                }
            }
        }
    }
}
