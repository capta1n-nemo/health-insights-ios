import SwiftUI
import InsightKit

/// The reader's unit choice, and the control that shows it beside the field it
/// governs.
///
/// ## Why the picker sits on the sheet rather than in Settings
///
/// The defect this closes is a **mislabelled input**: a text field that drew a
/// hard-coded `cm` next to it and stored whatever was typed as centimetres,
/// whoever typed it. A reader with an inch tape typed `34` and the app stored a
/// 34-centimetre waist — a figure no adult has, fed straight into
/// `BuildAssessmentModel`'s waist-to-height ratio.
///
/// A Settings toggle three screens away does not fix that. It fixes it for the
/// reader who went looking, and leaves it broken for the reader who did not
/// know there was anything to look for. Putting the unit *on the field*, as a
/// control rather than as a label, means the number and the unit are chosen in
/// the same glance and cannot silently disagree.
///
/// The choice is still remembered — `@AppStorage`, one key, shared by every
/// sheet — so it is asked once and thereafter merely confirmed.
enum MeasurementSystemStorage {
    /// One key, declared once. Every `@AppStorage` reading the reader's unit
    /// system must use this and not a literal, so a typo cannot give one sheet
    /// its own private preference.
    static let key = "measurementSystemPreference"

    /// The stored preference, resolved against the phone's region.
    static func resolved(_ raw: String) -> MeasurementSystem {
        MeasurementSystem.resolved(
            MeasurementSystemPreference(rawValue: raw) ?? .automatic)
    }
}

/// A two-way segmented control naming the units a field is being typed in.
///
/// Deliberately shows the *units*, not the system: "cm / in" is a question the
/// reader can answer while holding a tape measure. "Metric / British" is a
/// question about identity, and a British reader who answers it honestly then
/// gets asked for their cholesterol in the units their GP does not use.
struct MeasurementUnitToggle: View {
    let quantity: MeasurementQuantity
    @Binding var preference: String

    /// The two systems worth offering for this quantity, and the unit each one
    /// means. Collapses to nothing when a quantity does not vary — which is
    /// most of them, and is why the caller can place this unconditionally.
    private var options: [(preference: MeasurementSystemPreference, unit: DisplayUnit)] {
        let candidates: [MeasurementSystemPreference] = [.metric, .britishHybrid, .usCustomary]
        var seen: [String: MeasurementSystemPreference] = [:]
        var out: [(MeasurementSystemPreference, DisplayUnit)] = []
        for candidate in candidates {
            guard let unit = quantity.unit(in: MeasurementSystem.resolved(candidate)) else { continue }
            // Two systems that mean the same unit collapse into one button —
            // there is no point offering "mmol/L" twice because Britain and
            // France arrive at it separately.
            guard seen[unit.abbreviation] == nil else { continue }
            seen[unit.abbreviation] = candidate
            out.append((candidate, unit))
        }
        return out.map { (preference: $0.0, unit: $0.1) }
    }

    /// Which button is lit, given that the stored preference may be
    /// `.automatic` — in which case the region decides and the control must
    /// still show the reader what that decided.
    private var selection: Binding<String> {
        Binding(
            get: {
                let resolved = MeasurementSystemStorage.resolved(preference)
                guard let unit = quantity.unit(in: resolved),
                      let match = options.first(where: { $0.unit.abbreviation == unit.abbreviation })
                else { return options.first?.preference.rawValue ?? "" }
                return match.preference.rawValue
            },
            set: { preference = $0 })
    }

    var body: some View {
        if options.count > 1 {
            Picker("Units", selection: selection) {
                ForEach(options, id: \.preference.rawValue) { option in
                    Text(option.unit.abbreviation).tag(option.preference.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Units")
        }
    }
}
