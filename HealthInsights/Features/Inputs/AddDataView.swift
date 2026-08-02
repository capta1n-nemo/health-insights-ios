import SwiftUI
import PhotosUI
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
        case .screenTime:
            let days = model.screenTimeDaysRecorded
            return days == 0 ? nil : "\(days) \(days == 1 ? "day" : "days")"
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
        case .screenTime:
            ScreenTimeEntrySheet()
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

/// A day's screen time, entered by hand.
///
/// **This exists because Apple will not let an app read Screen Time.** The
/// `DeviceActivityReport` extension is sandboxed read-only so its figures cannot
/// reach the containing app at all — App Groups and shared files are blocked by
/// design — the entitlement needs a paid team, and the licence forbids the data
/// leaving the device. Researched 2026-08-02; see `docs/activeContext.md` before
/// anyone tries an automatic integration again.
///
/// So the reader supplies it, and the sheet is built to make that a five-second
/// job: hours and minutes, defaulting to yesterday, which is the figure Settings
/// shows as a completed day.
struct ScreenTimeEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Yesterday: today's total is still climbing, and a partial day compared
    /// against complete ones is the "Steps: 224 at breakfast" bug in another
    /// costume.
    @State private var date = Calendar.current.date(byAdding: .day, value: -1,
                                                    to: Date()) ?? Date()
    @State private var hours = 4
    @State private var minutes = 0
    /// Scanning state, for the screenshot route.
    @State private var pickerItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanOutcome: String?
    private let scanner = DocumentScanService()

    private var total: Double { Double(hours) * 60 + Double(minutes) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date,
                               in: ...Date(), displayedComponents: .date)
                    HStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0...24, id: \.self) { Text("\($0) h").tag($0) }
                        }
                        .pickerStyle(.wheel).frame(maxWidth: .infinity)
                        Picker("Minutes", selection: $minutes) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text("\($0) m").tag($0) }
                        }
                        .pickerStyle(.wheel).frame(maxWidth: .infinity)
                    }
                    .frame(height: 110)
                } header: {
                    Text("Screen time")
                } footer: {
                    Text("From Settings ▸ Screen Time — the daily total. Re-entering a day replaces it, so fixing a typo is just entering it again.")
                }

                // The camera route. Screenshot Settings ▸ Screen Time and the
                // numbers are read off it on-device — the one way to get the
                // exact figures, since Apple will not let an app query them.
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Scan a Screen Time screenshot", systemImage: "text.viewfinder")
                    }
                    if isScanning {
                        HStack {
                            ProgressView()
                            Text("Reading the screenshot…").foregroundStyle(.secondary)
                        }
                    }
                    if let scanOutcome {
                        Text(scanOutcome)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Or read it off a screenshot")
                } footer: {
                    Text("Screenshot Settings ▸ Screen Time and pick it here. The text is read on your device — nothing is uploaded — and the figures land in the pickers above for you to check before saving. A daily *average* is never taken as a day's total.")
                }

                Section {
                    Text("Apple doesn't let apps read Screen Time, so this is the way in. A Shortcuts automation can fill it each morning if you'd rather not type it.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.screenTimeDaysRecorded > 0 {
                        LabeledContent("Days recorded",
                                       value: "\(model.screenTimeDaysRecorded)")
                    }
                } footer: {
                    Text("With \(SleepOnsetModel.minimumNights) days the Sleep card can contrast your heavier screen days against the lighter ones — an association, never a cause.")
                }
            }
            .navigationTitle("Screen time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.logScreenTime(minutes: total, on: date)
                        dismiss()
                    }
                    .disabled(total <= 0)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await scan(item) }
            }
        }
    }
}

private extension ScreenTimeEntrySheet {
    /// OCR the chosen screenshot and fill the pickers from it.
    ///
    /// **Fills, never saves.** The reader still presses Save, because OCR of a
    /// screen full of numbers is exactly the place a wrong figure could slip in
    /// unnoticed — and because the parser deliberately refuses to offer a daily
    /// average as a day, this has to be able to say so rather than silently
    /// doing nothing.
    func scan(_ item: PhotosPickerItem) async {
        isScanning = true
        scanOutcome = nil
        defer { isScanning = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = PlatformImage(data: data) else {
            scanOutcome = "Couldn't read that image."
            return
        }
        let result = await scanner.extractScreenTime(from: image)

        if let day = result.dayTotal {
            hours = Int(day.minutes) / 60
            // Nearest quarter hour, because the picker offers quarters — and
            // the exact minutes are still what gets saved if the reader leaves
            // it alone... they are not, so round honestly and say the figure.
            minutes = Int((day.minutes.truncatingRemainder(dividingBy: 60) / 15).rounded()) * 15
            if minutes == 60 { hours += 1; minutes = 0 }
            if let scanned = result.date { date = scanned }
            var note = String(format: "Found %@ — %dh %dm.", day.label,
                              Int(day.minutes) / 60, Int(day.minutes) % 60)
            if let pickups = result.pickups { note += " \(pickups) pickups." }
            scanOutcome = note + " Check it and press Save."
        } else if let other = result.otherReadings.first {
            // The distinction the parser exists for, said out loud.
            scanOutcome = "That screenshot shows a \(other.kind.displayName.lowercased()) "
                + "(\(Int(other.minutes) / 60)h \(Int(other.minutes) % 60)m), not one day's "
                + "total — so it hasn't been filled in. Open a single day in Screen Time and "
                + "screenshot that."
        } else {
            scanOutcome = "No screen-time figures found in that image."
        }
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
