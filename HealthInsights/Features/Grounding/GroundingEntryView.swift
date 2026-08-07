import SwiftUI
import InsightKit

/// A focused sheet to capture one grounding fact. The control adapts to the kind
/// (date, choice, number). Values are encoded to the `Double` the pure core uses.
struct GroundingEntryView: View {
    let kind: GroundingKind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // Editable state, seeded from the current profile value where present.
    @State private var date = Date()
    @State private var number: Double = 0
    @State private var choice = 0
    @State private var systolic: Double = 120
    @State private var diastolic: Double = 80
    /// Shared with every other sheet that takes a measurement; see
    /// `MeasurementSystemStorage`.
    @AppStorage(MeasurementSystemStorage.key)
    private var unitPreference = MeasurementSystemPreference.automatic.rawValue

    /// The unit the cholesterol field is being typed in.
    ///
    /// ⚠️ **The reason this is not a hard-coded `mmol/L` any more.** A US lipid
    /// panel prints `Total 195`; the sheet used to offer a box labelled mmol/L
    /// and no way to say otherwise, and 195 mmol/L would go straight into ASCVD
    /// and SCORE2 — neither of which can tell an impossible number from a bad
    /// one. mmol/L → mg/dL for cholesterol is ×38.665, **not** the ×18.0156 that
    /// applies to glucose; the two factors live in `DisplayUnit` precisely so
    /// nobody reaches for the familiar one here.
    private var cholesterolUnit: DisplayUnit {
        MeasurementQuantity.cholesterol
            .unit(in: MeasurementSystemStorage.resolved(unitPreference)) ?? .millimolesPerLitre
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    control
                } header: {
                    Text(kind.displayName)
                } footer: {
                    Text(footer).font(.caption)
                }
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
            }
            .onAppear(perform: seed)
        }
    }

    @ViewBuilder private var control: some View {
        switch kind {
        case .dateOfBirth:
            DatePicker("Date of birth", selection: $date, in: ...Date(), displayedComponents: .date)
        case .biologicalSex:
            Picker("Sex", selection: $choice) {
                Text("Male").tag(0); Text("Female").tag(1)
            }.pickerStyle(.segmented)
        case .ascvdRaceGroup:
            Picker("Ethnicity", selection: $choice) {
                Text("White / Other").tag(0); Text("Black / African American").tag(1)
            }
        case .score2Region:
            Picker("Risk region", selection: $choice) {
                Text("Low").tag(0); Text("Moderate").tag(1); Text("High").tag(2); Text("Very high").tag(3)
            }
        case .currentSmoker, .hasDiabetes, .onBPMedication:
            Picker("", selection: $choice) { Text("No").tag(0); Text("Yes").tag(1) }
                .pickerStyle(.segmented)
        case .weightGoal:
            Picker("", selection: $choice) {
                ForEach(WeightGoal.allCases) { goal in
                    Text(goal.displayName).tag(Int(goal.rawValue))
                }
            }
            .pickerStyle(.segmented)
        case .totalCholesterol, .hdlCholesterol:
            HStack {
                TextField("Value", value: displayNumber,
                          format: .number.precision(
                            .fractionLength(cholesterolUnit.isCanonical ? 1 : 0)))
                    .keyboardType(.decimalPad)
                Text(cholesterolUnit.abbreviation).foregroundStyle(.secondary)
            }
            MeasurementUnitToggle(quantity: .cholesterol, preference: $unitPreference)
        case .cuffSystolic, .cuffDiastolic:
            // Capture both halves together for convenience, whichever was tapped.
            Stepper(value: $systolic, in: 70...220) { Text("Systolic: \(Int(systolic)) mmHg") }
            Stepper(value: $diastolic, in: 40...140) { Text("Diastolic: \(Int(diastolic)) mmHg") }
            Text("Category: \(BloodPressureEstimator.category(systolic: systolic, diastolic: diastolic))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The typed value, converted on the way in and out.
    ///
    /// `number` stays canonical mmol/L — what the profile stores and what
    /// ASCVD and SCORE2 read — so `seed()` and `save()` need no unit knowledge
    /// at all, and switching the toggle restates the figure already on screen
    /// rather than reinterpreting it.
    private var displayNumber: Binding<Double> {
        Binding(get: { cholesterolUnit.fromCanonical(number) },
                set: { number = cholesterolUnit.toCanonical($0) })
    }

    /// The same guidance in whichever units the reader's lab printed.
    ///
    /// Converted rather than written twice: a second hard-coded sentence is a
    /// second thing to get wrong, and the numbers in it are the ones a reader
    /// checks their own result against.
    private var cholesterolGuidance: String {
        let unit = cholesterolUnit
        func band(_ low: Double, _ high: Double) -> String {
            let digits = unit.isCanonical ? 1 : 0
            return String(format: "%.\(digits)f–%.\(digits)f",
                          unit.fromCanonical(low), unit.fromCanonical(high))
        }
        return "From a recent blood test, in the units it was printed in. Typical total is \(band(3.5, 6.5)) \(unit.abbreviation); HDL \(band(1.0, 2.0)) \(unit.abbreviation)."
    }

    private var footer: String {
        switch kind {
        case .totalCholesterol, .hdlCholesterol:
            return cholesterolGuidance
        case .cuffSystolic, .cuffDiastolic:
            return "Use a real upper-arm cuff, seated and rested. This measured reading is what the app trusts."
        case .ascvdRaceGroup:
            return "Used only by the ASCVD risk equation, which publishes separate coefficients."
        case .weightGoal:
            return "Body Composition scores how fast your weight is moving, and a rate only means something against a direction you chose. Losing 0.8 kg a week is good progress or an unexplained loss, and nothing your phone can sense tells them apart. Until you set this, the card judges the speed for safety alone."
        default:
            return "This helps the validated models estimate your risk accurately."
        }
    }

    private func seed() {
        switch kind {
        case .dateOfBirth:
            if let v = model.profile.value(.dateOfBirth) { date = Date(timeIntervalSince1970: v) }
        case .totalCholesterol, .hdlCholesterol:
            number = model.profile.value(kind) ?? (kind == .hdlCholesterol ? 1.3 : 5.0)
        case .cuffSystolic:
            systolic = model.profile.value(.cuffSystolic) ?? 120
            diastolic = model.profile.value(.cuffDiastolic) ?? 80
        case .cuffDiastolic:
            systolic = model.profile.value(.cuffSystolic) ?? 120
            diastolic = model.profile.value(.cuffDiastolic) ?? 80
        default:
            choice = Int(model.profile.value(kind) ?? 0)
        }
    }

    private func save() {
        switch kind {
        case .dateOfBirth:
            model.saveGrounding(kind: .dateOfBirth, value: date.timeIntervalSince1970)
        case .totalCholesterol, .hdlCholesterol:
            model.saveGrounding(kind: kind, value: number)
        case .cuffSystolic, .cuffDiastolic:
            // Save both halves so a single sheet completes the reading.
            model.saveGrounding(kind: .cuffSystolic, value: systolic)
            model.saveGrounding(kind: .cuffDiastolic, value: diastolic)
        default:
            model.saveGrounding(kind: kind, value: Double(choice))
        }
    }
}
